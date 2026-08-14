import SwiftUI
import UIKit

enum NoteTheme {
    static let ink = Color(red: 0.165, green: 0.090, blue: 0.145)
    static let secondaryInk = Color(
        red: V02ColorContrastPolicy.secondaryInk.red,
        green: V02ColorContrastPolicy.secondaryInk.green,
        blue: V02ColorContrastPolicy.secondaryInk.blue
    )
    static let accent = ink
    static let danger = Color.red
    static let canvasTop = Color(red: 0.980, green: 0.976, blue: 0.984)
    static let canvasBottom = Color(red: 0.953, green: 0.945, blue: 0.957)
    static let canvas = canvasTop
    static let paper = Color(red: 0.992, green: 0.988, blue: 0.994)
    static let receiptPaper = Color(red: 0.988, green: 0.988, blue: 0.984)
    static let receiptInk = Color(red: 0.075, green: 0.078, blue: 0.085)
    static let receiptSecondaryInk = Color(red: 0.37, green: 0.38, blue: 0.41)
    static let receiptDivider = receiptInk.opacity(0.16)
    static let divider = Color(red: 0.871, green: 0.851, blue: 0.878)
    static let paperBorder = divider
    static let selectedGlass = Color(red: 0.933, green: 0.906, blue: 0.925)

    static let horizontalPadding: CGFloat = 22
    static let topBarHeight: CGFloat = 56
    static let controlSize: CGFloat = 48
    static let controlVisualSize: CGFloat = 46
    static let floatingComposerSize: CGFloat = 56
    static let floatingComposerVisualSize: CGFloat = 48
    static let navigationHeight: CGFloat = 78
    static let cornerRadius: CGFloat = 30

    static let background = LinearGradient(
        colors: [canvasTop, canvasBottom],
        startPoint: .top,
        endPoint: .bottom
    )

    static let paperSurface = LinearGradient(
        colors: [
            Color(red: 0.998, green: 0.996, blue: 0.999),
            paper,
            Color(red: 0.976, green: 0.971, blue: 0.979)
        ],
        startPoint: .top,
        endPoint: .bottom
    )

