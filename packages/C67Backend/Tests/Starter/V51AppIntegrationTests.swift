import C67Domain
import C67PlannerV5
import Foundation
import PocketEngine
import Testing
@testable import C67Data

private struct V51TestConnection: PocketConnectionProviding {
    func credentials() async -> PocketCredentials { .init(serverURL: "", token: "") }
    func update(serverURL: String, token: String) async throws { throw PlanningError.unavailable }
}

@Test(arguments: ["estimate", "manual", "session"])
func v52MuseumPolriUsesLocalDurationAndRespectsExplicitChoices(choice: String) async throws {
    var input = try v41Input(count: 1)
    input.enginePreferences?.orderingMethod = .hybridV52
    input.enginePreferences?.semanticAssistance = .whenNeeded
    input.enginePreferences?.usesLuna = true
    input.enginePreferences?.allowsAIProcessing = true
    input.enginePreferences?.maximumWaitMinutes = 15
    input.enginePreferences?.mainSpotID = input.places[0].id
    input.places[0].name = "Synthetic Museum Polri"
    input.places[0].categories = ["MKPOICategoryMuseum"]
    input.places[0].visitSeconds = choice == "manual" ? 30 * 60 : 45 * 60
    input.places[0].durationOverridden = choice != "estimate"
    if choice == "session" {
        let startsAt = input.startsAt.addingTimeInterval(20 * 60)
        input.places[0].activitySession = .init(startsAt: startsAt, endsAt: startsAt.addingTimeInterval(30 * 60))
    }
    let calls = V41Calls()
    var services = v41Services(calls, model: false)
    services.experience = { _, _ in
        Issue.record("v5.2 should get durations without reaching Luna")
        throw PlanningError.unavailable
    }
    let now = input.startsAt
    let repository = try PocketPlanningRepository(services: services, connection: V51TestConnection(), storageURL: nil, synthetic: true,
                                                  jobClock: { now }, requiresExternalAIConsent: true, externalAIDisclosure: "fixture")
    let job = try await repository.requestPlan(.init(requestID: UUID(), purpose: .firstItinerary, input: input))
    let proposal = try #require(try await finished(repository, id: job.id).result?.proposal)
    let stop = try #require(proposal.stops.first)
    #expect(stop.visitSeconds == (choice == "estimate" ? 75 : 30) * 60)
    let rationale = ["estimate": "Estimated for a museum visit.", "manual": "Duration chosen by you.", "session": "Scheduled session."]
    #expect(stop.visitDurationAdvice?.rationale == rationale[choice])
    #expect(proposal.scheduleAssessment?.modelCalls == 0)
    if let session = input.places[0].activitySession { #expect(stop.visitStartsAt == session.startsAt) }
}

@Test(arguments: [nil, PlanningVisitActivity.coffeePickup, .seatedCoffee] as [PlanningVisitActivity?])
func v52CafeDurationUsesChosenActivity(activity: PlanningVisitActivity?) async throws {
    var input = try v41Input(count: 1)
    input.enginePreferences?.orderingMethod = .hybridV52
    input.places[0].categories = ["MKPOICategoryCafe"]
    input.places[0].durationOverridden = false
    input.places[0].visitActivity = activity
    let services = v41Services(V41Calls(), model: false)
    let planner = V41ItineraryPlanner(services: services, hours: { _ in .init(status: "unavailable") }, synthetic: true)
    let proposal = try await planner.schedule(input, semantic: nil, routes: .init(input: input, services: services))
    let stop = try #require(proposal.stops.first)
    #expect(stop.visitSeconds == (activity == nil ? 30 : activity == .coffeePickup ? 15 : 45) * 60)
    #expect(stop.visitDurationAdvice?.rationale == (activity.map { "\($0.title), chosen by you." } ?? "Estimated for a café visit."))
    #expect(stop.visitDurationAdvice?.asksCoffeeIntent == false)
}

@Test(arguments: [("MKPOICategoryPark", 35, PlanningVisitActivity.briefParkVisit, PlanningVisitActivity.picnicOrStroll, 20, 60),
                  ("restaurant", 60, .quickMeal, .leisurelyMeal, 35, 75)])
func v52LocalActivitiesUseTheCategoryDefaultsAndSelectedDurations(category: String, fallback: Int, short: PlanningVisitActivity,
                                                                  long: PlanningVisitActivity, shortMinutes: Int, longMinutes: Int) throws {
    var place = try #require(v41Input(count: 1).places.first)
    place.categories = [category]
    #expect(place.visitActivities == [short, long])
    #expect(place.localVisitEstimate.minutes == fallback)
    place.visitActivity = short
    #expect(place.localVisitEstimate.minutes == shortMinutes)
    #expect(place.localVisitEstimate.shorterActivity == nil)
    place.visitActivity = long
    #expect(place.localVisitEstimate.minutes == longMinutes)
    #expect(place.localVisitEstimate.shorterActivity == short)
}

private func v52TightSixStops() throws -> PlanningInput {
    var input = try v41Input(count: 6)
    input.enginePreferences?.orderingMethod = .hybridV52
    input.enginePreferences?.returnToOrigin = true
    input.preservesPlaceOrder = true
    input.finishBy = input.startsAt.addingTimeInterval(280 * 60)
    let categories = ["museum", "cafe", "park", "restaurant", "", ""]
    for index in input.places.indices {
        input.places[index].visitSeconds = 45 * 60
        input.places[index].durationOverridden = false
        input.places[index].categories = [categories[index]]
    }
    return input
}

@Test(arguments: [true, false])
func v52SixStopsOfferAShorterVisitOnlyAfterCheckingTheReturnLeg(returnETAAvailable: Bool) async throws {
    var input = try v52TightSixStops()
    let origin = Coordinate(latitude: input.origin.latitude, longitude: input.origin.longitude)
    let services = PocketPlanningServices(travel: { _, destination, _, _ in
        if destination == origin, !returnETAAvailable { throw PlanningError.unavailable }
        return .init(seconds: 120, meters: 500)
    }, weather: { _, _, _ in throw PlanningError.unavailable }, advise: { _ in throw PlanningError.unavailable })
    let planner = V41ItineraryPlanner(services: services, hours: { _ in .init(status: "unavailable") }, synthetic: true)
    do {
        _ = try await planner.schedule(input, semantic: nil, routes: .init(input: input, services: services))
        Issue.record("The default durations should exceed the deadline")
    } catch let failure as PlanningScheduleFailure {
        #expect(input.places[0].visitActivity == nil)
        let alternatives = failure.assessment.durationAlternatives
        if !returnETAAvailable {
            #expect(alternatives.isEmpty)
            #expect(failure.assessment.unresolved.contains { $0.code == "shorter_visit_unverified" })
            return
        }
        let choice = try #require(alternatives.first)
        #expect(alternatives.count == 1)
        #expect(choice.placeID == input.places[0].id)
        #expect(choice.activity == .oneExhibition)
        #expect(choice.originalSeconds == 75 * 60)
        #expect(choice.proposedSeconds == 45 * 60)
        choice.apply(to: &input.places[0])
        let accepted = try await planner.schedule(input, semantic: nil, routes: .init(input: input, services: services))
        #expect(accepted.stops.map { $0.visitSeconds / 60 } == [45, 30, 35, 60, 45, 45])
        #expect(accepted.returnTravelSeconds == 120)
        #expect(try #require(accepted.finishesAt) <= input.finishBy)
    }
}

private actor DurationApprovalRoutes {
    private(set) var calls = 0

    func quote() -> LegQuote {
        calls += 1
        return .init(seconds: 120, meters: 500)
    }
}

@Test(arguments: ["first", "edit", "expired", "differentOrigin", "unapproved", "sessionChanged"])
func v52ShorterVisitApprovalReusesOnlyTheFreshMatchingProposal(scenario: String) async throws {
    let clock = TestClock()
    let input = try v52TightSixStops()
    clock.advance(input.startsAt.addingTimeInterval(-600).timeIntervalSince(clock.now()))
    let purpose: PlanningPurpose = scenario == "edit" ? .plan : .firstItinerary
    let routes = DurationApprovalRoutes()
    let services = PocketPlanningServices(travel: { _, _, _, _ in await routes.quote() },
                                          weather: { _, _, _ in throw PlanningError.unavailable },
                                          advise: { _ in throw PlanningError.unavailable })
    let repository = try PocketPlanningRepository(services: services, connection: V51TestConnection(), storageURL: nil,
                                                  synthetic: true, jobClock: { clock.now() })
    let job = try await repository.requestPlan(.init(requestID: UUID(), purpose: purpose, input: input))
    let failed = try await finished(repository, id: job.id)
    #expect(failed.status == .failed)
    #expect(failed.result?.proposal == nil)
    let choice = try #require(failed.scheduleAssessment?.durationAlternatives.first)
    var updated = try #require(choice.applying(to: input))
    let callsBeforeApproval = await routes.calls
    #expect(callsBeforeApproval == 7)

    if scenario == "expired" { clock.advance(121) }
    if scenario == "differentOrigin" { updated.origin.latitude += 0.01 }
    if scenario == "sessionChanged" { await repository.suspendOrdering() }
    var approval = PlanningRequest(requestID: UUID(), purpose: purpose, input: updated)
    if scenario != "unapproved" { approval.durationAlternativeJobID = job.id }
    let next = try await repository.requestPlan(approval)
    let canReuse = scenario == "first" || scenario == "edit"
    #expect(next.status == (canReuse ? .succeeded : .running))
    let reviewed = canReuse ? next : try await finished(repository, id: next.id)
    let proposal = try #require(reviewed.result?.proposal)
    #expect(proposal.stops.map { $0.visitSeconds / 60 } == [45, 30, 35, 60, 45, 45])
    #expect(proposal.returnTravelSeconds == 120)
    if canReuse {
        #expect(await routes.calls == callsBeforeApproval)
        #expect(try await repository.requestPlan(approval) == reviewed)
        approval.durationAlternativeJobID = nil
        await #expect(throws: PlanningError.requestConflict) { try await repository.requestPlan(approval) }
    } else {
        #expect(await routes.calls > callsBeforeApproval)
    }
}

@Test(arguments: [(PlanningScheduleSource.automatic, false), (.manual, false), (.automatic, true)])
func v52KeepsTheDateWhenHoursAreEstimatedOrAllowTheVisit(source: PlanningScheduleSource, hasRegularHours: Bool) async throws {
    let formatter = ISO8601DateFormatter()
    let now = try #require(formatter.date(from: "2026-11-25T16:00:00+07:00"))
    let lateDeparture = try #require(formatter.date(from: "2026-11-25T19:30:00+07:00"))
    var input = try v41Input(count: 3)
    input.startsAt = source == .manual ? lateDeparture : now
    input.finishBy = try #require(formatter.date(from: "2026-11-25T23:59:59+07:00"))
    input.enginePreferences?.scheduleSource = source
    input.enginePreferences?.usesAutomaticTripDate = source == .automatic
    input.enginePreferences?.timingAnchor = now
    input.enginePreferences?.flexibleDeparture = source == .automatic
    input.enginePreferences?.semanticAssistance = .disabled
    for index in input.places.indices {
        input.places[index].categories = ["museum"]
        input.places[index].sourceID = "apple:synthetic-museum-\(index)"
        input.places[index].visitSeconds = 75 * 60
    }
    let hours = try v52RegularHours(open: 16, close: 24)
    let services = PocketPlanningServices(travel: { _, _, _, _ in .init(seconds: 600, meters: 1000) },
                                          weather: { _, _, _ in throw PlanningError.unavailable },
                                          advise: { _ in throw PlanningError.unavailable },
                                          hours: { _ in hasRegularHours ? hours : .init(status: "unavailable") })
    let repository = try PocketPlanningRepository(services: services, connection: V51TestConnection(), storageURL: nil,
                                                  synthetic: true, jobClock: { now }, currentOrderingOnly: true)
    let job = try await repository.requestPlan(.init(requestID: UUID(), purpose: .firstItinerary, input: input))
    let proposal = try #require(try await finished(repository, id: job.id).result?.proposal)

    #expect(proposal.stops.count == 3)
    #expect(proposal.scheduleAssessment?.unresolved.count { $0.source == EstimatedVisitWindow.source } == (hasRegularHours ? 0 : 3))
    #expect(proposal.rescheduledFromDate == nil)
    #expect(proposal.scheduleAssessment?.dates.count == 1)
    if source == .manual { #expect(proposal.departureAt == lateDeparture) }
}

private func v52RegularHours(open: Int, close: Int, weekdays: Set<Int> = Set(1 ... 7)) throws -> PlanningHoursLookup {
    let intervals = [["startSeconds": open * 3600, "endSeconds": close * 3600]]
    let weekly = (1 ... 7).map { ["weekday": $0, "intervals": weekdays.contains($0) ? intervals : []] as [String: Any] }
    let data = try JSONSerialization.data(withJSONObject: ["placeId": "I52", "timezone": "Asia/Jakarta", "weekly": weekly])
    return .init(status: "available", hours: try JSONDecoder().decode(PlanningRegularHours.self, from: data))
}

@Test(arguments: [false, true], [PlanningScheduleSource.automatic, .manual])
func v52ChecksCombinedOpeningHoursBeforeRouting(closedAtRequest: Bool, source: PlanningScheduleSource) async throws {
    let formatter = ISO8601DateFormatter()
    let now = try #require(formatter.date(from: closedAtRequest ? "2026-11-25T16:00:00+07:00" : "2026-11-25T15:00:00+07:00"))
    let tomorrow = try #require(formatter.date(from: "2026-11-26T09:00:00+07:00"))
    var input = try v41Input(count: 3)
    input.startsAt = now
    input.finishBy = try #require(formatter.date(from: "2026-11-25T23:59:59+07:00"))
    input.enginePreferences?.scheduleSource = source
    input.enginePreferences?.usesAutomaticTripDate = source == .automatic
    input.enginePreferences?.flexibleDeparture = source == .automatic
    input.enginePreferences?.timingAnchor = now
    for index in input.places.indices {
        input.places[index].sourceID = "apple:I52"
        input.places[index].visitSeconds = 30 * 60
    }
    let calls = V41Calls()
    let hours = try v52RegularHours(open: 9, close: 16)
    var services = v41Services(calls, model: false)
    services.hours = { _ in hours }
    let repository = try PocketPlanningRepository(services: services, connection: V51TestConnection(), storageURL: nil,
                                                  synthetic: true, jobClock: { now }, currentOrderingOnly: true)
    let job = try await repository.requestPlan(.init(requestID: UUID(), purpose: .firstItinerary, input: input))
    let result = try await finished(repository, id: job.id)
    let routeDates = await calls.routeDates
    if source == .automatic {
        let proposal = try #require(result.result?.proposal)
        #expect(proposal.stops.count == 3)
        #expect(proposal.rescheduledFromDate != nil)
        #expect(proposal.scheduleAssessment?.dates.count == 2)
        #expect(!routeDates.isEmpty)
        #expect(routeDates.allSatisfy { $0 >= tomorrow })
    } else {
        #expect(result.errorCode == "V41_ACCESS_CONFLICT")
        #expect(result.scheduleAssessment?.dates.count == 1)
        #expect(result.scheduleAssessment?.regularConflicts.map(\.code) == ["itinerary_outside_regular_hours"])
        #expect(result.scheduleAssessment?.conflicts.isEmpty == true)
        #expect(routeDates.isEmpty)
    }
}

@Test func v52ReportsARequiredVisitConflictEvenWithRegularOpeningHours() async throws {
    let now = try #require(ISO8601DateFormatter().date(from: "2026-11-25T16:30:00+07:00"))
    var input = try v41Input()
    input.startsAt = now
    input.finishBy = now.addingTimeInterval(5 * 3600)
    input.preservesPlaceOrder = true
    input.enginePreferences?.orderingMethod = .hybridV52
    input.enginePreferences?.flexibleDeparture = false
    input.places[0].sourceID = "apple:I52"
    input.places[1].sourceID = "apple:I52"
    input.places[1].visitTiming = .required
    input.places[1].preferredAfter = now.addingTimeInterval(5 * 60)
    input.places[1].preferredBefore = now.addingTimeInterval(20 * 60)
    let hours = try v52RegularHours(open: 9, close: 22)
    let calls = V41Calls()
    let planner = V41ItineraryPlanner(services: v41Services(calls, model: false), hours: { _ in hours }, synthetic: true)
    let job = PlanningJob(id: UUID(), status: .running, purpose: .firstItinerary, input: input, createdAt: now)
    do {
        _ = try await planner.plan(job)
        Issue.record("Expected the locked order to miss the required visit time")
    } catch let failure as PlanningScheduleFailure {
        #expect(failure.code == "V51_SCHEDULE_CONFLICT")
        #expect(failure.assessment.regularConflicts.isEmpty)
        #expect(failure.assessment.conflicts == [.init(code: "required_target_missed", placeID: input.places[1].id)])
        #expect(await calls.routeDates.isEmpty)
    }
}

@Test(arguments: [false, true])
func v52PreflightStillRequiresActualTravelForFeasibleOpeningHours(etaAvailable: Bool) async throws {
    let now = try #require(ISO8601DateFormatter().date(from: "2026-11-25T16:30:00+07:00"))
    var input = try v41Input(count: 1)
    input.startsAt = now
    input.finishBy = now.addingTimeInterval(4 * 3600)
    input.enginePreferences?.orderingMethod = .hybridV52
    input.enginePreferences?.scheduleSource = etaAvailable ? .manual : .automatic
    input.enginePreferences?.usesAutomaticTripDate = !etaAvailable
    input.enginePreferences?.timingAnchor = now
    input.enginePreferences?.flexibleDeparture = !etaAvailable
    input.enginePreferences?.maximumWaitMinutes = 0
    input.places[0].sourceID = "apple:I52"
    let hours = try v52RegularHours(open: 17, close: 22)
    let services = PocketPlanningServices(travel: { _, _, _, _ in
        guard etaAvailable else { throw PlanningError.unavailable }
        return .init(seconds: 1800, meters: 1000)
    }, weather: { _, _, _ in throw PlanningError.unavailable }, advise: { _ in throw PlanningError.unavailable })
    let planner = V41ItineraryPlanner(services: services, hours: { _ in hours }, synthetic: true)
    let job = PlanningJob(id: UUID(), status: .running, purpose: .firstItinerary, input: input, createdAt: now)
    do {
        let proposal = try #require(try await planner.plan(job).proposal)
        #expect(etaAvailable)
        #expect(proposal.stops.first?.arrivalAt == now.addingTimeInterval(1800))
        #expect(proposal.stops.first?.travelSeconds == 1800)
    } catch let failure as PlanningScheduleFailure {
        #expect(!etaAvailable)
        #expect(failure.code == "V52_ETA_UNAVAILABLE")
        #expect(failure.assessment.dates.count == 1)
        #expect(failure.assessment.regularConflicts.isEmpty)
    }
}

@Test(arguments: [30, 90])
func coffeeIntentQuestionAppearsOnlyWhenTheLongerVisitCannotFit(windowMinutes: Int) async throws {
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    let finish = start.addingTimeInterval(Double(windowMinutes * 60))
    var cafe = PlanningPlace(id: UUID(), name: "Synthetic café", location: .init(latitude: 0, longitude: 1), visitSeconds: 2700)
    cafe.visitConfirmation = .init(opensAt: start, closesAt: finish, publicAccessConfirmed: true)
    var input = PlanningInput(title: "Coffee visit", origin: .init(latitude: 0, longitude: 0), places: [cafe], preferences: "",
                              startsAt: start, finishBy: finish, timeZone: "UTC", mode: .automobile)
    input.enginePreferences = PlanningPreferences()
    input.enginePreferences?.orderingMethod = .hybridV51
    let stop = PlanningExperiencePlan.Stop(onDevicePlaceID: cafe.id, activity: "Coffee", basis: "unknown", isMain: false,
                                           duration: nil, preferredDayPart: "flexible", reason: "Synthetic suggestion")
    var semantic = PlanningExperiencePlan(onDeviceStops: [stop], order: [cafe.id], date: "2027-01-15", timeZone: "UTC", model: "Synthetic")
    semantic.coffeeVisits = [.init(placeID: cafe.id, style: .unknown)]
    let services = PocketPlanningServices(travel: { _, _, _, _ in .init(seconds: 120, meters: 500) },
                                          weather: { _, _, _ in throw PlanningError.unavailable },
                                          advise: { _ in throw PlanningError.unavailable })
    let planner = V41ItineraryPlanner(services: services, hours: { _ in .init(status: "unavailable") }, synthetic: true)
    let proposal = try await planner.scheduleV51(input, semantic: semantic, routes: .init(input: input, services: services),
                                                 preparedHours: [:], remainingVisit: nil, requestID: nil)
    let scheduled = try #require(proposal.stops.first)
    #expect(scheduled.visitSeconds == 15 * 60)
    #expect(scheduled.visitDurationAdvice?.asksCoffeeIntent == (windowMinutes == 30))
}

private actor V51ForecastCounter {
    private(set) var count = 0
    func forecast(start: Date, end: Date) -> PocketScheduleForecast {
        count += 1
        let source = "Synthetic hourly forecast"
        let firstMinuteEnds = start.addingTimeInterval(60)
        return .init(series: [.init(kind: .uvIndex, source: source, samples: [.init(interval: .init(start: start, end: end), value: 4)])],
                     rain: [.init(interval: .init(start: start, end: firstMinuteEnds), probability: 0.95, source: source),
                            .init(interval: .init(start: firstMinuteEnds, end: end), probability: 0.6, source: source)])
    }
}

private actor HoursRequests {
    var batches: [[String]] = []
    func lookup(_ ids: [String]) -> [String: PlanningHoursLookup] {
        batches.append(ids)
        return Dictionary(uniqueKeysWithValues: ids.map { ($0, .init(status: "unavailable")) })
    }
}

@Test func v52BatchesOpeningHoursOnceAndPreservesTheV51Schedule() async throws {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let finish = now.addingTimeInterval(7200)
    let connection = V51TestConnection()
    let calls = HoursRequests()
    var services = PocketPlanningServices(travel: { _, _, _, _ in .init(seconds: 120, meters: 500) },
                                          weather: { _, _, _ in throw PlanningError.unavailable },
                                          advise: { _ in throw PlanningError.unavailable },
                                          hours: { _ in .init(status: "unavailable") })
    let baseline = try PocketPlanningRepository(services: services, connection: connection, storageURL: nil,
                                                synthetic: true, jobClock: { now })
    services.batchHours = { await calls.lookup($0) }
    services.hours = { _ in
        Issue.record("The batch path must not issue a single lookup")
        return .init(status: "temporary_error")
    }
    let batch = try PocketPlanningRepository(services: services, connection: connection, storageURL: nil,
                                             synthetic: true, jobClock: { now }, currentOrderingOnly: true)
    let places = ["I1", "I2", "I2", "I3"].enumerated().map { index, id in
        var place = PlanningPlace(id: UUID(), name: "Stop \(index)", location: .init(latitude: 0, longitude: Double(index + 1)),
                                  visitSeconds: 600)
        place.durationOverridden = true
        place.sourceID = "apple:" + id
        if id == "I3" { place.visitConfirmation = .init(opensAt: now, closesAt: finish, publicAccessConfirmed: true) }
        return place
    }
    var input = PlanningInput(title: "Hours comparison", origin: .init(latitude: 0, longitude: 0), places: places,
                              preferences: "", startsAt: now, finishBy: finish, timeZone: "UTC", mode: .automobile)
    var preferences = PlanningPreferences()
    preferences.orderingMethod = .hybridV51
    preferences.semanticAssistance = .disabled
    preferences.scheduleSource = .manual
    input.enginePreferences = preferences
    var plans: [PlanProposal] = []
    var batchJob: PlanningJob?
    for repository in [baseline, batch] {
        let job = try await repository.requestPlan(.init(requestID: UUID(), purpose: .firstItinerary, input: input))
        plans.append(try #require(try await finished(repository, id: job.id).result?.proposal))
        batchJob = job
    }
    #expect(plans.map(\.effectiveOrderingMethod) == [.hybridV51, .hybridV52])
    #expect(plans[0].stops == plans[1].stops.map { stop in
        var schedule = stop
        schedule.visitDurationAdvice = nil
        return schedule
    })
    #expect(plans[0].scheduleAssessment == plans[1].scheduleAssessment)
    #expect(await calls.batches == [["I1", "I2"]])

    let edited = try await batch.updateExperienceRoute(jobID: try #require(batchJob).id,
                                                       orderedIDs: Array(plans[1].stops.map(\.id).reversed()),
                                                       departure: nil)
    #expect(edited.result?.proposal?.stops.map(\.id) == Array(plans[1].stops.map(\.id).reversed()))
    #expect(await calls.batches == [["I1", "I2"], ["I1", "I2"]])
}

@Test func v52RepositoryReadsV51AndUpgradesEditsAndActiveReplans() async throws {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let counter = V51ForecastCounter()
    let connection = V51TestConnection()
    var services = PocketPlanningServices(travel: { _, _, _, _ in .init(seconds: 120, meters: 500) },
                                          weather: { _, _, _ in throw PlanningError.invalidResponse },
                                          advise: { _ in throw PlanningError.invalidResponse })
    services.scheduleForecast = { _, start, end, _ in await counter.forecast(start: start, end: end) }
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let storage = directory.appendingPathComponent("trips.json")
    let legacyRepository = try PocketPlanningRepository(services: services, connection: connection, storageURL: storage,
                                                        synthetic: true, jobClock: { now })
    let origin = PlanningPoint(latitude: 0, longitude: 0)
    var outside = PlanningPlace(id: UUID(), name: "Synthetic park", location: .init(latitude: 0, longitude: 1), visitSeconds: 600)
    outside.visitExposure = .sheltered
    outside.durationOverridden = true
    var inside = PlanningPlace(id: UUID(), name: "Synthetic exhibit", location: outside.location, visitSeconds: 600)
    inside.visitExposure = .outdoor
    inside.durationOverridden = true
    let finish = now.addingTimeInterval(7200)
    let access = PlanningVisitConfirmation(opensAt: now, closesAt: finish, publicAccessConfirmed: true)
    outside.visitConfirmation = access
    inside.visitConfirmation = access
    var input = PlanningInput(title: "Synthetic v5.1 repository integration", origin: origin, places: [outside, inside],
                              preferences: "", startsAt: now, finishBy: finish, timeZone: "UTC", mode: .automobile)
    var options = PlanningPreferences()
    options.orderingMethod = .hybridV51
    options.semanticAssistance = .disabled
    options.scheduleSource = .manual
    options.checkInBufferMinutes = 17
    options.extraTravelMinutes = 4
    options.returnToOrigin = true
    input.enginePreferences = options
    let job = try await legacyRepository.requestPlan(.init(requestID: UUID(), purpose: .firstItinerary, input: input))
    let legacy = try #require(try await finished(legacyRepository, id: job.id).result?.proposal)
    let repository = try PocketPlanningRepository(services: services, connection: connection, storageURL: storage,
                                                  synthetic: true, jobClock: { now }, currentOrderingOnly: true)
    #expect(try await repository.planningJob(id: job.id).result?.proposal == legacy)
    #expect(legacy.effectiveOrderingMethod == .hybridV51)
    let archivedV51 = try JSONEncoder().encode(legacy)
    #expect(try JSONDecoder().decode(PlanProposal.self, from: archivedV51) == legacy)
    let order = legacy.stops.map(\.id).reversed()
    let edit = try await repository.updateExperienceRoute(jobID: job.id, orderedIDs: Array(order), departure: nil)
    let updated = try #require(edit.result?.proposal)
    #expect(updated.effectiveOrderingMethod == .hybridV52)
    #expect(updated.stops.map(\.id) == Array(order))
    #expect(updated.scheduleDecision?.outdoor.count == 2)
    #expect(updated.scheduleDecision?.outdoor.flatMap(\.readings).filter { $0.id == "UV index" }.map(\.value) == [4, 4])
    let rain = updated.scheduleDecision?.outdoor.flatMap(\.readings).filter { $0.kind == .precipitationChance }
    #expect(rain?.map(\.value) == [60, 60])
    #expect(rain?.map(\.source) == ["Synthetic hourly forecast", "Synthetic hourly forecast"])
    #expect(await counter.count == 2)
    #expect(updated.input.enginePreferences?.checkInBufferMinutes == 17)
    #expect(updated.input.enginePreferences?.extraTravelMinutes == 4)
    let archived = try JSONEncoder().encode(updated)
    #expect(try JSONDecoder().decode(PlanProposal.self, from: archived) == updated)

    let saved = try await repository.applyProposal(jobID: job.id, expectedRevision: nil, requestID: UUID())
    let prepared = try #require(try await repository.prepareStart(tripID: saved.id, expectedRevision: saved.revision))
    var startEvent = PlanningEvent(requestID: UUID(), expectedRevision: saved.revision, kind: .start)
    startEvent.preparationID = prepared.id
    let active = try await repository.recordEvent(tripID: saved.id, event: startEvent)
    let first = try #require(active.nextStop)
    let arrived = try await repository.recordEvent(tripID: active.id, event: .init(requestID: UUID(), expectedRevision: active.revision,
                                                                                   kind: .arrive, stopID: first.id))
    let replan = try await repository.requestPlan(.init(requestID: UUID(), purpose: .replan, input: arrived.input,
                                                        tripID: arrived.id, baseRevision: arrived.revision))
    let repeated = try #require(try await finished(repository, id: replan.id).result?.proposal)
    #expect(repeated.effectiveOrderingMethod == .hybridV52)
    #expect(repeated.stops.first?.arrivalAt == arrived.currentArrivedAt)
    #expect(repeated.stops.map(\.id) == Array(order))
    #expect(repeated.returnTravelSeconds == 120)
}

@Test(arguments: [nil, PlanningOrderingMethod.hybridV42, .hybridV51])
func currentRepositoryUsesV52ForNewPlansAndReplans(method: PlanningOrderingMethod?) async throws {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let services = PocketPlanningServices(travel: { _, _, _, _ in .init(seconds: 120, meters: 500) },
                                          weather: { _, _, _ in throw PlanningError.unavailable },
                                          advise: { _ in throw PlanningError.unavailable })
    let repository = try PocketPlanningRepository(services: services, connection: V51TestConnection(),
                                                  storageURL: nil, synthetic: true, jobClock: { now },
                                                  currentOrderingOnly: true)
    let origin = PlanningPoint(latitude: 0, longitude: 0)
    var place = PlanningPlace(id: UUID(), name: "Synthetic stop",
                              location: .init(latitude: 0, longitude: 1), visitSeconds: 600)
    place.durationOverridden = true
    var input = PlanningInput(title: "Current ordering", origin: origin, places: [place], preferences: "",
                              startsAt: now, finishBy: now.addingTimeInterval(7200), timeZone: "UTC", mode: .automobile)
    var preferences = PlanningPreferences()
    preferences.orderingMethod = method
    preferences.semanticAssistance = .disabled
    preferences.scheduleSource = .manual
    preferences.checkInBufferMinutes = 19
    input.enginePreferences = preferences

    for purpose in [PlanningPurpose.firstItinerary, .plan] {
        let job = try await repository.requestPlan(.init(requestID: UUID(), purpose: purpose, input: input))
        let proposal = try #require(try await finished(repository, id: job.id).result?.proposal)
        #expect(proposal.effectiveOrderingMethod == .hybridV52)
        #expect(proposal.input.enginePreferences?.checkInBufferMinutes == 19)
        let trip = try await repository.applyProposal(jobID: job.id, expectedRevision: nil, requestID: UUID())
        let replan = try await repository.requestPlan(.init(requestID: UUID(), purpose: .replan, input: trip.input,
                                                            tripID: trip.id, baseRevision: trip.revision))
        let revised = try #require(try await finished(repository, id: replan.id).result?.proposal)
        #expect(revised.effectiveOrderingMethod == .hybridV52)
        #expect(revised.input.enginePreferences?.checkInBufferMinutes == 19)
    }
}

@Test func savedV51DateRevisionPersistsOnlyAfterSuccessfulApply() async throws {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let canceledDate = now.addingTimeInterval(86_400)
    let newDate = now.addingTimeInterval(172_800)
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let storage = directory.appendingPathComponent("trips.json")
    let connection = V51TestConnection()
    let services = PocketPlanningServices(travel: { _, _, departure, _ in
        if departure >= canceledDate, departure < newDate {
            try await Task.sleep(for: .seconds(30))
        }
        return .init(seconds: 120, meters: 500)
    }, weather: { _, _, _ in throw PlanningError.unavailable },
    advise: { _ in throw PlanningError.unavailable })
    let legacy = try PocketPlanningRepository(services: services, connection: connection, storageURL: storage,
                                              synthetic: true, jobClock: { now })
    func openCurrent() throws -> PocketPlanningRepository {
        try PocketPlanningRepository(services: services, connection: connection, storageURL: storage,
                                     synthetic: true, jobClock: { now }, currentOrderingOnly: true)
    }
    var place = PlanningPlace(id: UUID(), name: "Synthetic stop",
                              location: .init(latitude: 0, longitude: 1), visitSeconds: 600)
    place.durationOverridden = true
    var input = PlanningInput(title: "Saved v5.1", origin: .init(latitude: 0, longitude: 0), places: [place],
                              preferences: "", startsAt: now, finishBy: now.addingTimeInterval(7200), timeZone: "UTC",
                              mode: .automobile)
    var preferences = PlanningPreferences()
    preferences.orderingMethod = .hybridV51
    preferences.semanticAssistance = .disabled
    preferences.scheduleSource = .manual
    input.enginePreferences = preferences
    let initial = try await legacy.requestPlan(.init(requestID: UUID(), purpose: .firstItinerary, input: input))
    _ = try #require(try await finished(legacy, id: initial.id).result?.proposal)
    let saved = try await legacy.applyProposal(jobID: initial.id, expectedRevision: nil, requestID: UUID())
    #expect(saved.plan.effectiveOrderingMethod == .hybridV51)

    let repository = try openCurrent()
    func request(_ departure: Date) -> PlanningRequest {
        var request = PlanningRequest(requestID: UUID(), purpose: .replan, input: saved.input,
                                      tripID: saved.id, baseRevision: saved.revision)
        request.replacementDeparture = departure
        return request
    }
    await #expect(throws: PlanningError.invalidInput) {
        try await repository.requestPlan(request(input.finishBy))
    }
    #expect(try await openCurrent().personalTrips() == [saved])

    let canceled = try await repository.requestPlan(request(canceledDate))
    try await repository.cancelPlanning(id: canceled.id)
    #expect(try await openCurrent().personalTrips() == [saved])

    let revised = try await repository.requestPlan(request(newDate))
    let proposal = try #require(try await finished(repository, id: revised.id).result?.proposal)
    #expect(proposal.effectiveOrderingMethod == .hybridV52)
    #expect(proposal.departureAt == newDate)
    #expect(try await openCurrent().personalTrips() == [saved])
    let applied = try await repository.applyProposal(jobID: revised.id, expectedRevision: saved.revision, requestID: UUID())
    #expect(applied.revision == saved.revision + 1)
    #expect(applied.plan.stops.map(\.id) == saved.plan.stops.map(\.id))
    #expect(try await openCurrent().personalTrips() == [applied])
}

