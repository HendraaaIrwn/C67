import SwiftUI
import UIKit
import MapKit
import C67Domain

struct TripProgressView: View {
    let tripID: UUID
    let presenter: PlanningPresenter
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @State private var navigation = TripNavigation()

    var body: some View {
        if let trip = presenter.trips.first(where: { $0.id == tripID }) {
            let issue = presenter.issues[.activity(tripID)]
            let target = trip.pendingEndpoint ?? trip.nextStop?.location
            let startingPoint = trip.completedStopIDs.isEmpty && trip.pendingEndpoint == nil ? trip.input.origin : nil
            TripProgressContent(trip: trip, isBusy: presenter.isBusy, error: issue?.message,
                                recovery: recovery(for: issue, trip: trip),
                                route: navigation.route, plannedRoute: navigation.plannedRoute, startingPoint: startingPoint,
                                hasCurrentLocation: navigation.location != nil, locationError: navigation.error,
                                locationPermissionDenied: navigation.permissionDenied,
                                openDirections: {
                                    startNavigation(trip, target: target, startingPoint: startingPoint)
                                }, openSettings: {
                                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                                }, openMaps: {
                                    if let endpoint = trip.pendingEndpoint {
                                        let name = trip.plan.input.enginePreferences?.endPointName ?? String(localized: "Trip end point")
                                        PlanningDirections.open(endpoint, name: name, mode: trip.input.mode)
                                    } else if let next = trip.nextStop {
                                        PlanningDirections.open(next, mode: trip.input.mode)
                                    }
                                }, arrive: { send(.arrive, trip: trip) },
                                arriveAtEndpoint: { send(.arriveAtEndpoint, trip: trip) },
                                completeVisit: { send(.completeStop, trip: trip) }, returnToTrip: { dismiss() })
                .refreshable { await presenter.load(resumesJobs: false) }
                .task(id: trip.revision) { startNavigation(trip, target: target, startingPoint: startingPoint) }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { startNavigation(trip, target: target, startingPoint: startingPoint) }
                    else { navigation.stop() }
                }
                .onChange(of: navigation.arrivalReady) { _, ready in
                    if ready { confirmAutomaticArrival(trip, target: target) }
                }
                .onChange(of: presenter.isBusy) { _, busy in
                    if !busy { confirmAutomaticArrival(trip, target: target) }
                }
                .onDisappear { navigation.stop() }
        } else {
            ContentUnavailableView {
                Label("Trip unavailable", systemImage: "map")
            } description: {
                Text("Return to Home and refresh your trips.")
            } actions: {
                Button("Go back") { dismiss() }
            }
        }
    }

    private func startNavigation(_ trip: PersonalPlanningTrip, target: PlanningPoint?, startingPoint: PlanningPoint?) {
        guard scenePhase == .active, trip.status == .active, trip.currentStopID == nil, let target else {
            navigation.stop()
            return
        }
        navigation.start(to: target, mode: trip.input.mode, plannedOrigin: trip.synthetic ? nil : startingPoint)
    }

    private func confirmAutomaticArrival(_ trip: PersonalPlanningTrip, target: PlanningPoint?) {
        guard scenePhase == .active, !presenter.isBusy, let target,
              navigation.canConfirmArrival(at: target),
              presenter.trips.first(where: { $0.id == trip.id })?.revision == trip.revision else { return }
        let kind: PlanningEventKind = trip.pendingEndpoint == nil ? .arrive : .arriveAtEndpoint
        if kind == .arrive, !presenter.claimAutomaticArrival(for: trip) { return }
        navigation.stop()
        send(kind, trip: trip)
    }

    private func recovery(for issue: PresentationIssue?, trip: PersonalPlanningTrip) -> RecoveryNotice.Action? {
        guard let issue else { return nil }
        if issue.recovery == .refreshTrip {
            return .init(title: "Refresh trip") { Task { await presenter.load(resumesJobs: false) } }
        }
        guard issue.recovery == .retry, issue.stopID == trip.nextStop?.id,
              case .event(let kind, _) = issue.operation else { return nil }
        return .init(title: "Try again") { send(kind, trip: trip) }
    }

    private func send(_ kind: PlanningEventKind, trip: PersonalPlanningTrip) {
        guard !presenter.isBusy else { return }
        Task { await presenter.event(kind, trip: trip) }
    }
}

struct TripReturnRouteView: View {
    let trip: PersonalPlanningTrip
    let isDesignPreview: Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @State private var navigation = TripNavigation()
    @State private var mapPosition: MapCameraPosition = .automatic

    private var lastStop: ScheduledPlanningStop? {
        trip.completedStopIDs.last.flatMap { id in trip.plan.stops.first { $0.id == id } }
    }

    private var route: MKRoute? { navigation.route ?? navigation.plannedRoute }
    private var instruction: (distance: String, instruction: String)? {
        if navigation.arrivalReady { return nil }
        if isDesignPreview { return ("80 m", String(localized: "Turn right onto Jalan Cikini Raya")) }
        guard let step = route?.steps.first(where: { $0.distance > 0 && !$0.instructions.isEmpty }) else { return nil }
        return (TripProgressContent.distance(step.distance), step.instructions)
    }

