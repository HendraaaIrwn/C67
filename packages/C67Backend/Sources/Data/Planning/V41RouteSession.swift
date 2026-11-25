import Foundation
import C67Domain
import PocketEngine
#if canImport(MapKit)
    import MapKit
#endif

/// A single Go Trip attempt can reuse exact, recent quotes from the same saved revision.
struct TripStartRouting: Sendable {
    actor Progress {
        let expiresAt = ContinuousClock.now.advanced(by: .seconds(90))
        private var quotes: [V41RouteSession.Key: V4Quote] = [:]

        func quote(for key: V41RouteSession.Key) -> V4Quote? {
            expiresAt > .now ? quotes[key] : nil
        }

        func record(_ quote: V4Quote, for key: V41RouteSession.Key) {
            quotes[key] = quote
        }
    }

    struct DeadlineReached: Error {}

    let progress: Progress
    let deadline: ContinuousClock.Instant

    static func before<T: Sendable>(_ deadline: ContinuousClock.Instant,
                                    operation: @escaping @Sendable () async throws -> T) async throws -> T {
        guard ContinuousClock.now < deadline else { throw DeadlineReached() }
        return try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask(operation: operation)
            group.addTask {
                try await ContinuousClock().sleep(until: deadline)
                throw DeadlineReached()
            }
            defer { group.cancelAll() }
            guard let result = try await group.next() else { throw CancellationError() }
            try Task.checkCancellation()
            guard ContinuousClock.now < deadline else { throw DeadlineReached() }
            return result
        }
    }

    static func retryDelay(for error: any Error) -> Duration? {
        if case TravelQuoteError.temporary(let delay) = error { return max(.zero, delay) }
        if error is DeadlineReached { return .milliseconds(350) }
        let provider = error as NSError
        if provider.domain == NSURLErrorDomain,
           [.timedOut, .networkConnectionLost, .notConnectedToInternet, .cannotConnectToHost].contains(URLError.Code(rawValue: provider.code)) {
            return .milliseconds(350)
        }
        #if canImport(MapKit)
            if provider.domain == MKErrorDomain, provider.code == MKError.Code.serverFailure.rawValue { return .milliseconds(350) }
        #endif
        return nil
    }
}