@Test func openMeteoScheduleForecastUsesPrecedingHoursAndPreservesGaps() throws {
    let data = Data("""
    {"hourly_units":{"time":"unixtime","apparent_temperature":"°C","uv_index":"","direct_radiation":"W/m²","precipitation_probability":"%"},
     "hourly":{"time":[3600,7200],"apparent_temperature":[28,30],"uv_index":[5,null],
               "direct_radiation":[240,280],"precipitation_probability":[30,60]}}
    """.utf8)
    let forecast = try PocketOpenMeteoScheduleForecast.decode(data)
    let temperature = try #require(forecast.series.first { $0.kind == .apparentTemperature })
    let uv = try #require(forecast.series.first { $0.kind == .uvIndex })
    let radiation = try #require(forecast.series.first { $0.kind == .directIrradiance })
    #expect(temperature.samples.first?.interval.start == Date(timeIntervalSince1970: 3600))
    #expect(uv.samples.count == 1)
    #expect(uv.samples.first?.interval.start == Date(timeIntervalSince1970: 0))
    #expect(radiation.samples.last?.interval.end == Date(timeIntervalSince1970: 7200))
    #expect(forecast.rain.map(\.probability) == [0.3, 0.6])
}

private actor V51RouteProbe {
    private(set) var dates: [Date] = []
    let pauseFirst: Bool

    init(pauseFirst: Bool = false) { self.pauseFirst = pauseFirst }

    func record(_ at: Date) async throws {
        dates.append(at)
        if pauseFirst, dates.count == 1 { try await Task.sleep(for: .seconds(30)) }
    }
}