    static let receiptPaperSurface = LinearGradient(
        colors: [
            Color(red: 0.998, green: 0.998, blue: 0.996),
            receiptPaper,
            Color(red: 0.958, green: 0.958, blue: 0.954)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

/// Small secondary labels appear directly on the darkest stop of NOTE1's
/// light canvas as well as on paper. Keep their shared ink above the 4.5:1
/// body-text contrast floor instead of compensating page by page.
enum V02ColorContrastPolicy {
    static let secondaryInk = (red: 0.443, green: 0.416, blue: 0.447)
    static let darkestCanvas = (red: 0.953, green: 0.945, blue: 0.957)

    static var minimumSecondaryTextContrast: Double {
        contrastRatio(foreground: secondaryInk, background: darkestCanvas)
    }

    private static func contrastRatio(
        foreground: (red: Double, green: Double, blue: Double),
        background: (red: Double, green: Double, blue: Double)
    ) -> Double {
        let foregroundLuminance = relativeLuminance(foreground)
        let backgroundLuminance = relativeLuminance(background)
        return (max(foregroundLuminance, backgroundLuminance) + 0.05)
            / (min(foregroundLuminance, backgroundLuminance) + 0.05)
    }

    private static func relativeLuminance(
        _ color: (red: Double, green: Double, blue: Double)
    ) -> Double {
        let red = linearized(color.red)
        let green = linearized(color.green)
        let blue = linearized(color.blue)
        return 0.2126 * red + 0.7152 * green + 0.0722 * blue
    }

    private static func linearized(_ component: Double) -> Double {
        component <= 0.04045
            ? component / 12.92
            : pow((component + 0.055) / 1.055, 2.4)
    }
}

enum NoteMotion {
    static func press(reduceMotion: Bool) -> Animation {
        .easeOut(duration: reduceMotion ? 0.08 : 0.12)
    }

    static func reveal(reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeOut(duration: 0.14) : .spring(response: 0.34, dampingFraction: 0.82)
    }

    static func settle(reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeOut(duration: 0.14) : .spring(response: 0.36, dampingFraction: 0.88)
    }
}

/// Shared geometry decisions for the four primary destinations. Keeping these
/// values in one place prevents the visual bar and its hit targets drifting
/// apart on the narrow 368pt viewport.
enum V02NavigationLayoutPolicy {
    static let cellMinHeight: CGFloat = 72
    static let barHeight: CGFloat = 76
    /// Compact page-level header height shared by primary roots and global
    /// secondary pages with full-width centered titles.
    static let pageHeaderHeight: CGFloat = NoteTheme.controlSize + 8
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
        !isOverlayPresented
    }

    static func composerLabel(for page: V02PrimaryPage) -> String {
        "新增灵感"
    }
}

/// One geometry and brand contract for the four primary-page headers. Page
/// actions may differ, but the left, center, and right anchors never do.
enum V02PrimaryHeaderPolicy {
    static let title = "NOTE1"
    static let titleWidth: CGFloat = 120
    static let titleTracking: CGFloat = 5
    static let actionSpacing: CGFloat = 4
}

/// Shared first-screen rhythm for the four primary destinations. The content
/// type may change from a timeline to a paper deck, but its visible start and
/// outer edge stay anchored to the same canvas grid.
enum V02PrimaryContentLayoutPolicy {
    static let horizontalInset = NoteTheme.horizontalPadding
    static let topSpacing: CGFloat = 8
    static let stackedPaperBackOffset: CGFloat = 9
    static let stackedPaperMiddleOffset: CGFloat = 5
}

enum V02PrimaryTypographyPolicy {
    static let contextLabelSize: CGFloat = 14
    static let contextLabelMaximumScale: CGFloat = 1.25
}

/// Shared visible nouns for batch actions that operate on inspirations. The
/// full object/action names stay stable even when a compact toolbar falls back
/// to a vertical layout on narrow screens.
enum V02InspirationSelectionCopy {
    static let returnToCardFlow = "放回卡片流"
    static let assignToCollection = "归入构思集"
}

/// One accessibility fallback for every NOTE1-owned glass surface. The
/// geometry stays unchanged when Reduce Transparency is enabled; only the
/// material becomes opaque and its edge gains enough contrast to remain
/// legible against the light canvas.
enum V02GlassSurfacePolicy {
    static let reducedTransparencyBorderOpacity = 0.50
    static let reducedTransparencyShadowOpacity = 0.08

    static func usesOpaqueSurface(reduceTransparency: Bool) -> Bool {
        reduceTransparency
    }
}

struct GlassSurface: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var cornerRadius: CGFloat = NoteTheme.cornerRadius
    var strokeOpacity: Double = 0.76
    var castsShadow = true

    @ViewBuilder
    func body(content: Content) -> some View {
        if V02GlassSurfacePolicy.usesOpaqueSurface(reduceTransparency: reduceTransparency) {
            content
                .background(NoteTheme.canvasTop)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(
                            NoteTheme.divider,
                            lineWidth: 1
                        )
                }
                .shadow(
                    color: castsShadow
                        ? NoteTheme.ink.opacity(V02GlassSurfacePolicy.reducedTransparencyShadowOpacity)
                        : .clear,
                    radius: castsShadow ? 8 : 0,
                    y: castsShadow ? 3 : 0
                )
        } else if #available(iOS 26.0, *) {
            content
                .glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
                .shadow(
                    color: castsShadow ? NoteTheme.ink.opacity(0.07) : .clear,
                    radius: castsShadow ? 10 : 0,
                    y: castsShadow ? 4 : 0
                )
        } else {
            content
                .background(.ultraThinMaterial)
                .background(NoteTheme.canvasTop.opacity(0.18))
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(NoteTheme.divider.opacity(strokeOpacity), lineWidth: 1)
                }
                .shadow(
                    color: castsShadow ? NoteTheme.ink.opacity(0.07) : .clear,
                    radius: castsShadow ? 10 : 0,
                    y: castsShadow ? 4 : 0
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

/// Hides the SwiftUI presentation host behind a nested sheet from VoiceOver.
/// SwiftUI's `accessibilityHidden` is not sufficient when the presenting and
/// presented surfaces live in separate UIKit hosting controllers.
struct V02PresentedContentAccessibilityIsolation: UIViewRepresentable {
    let isPresented: Bool

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        Self.apply(isPresented, from: uiView)
        DispatchQueue.main.async { Self.apply(isPresented, from: uiView) }
    }

    static func dismantleUIView(_ uiView: UIView, coordinator: Void) {
        apply(false, from: uiView)
    }

    private static func apply(_ hidden: Bool, from view: UIView) {
        var responder: UIResponder? = view
        while let current = responder {
            if let controller = current as? UIViewController {
                controller.view.accessibilityElementsHidden = hidden
                return
            }
            responder = current.next
        }
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
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    let systemName: String

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(NoteTheme.ink)
            .frame(width: NoteTheme.controlSize, height: NoteTheme.controlSize)
            .background {
                if V02GlassSurfacePolicy.usesOpaqueSurface(reduceTransparency: reduceTransparency) {
                    Circle()
                        .fill(NoteTheme.canvasTop)
                        .frame(width: NoteTheme.controlVisualSize, height: NoteTheme.controlVisualSize)
                        .overlay {
                            Circle()
                                .stroke(
                                    NoteTheme.divider,
                                    lineWidth: 1
                                )
                        }
                } else if #available(iOS 26.0, *) {
                    Color.clear.frame(width: NoteTheme.controlVisualSize, height: NoteTheme.controlVisualSize).glassEffect(.regular.interactive(), in: .circle)
                } else {
                    Circle()
                        .fill(.ultraThinMaterial)
                        .frame(width: NoteTheme.controlVisualSize, height: NoteTheme.controlVisualSize)
                        .overlay { Circle().fill(NoteTheme.canvasTop.opacity(0.22)) }
                        .overlay { Circle().stroke(NoteTheme.divider, lineWidth: 1) }
                }
            }
            .shadow(color: NoteTheme.ink.opacity(0.055), radius: 8, y: 3)
            .contentShape(Circle())
    }
}

