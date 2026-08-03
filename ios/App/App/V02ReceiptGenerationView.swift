import SwiftUI
import UIKit

enum V02ReceiptGenerationPhase: Equatable {
    case preparing
    case printing
    case settled
    case cancelled
}

enum V02ReceiptGenerationPolicy {
    static let normalDuration: TimeInterval = 0.78
    static let reducedMotionDuration: TimeInterval = 0.28
    static let undoWindow: TimeInterval = 2

    static func contentOpacity(for progress: CGFloat) -> CGFloat {
        min(1, max(0, (progress - 0.18) / 0.52))
    }
}

/// Root-shell layout contract: generation feedback stays below the primary navigation layer.
enum V02ReceiptGenerationLayoutPolicy {
    static let navigationGap: CGFloat = 18
    static let generationZIndex: Double = 10
    static let primaryNavigationZIndex: Double = 20
    static let composerZIndex: Double = 30

    static func bottomPadding(navigationHeight: CGFloat) -> CGFloat {
        navigationHeight + navigationGap
    }
}

/// 结束本轮构思成功后的唯一出票反馈。数据保存由调用方先完成，视图只负责展示与后续路径。
struct V02ReceiptGenerationView: View {
    @ObservedObject var store: V02Store
    let receipt: V02Receipt
    let onView: (V02Receipt) -> Void
    let onReturn: () -> Void
    let onUndo: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var phase: V02ReceiptGenerationPhase = .preparing
    @State private var progress: CGFloat = 0
    @State private var didStart = false
    @State private var undoRemaining = V02ReceiptGenerationPolicy.undoWindow

    var body: some View {
        ZStack {
            NoteTheme.background
                .opacity(reduceTransparency ? 1 : 0.98)
                .ignoresSafeArea()
            VStack(spacing: 12) {
                generationHeader
                ZStack(alignment: .top) {
                    V02ReceiptPaper(
                        store: store,
                        receipt: receipt,
                        template: V02ReceiptTemplate.recommended(for: receipt, resources: store.state.resources),
                        minimumHeight: 500
                    )
                    .padding(.horizontal, 44)
                    .offset(y: -500 + progress * 522)
                    .opacity(V02ReceiptGenerationPolicy.contentOpacity(for: progress))
                    .scaleEffect(0.98 + progress * 0.02, anchor: .top)
                    .accessibilityHidden(phase != .settled)

                    V02TicketClip()
                        .padding(.horizontal, 20)
                        .zIndex(2)
                }
                .frame(maxWidth: .infinity, minHeight: 500, maxHeight: .infinity, alignment: .top)
                .clipped()
                .accessibilityHidden(true)

                if phase == .settled {
                    settledActions
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                } else {
                    Text(statusMessage)
                        .noteFont(size: 13, relativeTo: .caption)
                        .foregroundStyle(NoteTheme.secondaryInk)
                        .accessibilityIdentifier("v02.receipt.generation.status")
                        .transition(.opacity)
                }
            }
            .padding(.horizontal, NoteTheme.horizontalPadding)
            .padding(.top, 14)
            .padding(.bottom, 4)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(phase == .settled ? "小票已生成，来自\(receipt.snapshot.collectionName)" : "正在生成构思小票")
        .onAppear { startAnimationIfNeeded() }
        .onDisappear { didStart = false }
    }

    private var generationHeader: some View {
        Text("小票册")
            .noteFont(size: 22, weight: .semibold, design: .rounded, relativeTo: .title2)
            .foregroundStyle(NoteTheme.ink)
            .accessibilityAddTraits(.isHeader)
            .frame(maxWidth: .infinity, minHeight: NoteTheme.topBarHeight)
    }

    private var statusMessage: String {
        switch phase {
        case .preparing: return "夹口已固定，准备出票"
        case .printing: return "这一轮构思正在变成一张存根"
        case .settled: return "这张小票已保存"
        case .cancelled: return "已撤回本轮小票"
        }
    }

    private var settledActions: some View {
        HStack(spacing: 8) {
            Button("查看小票") { onView(receipt) }
                .buttonStyle(V02ReceiptGenerationActionStyle(prominent: true))
                .accessibilityIdentifier("v02.receipt.generation.view")
            Button("返回") { onReturn() }
                .buttonStyle(V02ReceiptGenerationActionStyle(prominent: false))
                .accessibilityIdentifier("v02.receipt.generation.return")

            if undoRemaining > 0 {
                Button("撤回（\(Int(ceil(undoRemaining)))s）") { onUndo() }
                    .buttonStyle(V02ReceiptGenerationActionStyle(prominent: false))
                    .accessibilityLabel("撤回刚生成的小票")
                    .accessibilityIdentifier("v02.receipt.generation.undo")
            }
        }
        .frame(minHeight: 46)
        .onAppear { startUndoCountdown() }
    }

    private func startAnimationIfNeeded() {
        guard !didStart else { return }
        didStart = true
        let duration = reduceMotion
            ? V02ReceiptGenerationPolicy.reducedMotionDuration
            : V02ReceiptGenerationPolicy.normalDuration
        DispatchQueue.main.asyncAfter(deadline: .now() + (reduceMotion ? 0.06 : 0.16)) {
            guard didStart else { return }
            phase = .printing
            withAnimation(.easeOut(duration: duration)) { progress = 1 }
            DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
                guard didStart else { return }
                phase = .settled
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
        }
    }

    private func startUndoCountdown() {
        guard undoRemaining > 0 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            guard phase == .settled, undoRemaining > 0 else { return }
            undoRemaining = max(0, undoRemaining - 0.1)
            startUndoCountdown()
        }
    }
}

private struct V02ReceiptGenerationActionStyle: ButtonStyle {
    let prominent: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .noteFont(size: 14, weight: .semibold, relativeTo: .subheadline)
            .foregroundStyle(prominent ? .white : NoteTheme.ink)
            .frame(maxWidth: .infinity, minHeight: 42)
            .background(
                prominent ? NoteTheme.ink : Color.white.opacity(0.62),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.white.opacity(prominent ? 0.32 : 0.82), lineWidth: 1)
            }
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
    }
}