private func v52MuseumInput(flexible: Bool, wait: Int = 10) -> PlanningInput {
    func at(_ minute: Int) -> Date { Date(timeIntervalSince1970: Double(minute * 60)) }
    var museum = PlanningPlace(id: UUID(), name: "Synthetic museum", location: .init(latitude: 0, longitude: 0.002),
                               visitSeconds: 1800)
    museum.durationOverridden = true
    museum.visitConfirmation = .init(opensAt: at(540), closesAt: at(570), publicAccessConfirmed: true)
    var input = PlanningInput(title: "Synthetic morning visit", origin: .init(latitude: 0, longitude: 0),
                              places: [museum], preferences: "", startsAt: at(516), finishBy: at(580),
                              timeZone: "UTC", mode: .automobile, firstPlaceID: museum.id, preservesPlaceOrder: true)
    var options = PlanningPreferences()
    options.orderingMethod = .hybridV52
    options.scheduleSource = .manual
    options.semanticAssistance = .disabled
    options.flexibleDeparture = flexible
    options.returnToOrigin = true
    options.maximumWaitMinutes = wait
    input.enginePreferences = options
    return input
}

@Test func v52RecoversAnUntestedDepartureAndChecksTheRequiredReturn() async throws {
    let input = v52MuseumInput(flexible: true)
    let probe = V51RouteProbe()
    let services = PocketPlanningServices(travel: { from, _, date, _ in
        try await probe.record(date)
        return .init(seconds: from.longitude == 0 ? 720 : 600, meters: 500)
    }, weather: { _, _, _ in throw PlanningError.unavailable }, advise: { _ in throw PlanningError.unavailable })
    let repository = try PocketPlanningRepository(services: services, connection: V51TestConnection(), storageURL: nil,
                                                  synthetic: true, jobClock: { input.startsAt }, currentOrderingOnly: true)
    let job = try await repository.requestPlan(.init(requestID: UUID(), purpose: .firstItinerary, input: input))
    let finishedJob = try await finished(repository, id: job.id)
    let plan = try #require(finishedJob.result?.proposal)
    #expect(plan.stops.map(\.id) == input.places.map(\.id))
    #expect(plan.input.enginePreferences?.maximumWaitMinutes == 10)
    #expect(plan.departureAt == Date(timeIntervalSince1970: 523 * 60))
    #expect(plan.returnTravelSeconds == 600)
    #expect(plan.finishesAt == input.finishBy)
    #expect(await probe.dates.map { Int($0.timeIntervalSince1970 / 60) } == [516, 540, 541, 546, 523, 570])
}

