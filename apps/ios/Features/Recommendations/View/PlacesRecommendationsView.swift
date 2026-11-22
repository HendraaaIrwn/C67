import SwiftUI
import UIKit
import C67Domain

struct PlacesRecommendationsView: View {
    let batch: RecommendationsBatch
    let selected: [RecommendedPlace]
    var isLoading = false
    var error: String?
    var usesDeviceLocation = true
    var previewLocation: PlanningPoint?
    var requiresOrigin = false
    var origin: PlanningPoint?
    var setOrigin: ((PlanningPlace) -> Void)?
    /// The most places this flow accepts; `nil` means no limit.
    var maximumSelection: Int?
    var minimumSelection = 1
    /// Names the selection in the primary button ("Plan with 4 places") once the minimum is met.
    var countsInNextButton = false
    let load: @MainActor () async -> Void
    let refresh: @MainActor () async -> Void
    let cancel: () -> Void
    let toggle: (RecommendedPlace) -> Void
    let findPlace: () -> Void
    let complete: () -> Void
    @State private var location = PlanningLocation()
    @Environment(\.openURL) private var openURL
    @State private var showsSelected = false
    @State private var searchAfterDismiss = false
    @State private var retryTask: Task<Void, Never>?
    @State private var showsOriginSearch = false
    @State private var rejectedSelectionCount = 0

    private var canLoadRecommendations: Bool { !requiresOrigin || origin != nil }

