import SwiftUI
import UIKit

enum NoteTheme {
    static let ink = Color(red: 0.035, green: 0.105, blue: 0.205)
    static let secondaryInk = Color(red: 0.48, green: 0.54, blue: 0.67)
    static let accent = ink
    static let danger = Color(red: 0.91, green: 0.24, blue: 0.27)
    static let canvas = Color(red: 0.955, green: 0.955, blue: 1.0)
    static let paper = Color(red: 0.988, green: 0.987, blue: 0.998)
    static let divider = Color.white.opacity(0.72)

    static let horizontalPadding: CGFloat = 22
    static let topBarHeight: CGFloat = 72
    static let controlSize: CGFloat = 48
    static let controlVisualSize: CGFloat = 46
    static let floatingComposerSize: CGFloat = 56
    static let floatingComposerVisualSize: CGFloat = 48
    static let navigationHeight: CGFloat = 78
    static let cornerRadius: CGFloat = 30

    static let background = LinearGradient(
        colors: [
            Color(red: 0.965, green: 0.965, blue: 1.0),
            Color(red: 0.92, green: 0.925, blue: 0.995)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

/// Shared geometry decisions for the four primary destinations. Keeping these
/// values in one place prevents the visual bar and its hit targets drifting
/// apart on the narrow 368pt viewport.
enum V02NavigationLayoutPolicy {
    static let cellMinHeight: CGFloat = 72
    static let barHeight: CGFloat = 76
    /// Compact page-level header height used when a root page needs a
    /// full-width centered title with asymmetric actions on iOS 26.
    static let primaryHeaderHeight: CGFloat = NoteTheme.controlSize + 8
    static let barHorizontalInset: CGFloat = 18
    static let composerBottomGap: CGFloat = 16
    /// All primary scroll containers use the same bottom inset policy so the
    /// native TabView bar and page content do not drift apart.
    static let primaryContentSpacing: CGFloat = 12
    /// Keep enough breathing room for the native TabView and the shell-owned
    /// floating action button when a scroll page is hosted inside the shell's
    /// GeometryReader. Without the action clearance, the last row can remain
    /// under the plus button even after the user reaches the end.
    static let primaryContentBottomPadding: CGFloat =
        barHeight + primaryContentSpacing + NoteTheme.floatingComposerSize + composerBottomGap
    /// The card page's local operation row follows the paper. Keep the gap
    /// explicit so sparse cards do not turn the remaining viewport into a
    /// second, visually empty module.
    static let cardOperationGap: CGFloat = 24
    /// Shared optical anchor for root-page and workbench floating actions.
    static let floatingComposerBottomPadding: CGFloat = NoteTheme.navigationHeight + composerBottomGap
    /// The workbench action row belongs to the paper; keep the floating
    /// composer in the space above the shared TabView instead of over that
    /// row. It follows the same safe-area anchor as the root-page composer.
    static let workbenchFloatingComposerBottomPadding: CGFloat = floatingComposerBottomPadding
    /// Transient undo banners float above the shared navigation surface and
    /// must not participate in the page's scroll layout.
    static let transientBannerBottomPadding: CGFloat = NoteTheme.navigationHeight + composerBottomGap

    static func showsFloatingComposer(on page: V02PrimaryPage, isOverlayPresented: Bool) -> Bool {
        // The shell owns the shared floating component for every page that
        // supports creation. Collection creation is routed back into the
        // collection root, while the receipt book deliberately has no plus.
        !isOverlayPresented && page != .receipts
    }

    static func composerLabel(for page: V02PrimaryPage) -> String {
        switch page {
        case .inspirations: "记录灵感"
        case .cards: "新增卡片"
        case .collections: "新建构思集"
        case .receipts: ""
        }
    }
}

struct GlassSurface: ViewModifier {
    var cornerRadius: CGFloat = NoteTheme.cornerRadius
    var strokeOpacity: Double = 0.76
    var castsShadow = true

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
                .shadow(
                    color: castsShadow ? NoteTheme.ink.opacity(0.07) : .clear,
                    radius: castsShadow ? 20 : 0,
                    y: castsShadow ? 10 : 0
                )
        } else {
            content
                .background(.ultraThinMaterial)
                .background(Color.white.opacity(0.16))
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(Color.white.opacity(strokeOpacity), lineWidth: 1)
                }
                .shadow(
                    color: castsShadow ? NoteTheme.ink.opacity(0.09) : .clear,
                    radius: castsShadow ? 24 : 0,
                    y: castsShadow ? 12 : 0
                )
        }
    }
}