@Test func v52RetainsFixedDepartureAndSkipsRecoveryAfterSuccess() async throws {
    let planner = PlannerV51 { from, _, _, _ in .init(seconds: from.longitude == 0 ? 720 : 600) }
    let fixed = v52MuseumInput(flexible: false)
    let conflict = try await planner.plan(.init(trip: fixed))
    #expect(conflict.status == .conflicts)
    #expect(conflict.routeQuotes == 1)

    var flexible = v52MuseumInput(flexible: true, wait: 15)
    let current = try await planner.plan(.init(trip: flexible))
    flexible.enginePreferences?.orderingMethod = .hybridV51
    let baseline = try await planner.plan(.init(trip: flexible))
    #expect(current.status == .scheduled)
    #expect(current.schedule?.departsAt == baseline.schedule?.departsAt)
    #expect(current.routeQuotes == baseline.routeQuotes)
}

@Test func v52RejectsRecoveryWhenTheExactETAChanges() async throws {
    let input = v52MuseumInput(flexible: true)
    let probe = V51RouteProbe()
    let planner = PlannerV51 { _, _, date, _ in
        try await probe.record(date)
        let minute = Int(date.timeIntervalSince1970 / 60)
        return .init(seconds: minute == 523 ? 1800 : 720)
    }
    let result = try await planner.plan(.init(trip: input))
    #expect(result.status == .incomplete)
    #expect(result.schedule == nil)
    #expect(await probe.dates.map { Int($0.timeIntervalSince1970 / 60) } == [516, 540, 541, 546, 523])
}

