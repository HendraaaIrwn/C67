import C67Domain
import Foundation

extension PlannerV5 {
    func recover(_ day: Day, durations: [Int], latestDeparture: Int, evaluated: Set<Candidate>,
                 work: inout Work, result: inout Search) async throws -> PlannerV5Schedule? {
        guard work.limit == nil else { return nil }
        guard work.quotes < Work.quoteLimit else {
            work.limit = .routeQuotes
            return nil
        }
        guard !work.routes.isEmpty, await canRecover() else { return nil }
        let quoteLimit = min(Work.quoteLimit, work.quotes + 12)
        let seeds = try recoverySeeds(day, durations: durations, latestDeparture: latestDeparture,
                                      evaluated: evaluated, work: work)
        // Keep the ranking from the first pass even as exact validation obtains more quotes.
        for candidate in seeds {
            try Task.checkCancellation()
            guard await canRecover() else { break }
            guard work.candidates < Work.candidateLimit else {
                work.limit = .candidates
                break
            }
            work.candidates += 1
            switch try await evaluate(candidate, day: day, durations: durations, work: &work, quoteLimit: quoteLimit) {
            case let .complete(schedule):
                return schedule
            case let .missing(issue):
                result.missingETA = true
                if !result.issues.contains(issue) { result.issues.append(issue) }
            case let .conflict(issue, endpoint):
                if !result.issues.contains(issue) { result.issues.append(issue) }
                if let endpoint { result.endpointDeadline = endpoint }
            case .limited:
                return nil
            }
        }
        return nil
    }

    private func recoverySeeds(_ day: Day, durations: [Int], latestDeparture: Int,
                               evaluated: Set<Candidate>, work: Work) throws -> [Candidate] {
        let samples = Dictionary(grouping: work.routes.keys) { [$0.from, $0.to] }
        let flexible = day.input.trip.enginePreferences?.flexibleDeparture == true
        let last = flexible ? latestDeparture : day.start
        let cutoff = ContinuousClock.now.advanced(by: .milliseconds(300))
        var ranked: [(candidate: Candidate, travel: Int)] = []

        for order in day.orders {
            try Task.checkCancellation()
            if ContinuousClock.now >= cutoff { break }
            let legs = order + (day.endpoint.map { [$0] } ?? [])
            var intervalStart: Int?

            // Each contiguous range contributes a midpoint so adjacent times do not fill the shortlist.
            for departure in day.start ... (last + 1) {
                let seed = Candidate(order: order, departure: departure)
                if departure <= last, !evaluated.contains(seed),
                   predictedTravel(departure, legs: legs, day: day, durations: durations, work: work, samples: samples) != nil {
                    if intervalStart == nil { intervalStart = departure }
                    continue
                }
                guard let start = intervalStart else { continue }
                intervalStart = nil
                let midpoint = start + (departure - start) / 2
                guard let travel = predictedTravel(midpoint, legs: legs, day: day, durations: durations,
                                                   work: work, samples: samples) else { continue }
                ranked.append((.init(order: order, departure: midpoint), travel))
                ranked.sort {
                    if $0.travel != $1.travel { return $0.travel < $1.travel }
                    if $0.candidate.departure != $1.candidate.departure { return $0.candidate.departure < $1.candidate.departure }
                    return $0.candidate.order.lexicographicallyPrecedes($1.candidate.order)
                }
                if ranked.count > 4 { ranked.removeLast() }
            }
        }
        return ranked.map(\.candidate)
    }

    private func predictedTravel(_ departure: Int, legs: [Int], day: Day, durations: [Int],
                                 work: Work, samples: [[Int]: [Key]]) -> Int? {
        var from = day.origin
        var clock = departure
        var travel = 0
        var waiting = 0
        var usedQuote = false

        for to in legs {
            let a = day.points[from]
            let b = day.points[to]
            if a != b {
                let key = Key(from: from, to: to, minute: clock)
                if work.missing.contains(key) { return nil }
                let nearest = samples[[from, to]]?.min {
                    (abs($0.minute - clock), $0.minute) < (abs($1.minute - clock), $1.minute)
                }
                let minutes: Int
                if let nearest, abs(nearest.minute - clock) <= 30, let quote = work.routes[nearest] {
                    minutes = (quote.seconds + 59) / 60
                    usedQuote = true
                } else {
                    let km = hypot((b.latitude - a.latitude) * 111, (b.longitude - a.longitude) * 110)
                    minutes = max(2, Int(ceil(km * (day.input.trip.mode == .walking ? 15 : 4.5) + 1)))
                }
                clock += minutes
                travel += minutes
            }
            guard clock <= day.end else { return nil }
            from = to
            guard to < day.stops.count else { continue }
            guard case let .visit(start, end) = visitTiming(day.stops[to], arrival: clock,
                                                            length: durations[to], deadline: day.end) else { return nil }
            waiting += Self.minute(start, rounding: .up) - clock
            if waiting > day.wait { return nil }
            clock = Self.minute(end, rounding: .up)
            if clock > day.end { return nil }
        }
        return usedQuote ? travel : nil
    }
}
