import SwiftUI
import UIKit

enum NoteTheme {
    static let ink = Color(red: 0.035, green: 0.105, blue: 0.205)
    static let secondaryInk = Color(red: 0.48, green: 0.54, blue: 0.67)
    static let accent = Color(red: 0.20, green: 0.45, blue: 0.95)
    static let danger = Color(red: 0.91, green: 0.24, blue: 0.27)
    static let canvas = Color(red: 0.955, green: 0.955, blue: 1.0)
    static let divider = Color.white.opacity(0.72)

    static let horizontalPadding: CGFloat = 24
    static let topBarHeight: CGFloat = 58
    static let controlSize: CGFloat = 48
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
                        .fill(Color.white.opacity(0.46))
                        .overlay {
                            Circle()
                                .fill(NoteTheme.ink.opacity(0.014))
                        }
                }
            }
            .contentShape(Circle())
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
                .noteFont(
                    size: 22,
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