/// The same global menu is used by every primary page. Page-specific actions
/// stay out of this menu so the left slot remains predictable: only local
/// archive access (回收站) and app preferences (设置) are exposed here.
struct V02GlobalMenuButton: View {
    let showTrash: () -> Void
    let showSettings: () -> Void

    var body: some View {
        Menu {
            Button("回收站", systemImage: "trash", action: showTrash)
            Button("设置", systemImage: "gearshape", action: showSettings)
        } label: {
            V02GlassIconLabel(systemName: "line.3.horizontal")
        }
        .accessibilityLabel("本机功能与设置")
    }
}

struct V02PrimaryHeaderTitle: View {
    var showsMenuIndicator = false

    var body: some View {
        ZStack {
            Text(V02PrimaryHeaderPolicy.title)
                .noteFontCapped(
                    size: 20,
                    maximumScale: 1.2,
                    weight: .semibold,
                    design: .rounded,
                    relativeTo: .headline
                )
                .tracking(V02PrimaryHeaderPolicy.titleTracking)

            if showsMenuIndicator {
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .offset(x: 55)
                    .accessibilityHidden(true)
            }
        }
        .frame(width: V02PrimaryHeaderPolicy.titleWidth, height: NoteTheme.controlSize)
        .foregroundStyle(NoteTheme.ink)
        .accessibilityAddTraits(.isHeader)
    }
}

struct V02PrimaryPageHeader<Center: View>: View {
    let showTrash: () -> Void
    let showSettings: () -> Void
    let showHistory: () -> Void
    let showSearch: () -> Void
    let center: Center

    init(
        showTrash: @escaping () -> Void,
        showSettings: @escaping () -> Void,
        showHistory: @escaping () -> Void,
        showSearch: @escaping () -> Void,
        @ViewBuilder center: () -> Center
    ) {
        self.showTrash = showTrash
        self.showSettings = showSettings
        self.showHistory = showHistory
        self.showSearch = showSearch
        self.center = center()
    }

    var body: some View {
        ZStack {
            HStack(spacing: 0) {
                V02GlobalMenuButton(showTrash: showTrash, showSettings: showSettings)
                Spacer(minLength: 0)
                HStack(spacing: V02PrimaryHeaderPolicy.actionSpacing) {
                    V02GlassIconButton(
                        systemName: "clock.arrow.circlepath",
                        label: "历史记录",
                        action: showHistory
                    )
                    V02GlassIconButton(
                        systemName: "magnifyingglass",
                        label: "搜索",
                        action: showSearch
                    )
                }
            }

            center
        }
        .padding(.horizontal, NoteTheme.horizontalPadding)
        .frame(height: V02NavigationLayoutPolicy.pageHeaderHeight)
        .background(NoteTheme.canvasTop.opacity(0.96))
    }
}

