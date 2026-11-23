import SwiftUI
import C67Domain

struct TravelantsSignInView: View {
    let accountDeleted: Bool
    let appleRevocationHelp: URL?
    let privacyPolicy: URL?
    let busy: Bool
    let issue: PresentationIssue?
    let onReviewSignIn: (() -> Void)?
    let onCheckSession: () -> Void
    let onAppleSignIn: (Result<AppleSignInCredentials, AuthenticationError>) -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var palette: SignInMapPalette { .init(dark: colorScheme == .dark) }

    var body: some View {
        GeometryReader { geometry in
            let wide = geometry.size.width >= 700
            let compact = geometry.size.height < 650 || dynamicTypeSize.isAccessibilitySize

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if !compact, !wide { Spacer(minLength: 14) }
                    mapArtwork(wide: wide, compact: compact)
                    introduction
                        .padding(.top, compact ? 24 : 30)

                    if compact || wide {
                        Spacer().frame(height: compact ? 28 : 48)
                    } else {
                        Spacer(minLength: 46)
                    }
                    actions
                }
                .frame(maxWidth: wide ? 420 : 390)
                .padding(.horizontal, 28)
                .padding(.top, compact ? 20 : 28)
                .padding(.bottom, compact ? 16 : 24)
                .frame(minHeight: compact ? nil : geometry.size.height)
                .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .background(palette.canvas.ignoresSafeArea())
        .tint(palette.accent)
    }

    private func mapArtwork(wide: Bool, compact: Bool) -> some View {
        ZStack {
            SignInMapArtwork(palette: palette)
            Image("TravelantsMark")
                .resizable()
                .scaledToFit()
                .frame(height: compact ? 92 : 134)
                .rotationEffect(.degrees(15))
                .offset(x: -5, y: 4)
        }
        .frame(height: compact ? 170 : wide ? 374 : 324)
        .clipShape(.rect(cornerRadius: 24))
        .overlay {
            RoundedRectangle(cornerRadius: 24).strokeBorder(palette.border)
        }
        .accessibilityHidden(true)
    }