    private var selectedIDs: Set<UUID> { Set(selected.map(\.id)) }
    private var selectedPlaces: Binding<[PlanningPlace]> {
        Binding(get: { selected.map(\.place) }, set: { remaining in
            let ids = Set(remaining.map(\.id))
            for item in selected where !ids.contains(item.id) { toggle(item) }
        })
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("List of \(Text("Places").foregroundStyle(AppColor.accent))")
                            .font(.title.bold())
                            .accessibilityAddTraits(.isHeader)
                        // The selection summary sits with the list it describes; the footer keeps one action.
                        HStack(spacing: 6) {
                            Text("\(selected.count) places selected")
                                .foregroundStyle(AppColor.secondaryText)
                                .contentTransition(.numericText())
                                .animation(.snappy, value: selected.count)
                            Text(verbatim: "·")
                                .foregroundStyle(AppColor.secondaryText)
                                .accessibilityHidden(true)
                            Button("My Places") { showsSelected = true }
                                .fontWeight(.semibold)
                        }
                        .font(.subheadline)
                    }
                    Spacer(minLength: 8)
                    Button("Refresh", systemImage: "arrow.clockwise", action: retry)
                        .labelStyle(.iconOnly)
                        .frame(minWidth: 44, minHeight: 44)
                        .disabled(isLoading || !canLoadRecommendations)
                        .accessibilityIdentifier("refreshRecommendations")
                }

                if requiresOrigin && origin == nil {
                    OriginPrompt(isRequesting: location.isRequesting,
                                 permissionDenied: usesDeviceLocation && location.permissionDenied,
                                 failed: usesDeviceLocation && location.error != nil,
                                 offersDeviceLocation: usesDeviceLocation,
                                 useCurrentLocation: { location.request() },
                                 openSettings: {
                                     if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                                 },
                                 chooseStartingPoint: {
                                     location.cancel()
                                     showsOriginSearch = true
                                 })
                } else if !requiresOrigin && usesDeviceLocation && location.point == nil {
                    if location.isRequesting {
                        Label("Finding your location…", systemImage: "location")
                            .font(.footnote).foregroundStyle(.secondary)
                    } else if location.permissionDenied {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Enable location access to see distances.")
                                .font(.footnote).foregroundStyle(.secondary)
                            Button("Open Settings") {
                                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                            }
                        }
                    } else if location.error != nil {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Couldn’t get your location. Try again to see distances.")
                                .font(.footnote).foregroundStyle(.secondary)
                            Button("Try location again") { location.request() }
                        }
                    } else {
                        Button("Use current location") { location.request() }
                    }
                }

                if isLoading { ProgressView("Finding places…").frame(maxWidth: .infinity).padding() }
                if let error {
                    RecoveryNotice(title: "Couldn’t refresh recommendations", message: error,
                                   primary: isLoading ? nil : .init(title: "Try again", perform: retry),
                                   secondary: .init(title: "Search for a place", perform: findPlace))
                }
                if !batch.warnings.isEmpty {
                    DisclosureGroup(batch.places.isEmpty ? "Recommendation details" : "Some recommendations are unavailable") {
                        ForEach(batch.warnings, id: \.self) { warning in
                            Text(warning).font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }
                if batch.places.isEmpty && !isLoading && error == nil && (!requiresOrigin || origin != nil) {
                    ContentUnavailableView {
                        Label("No recommendations yet", systemImage: "mappin.and.ellipse")
                    } description: {
                        Text("Try refreshing, adjust your preferences, or search for a place.")
                    } actions: {
                        Button("Try again", action: retry)
                        Button("Search for a place", action: findPlace)
                    }
                }
                LazyVStack(spacing: 10) {
                    ForEach(batch.places) { item in
                        RecommendationPlaceRow(item: item, userLocation: requiresOrigin ? origin : (usesDeviceLocation ? location.point : previewLocation), isSelected: selectedIDs.contains(item.id),
                                               isExisting: false,
                                               isDisabled: false, isLocked: isLocked(item)) {
                        isLocked(item) ? rejectedSelectionCount += 1 : toggle(item)
                    }
                    }
                }
                if batch.synthetic {
                    Text("Synthetic recommendations for demonstration.")
                        .font(.footnote).foregroundStyle(.secondary)
                } else if !batch.places.isEmpty {
                    Text("Check opening hours and any facilities you need before visiting.")
                        .font(.footnote).foregroundStyle(.secondary)
                    TripRecommendationsMap(places: batch.places)
                        .frame(height: 180)
                        .clipShape(.rect(cornerRadius: 20))
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 20)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .task(id: origin) {
            if canLoadRecommendations { await load() }
        }
        .onChange(of: location.point) { _, point in
            if requiresOrigin, origin == nil, let point {
                setOrigin?(.init(id: UUID(), name: "Current device position", location: point, visitSeconds: 2700))
            }
        }
        .overlay {
            if isLoading && batch.places.isEmpty {
                RecommendationsProcessingView()
            }
        }
        .refreshable {
            if canLoadRecommendations { await refresh() }
        }
        .onDisappear { location.cancel(); retryTask?.cancel(); cancel() }
        .background(AppColor.canvas.ignoresSafeArea())
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 10) {
                PlaceSelectionStatus(count: selected.count, minimum: minimumSelection, maximum: maximumSelection,
                                     rejectedCount: rejectedSelectionCount, alignment: .center)
                if let limit = maximumSelection, selected.count > limit {
                    Button("Review My Places") { showsSelected = true }
                }
                QuestionPrimaryButton(nextTitle, action: complete)
                    .disabled(selected.count < minimumSelection)
                    .accessibilityIdentifier("recommendationsNext")
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(AppColor.surface)
        }
        .sheet(isPresented: $showsSelected, onDismiss: {
            if searchAfterDismiss {
                searchAfterDismiss = false
                findPlace()
            }
        }) {
            SelectedPlacesView(existing: [], selected: selectedPlaces,
                               details: Dictionary(selected.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }),
                               searchForPlace: { searchAfterDismiss = true; showsSelected = false })
        }
        .fullScreenCover(isPresented: $showsOriginSearch) {
            PlanningSearchSheet(near: origin, title: "Starting point") { place in
                location.cancel()
                setOrigin?(place)
            }
        }
        .navigationTitle("Recommendations")
        .navigationBarTitleDisplayMode(.inline)
        .tint(AppColor.accent)
    }

    private var nextTitle: LocalizedStringKey {
        countsInNextButton && selected.count >= minimumSelection ? "Plan with \(selected.count) places" : "Next"
    }

    private func isLocked(_ item: RecommendedPlace) -> Bool {
        guard let limit = maximumSelection else { return false }
        return !selectedIDs.contains(item.id) && selected.count >= limit
    }

    private func retry() {
        guard !isLoading, canLoadRecommendations else { return }
        retryTask?.cancel()
        retryTask = Task { await refresh() }
    }
}

/// One line under the selection count. Readiness is reached at the minimum; the maximum
/// is mentioned only when one spot is left or the selection is full, so it never reads as a target.
struct PlaceSelectionStatus: View {
    let count: Int
    let minimum: Int
    let maximum: Int?
    var rejectedCount = 0
    var alignment: Alignment = .leading
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isFull: Bool { maximum.map { count >= $0 } ?? false }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            if count >= minimum, !isFull {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .accessibilityHidden(true)
            }
            message
                .foregroundStyle(isFull ? AppColor.primaryText : AppColor.secondaryText)
        }
        .font(.footnote)
        .multilineTextAlignment(alignment == .center ? .center : .leading)
        .frame(maxWidth: .infinity, alignment: alignment)
        .keyframeAnimator(initialValue: CGFloat.zero, trigger: rejectedCount) { line, offset in
            line.offset(x: reduceMotion ? 0 : offset)
        } keyframes: { _ in
            KeyframeTrack {
                SpringKeyframe(CGFloat(-6), duration: 0.07)
                SpringKeyframe(CGFloat(6), duration: 0.07)
                SpringKeyframe(CGFloat(-3), duration: 0.07)
                SpringKeyframe(CGFloat.zero, duration: 0.12)
            }
        }
        .sensoryFeedback(.warning, trigger: rejectedCount)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("placeSelectionStatus")
    }

    private var message: Text {
        if count < minimum {
            return count == 0 ? Text("Pick at least \(minimum) places") : Text("Pick \(minimum - count) more to start")
        }
        if let maximum {
            if count >= maximum { return Text("That's the most for one trip. Remove one to swap.") }
            if count == maximum - 1 { return Text("Ready to plan · 1 spot left") }
        }
        return Text("Ready to plan · Add more if you like")
    }
}