@Test(arguments: [true, false])
func v52DistinguishesMissingETAFromTheQuoteLimit(hasETA: Bool) async throws {
    let input = v52MuseumInput(flexible: true)
    let probe = V51RouteProbe()
    let services = PocketPlanningServices(travel: { _, _, departure, _ in
        try await probe.record(departure)
        guard hasETA else { throw URLError(.timedOut) }
        return .init(seconds: 720, meters: 500)
    }, weather: { _, _, _ in throw PlanningError.unavailable }, advise: { _ in throw PlanningError.unavailable })
    let planner = V41ItineraryPlanner(services: services, hours: { _ in .init(status: "unavailable") },
                                      quoteLimit: hasETA ? 4 : 72, synthetic: true)
    let job = PlanningJob(id: UUID(), status: .running, purpose: .firstItinerary, input: input, createdAt: input.startsAt)
    do {
        _ = try await planner.plan(job)
        Issue.record("Expected an incomplete schedule")
    } catch let failure as PlanningScheduleFailure {
        #expect(failure.code == (hasETA ? "V41_BUDGET_REACHED" : "V52_ETA_UNAVAILABLE"))
        #expect(failure.errorDescription?.contains(hasETA ? "route-checking limit" : "couldn’t provide travel times") == true)
        #expect(failure.assessment.stopReason == (hasETA ? "quote_budget_exhausted" : "unavailableETA"))
        #expect(failure.assessment.conflicts.isEmpty)
        #expect(await probe.dates.count == 4)
    }
}

