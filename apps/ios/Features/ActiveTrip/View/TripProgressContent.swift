import SwiftUI
import MapKit
import C67Domain
import Lottie

/// TRIP STARTED and TRIP DONE (arrival at a stop), driven by accepted trip events.
struct TripProgressContent: View {
    let trip: PersonalPlanningTrip
    var details: [UUID: ItineraryStopDetails] = [:]
    var isDesignPreview = false
    var isBusy = false
    var error: String?
    var recovery: RecoveryNotice.Action?
    var previewDistance: String?
    var previewStep: (distance: String, instruction: String)?
    var previewPath: [PlanningPoint] = []
    var route: MKRoute?
    var plannedRoute: MKRoute?
    var startingPoint: PlanningPoint?
    var hasCurrentLocation = false
    var locationError: String?
    var locationPermissionDenied = false
    let openDirections: () -> Void
    var openSettings: () -> Void = {}
    var openMaps: () -> Void = {}
    let arrive: () -> Void
    var arriveAtEndpoint: () -> Void = {}
    let completeVisit: () -> Void
    let returnToTrip: () -> Void
    let returnToStartingPoint: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.locale) private var locale
    @State private var mapPosition: MapCameraPosition = .automatic
    @State private var panelHeight: CGFloat = 280

    private var stop: ScheduledPlanningStop? { trip.nextStop }
    private var arrived: Bool { stop != nil && trip.currentStopID == stop?.id }
    private var upcoming: ScheduledPlanningStop? {
        guard let stop, let index = trip.plan.stops.firstIndex(where: { $0.id == stop.id }), index + 1 < trip.plan.stops.count else { return nil }
        return trip.plan.stops[index + 1]
    }
    private var number: Int { trip.completedStopIDs.count + 1 }
    private var walking: Bool { trip.input.mode == .walking }
    private var displayedRoute: MKRoute? { route ?? (arrived ? nil : plannedRoute) }
    private var showsStartingPoint: Bool {
        !arrived && startingPoint != nil && route == nil && (!hasCurrentLocation || plannedRoute != nil)
    }

    private var nextInstruction: (distance: String, instruction: String)? {
        if isDesignPreview { return previewStep }
        guard let step = displayedRoute?.steps.first(where: { $0.distance > 0 && !$0.instructions.isEmpty }) else { return nil }
        return (Self.distance(step.distance), step.instructions)
    }

    var body: some View {
        if trip.status == .completed {
            TripCompletedContent(trip: trip, details: details, returnToStartingPoint: returnToStartingPoint, done: returnToTrip)
        } else if trip.pendingEndpoint != nil {
            VStack(spacing: 16) {
                Text(trip.plan.input.enginePreferences?.endPointName ?? "Return to starting point").font(.headline)
                if let route { Text("Estimated travel: \(Int(ceil(route.expectedTravelTime / 60))) min") }
                if let locationError { Text(locationError).font(.footnote) }
                if locationPermissionDenied { Button("Open Settings", action: openSettings) }
                if let error { RecoveryNotice(title: "Trip update needs attention", message: error, primary: recovery) }
                Button("Open directions in Maps", action: openMaps)
                Button("I’ve arrived at the endpoint", action: arriveAtEndpoint).disabled(isBusy)
            }.padding()
        } else {
            activeContent
        }
    }

    private var activeContent: some View {
        GeometryReader { geometry in
            Map(position: $mapPosition) {
                if !isDesignPreview, hasCurrentLocation { UserAnnotation() }
                if showsStartingPoint, let startingPoint {
                    Annotation("Trip starting point", coordinate: .init(latitude: startingPoint.latitude, longitude: startingPoint.longitude)) {
                        Image(systemName: "flag.fill")
                            .font(.headline)
                            .foregroundStyle(AppColor.accent)
                            .padding(8)
                            .background(AppColor.surface, in: .circle)
                            .accessibilityLabel("Trip starting point")
                    }
                }
                if let line = routeLine {
                    MapPolyline(line).stroke(.white, style: .init(lineWidth: 9, lineCap: .round, lineJoin: .round))
                    MapPolyline(line).stroke(AppColor.accent, style: .init(lineWidth: 5, lineCap: .round, lineJoin: .round))
                }
                if isDesignPreview, !arrived, let origin = previewPath.first {
                    Annotation("Sample starting point", coordinate: .init(latitude: origin.latitude, longitude: origin.longitude)) {
                        Image(systemName: "location.fill")
                            .font(.title2)
                            .foregroundStyle(AppColor.brand)
                            .padding(10)
                            .background(AppColor.surface, in: .circle)
                    }
                }
                ForEach(trip.plan.stops.filter { $0.id == stop?.id }) { item in
                    Annotation("", coordinate: .init(latitude: item.location.latitude, longitude: item.location.longitude)) {
                        VStack(spacing: 12) {
                            if arrived {
                                Text(item.name).font(.caption.bold()).lineLimit(1)
                                    .padding(.horizontal, 24).padding(.vertical, 8)
                                    .background(.background, in: .capsule)
                            }
                            Image(systemName: arrived ? "checkmark.circle.fill" : "mappin.circle.fill")
                                .font(.largeTitle)
                                .foregroundStyle(arrived ? .green : AppColor.brand)
                                .padding(6).background(.background, in: .circle)
                        }
                        .accessibilityLabel(item.name)
                    }
                }
            }
            .onChange(of: stop?.id) { _, _ in mapPosition = .automatic }
            .onChange(of: displayedRoute, initial: true) { _, _ in focusRoute() }
            .accessibilityLabel("Trip stops on the map")
            .overlay(alignment: .trailing) {
                if displayedRoute != nil {
                    Button(action: focusRoute) {
                        Image(systemName: "location.viewfinder")
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.circle)
                    .accessibilityLabel("Show route")
                    .padding(.trailing, 16)
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                if let stop { tripBanner(for: stop) }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if let stop {
                    let maxHeight = min(geometry.size.height * (dynamicTypeSize.isAccessibilitySize ? 0.67 : 0.53), 560)
                    ScrollView {
                        tripPanel(for: stop)
                            .frame(maxWidth: .infinity)
                            .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { panelHeight = $0 }
                    }
                    .scrollBounceBehavior(.basedOnSize)
                    .frame(maxWidth: 640)
                    .frame(height: min(panelHeight, maxHeight))
                    .accessibilityIdentifier("tripProgressPanel")
                    .foregroundStyle(.primary)
                    .background(AppColor.surface, in: .rect(cornerRadius: 24))
                    .shadow(color: .black.opacity(0.18), radius: 12, y: 6)
                    .padding(.horizontal, 8)
                    .padding(.bottom, 8)
                }
            }
        }
        .background(AppColor.canvas)
        .navigationTitle(arrived ? "Arrival" : "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
    }

    private var routeLine: MKPolyline? {
        if let displayedRoute { return displayedRoute.polyline }
        guard isDesignPreview, !arrived, previewPath.count > 1 else { return nil }
        let coordinates = previewPath.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
        return MKPolyline(coordinates: coordinates, count: coordinates.count)
    }

    private func tripBanner(for stop: ScheduledPlanningStop) -> some View {
        let instruction = arrived ? nil : nextInstruction
        return HStack(alignment: .center, spacing: 16) {
            Image(systemName: arrived ? "checkmark" : instruction == nil ? "map" : "arrow.up.forward")
                .font(.title.weight(.semibold))
                .padding(10)
                .background(.white.opacity(0.15), in: .rect(cornerRadius: 13))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                if let instruction {
                    Text(instruction.distance)
                        .font(.largeTitle.bold().monospacedDigit())
                    Text(instruction.instruction)
                        .font(.title3.weight(.semibold))
                        .accessibilityIdentifier("tripRouteInstruction")
                    Text(route == nil && (plannedRoute != nil || isDesignPreview) ? "Route from starting point" : "Route preview")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white.opacity(0.91))
                } else {
                    Text(arrived ? "You’ve arrived" : "On your way")
                        .font(.headline)
                    Text(stop.name)
                        .font(.title3.bold())
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 19)
        .padding(.vertical, 17)
        .frame(maxWidth: 640, alignment: .leading)
        .foregroundStyle(AppColor.onBrand)
        .background(AppColor.brand.mix(with: .black, by: 0.14), in: .rect(cornerRadius: 25))
        .shadow(color: .black.opacity(0.16), radius: 16, y: 9)
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    private func tripPanel(for stop: ScheduledPlanningStop) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if let error { RecoveryNotice(title: "Trip update needs attention", message: error, primary: recovery) }
            if arrived {
                arrivalDetails(for: stop)
            } else {
                HStack(spacing: 10) {
                    stopIdentity(for: stop)
                    Spacer(minLength: 0)
                    mapsButton
                }
                routeMetrics(for: stop)
                locationStatus
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) {
                        backButton
                        arrivalButton
                    }
                    VStack(spacing: 8) {
                        arrivalButton
                        backButton
                    }
                }
            }
            if isDesignPreview {
                Text("Design preview · sample route and estimates")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if trip.synthetic {
                Text("Synthetic trip · estimates are demonstration data")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if isBusy { ProgressView("Updating trip…").tint(AppColor.brand) }
        }
        .padding(arrived ? 20 : 16)
        .frame(maxWidth: 640, alignment: .leading)
    }

    private func routeMetrics(for stop: ScheduledPlanningStop) -> some View {
        let distance = previewDistance ?? displayedRoute.map { Self.distance($0.distance) }
            ?? stop.roadDistanceMeters.map(Self.distance)
        let minutes = isDesignPreview ? 6 : displayedRoute.map { max(1, Int(ceil($0.expectedTravelTime / 60))) }
            ?? (stop.roadDistanceMeters != nil && stop.travelSeconds > 0 ? (stop.travelSeconds + 59) / 60 : nil)
        let hasRoute = route != nil || isDesignPreview
        let distanceLabel: LocalizedStringKey = hasRoute ? "Remaining" : distance == nil ? "Distance" : "Planned distance"
        let timeLabel: LocalizedStringKey = hasRoute ? (walking ? "Walking" : "Driving") : "Travel estimate"
        return ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 14) {
                metric(distance ?? "—", label: distanceLabel)
                Rectangle()
                    .fill(AppColor.secondaryText.opacity(0.28))
                    .frame(width: 1, height: 39)
                    .accessibilityHidden(true)
                metric(minutes.map { String(localized: "\($0) min") } ?? "—", label: timeLabel,
                       symbol: walking ? "figure.walk" : "car")
            }
            VStack(alignment: .leading, spacing: 10) {
                metric(distance ?? "—", label: distanceLabel)
                metric(minutes.map { String(localized: "\($0) min") } ?? "—", label: timeLabel,
                       symbol: walking ? "figure.walk" : "car")
            }
        }
        .accessibilityIdentifier("tripRouteMetrics")
    }

    private func metric(_ value: String, label: LocalizedStringKey, symbol: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 7) {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.title3)
                        .accessibilityHidden(true)
                }
                Text(value)
                    .font(.largeTitle.bold().monospacedDigit())
                    .fixedSize(horizontal: true, vertical: false)
            }
            Text(label).font(.subheadline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func stopIdentity(for stop: ScheduledPlanningStop) -> some View {
        let place = trip.input.places.first { $0.id == stop.id }
        let poi = place.flatMap { RecommendedPlace(place: $0).poiPresentation }
        let category = details[stop.id]?.category ?? poi?.label
        return HStack(spacing: 10) {
            PlaceThumbnail(imageName: details[stop.id]?.photoAsset,
                           systemImage: poi?.symbol ?? "mappin.and.ellipse",
                           placeholderBackground: arrived ? AppColor.tertiaryFill : AppColor.accent.opacity(0.10))
            VStack(alignment: .leading, spacing: 3) {
                Text(stop.name).font(arrived ? .headline : .title3.bold()).accessibilityIdentifier("tripCurrentStop")
                if let category {
                    Text("Stop \(number) of \(trip.plan.stops.count) · \(category)")
                        .font(.subheadline).foregroundStyle(.secondary)
                } else {
                    Text("Stop \(number) of \(trip.plan.stops.count)")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var mapsButton: some View {
        Button(action: openMaps) {
            VStack(spacing: 3) {
                Image(systemName: "map")
                    .font(.callout.weight(.semibold))
                Text("Maps")
                    .font(.caption.weight(.semibold))
            }
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .foregroundStyle(AppColor.accent)
        .accessibilityLabel("Navigate with Apple Maps")
        .disabled(isBusy)
    }

    @ViewBuilder private var locationStatus: some View {
        if isDesignPreview || (!hasCurrentLocation && !locationPermissionDenied) {
            locationStatusRow("Waiting for GPS", actionTitle: "Try again", action: openDirections)
        } else if let locationError {
            locationStatusRow(locationError, actionTitle: locationPermissionDenied ? "Open Settings" : "Try again",
                              action: locationPermissionDenied ? openSettings : openDirections)
        } else if route == nil {
            ProgressView("Finding directions…")
                .font(.footnote)
                .tint(AppColor.brand)
        } else {
            Text("Arrival may be detected automatically.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private func locationStatusRow(_ message: String, actionTitle: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        let indicator = Label {
            Text(message)
                .accessibilityIdentifier(showsStartingPoint ? "tripStartingPointStatus" : "tripLocationStatus")
        } icon: {
            Image(systemName: hasCurrentLocation ? "map" : "location.slash")
                .accessibilityHidden(true)
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .accessibilityHint(showsStartingPoint ? Text("Using the trip’s starting point for this first leg.") : Text(""))

        let retry = Button(action: action) {
            Text(actionTitle)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppColor.accent)
                .frame(minHeight: 44)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(isBusy)

        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                indicator
                Spacer(minLength: 8)
                retry
            }
            VStack(alignment: .leading, spacing: 0) {
                indicator
                retry
            }
        }
    }

    private func arrivalDetails(for stop: ScheduledPlanningStop) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(plannedVisitWindow(for: stop) ?? String(localized: "Visit time unavailable"))
                        .font(.largeTitle.bold().monospacedDigit())
                        .accessibilityIdentifier("arrivalPlannedVisitWindow")
                    Text("Planned visit")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                arrivalTile("clock")
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(stop.name).font(.title3.bold()).accessibilityIdentifier("tripCurrentStop")
                Text("Stop \(number) of \(trip.plan.stops.count)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if let upcoming {
                Divider()
                HStack(spacing: 12) {
                    arrivalTile("arrow.up.forward")
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Up next").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                        Text(upcoming.name).font(.headline)
                        if trip.plan.usesExperienceFlow {
                            Text(ItineraryFormatting.drivingEstimate(upcoming, showsApproximation: false))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("\(upcoming.travelSeconds / 60) min · planned travel").font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            action(upcoming == nil ? "Finish last visit" : "Continue to next stop", action: completeVisit)
                .accessibilityIdentifier("completeTripVisit")
            Button(action: returnToTrip) {
                Text("Back to trip")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppColor.accent)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .disabled(isBusy)
        }
    }

    private func arrivalTile(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.title3.weight(.medium))
            .foregroundStyle(AppColor.accent)
            .frame(width: 44, height: 44)
            .background(AppColor.accent.opacity(0.10), in: .rect(cornerRadius: 12))
            .accessibilityHidden(true)
    }

    private func plannedVisitWindow(for stop: ScheduledPlanningStop) -> String? {
        func window(for item: ScheduledPlanningStop) -> String? {
            guard let start = item.visitStartsAt ?? item.arrivalAt, let end = item.departureAt, end > start else { return nil }
            let zone = trip.input.timeZone
            let from = ItineraryFormatting.time(start, zone: zone, locale: locale)
            let to = ItineraryFormatting.time(end, zone: zone, locale: locale)
            return "\(from)–\(to)".replacingOccurrences(of: ":", with: ".")
        }
        if let scheduled = window(for: stop) { return scheduled }
        guard trip.plan.usesExperienceFlow,
              let estimated = trip.plan.stopsWithExperienceEstimates.first(where: { $0.id == stop.id }) else { return nil }
        return window(for: estimated)
    }

    private var arrivalButton: some View {
        action("I’m here", action: arrive)
            .accessibilityIdentifier("confirmTripArrival")
    }

    private var backButton: some View {
        Button(action: returnToTrip) {
            Text("Back to trip")
                .font(.body.weight(.semibold))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
        .controlSize(.large)
        .tint(AppColor.accent)
        .disabled(isBusy)
    }

    private func focusRoute() {
        guard let routeLine else { return }
        let rect = routeLine.boundingMapRect
        guard !rect.isNull, !rect.isEmpty else { return }
        mapPosition = .rect(rect.insetBy(dx: -max(rect.size.width * 0.25, 500), dy: -max(rect.size.height * 0.25, 500)))
    }

    private static func distance(_ meters: CLLocationDistance) -> String {
        if meters < 1000 { return "\(Int((meters / 10).rounded() * 10)) m" }
        return Measurement(value: meters / 1000, unit: UnitLength.kilometers).formatted(.measurement(width: .abbreviated, numberFormatStyle: .number.precision(.fractionLength(1))))
    }

    private func action(_ title: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .foregroundStyle(AppColor.onBrand)
        }
        .buttonStyle(TripPrimaryButtonStyle())
        .disabled(isBusy)
    }
}

private struct TripCompletedContent: View {
    let trip: PersonalPlanningTrip
    let details: [UUID: ItineraryStopDetails]
    let returnToStartingPoint: () -> Void
    let done: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.locale) private var locale
    @State private var revealed = false
    @State private var playsCheckmark = false
    private static let completionAnimation = LottieAnimation.named("trip-complete-checkmark")
    private static let doneEntranceDelay = 0.28
    private static let lastVisitEntranceDelay = visitEntranceDelay(at: 4)

    private var isVisible: Bool { revealed || reduceMotion }

    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                confirmation
                visitedStops
            }
            .padding(.horizontal, 24)
            .padding(.top, 48)
            .padding(.bottom, 24)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("tripCompletedSummary")
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(AppColor.canvas)
        .bottomActionBar(background: AppColor.canvas) {
            actions
        }
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .task(id: reduceMotion) {
            revealed = true
            guard !reduceMotion, !playsCheckmark else { return }
            let lastEntranceDelay = max(Self.doneEntranceDelay, Self.lastVisitEntranceDelay)
            try? await Task.sleep(for: .seconds(lastEntranceDelay + CompletionEntrance.duration + 0.10))
            guard !Task.isCancelled else { return }
            playsCheckmark = true
        }
    }

    private var confirmation: some View {
        VStack(spacing: 24) {
            completionCheckmark

            VStack(spacing: 5) {
                Text("Trip complete")
                    .font(.largeTitle.bold())
                    .accessibilityAddTraits(.isHeader)
                Text("All \(trip.completedStopIDs.count) stops visited")
                    .foregroundStyle(.secondary)
            }
            .modifier(CompletionEntrance(visible: isVisible, delay: 0.05))

            VStack(spacing: 5) {
                Text(trip.title).font(.title2.bold())
                Text(ItineraryFormatting.date(trip.input.startsAt, zone: trip.input.timeZone, locale: locale))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .modifier(CompletionEntrance(visible: isVisible, delay: 0.10))
        }
        .multilineTextAlignment(.center)
    }

    private var completionCheckmark: some View {
        Color.clear.frame(width: 56, height: 56)
            .overlay {
                if !reduceMotion, let animation = Self.completionAnimation {
                    if playsCheckmark {
                        LottieView(animation: animation)
                            .playing(loopMode: .playOnce)
                            .frame(width: 64, height: 64)
                    }
                } else {
                    Image(systemName: "checkmark")
                        .font(.system(size: 27, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 56, height: 56)
                        .background(.green.mix(with: .black, by: 0.36), in: .circle)
                }
            }
            .accessibilityHidden(true)
            .allowsHitTesting(false)
    }

    private var visitedStops: some View {
        let visited = trip.plan.stops.filter { trip.completedStopIDs.contains($0.id) }
        return VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("Visited stops")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                if !dynamicTypeSize.isAccessibilitySize, visited.contains(where: { trip.visitedAtByStopID?[$0.id] != nil }) {
                    Text("Visited at")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
            }
            .padding(.bottom, 10)
            .modifier(CompletionEntrance(visible: isVisible, delay: 0.14))

            Divider()
            ForEach(Array(visited.enumerated()), id: \.element.id) { index, stop in
                VStack(spacing: 0) {
                    visitRow(stop)
                        .padding(.vertical, 10)
                    Divider()
                }
                .modifier(CompletionEntrance(visible: isVisible, delay: Self.visitEntranceDelay(at: index)))
            }
        }
    }

    private static func visitEntranceDelay(at index: Int) -> Double {
        0.17 + Double(min(index, 4)) * 0.035
    }

    private func visitRow(_ stop: ScheduledPlanningStop) -> some View {
        let time = trip.visitedAtByStopID?[stop.id].map { arrivedAt in
            var style = Date.FormatStyle.dateTime.hour().minute()
            style.locale = locale
            style.timeZone = TimeZone(identifier: trip.input.timeZone) ?? .current
            return arrivedAt.formatted(style)
        }
        let place = trip.input.places.first { $0.id == stop.id }
        let symbol = place.flatMap { RecommendedPlace(place: $0).poiPresentation?.symbol } ?? "mappin.and.ellipse"
        return HStack(spacing: 11) {
            PlaceThumbnail(imageName: details[stop.id]?.photoAsset, size: 38, systemImage: symbol)
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 4) {
                    Text(stop.name).font(.subheadline.weight(.semibold))
                    if let time {
                        Text("Visited at \(time)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("tripCompletedVisitTime")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text(stop.name).font(.subheadline.weight(.semibold))
                Spacer(minLength: 4)
                if let time {
                    Text(time)
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: true, vertical: false)
                        .accessibilityLabel(Text("Visited at \(time)"))
                        .accessibilityIdentifier("tripCompletedVisitTime")
                }
            }
        }
        .frame(minHeight: 62)
    }

    private var actions: some View {
        VStack(spacing: 10) {
            Button(action: returnToStartingPoint) {
                Label("Return to starting point", systemImage: "flag")
                    .font(.subheadline.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(AppColor.surface, in: .capsule)
                    .overlay { Capsule().strokeBorder(AppColor.accent.opacity(0.4)) }
                    .contentShape(.capsule)
            }
            .buttonStyle(.borderless)
            .tint(AppColor.accent)
            .accessibilityIdentifier("tripReturnToStartingPoint")
            .modifier(CompletionEntrance(visible: isVisible, delay: 0.24))

            Button("Done", action: done)
                .buttonStyle(TripPrimaryButtonStyle())
                .modifier(CompletionEntrance(visible: isVisible, delay: Self.doneEntranceDelay))
        }
    }
}

private struct CompletionEntrance: ViewModifier {
    static let duration = 0.33
    let visible: Bool
    let delay: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let animation = Animation.spring(duration: Self.duration, bounce: 0).delay(delay)
        content.animation(reduceMotion ? nil : animation) { element in
            element
                .opacity(visible ? 1 : 0)
                .offset(y: visible ? 0 : 8)
        }
    }
}