#if DEBUG
    #Preview("PLACES LISTS · Light") {
        RecommendationsDesignPreview(addedCount: 0)
    }

    #Preview("PLACES LIST ADDED · Light") {
        RecommendationsDesignPreview(addedCount: 3)
    }

    #Preview("PLACES LIST ADDED · Dark") {
        RecommendationsDesignPreview(addedCount: 3).preferredColorScheme(.dark)
    }
#endif

// MARK: - Starting point prompt

/// Shown before recommendations can load: the list needs a starting point to measure "nearby".
private struct OriginPrompt: View {
    let isRequesting: Bool
    let permissionDenied: Bool
    let failed: Bool
    let offersDeviceLocation: Bool
    let useCurrentLocation: () -> Void
    let openSettings: () -> Void
    let chooseStartingPoint: () -> Void

    private var statusText: LocalizedStringKey? {
        if permissionDenied { return "Location access is off. Turn it on in Settings or choose a starting point." }
        if failed { return "Couldn’t get your location. Try again or choose a starting point." }
        return nil
    }

    var body: some View {
        VStack(spacing: 18) {
            OriginEmblem(isRequesting: isRequesting, permissionDenied: permissionDenied)
                .accessibilityHidden(true)
            VStack(spacing: 6) {
                Text("Where does your trip start?").font(.title3.bold())
                Text(statusText ?? "Choose a starting point to find nearby places.")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .contentTransition(.opacity)
            }
            VStack(spacing: 6) {
                if offersDeviceLocation { deviceLocationButton }
                Button("Choose starting point", action: chooseStartingPoint)
                    .font(.body.weight(.semibold))
                    .tint(AppColor.accent)
                    .frame(minHeight: 44)
            }
            .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 56)
        .animation(.snappy, value: isRequesting)
        .animation(.snappy, value: permissionDenied)
    }

    private var deviceLocationButton: some View {
        Button(action: permissionDenied ? openSettings : useCurrentLocation) {
            HStack(spacing: 8) {
                if isRequesting { ProgressView().tint(AppColor.onBrand) }
                else { Image(systemName: permissionDenied ? "gear" : "location.fill") }
                Text(isRequesting ? "Finding your location…" : permissionDenied ? "Open Settings" : "Use current location")
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.capsule)
        .controlSize(.large)
        .tint(AppColor.brand)
        .disabled(isRequesting)
    }
}

/// A pin floating over its shadow inside two soft discs; it bobs faster while locating.
/// Reduce Motion and denied access show it at rest.
private struct OriginEmblem: View {
    let isRequesting: Bool
    let permissionDenied: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle().fill(AppColor.accent.opacity(0.08)).frame(width: 132, height: 132)
            Circle().fill(AppColor.accent.opacity(0.12)).frame(width: 92, height: 92)
            if permissionDenied {
                Image(systemName: "location.slash.fill")
                    .font(.system(size: 36, weight: .semibold))
                    .foregroundStyle(AppColor.accent)
                    .transition(.scale.combined(with: .opacity))
            } else if reduceMotion {
                pin(lift: 0.5)
            } else {
                TimelineView(.animation) { context in
                    let speed = isRequesting ? 4.0 : 1.6
                    pin(lift: (sin(context.date.timeIntervalSinceReferenceDate * speed) + 1) / 2)
                }
            }
        }
        .frame(width: 200, height: 200)
    }

    /// `lift` runs 0 (resting) to 1 (highest); the shadow shrinks and fades as the pin rises.
    private func pin(lift: Double) -> some View {
        ZStack {
            Ellipse().fill(AppColor.accent.opacity(0.35 - 0.2 * lift))
                .frame(width: 28 - 12 * lift, height: 8 - 3 * lift)
                .offset(y: 22)
            Image(systemName: "mappin")
                .font(.system(size: 38, weight: .semibold))
                .foregroundStyle(AppColor.accent)
                .offset(y: -4 - 14 * lift)
        }
    }
}
