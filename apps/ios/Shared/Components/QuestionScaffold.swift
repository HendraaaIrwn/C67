import SwiftUI

/// Screen layout shared by the trip preference questions.
///
/// Shows a `QuestionTitle`, the question's content, an optional bottom action and a native
/// Skip toolbar button. Push it inside a `NavigationStack`; the system back button provides the
/// leading control.
struct QuestionScaffold<Content: View, Footer: View>: View {
    private let title: Text
    private let contentSpacing: CGFloat
    private let skip: (() -> Void)?
    private let content: Content
    private let footer: Footer

    init(
        title: Text,
        contentSpacing: CGFloat = 64,
        skip: (() -> Void)? = nil,
        @ViewBuilder content: () -> Content,
        @ViewBuilder footer: () -> Footer
    ) {
        self.title = title
        self.contentSpacing = contentSpacing
        self.skip = skip
        self.content = content()
        self.footer = footer()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: contentSpacing) {
                QuestionTitle(title)
                content
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 32)
        }
        .scrollBounceBehavior(.basedOnSize)
        .bottomActionBar {
            if Footer.self != EmptyView.self {
                footer
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
            }
        }
        .background(AppColor.canvas)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if let skip {
                    Button("Skip", action: skip)
                }
            }
        }
        .tint(AppColor.accent)
    }
}

extension QuestionScaffold where Footer == EmptyView {
    init(
        title: Text,
        contentSpacing: CGFloat = 64,
        skip: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.init(title: title, contentSpacing: contentSpacing, skip: skip, content: content) {
            EmptyView()
        }
    }
}

extension View {
    /// Pins primary actions to the bottom edge with no backdrop. On iOS 26 and later, content
    /// scrolling beneath the buttons blurs softly, matching the navigation bar's scroll edge effect.
    func bottomActionBar<Bar: View>(@ViewBuilder _ bar: () -> Bar) -> some View {
        modifier(BottomActionBar(bar: bar()))
    }
}

private struct BottomActionBar<Bar: View>: ViewModifier {
    let bar: Bar

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .safeAreaBar(edge: .bottom, spacing: 0) { bar }
                .scrollEdgeEffectStyle(.soft, for: .bottom)
        } else {
            content.safeAreaInset(edge: .bottom, spacing: 0) { bar }
        }
    }
}
