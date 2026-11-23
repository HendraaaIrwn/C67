import AVFoundation
import Combine
import SwiftUI
import UIKit

/// Covers the app's normal entry screen while the bundled launch movie plays once.
struct LaunchSplashView<Content: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var finished = false
    @State private var isFading = false

    private let movieURL: URL?
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
        #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--skip-splash") {
                movieURL = nil
                return
            }
        #endif
        movieURL = Bundle.main.url(forResource: "TravelantsSplash", withExtension: "mp4")
    }

    private var showsSplash: Bool {
        movieURL != nil && !finished && !reduceMotion
    }

    var body: some View {
        content
            .accessibilityHidden(showsSplash)
            .allowsHitTesting(!showsSplash)
            .overlay {
                if showsSplash, let movieURL {
                    LaunchSplashPlaybackView(url: movieURL, finish: finishSplash)
                        .ignoresSafeArea()
                        .opacity(isFading ? 0 : 1)
                }
            }
            .onChange(of: reduceMotion, initial: true) {
                if reduceMotion { finished = true }
            }
            .onChange(of: scenePhase) {
                if scenePhase == .background { finished = true }
            }
    }

    private func finishSplash(didPlayToEnd: Bool) {
        guard showsSplash, !isFading else { return }
        guard didPlayToEnd, scenePhase == .active else {
            finished = true
            return
        }

        withAnimation(.easeInOut(duration: 0.32), completionCriteria: .removed) {
            isFading = true
        } completion: {
            finished = true
        }
    }
}

private struct LaunchSplashPlaybackView: View {
    let url: URL
    let finish: (_ didPlayToEnd: Bool) -> Void

    @State private var player: AVPlayer?

    var body: some View {
        GeometryReader { geometry in
            let size = min(224, geometry.size.width, geometry.size.height)
            SplashPlayerLayer(player: player)
                .frame(width: size, height: size)
                .clipShape(.rect(cornerRadius: size * 0.23))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(AppColor.canvas)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Opening Travelants")
        .accessibilityIdentifier("launchSplash")
        .onReceive(completion, perform: finish)
        .task {
            let playback = AVPlayer(url: url)
            player = playback
            playback.isMuted = true
            playback.play()
            defer { playback.pause() }

            // Bound unavailable or stalled playback. Successful playback ends via the item notification.
            do {
                try await Task.sleep(for: .seconds(5))
            } catch {
                return
            }
            if !Task.isCancelled { finish(false) }
        }
    }

    private var completion: AnyPublisher<Bool, Never> {
        guard let item = player?.currentItem else {
            return Empty().eraseToAnyPublisher()
        }
        let notifications = NotificationCenter.default
        return Publishers.Merge3(
            notifications.publisher(for: AVPlayerItem.didPlayToEndTimeNotification, object: item).map { _ in true },
            notifications.publisher(for: AVPlayerItem.failedToPlayToEndTimeNotification, object: item).map { _ in false },
            item.publisher(for: \.status).filter { $0 == .failed }.map { _ in false }
        )
        .receive(on: RunLoop.main)
        .eraseToAnyPublisher()
    }
}

private struct SplashPlayerLayer: UIViewRepresentable {
    let player: AVPlayer?

    func makeUIView(context: Context) -> PlayerView {
        let view = PlayerView()
        view.playerLayer.videoGravity = .resizeAspect
        return view
    }

    func updateUIView(_ uiView: PlayerView, context: Context) {
        uiView.playerLayer.player = player
    }

    final class PlayerView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }
}