/// One command's route budget and exact-time cache, shared across dates and candidates.
actor V41RouteSession {
    struct Key: Hashable {
        var from: String
        var to: String
        var minute: Int
    }

    struct Pair: Hashable {
        var from: String
        var to: String
    }

    let limit: Int
    private let services: PocketPlanningServices
    private let input: PlanningInput
    private let startRouting: TripStartRouting?
    private var usedStartRetry = false
    private var cache: [Key: V4Quote] = [:]
    private(set) var proxies: [Pair: V4Quote] = [:]
    private(set) var failedPairs = Set<Pair>()
    private(set) var calls = 0
    private(set) var providerDuration: Duration = .zero
    private(set) var stopReason: String?
    private var firstCallAt: ContinuousClock.Instant?
    private let maximumSeconds: Double
    private let reserve: @Sendable (Int) async throws -> Void
    private let candidateLimit: Int
    private var candidates = 0
    private var reservationError: (any Error)?

    func checkReservation() throws {
        if let reservationError { throw reservationError }
    }

    func quote(_ from: PlanningPoint, _ to: PlanningPoint, _ minute: Int) async throws -> V4Quote {
        func key(for point: PlanningPoint) -> String? {
            if point == input.origin { return "origin" }
            if point == input.planningEndpoint { return "endpoint" }
            return input.places.first { $0.location == point }?.id.uuidString
        }
        guard let fromID = key(for: from), let toID = key(for: to) else {
            return .init(minutes: nil, meters: nil, status: "missing_point")
        }
        return try await quote(fromID, toID, minute)
    }

    init(input: PlanningInput, services: PocketPlanningServices, limit: Int = 72, maximumSeconds: Double = 90,
         candidateLimit: Int = 500, initialCalls: Int = 0, startRouting: TripStartRouting? = nil,
         reserve: @escaping @Sendable (Int) async throws -> Void = { _ in }) {
        self.input = input
        self.services = services
        self.startRouting = startRouting
        self.limit = limit
        self.maximumSeconds = maximumSeconds
        calls = initialCalls
        self.reserve = reserve
        self.candidateLimit = candidateLimit
    }

    func startSearch() { firstCallAt = firstCallAt ?? .now }

    func canRecover() -> Bool {
        checkQuoteBudget()
        return stopReason == nil
    }

    private func checkQuoteBudget() {
        if stopReason == nil, calls >= limit { stopReason = "quote_budget_exhausted" }
        if let start = firstCallAt, start.duration(to: .now) > .seconds(maximumSeconds) { stopReason = stopReason ?? "time_budget_exhausted" }
    }

    func reserveCandidate() -> Bool {
        if let start = firstCallAt, start.duration(to: .now) > .seconds(maximumSeconds) { stopReason = stopReason ?? "time_budget_exhausted" }
        if candidates >= candidateLimit { stopReason = stopReason ?? "candidate_budget_exhausted" }
        guard stopReason == nil else { return false }
        candidates += 1
        return true
    }

    func quote(_ from: String, _ to: String, _ minute: Int) async throws -> V4Quote {
        try Task.checkCancellation()
        let key = Key(from: from, to: to, minute: minute)
        if let value = cache[key] { return value }
        let pair = Pair(from: from, to: to)
        if let value = await startRouting?.progress.quote(for: key) {
            cache[key] = value
            proxies[pair] = value
            return value
        }
        let endpoint = input.enginePreferences?.endPoint ?? (input.enginePreferences?.returnToOrigin == true ? input.origin : nil)
        if to == "endpoint", endpoint == nil { return .init(minutes: 0, meters: 0, status: "no_endpoint") }
        func point(_ id: String) -> PlanningPoint? {
            if id == "origin" { return input.origin }
            if id == "endpoint" { return endpoint }
            return input.places.first { $0.id.uuidString == id }?.location
        }
        guard let a = point(from), let b = point(to) else { return .init(minutes: nil, meters: nil, status: "missing_point") }
        if a == b { return .init(minutes: 0, meters: 0, status: "same_point") }
        checkQuoteBudget()
        if let stopReason { return .init(minutes: nil, meters: nil, status: stopReason) }
        firstCallAt = firstCallAt ?? .now
        try await reserveQuote()
        let value: V4Quote
        let started = ContinuousClock.now
        defer { providerDuration += started.duration(to: .now) }
        do {
            let departure = Date(timeIntervalSince1970: Double(minute * 60))
            let origin = Coordinate(latitude: a.latitude, longitude: a.longitude)
            let destination = Coordinate(latitude: b.latitude, longitude: b.longitude)
            let operation = services.travel
            let mode = input.mode
            let travel: @Sendable () async throws -> LegQuote = { try await operation(origin, destination, departure, mode) }
            let leg = try await travelQuote(travel)
            try Task.checkCancellation()
            if leg.seconds.isFinite, (0 ... 604_800).contains(leg.seconds), leg.meters.isFinite, leg.meters >= 0 {
                value = .init(minutes: Int(ceil(leg.seconds / 60)), meters: Int(ceil(leg.meters)), status: "mapkit_quote")
                proxies[pair] = value
                await startRouting?.progress.record(value, for: key)
            } else { value = .init(minutes: nil, meters: nil, status: "invalid_quote") }
        } catch TravelQuoteError.throttled {
            stopReason = "route_throttled"
            value = .init(minutes: nil, meters: nil, status: "route_throttled")
        } catch {
            try Task.checkCancellation()
            try checkReservation()
            if let startRouting, ContinuousClock.now >= startRouting.deadline { throw TripStartRouting.DeadlineReached() }
            value = .init(minutes: nil, meters: nil, status: "route_unavailable")
        }
        if value.minutes == nil { failedPairs.insert(pair) }
        cache[key] = value
        return value
    }

    private func reserveQuote() async throws {
        try Task.checkCancellation()
        try checkReservation()
        calls += 1
        do { try await reserve(calls) }
        catch {
            reservationError = error
            stopReason = "route_reservation_failed"
            throw error
        }
        try Task.checkCancellation()
    }

    private func travelQuote(_ travel: @escaping @Sendable () async throws -> LegQuote) async throws -> LegQuote {
        guard let startRouting else { return try await travel() }
        let firstDeadline = min(startRouting.deadline, .now.advanced(by: .seconds(7)))
        do {
            return try await TripStartRouting.before(firstDeadline, operation: travel)
        } catch {
            try Task.checkCancellation()
            guard !usedStartRetry, let delay = TripStartRouting.retryDelay(for: error),
                  ContinuousClock.now.advanced(by: delay + .seconds(1)) < startRouting.deadline else { throw error }
            checkQuoteBudget()
            guard stopReason == nil else { throw error }
            usedStartRetry = true
            try await Task.sleep(for: delay)
            try Task.checkCancellation()
            guard ContinuousClock.now < startRouting.deadline else { throw TripStartRouting.DeadlineReached() }
            try await reserveQuote()
            let retryDeadline = min(startRouting.deadline, .now.advanced(by: .seconds(7)))
            return try await TripStartRouting.before(retryDeadline, operation: travel)
        }
    }
}