@Test func v52KeepsAnUnverifiedDateWhenTheFinalDateIsClosed() async throws {
    var input = try v41Input(count: 1)
    input.enginePreferences?.orderingMethod = .hybridV52
    input.enginePreferences?.scheduleSource = .timingAnswer
    input.enginePreferences?.tripTiming = .inAFewDays
    input.places[0].sourceID = "apple:I52"
    let hours = try v52RegularHours(open: 9, close: 18, weekdays: [4])
    let services = PocketPlanningServices(travel: { _, _, _, _ in throw URLError(.timedOut) },
                                          weather: { _, _, _ in throw PlanningError.unavailable },
                                          advise: { _ in throw PlanningError.unavailable })
    let planner = V41ItineraryPlanner(services: services, hours: { _ in hours }, synthetic: true)
    let job = PlanningJob(id: UUID(), status: .running, purpose: .firstItinerary, input: input, createdAt: input.startsAt)
    do {
        _ = try await planner.plan(job)
        Issue.record("The available date still needs a verified ETA")
    } catch let failure as PlanningScheduleFailure {
        #expect(failure.code == "V52_ETA_UNAVAILABLE")
        #expect(failure.assessment.dates.count == 2)
        #expect(failure.assessment.dates.first?.stopReason == "unavailableETA")
        #expect(failure.assessment.dates.last?.stopReason != "unavailableETA")
    }
}

private actor GoTripRouteProbe {
    enum Failure: Sendable { case timeout, throttle, noRoute }

    struct Call: Equatable, Sendable {
        let from: Coordinate
        let to: Coordinate
        let departure: Date
    }

    private var failures: [Failure]?
    private var returnSeconds = 360.0
    private(set) var calls: [Call] = []

    func failReturn(_ failures: [Failure], returningIn seconds: Double = 360) {
        self.failures = failures
        returnSeconds = seconds
    }

    func quote(from: Coordinate, to: Coordinate, departure: Date) throws -> LegQuote {
        if failures != nil { calls.append(.init(from: from, to: to, departure: departure)) }
        if to == .init(latitude: -6.243464, longitude: 106.798194) {
            if let failure = failures?.first {
                failures?.removeFirst()
                switch failure {
                case .timeout: throw URLError(.timedOut)
                case .throttle: throw TravelQuoteError.throttled
                case .noRoute: throw URLError(.resourceUnavailable)
                }
            }
            return .init(seconds: returnSeconds, meters: 1000)
        }
        let minutes = from.longitude == 106.80244 && to.longitude == 106.8326 ? 25.0 : 6.0
        return .init(seconds: minutes * 60, meters: 1000)
    }
}