extension View {
    func noteGlass(
        cornerRadius: CGFloat = NoteTheme.cornerRadius,
        strokeOpacity: Double = 0.76,
        castsShadow: Bool = true
    ) -> some View {
        modifier(
            GlassSurface(
                cornerRadius: cornerRadius,
                strokeOpacity: strokeOpacity,
                castsShadow: castsShadow
            )
        )
    }
}

extension View {
    /// Pins a page-owned header to the safe-area bar on iOS 26 and uses the
    /// compatible inset fallback on older systems. Keeping this in one
    /// modifier prevents root pages from stacking independent top spacers.
    @ViewBuilder
    func notePrimaryHeader<Header: View>(@ViewBuilder _ content: () -> Header) -> some View {
        if #available(iOS 26.0, *) {
            safeAreaBar(edge: .top, spacing: 0, content: content)
        } else {
            safeAreaInset(edge: .top, spacing: 0, content: content)
        }
    }
}

struct RoundGlassButton: View {
    let systemName: String
    let label: String
    var selected = false
    var size = NoteTheme.controlSize
    var iconSize: CGFloat = 19
    var externallyPressed: Bool?
    let action: () -> Void

    @ViewBuilder
    var body: some View {
        if let externallyPressed {
            button
                .buttonStyle(.plain)
                .modifier(
                    RoundGlassPressedFeedback(
                        isPressed: externallyPressed
                    )
                )
        } else {
            button
                .buttonStyle(RoundGlassPressButtonStyle())
        }
    }

    private var button: some View {
        Button(action: action) {
            visualLabel
        }
        .frame(width: size, height: size)
        .contentShape(Circle())
        .accessibilityLabel(label)
    }

    @ViewBuilder
    private var visualLabel: some View {
        iconLabel
            .clipShape(Circle())
            .overlay {
                if !selected {
                    Circle()
                        .stroke(Color.white.opacity(0.68), lineWidth: 1)
                }
            }
            .shadow(color: NoteTheme.ink.opacity(0.07), radius: 16, y: 7)
    }

    private var iconLabel: some View {
        Image(systemName: systemName)
            .font(.system(size: iconSize, weight: .semibold))
            .foregroundStyle(selected ? .white : NoteTheme.ink)
            .frame(width: size, height: size)
            .background {
                if selected {
                    Circle().fill(NoteTheme.ink)
                } else {
                        Circle()
                        .fill(Color.white.opacity(0.24))
                        .overlay {
                            Circle()
                                .fill(NoteTheme.ink.opacity(0.014))
                        }
                }
            }
            .contentShape(Circle())
    }
}

struct V02GlassIconButton: View {
    let systemName: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) { V02GlassIconLabel(systemName: systemName) }
            .buttonStyle(RoundGlassPressButtonStyle())
            .accessibilityLabel(label)
    }
}

struct V02GlassIconLabel: View {
    let systemName: String

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(NoteTheme.ink)
            .frame(width: NoteTheme.controlSize, height: NoteTheme.controlSize)
            .background {
                if #available(iOS 26.0, *) {
                    Color.clear.frame(width: NoteTheme.controlVisualSize, height: NoteTheme.controlVisualSize).glassEffect(.regular.interactive(), in: .circle)
                } else {
                    Circle()
                        .fill(.ultraThinMaterial)
                        .frame(width: NoteTheme.controlVisualSize, height: NoteTheme.controlVisualSize)
                        .overlay { Circle().fill(Color.white.opacity(0.28)) }
                        .overlay { Circle().stroke(Color.white.opacity(0.78), lineWidth: 1) }
                }
            }
            .shadow(color: NoteTheme.ink.opacity(0.055), radius: 8, y: 3)
            .contentShape(Circle())
    }
}

extension ToolbarContent {
    @ToolbarContentBuilder
    func noteSharedBackgroundHidden() -> some ToolbarContent {
        if #available(iOS 26.0, *) {
            sharedBackgroundVisibility(.hidden)
        } else {
            self
        }
    }
}

struct V02FloatingComposerButton: View {
    let action: () -> Void
    var label: String = "记录灵感"

    var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(.system(size: 21, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: NoteTheme.floatingComposerVisualSize, height: NoteTheme.floatingComposerVisualSize)
                .background(NoteTheme.ink, in: Circle())
                .overlay { Circle().stroke(Color.white.opacity(0.28), lineWidth: 1) }
                .frame(width: NoteTheme.floatingComposerSize, height: NoteTheme.floatingComposerSize)
                .shadow(color: NoteTheme.ink.opacity(0.11), radius: 9, y: 5)
        }
        .buttonStyle(PressScaleButtonStyle())
        .accessibilityLabel(label)
    }
}