    private var introduction: some View {
        let brandName = Text(verbatim: "Travelants").foregroundStyle(palette.accent)
        let message: LocalizedStringKey = accountDeleted
            ? "Your account has been deleted."
            : "Plan a trip and pick up where you left off."

        return VStack(alignment: .leading, spacing: 12) {
            Text("Welcome to\n\(brandName)")
                .font(AppFont.largeTitleBold)
                .tracking(-0.9)
                .accessibilityLabel("Welcome to Travelants")
                .accessibilityAddTraits(.isHeader)
            Text(message)
                .font(AppFont.body)
                .foregroundStyle(palette.secondaryText)
                .frame(maxWidth: dynamicTypeSize <= .large && !accountDeleted ? 222 : .infinity, alignment: .leading)
            if let appleRevocationHelp {
                Link(destination: appleRevocationHelp) {
                    Text("How to remove Apple access")
                        .font(AppFont.subheadline)
                        .frame(minHeight: 44)
                        .contentShape(.rect)
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var actions: some View {
        VStack(spacing: 8) {
            AppleSignInButtonView(onCompletion: onAppleSignIn)
                .clipShape(.rect(cornerRadius: 10))
                .disabled(busy)
            if let onReviewSignIn {
                Button(action: onReviewSignIn) {
                    Text("App Review Sign-In")
                        .frame(minHeight: 44)
                        .contentShape(.rect)
                }
                .accessibilityIdentifier("appReviewSignIn")
                .disabled(busy)
            }
            if let privacyPolicy {
                Link(destination: privacyPolicy) {
                    Text("Privacy Policy")
                        .font(AppFont.footnote.weight(.medium))
                        .frame(minWidth: 100, minHeight: 44)
                        .contentShape(.rect)
                }
            }
            if busy { ProgressView("Signing in…") }
            if let issue {
                RecoveryNotice(
                    title: "Sign-in needs attention",
                    message: issue.message,
                    primary: issue.recovery == .checkSession
                        ? .init(title: "Check session again", perform: onCheckSession)
                        : nil
                )
            }
        }
        .frame(maxWidth: .infinity)
    }
}

/// Draws an illustrative map in normalized coordinates without any location or map requests.
private struct SignInMapArtwork: View {
    let palette: SignInMapPalette

    var body: some View {
        Canvas { context, size in
            func point(_ x: Double, _ y: Double) -> CGPoint {
                CGPoint(x: size.width * x, y: size.height * y)
            }

            func road(_ vertices: [(Double, Double)], color: Color, width: CGFloat) {
                let path = Path { $0.addLines(vertices.map { point($0.0, $0.1) }) }
                context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
            }

            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(palette.land))
            let parks: [[(Double, Double)]] = [
                [(0.01, 0.20), (0.20, 0.16), (0.22, 0.28), (0.06, 0.35)],
                [(0.66, 0.13), (0.79, 0.12), (0.88, 0.26), (0.71, 0.33), (0.64, 0.23)],
                [(0.77, 0.78), (0.97, 0.63), (1.06, 0.77), (0.91, 0.96)],
                [(0.06, 0.67), (0.22, 0.61), (0.31, 0.75), (0.26, 0.83), (0.09, 0.80)],
            ]
            for polygon in parks {
                let shape = Path { path in
                    path.addLines(polygon.map { point($0.0, $0.1) })
                    path.closeSubpath()
                }
                context.fill(shape, with: .color(palette.park))
            }

            for offset in stride(from: -0.32, through: 1.20, by: 0.072) {
                road([(offset, -0.10), (offset + 0.16, 0.37), (offset + 0.28, 0.66), (offset + 0.31, 1.12)],
                     color: palette.localRoad, width: 1.25)
            }
            for offset in stride(from: -0.13, through: 1.43, by: 0.084) {
                road([(-0.10, offset + 0.18), (0.32, offset + 0.11), (0.58, offset - 0.03), (1.16, offset - 0.14)],
                     color: palette.localRoad, width: 1.3)
            }

            let river = Path { path in
                path.move(to: point(1.11, 0.07))
                path.addCurve(to: point(0.85, 0.50), control1: point(0.72, 0.12), control2: point(0.96, 0.28))
                path.addCurve(to: point(0.50, 0.78), control1: point(0.77, 0.71), control2: point(0.46, 0.57))
                path.addCurve(to: point(0.64, 1.08), control1: point(0.52, 0.90), control2: point(0.73, 0.89))
            }
            context.stroke(river, with: .color(palette.water), style: StrokeStyle(lineWidth: 29, lineCap: .round))

            road([(-0.08, 0.42), (0.23, 0.39), (0.52, 0.32), (0.74, 0.23), (1.10, 0.18)], color: palette.mainRoad, width: 3.3)
            road([(0.24, -0.05), (0.25, 0.19), (0.36, 0.47), (0.43, 0.79), (0.46, 1.10)], color: palette.mainRoad, width: 3.7)
            road([(-0.06, 0.89), (0.20, 0.82), (0.44, 0.67), (0.70, 0.57), (1.06, 0.54)], color: palette.mainRoad, width: 3.4)

            let origin = point(0.18, 0.63)
            let destination = point(0.84, 0.31)
            let route = Path { path in
                path.move(to: origin)
                path.addQuadCurve(to: point(0.39, 0.56), control: point(0.32, 0.63))
                path.addQuadCurve(to: point(0.57, 0.50), control: point(0.47, 0.48))
                path.addQuadCurve(to: point(0.72, 0.43), control: point(0.65, 0.51))
                path.addQuadCurve(to: destination, control: point(0.79, 0.36))
            }
            context.stroke(route, with: .color(palette.route), style: StrokeStyle(lineWidth: 1.9, lineCap: .round, dash: [2, 5.5]))
            for endpoint in [origin, destination] {
                let ring = Path(ellipseIn: CGRect(x: endpoint.x - 5, y: endpoint.y - 5, width: 10, height: 10))
                context.fill(ring, with: .color(palette.land))
                context.stroke(ring, with: .color(palette.route), lineWidth: 1.8)
            }
        }
    }
}

private struct SignInMapPalette {
    let dark: Bool
    var canvas: Color { Color(rgb: dark ? 0x101822 : 0xF8FAFD) }
    var accent: Color { Color(rgb: dark ? 0xAAC9FF : 0x1A4EEA) }
    var secondaryText: Color { Color(rgb: dark ? 0xCEDBF1 : 0x505D71) }
    var border: Color { Color(rgb: dark ? 0x334A68 : 0xD8E4F4) }
    var land: Color { Color(rgb: dark ? 0x192D43 : 0xE5EEF9) }
    var water: Color { Color(rgb: dark ? 0x1C3B5E : 0xCDDEF5) }
    var park: Color { Color(rgb: dark ? 0x213A47 : 0xD8E8E9) }
    var localRoad: Color { Color(rgb: dark ? 0x29445E : 0xF6F9FD) }
    var mainRoad: Color { Color(rgb: dark ? 0x4B6888 : 0xFFFFFF) }
    var route: Color { Color(rgb: dark ? 0x779EDF : 0x709AE6) }
}

private extension Color {
    init(rgb: UInt32) {
        self.init(
            red: Double((rgb >> 16) & 255) / 255,
            green: Double((rgb >> 8) & 255) / 255,
            blue: Double(rgb & 255) / 255
        )
    }
}