private func savedBlokMGoTrip(stopCount: Int, storageURL: URL? = nil) async throws -> (PocketPlanningRepository, PersonalPlanningTrip, TestClock, GoTripRouteProbe) {
    let starts = try #require(ISO8601DateFormatter().date(from: "2026-11-26T01:48:00Z"))
    let finish = starts.addingTimeInterval((stopCount == 1 ? 52.0 : 277.0) * 60)
    let origin = PlanningPoint(latitude: -6.243464, longitude: 106.798194)
    let venues: [(name: String, lat: Double, lon: Double, minutes: Int)] = [
        ("Museum Polri", -6.239306, 106.802778, 30),
        ("Gelora Bung Karno", -6.21865, 106.80244, 25),
        ("Taman Suropati", -6.1994, 106.8326, 15),
        ("M Bloc Space", -6.2408, 106.7996, 20),
        ("Taman Literasi", -6.2445, 106.7989, 20),
        ("Taman Bendera Pusaka", -6.245659, 106.793781, 25),
    ]
    let places = venues.prefix(stopCount).enumerated().map { index, venue in
        var place = PlanningPlace(id: UUID(), name: venue.name, location: .init(latitude: venue.lat, longitude: venue.lon),
                                  visitSeconds: venue.minutes * 60)
        place.durationOverridden = true
        let opens = starts.addingTimeInterval((index == 0 ? 12.0 : index == 2 ? 102.0 : 0.0) * 60)
        let closes = index == 0 ? opens.addingTimeInterval(1800) : finish
        place.visitConfirmation = .init(opensAt: opens, closesAt: closes, publicAccessConfirmed: true)
        if index == 2 { place.visitConfirmation?.lastEntryAt = starts.addingTimeInterval(147 * 60) }
        return place
    }
    var input = PlanningInput(title: "Synthetic Blok M start verification", origin: origin, places: places, preferences: "",
                              startsAt: starts, finishBy: finish, timeZone: "Asia/Jakarta", mode: .automobile,
                              firstPlaceID: places.first?.id, preservesPlaceOrder: true)
    input.originName = "Blok M MRT"
    var preferences = PlanningPreferences()
    preferences.orderingMethod = .hybridV52
    preferences.scheduleSource = .manual
    preferences.semanticAssistance = .disabled
    preferences.returnToOrigin = true
    preferences.maximumWaitMinutes = 10
    input.enginePreferences = preferences
    let clock = TestClock()
    clock.advance(starts.timeIntervalSince(clock.now()))
    let probe = GoTripRouteProbe()
    let services = PocketPlanningServices(travel: { from, to, departure, _ in try await probe.quote(from: from, to: to, departure: departure) },
                                          weather: { _, _, _ in throw PlanningError.unavailable },
                                          advise: { _ in throw PlanningError.unavailable })
    let repository = try PocketPlanningRepository(services: services, connection: V51TestConnection(), storageURL: storageURL,
                                                  synthetic: true, jobClock: clock.now, currentOrderingOnly: true)
    let job = try await repository.requestPlan(.init(requestID: UUID(), purpose: .firstItinerary, input: input))
    let result = try await finished(repository, id: job.id)
    _ = try #require(result.result?.proposal)
    let saved = try await repository.applyProposal(jobID: job.id, expectedRevision: nil, requestID: UUID())
    clock.advance(60)
    return (repository, saved, clock, probe)
}

@Test func goTripKeepsTheSelectedStartingPointNameAfterReopening() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let storage = directory.appendingPathComponent("trips.json")
    let (_, saved, _, _) = try await savedBlokMGoTrip(stopCount: 1, storageURL: storage)
    let services = PocketPlanningServices(travel: { _, _, _, _ in throw PlanningError.unavailable },
                                          weather: { _, _, _ in throw PlanningError.unavailable },
                                          advise: { _ in throw PlanningError.unavailable })
    let reopened = try PocketPlanningRepository(services: services, connection: V51TestConnection(), storageURL: storage, synthetic: true)
    let trip = try #require(await reopened.personalTrips().first)
    #expect(trip.id == saved.id)
    #expect(trip.input.originName == "Blok M MRT")
    #expect(trip.plan.input.originName == "Blok M MRT")

    var legacy = trip.plan.input
    legacy.originName = nil
    #expect(try JSONDecoder().decode(PlanningInput.self, from: JSONEncoder().encode(legacy)).originName == nil)

    var changed = trip.plan.input
    changed.origin = try #require(trip.plan.stops.first?.location)
    #expect(changed.originName == nil)
}

@Test(arguments: [1, 6])
func goTripRetriesOnlyTheFailedReturnLegInBlokM(stopCount: Int) async throws {
    let (repository, trip, _, probe) = try await savedBlokMGoTrip(stopCount: stopCount)
    await probe.failReturn([.timeout])

    let prepared = try #require(try await repository.prepareStart(tripID: trip.id, expectedRevision: trip.revision))
    let calls = await probe.calls
    #expect(!prepared.requiresConfirmation)
    #expect(prepared.proposal.departureAt != trip.plan.departureAt)
    #expect(calls.count == stopCount + 2)
    #expect(calls.suffix(2).first == calls.last)
    #expect(prepared.proposal.stops.map(\.id) == trip.plan.stops.map(\.id))
    #expect(prepared.proposal.returnTravelSeconds == 360)
    let finish = try #require(prepared.proposal.finishesAt)
    #expect(finish <= trip.input.finishBy)
    #expect(prepared.proposal.stops.first?.departureAt == trip.input.startsAt.addingTimeInterval(42 * 60))
    var event = PlanningEvent(requestID: UUID(), expectedRevision: trip.revision, kind: .start)
    event.preparationID = prepared.id
    let active = try await repository.recordEvent(tripID: trip.id, event: event)
    #expect(active.status == .active)
}

@Test(arguments: [5, 6])
func goTripConfirmsWhenTheDepartureShiftExceedsFiveMinutes(departureShiftMinutes: Int) async throws {
    let (repository, trip, clock, _) = try await savedBlokMGoTrip(stopCount: 1)
    clock.advance(Double(departureShiftMinutes - 1) * 60)
    let prepared = try #require(try await repository.prepareStart(tripID: trip.id, expectedRevision: trip.revision))
    #expect(prepared.requiresConfirmation == (departureShiftMinutes > 5))
    #expect(prepared.proposal.stops.first?.visitStartsAt == trip.plan.stops.first?.visitStartsAt)
    #expect(prepared.proposal.finishesAt == trip.plan.finishesAt)
}

@Test func goTripConfirmsImportantChangesEvenWithASmallDepartureShift() async throws {
    let (_, trip, _, _) = try await savedBlokMGoTrip(stopCount: 6)
    var saved = trip.plan
    let first = try #require(saved.stops.first)
    let departure = try #require(saved.departureAt)
    let finish = try #require(saved.finishesAt)
    saved.scheduleDecision = .init(checkIns: [.init(id: first.id, buffer: 10, target: 10, shortfall: 0)],
                                   outdoor: [], extraTravel: 0, alternative: [])
    var smallShift = saved
    smallShift.departureAt = departure.addingTimeInterval(60)
    #expect(!smallShift.requiresStartConfirmation(comparedTo: saved))

    var reordered = smallShift
    reordered.stops.swapAt(0, 1)
    #expect(reordered.requiresStartConfirmation(comparedTo: saved))
    var movedVisit = smallShift
    movedVisit.stops[0].visitStartsAt = try #require(first.visitStartsAt).addingTimeInterval(360)
    #expect(movedVisit.requiresStartConfirmation(comparedTo: saved))
    var shorterVisit = smallShift
    shorterVisit.stops[0].visitSeconds -= 60
    #expect(shorterVisit.requiresStartConfirmation(comparedTo: saved))
    var laterReturn = smallShift
    laterReturn.finishesAt = finish.addingTimeInterval(360)
    #expect(laterReturn.requiresStartConfirmation(comparedTo: saved))
    var differentEndpoint = smallShift
    differentEndpoint.input.enginePreferences?.endPoint = first.location
    #expect(differentEndpoint.requiresStartConfirmation(comparedTo: saved))
    var worseCheckIn = smallShift
    worseCheckIn.scheduleDecision = .init(checkIns: [.init(id: first.id, buffer: 9, target: 10, shortfall: 1)],
                                          outdoor: [], extraTravel: 0, alternative: [])
    #expect(worseCheckIn.requiresStartConfirmation(comparedTo: saved))
}