/// Shared geometry for global modal pages such as search, history, trash and
/// settings. Their leading semantics may differ (cancel, back or close), but
/// the title anchor, hit targets and safe-area rhythm stay identical.
struct V02SecondaryPageHeader<Leading: View, Trailing: View>: View {
    let title: String
    let leading: Leading
    let trailing: Trailing

    init(
        _ title: String,
        @ViewBuilder leading: () -> Leading,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.title = title
        self.leading = leading()
        self.trailing = trailing()
    }

    var body: some View {
        ZStack {
            Text(title)
                .noteFontCapped(
                    size: 20,
                    maximumScale: 1.2,
                    weight: .semibold,
                    design: .rounded,
                    relativeTo: .headline
                )
                .foregroundStyle(NoteTheme.ink)
                .accessibilityAddTraits(.isHeader)

            HStack(spacing: 0) {
                leading
                    .frame(minWidth: NoteTheme.controlSize, alignment: .leading)
                Spacer(minLength: 0)
                trailing
                    .frame(minWidth: NoteTheme.controlSize, alignment: .trailing)
            }
        }
        .padding(.horizontal, NoteTheme.horizontalPadding)
        .frame(height: V02NavigationLayoutPolicy.pageHeaderHeight)
        .background(NoteTheme.canvasTop.opacity(0.96))
    }
}

struct V02ScopeSectionLabel: View {
    var body: some View {
        Text("当前范围")
            .noteFontCapped(
                size: V02PrimaryTypographyPolicy.contextLabelSize,
                maximumScale: V02PrimaryTypographyPolicy.contextLabelMaximumScale,
                weight: .semibold,
                relativeTo: .subheadline
            )
            .foregroundStyle(NoteTheme.secondaryInk)
    }
}

struct V02SecondaryHeaderPlaceholder: View {
    var body: some View {
        Color.clear
            .frame(width: NoteTheme.controlSize, height: NoteTheme.controlSize)
            .accessibilityHidden(true)
    }
}

struct V02GlassTextButton: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            textLabel
        }
        .buttonStyle(RoundGlassPressButtonStyle())
        .accessibilityLabel(title)
    }

    @ViewBuilder
    private var textLabel: some View {
        if V02GlassSurfacePolicy.usesOpaqueSurface(reduceTransparency: reduceTransparency) {
            labelContent
                .background(NoteTheme.canvasTop, in: Capsule())
                .overlay {
                    Capsule()
                        .stroke(
                            NoteTheme.divider,
                            lineWidth: 1
                        )
                }
        } else if #available(iOS 26.0, *) {
            labelContent
                .glassEffect(.regular.interactive(), in: .capsule)
        } else {
            labelContent
                .background(.ultraThinMaterial, in: Capsule())
                .overlay { Capsule().stroke(NoteTheme.divider, lineWidth: 1) }
        }
    }

    private var labelContent: some View {
        Text(title)
            .noteFontCapped(
                size: 16,
                maximumScale: 1.2,
                weight: .medium,
                relativeTo: .body
            )
            .foregroundStyle(NoteTheme.ink)
            .padding(.horizontal, 14)
            .frame(minWidth: NoteTheme.controlSize, minHeight: NoteTheme.controlVisualSize)
            .contentShape(Capsule())
            .shadow(color: NoteTheme.ink.opacity(0.055), radius: 8, y: 3)
            .frame(minHeight: NoteTheme.controlSize)
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
            .scaleEffect(isPressed && !reduceMotion ? 0.97 : 1)
            .brightness(isPressed ? -0.055 : 0)
            .saturation(isPressed ? 0.9 : 1)
            .animation(NoteMotion.press(reduceMotion: reduceMotion), value: isPressed)
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
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.84 : 1)
            .animation(NoteMotion.press(reduceMotion: reduceMotion), value: configuration.isPressed)
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
        if let storeError = error as? StoreError,
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