struct RoundGlassPressedFeedback: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let isPressed: Bool

    func body(content: Content) -> some View {
        content
            .scaleEffect(isPressed && !reduceMotion ? 0.95 : 1)
            .brightness(isPressed ? -0.1 : 0)
            .saturation(isPressed ? 0.82 : 1)
            .animation(
                reduceMotion ? nil : .spring(response: 0.2, dampingFraction: 0.76),
                value: isPressed
            )
    }
}

struct RoundGlassPressButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .modifier(
                RoundGlassPressedFeedback(
                    isPressed: configuration.isPressed
                )
            )
    }
}

struct PressScaleButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.94 : 1)
            .opacity(configuration.isPressed ? 0.72 : 1)
            .animation(
                reduceMotion ? nil : .spring(response: 0.24, dampingFraction: 0.72),
                value: configuration.isPressed
            )
    }
}

struct SharedTopBar: View {
    var onBack: (() -> Void)?
    let historySelected: Bool
    let onHistory: () -> Void

    var body: some View {
        ZStack {
            Text("NOTE1")
                .noteFontCapped(
                    size: 22,
                    maximumScale: 1.3,
                    weight: .medium,
                    design: .rounded,
                    relativeTo: .title3
                )
                .tracking(7)
                .foregroundStyle(NoteTheme.ink)
                .accessibilityAddTraits(.isHeader)

            HStack {
                Group {
                    if let onBack {
                        RoundGlassButton(
                            systemName: "chevron.left",
                            label: "返回",
                            action: onBack
                        )
                    } else {
                        Color.clear
                    }
                }
                .frame(width: NoteTheme.controlSize, height: NoteTheme.controlSize)

                Spacer()

                RoundGlassButton(
                    systemName: "clock.arrow.circlepath",
                    label: "历史记录",
                    selected: historySelected,
                    action: onHistory
                )
            }
        }
        .frame(height: NoteTheme.topBarHeight)
    }
}

struct EmptyStateView: View {
    let systemName: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: systemName)
                .font(.system(size: 34, weight: .light))
            Text(title)
                .noteFont(
                    size: 21,
                    weight: .semibold,
                    design: .rounded,
                    relativeTo: .title3
                )
            if !message.isEmpty {
                Text(message)
                    .noteFont(size: 15, relativeTo: .subheadline)
                    .foregroundStyle(NoteTheme.secondaryInk)
                    .multilineTextAlignment(.center)
            }
        }
        .foregroundStyle(NoteTheme.ink)
        .padding(28)
    }
}

struct UserFacingAlert: Identifiable {
    let id = UUID()
    let message: String

    init(error: Error) {
        message = error.localizedDescription
    }

    init(message: String) {
        self.message = message
    }

    static func local(error: Error) -> UserFacingAlert? {
        if let storeError = error as? NoteStoreError,
           case .persistenceWriteFailed = storeError {
            return nil
        }
        return UserFacingAlert(error: error)
    }
}

extension View {
    func noteErrorAlert(_ alert: Binding<UserFacingAlert?>) -> some View {
        self.alert(item: alert) { alert in
            Alert(
                title: Text("操作未完成"),
                message: Text(alert.message),
                dismissButton: .default(Text("知道了"))
            )
        }
    }
}

enum NoteDateFormatter {
    static let relative: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日 HH:mm"
        return formatter
    }()

    static let group: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日 EEEE"
        return formatter
    }()

    static let time: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    static func display(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) {
            return "今天 \(time.string(from: date))"
        }
        if Calendar.current.isDateInYesterday(date) {
            return "昨天 \(time.string(from: date))"
        }
        return relative.string(from: date)
    }
}

extension View {
    func hideKeyboardOnTap() -> some View {
        simultaneousGesture(
            TapGesture().onEnded {
                UIApplication.shared.sendAction(
                    #selector(UIResponder.resignFirstResponder),
                    to: nil,
                    from: nil,
                    for: nil
                )
            }
        )
    }

    @ViewBuilder
    func noteScrollBackgroundHidden() -> some View {
        if #available(iOS 16.0, *) {
            scrollContentBackground(.hidden)
        } else {
            self
        }
    }

    @ViewBuilder
    func noteScrollDismissesKeyboard() -> some View {
        if #available(iOS 16.0, *) {
            scrollDismissesKeyboard(.interactively)
        } else {
            self
        }
    }
}