    private var usesLastStop: Bool {
        lastStop != nil && (isDesignPreview || (navigation.route == nil && (navigation.location == nil || navigation.plannedRoute != nil)))
    }

    private var routeLine: MKPolyline? {
        if let route { return route.polyline }
        guard isDesignPreview, let lastStop else { return nil }
        let coordinates = [coordinate(lastStop.location), coordinate(trip.input.origin)]
        return MKPolyline(coordinates: coordinates, count: coordinates.count)
    }

    var body: some View {
        GeometryReader { geometry in
            Map(position: $mapPosition) {
                Annotation("Trip starting point", coordinate: coordinate(trip.input.origin)) {
                    Image(systemName: "flag.fill")
                        .font(.headline)
                        .foregroundStyle(AppColor.accent)
                        .padding(8)
                        .background(AppColor.surface, in: .circle)
                        .accessibilityLabel("Trip starting point")
                }
                if usesLastStop, let lastStop {
                    Marker(lastStop.name, coordinate: coordinate(lastStop.location))
                }
                if navigation.location != nil { UserAnnotation() }
                if let routeLine { TripRouteLine(polyline: routeLine) }
            }
            .accessibilityIdentifier("tripReturnMap")
            .onChange(of: route, initial: true) { _, _ in focusRoute() }
            .overlay(alignment: .trailing) {
                if routeLine != nil { TripRouteFocusButton(action: focusRoute) }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                let instruction = instruction
                TripRouteBanner(symbol: navigation.arrivalReady ? "checkmark" : instruction == nil ? "flag.fill" : "arrow.up.forward",
                                heading: navigation.arrivalReady ? "You’ve arrived" : "Returning to starting point",
                                destination: String(localized: "Starting point"), instruction: instruction,
                                routeContext: usesLastStop ? "Route from last visited stop" : "Route preview")
                    .accessibilityIdentifier("tripReturnBanner")
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                TripRoutePanel(availableHeight: geometry.size.height) {
                    routeDetails
                }
                .accessibilityIdentifier("tripReturnPanel")
            }
        }
        .background(AppColor.canvas)
        .task(id: scenePhase == .background) {
            if scenePhase == .background { navigation.stop() }
            else if !isDesignPreview { startRoute() }
        }
        .onDisappear { navigation.stop() }
    }

    private var routeDetails: some View {
        VStack(alignment: .leading, spacing: 12) {
            let distance = isDesignPreview ? "1.2 km" : route.map { TripProgressContent.distance($0.distance) }
            let minutes = isDesignPreview ? 6 : route.map { max(1, Int(ceil($0.expectedTravelTime / 60))) }
            TripRouteMetrics(distance: distance, minutes: minutes, hasRoute: navigation.route != nil, walking: trip.input.mode == .walking)
                .accessibilityIdentifier("tripReturnEstimate")
            HStack(spacing: 10) {
                PlaceThumbnail(imageName: nil, systemImage: "flag.fill", placeholderBackground: AppColor.accent.opacity(0.10))
                Text("Starting point")
                    .font(.title3.bold())
                    .accessibilityIdentifier("tripReturnDestination")
            }
            if usesLastStop, let lastStop {
                Text("From last visited stop · \(lastStop.name)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else if navigation.location != nil {
                Text("From your current location")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if isDesignPreview {
                Text("Design preview · sample route and estimates")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if route == nil && !navigation.arrivalReady {
                routeStatus
            }
            if navigation.permissionDenied {
                Button("Enable current location in Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
                .font(.subheadline)
                .frame(minHeight: 44)
            }
            Divider()
            Button {
                dismiss()
            } label: {
                Text("Back to summary")
                    .foregroundStyle(AppColor.onBrand)
            }
            .buttonStyle(TripPrimaryButtonStyle())
            .accessibilityIdentifier("tripReturnClose")
        }
        .padding(16)
        .frame(maxWidth: 640, alignment: .leading)
    }

    @ViewBuilder private var routeStatus: some View {
        if navigation.directionsError != nil || navigation.plannedDirectionsUnavailable {
            Text("Directions are unavailable.")
                .font(.subheadline)
            Button("Try again", action: startRoute)
                .buttonStyle(.bordered)
        } else if lastStop != nil || navigation.location != nil {
            ProgressView("Finding directions…")
                .font(.subheadline)
        } else if !navigation.permissionDenied {
            Text("Waiting for your current location.")
                .font(.subheadline)
            Button("Try again", action: startRoute)
                .buttonStyle(.bordered)
        }
    }

    private func focusRoute() {
        mapPosition = routeLine.map(TripRouteLine.cameraPosition) ?? .automatic
    }

    private func coordinate(_ point: PlanningPoint) -> CLLocationCoordinate2D {
        .init(latitude: point.latitude, longitude: point.longitude)
    }

    private func startRoute() {
        navigation.start(to: trip.input.origin, mode: trip.input.mode, plannedOrigin: lastStop?.location)
    }
}
