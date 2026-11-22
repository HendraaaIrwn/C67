import SwiftUI
import C67Domain

/// Full-screen trip ordering and completion states.
///
/// The message moves from the trip, to the weather, to live traffic, then stays on the last one
/// until the caller replaces this view with the result.
struct TripProcessingView: View {
    @State private var stage: TripProcessingStage
    private let advances: Bool
    private let messageOverride: String?
    private let activity: PlanningActivity?
    private let isReady: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// - Parameters:
    ///   - stage: The first message to show.
    ///   - advances: Whether the messages move on by themselves. Previews pass false to hold one.
    init(stage: TripProcessingStage = .puttingTogether, advances: Bool = true, messageOverride: String? = nil, activity: PlanningActivity? = nil, isReady: Bool = false) {
        _stage = State(initialValue: stage)
        self.advances = advances
        self.messageOverride = messageOverride
        self.activity = activity
        self.isReady = isReady
    }

    var body: some View {
        Group {
            if isReady {
                // Same hand-off as "Here's what we found"; it lifts away just before the itinerary appears.
                HandOffMessage(text: Text("\(QuestionTitle.highlight("All set!")) Here’s come your \(QuestionTitle.highlight("itinerary"))"),
                               leavesAfter: .seconds(1.25))
                    .accessibilityIdentifier("tripProcessingReady")
            } else {
                TripPlanningWaitLayout(
                    message: activity.map { Self.message(for: Scene($0)) } ?? messageOverride.map { Text($0) }
                        ?? Self.message(for: Scene(stage)),
                    raining: scene == .forecast
                )
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.35), value: scene)
            }
        }
        .accessibilityIdentifier("tripProcessing")
        .task {
            guard advances else { return }
            while let next = stage.next {
                try? await Task.sleep(for: TripProcessingStage.interval)
                guard !Task.isCancelled else { return }
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.35)) {
                    stage = next
                }
            }
        }
    }

    /// The three scenes from Sketch HI-FI `PREFERENCES PROCESSING 2`: forecast (with rain), routes,
    /// then putting the itinerary together. Planning activities and timed stages both map onto them.
    enum Scene: Equatable {
        case forecast, routes, together

        init(_ activity: PlanningActivity) {
            switch activity {
            case .weather: self = .forecast
            case .travelTimes: self = .routes
            case .luna, .onDeviceAdvice, .openingHours: self = .together
            }
        }

        init(_ stage: TripProcessingStage) {
            switch stage {
            case .checkingWeather: self = .forecast
            case .scanningTraffic: self = .routes
            case .puttingTogether: self = .together
            }
        }
    }

    private var scene: Scene { activity.map(Scene.init) ?? Scene(stage) }

    static func message(for scene: Scene) -> Text {
        switch scene {
        case .forecast: Text("Checking the \(QuestionTitle.highlight("forecast")) so you don’t get rained on…")
        case .routes: Text("Finding the \(QuestionTitle.highlight("smoothest routes")) between spots…")
        case .together: Text("Putting your \(QuestionTitle.highlight("itinerary")) together…")
        }
    }

    static func message(for stage: TripProcessingStage) -> Text { message(for: Scene(stage)) }
}

/// Sketch HI-FI `PREFERENCES PROCESSING 2`, measured on the 402 × 874 artboard: the drive scene
/// bleeds past both edges with its top at 91 pt, then a centred title at 424 pt and the
/// status at 489 pt. Shorter screens scale the vertical positions down; actions sit in the caller's inset.
private struct TripPlanningWaitLayout: View {
    let message: Text
    let raining: Bool

    private static let artboardHeight = 874.0

    var body: some View {
        GeometryReader { proxy in
            let fullHeight = proxy.size.height + proxy.safeAreaInsets.top + proxy.safeAreaInsets.bottom
            let scale = min(1, fullHeight / Self.artboardHeight)
            let sceneWidth = proxy.size.width * 386.75 / 402
            VStack(alignment: .leading, spacing: 0) {
                // The scene bleeds past the margins without widening the centred text column.
                Color.clear
                    .frame(height: sceneWidth * 185 / 364)
                    .overlay(alignment: .leading) {
                        TripPlanningDriveIllustration(raining: raining)
                            .frame(width: sceneWidth, height: sceneWidth * 185 / 364)
                            .offset(x: -3 - 20)
                    }
                    .padding(.top, 91 * scale - proxy.safeAreaInsets.top)
                Text("Hang on tight!")
                    .font(.system(size: 34, weight: .bold))
                    .frame(maxWidth: .infinity)
                    .foregroundStyle(AppColor.primaryText)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.top, max(16, (424 - 91) * scale - sceneWidth * 185 / 364))
                message
                    .contentTransition(.opacity)
                    .font(.system(size: 28))
                    .foregroundStyle(AppColor.primaryText)
                    .frame(maxWidth: 306)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 24 * scale)
                Spacer(minLength: 0)
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(AppColor.canvas.ignoresSafeArea())
    }
}

#if DEBUG
    struct TripProcessingActivityPreview: View {
        @State private var activity: PlanningActivity?

        var body: some View {
            TripProcessingView(advances: false, activity: activity)
                .task {
                    let scenes: [PlanningActivity] = [.weather, .luna, .openingHours, .travelTimes]
                    var index = 0
                    while !Task.isCancelled {
                        guard (try? await Task.sleep(for: .seconds(2.8))) != nil, !Task.isCancelled else { return }
                        activity = scenes[index]
                        index = (index + 1) % scenes.count
                    }
                }
        }
    }

    #Preview("Planning activities") {
        TripProcessingActivityPreview()
    }

    #Preview("PREFERENCES PROCESSING 2") {
        TripProcessingView(stage: .puttingTogether, advances: false)
    }

    #Preview("PREFERENCES PROCESSING 3") {
        TripProcessingView(stage: .checkingWeather, advances: false)
    }

    #Preview("PREFERENCES PROCESSING 4") {
        TripProcessingView(stage: .scanningTraffic, advances: false)
    }

    #Preview("Itinerary ready") {
        TripProcessingView(advances: false, isReady: true)
    }

    #Preview("Animated · Dark") {
        TripProcessingView()
            .preferredColorScheme(.dark)
    }
#endif