@Test(arguments: [false, true])
func goTripTryAgainReusesOnlyMatchingDepartureMinutes(advanceMinute: Bool) async throws {
    let (repository, trip, clock, probe) = try await savedBlokMGoTrip(stopCount: 6)
    await probe.failReturn([.timeout, .timeout])
    do {
        _ = try await repository.prepareStart(tripID: trip.id, expectedRevision: trip.revision)
        Issue.record("The return ETA stayed unavailable through the single automatic retry")
    } catch let failure as PlanningScheduleFailure {
        #expect(failure.code == "V52_ETA_UNAVAILABLE")
    }
    let firstAttempt = await probe.calls
    #expect(firstAttempt.count == 8)
    if advanceMinute { clock.advance(60) }

    let prepared = try #require(try await repository.prepareStart(tripID: trip.id, expectedRevision: trip.revision))
    let resumed = Array(await probe.calls.dropFirst(firstAttempt.count))
    #expect(resumed.count == (advanceMinute ? 2 : 1))
    #expect(resumed.last == firstAttempt.last)
    if advanceMinute {
        #expect(resumed.first?.departure == firstAttempt.first?.departure.addingTimeInterval(60))
    }
    #expect(prepared.proposal.returnTravelSeconds == 360)
}

@Test(arguments: [GoTripRouteProbe.Failure.throttle, .noRoute])
private func goTripDoesNotAutomaticallyRetryAnUnclassifiedOrThrottledReturn(failure: GoTripRouteProbe.Failure) async throws {
    let (repository, trip, _, probe) = try await savedBlokMGoTrip(stopCount: 6)
    await probe.failReturn([failure])
    do {
        _ = try await repository.prepareStart(tripID: trip.id, expectedRevision: trip.revision)
        Issue.record("The return ETA was unavailable")
    } catch let result as PlanningScheduleFailure {
        #expect(result.code == (failure == .throttle ? "PROVIDER_RATE_LIMITED" : "V52_ETA_UNAVAILABLE"))
    }
    #expect(await probe.calls.count == 7)
}

@Test func goTripRechecksTheDeadlineAfterRecoveringTheReturnETA() async throws {
    let (repository, trip, _, probe) = try await savedBlokMGoTrip(stopCount: 1)
    await probe.failReturn([.timeout], returningIn: 11 * 60)
    do {
        _ = try await repository.prepareStart(tripID: trip.id, expectedRevision: trip.revision)
        Issue.record("The recovered return ETA misses the 09:40 deadline")
    } catch let result as PlanningScheduleFailure {
        #expect(result.code == "V4_WINDOW_TOO_SHORT")
        let conflict = try #require(result.endpointDeadlineConflict)
        #expect(conflict.fromPlaceID == trip.plan.stops.last?.id)
        #expect(conflict.estimatedArrival == trip.input.startsAt.addingTimeInterval(53 * 60))
        #expect(conflict.deadline == trip.input.finishBy)
    }
    #expect(await probe.calls.count == 3)
    await #expect(throws: PlanningError.expired) {
        try await repository.recordEvent(tripID: trip.id, event: .init(requestID: UUID(), expectedRevision: trip.revision, kind: .start))
    }
}

@Test func v51RepositorySharesBudgetAcrossDatesAndRestarts() async throws {
    let repositoryFile = FileManager.default.temporaryDirectory.appendingPathComponent("v51-\(UUID()).json")
    defer { try? FileManager.default.removeItem(at: repositoryFile) }
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let probe = V51RouteProbe(pauseFirst: true)
    let connection = V51TestConnection()
    let services = PocketPlanningServices(travel: { _, _, date, _ in
        try await probe.record(date)
        return .init(seconds: 120, meters: 500)
    }, weather: { _, _, _ in throw PlanningError.unavailable }, advise: { _ in throw PlanningError.invalidResponse })
    func repository() throws -> PocketPlanningRepository {
        try .init(services: services, connection: connection, storageURL: repositoryFile, synthetic: true, jobClock: { now })
    }
    let first = try repository()
    var input = PlanningInput(title: "Synthetic date budget", origin: .init(latitude: 0, longitude: 0), places: [
        .init(id: UUID(), name: "Synthetic stop", location: .init(latitude: 0, longitude: 1), visitSeconds: 600)
    ], preferences: "", startsAt: now, finishBy: now.addingTimeInterval(3600), timeZone: "UTC", mode: .automobile)
    input.enginePreferences = .init()
    input.enginePreferences?.orderingMethod = .hybridV51
    input.enginePreferences?.semanticAssistance = .disabled
    input.enginePreferences?.tripTiming = .bestDay
    input.enginePreferences?.scheduleSource = .timingAnswer
    input.enginePreferences?.flexibleDeparture = true
    input.enginePreferences?.returnToOrigin = true
    let command = PlanningRequest(requestID: UUID(), purpose: .firstItinerary, input: input)
    let job = try await first.requestPlan(command)
    for _ in 0 ..< 100 {
        if await !probe.dates.isEmpty { break }
        try await Task.sleep(for: .milliseconds(5))
    }
    #expect(await probe.dates.count == 1)
    await first.suspendOrdering()
    let reopened = try repository()
    let resumed = try await reopened.requestPlan(command)
    #expect(resumed.id == job.id)
    let completed = try await finished(reopened, id: job.id)
    let timestamps = await probe.dates
    #expect(completed.status == .succeeded)
    #expect(timestamps.count <= 72)
    #expect(completed.scheduleAssessment?.routeCalls == timestamps.count)
    #expect(completed.scheduleAssessment?.dates.count ?? 0 >= 2)
}

@Test func v51CancellationRetainsReservedRouteCount() async throws {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let probe = V51RouteProbe(pauseFirst: true)
    let connection = V51TestConnection()
    let services = PocketPlanningServices(travel: { _, _, date, _ in
        try await probe.record(date)
        return .init(seconds: 120, meters: 500)
    }, weather: { _, _, _ in throw PlanningError.unavailable }, advise: { _ in throw PlanningError.invalidResponse })
    let repository = try PocketPlanningRepository(services: services, connection: connection, storageURL: nil,
                                                  synthetic: true, jobClock: { now })
    var input = PlanningInput(title: "Synthetic cancellation", origin: .init(latitude: 0, longitude: 0), places: [
        .init(id: UUID(), name: "Synthetic stop", location: .init(latitude: 0, longitude: 1), visitSeconds: 600)
    ], preferences: "", startsAt: now, finishBy: now.addingTimeInterval(3600), timeZone: "UTC", mode: .automobile)
    input.enginePreferences = .init()
    input.enginePreferences?.orderingMethod = .hybridV51
    input.enginePreferences?.semanticAssistance = .disabled
    let job = try await repository.requestPlan(.init(requestID: UUID(), purpose: .firstItinerary, input: input))
    for _ in 0 ..< 100 {
        if await !probe.dates.isEmpty { break }
        try await Task.sleep(for: .milliseconds(5))
    }
    try await repository.cancelPlanning(id: job.id)
    let cancelled = try await repository.planningJob(id: job.id)
    #expect(cancelled.status == .failed && cancelled.errorCode == "PLANNING_CANCELLED")
    #expect(cancelled.scheduleAssessment?.routeCalls == 1)
    #expect(await probe.dates.count == 1)
}
