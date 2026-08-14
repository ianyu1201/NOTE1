import SwiftUI
import UIKit

enum V02ReceiptGenerationPhase: Equatable {
    case preparing
    case printing
    case settled
    case cancelled
}

enum V02ReceiptGenerationPolicy {
    /// The receipt reveal follows the contracted thermal-printer storyboard:
    /// a continuous 1.4 second feed, a short pause, then a 0.42 second lift.
    static let normalDuration: TimeInterval = 1.4
    static let outletRevealDuration: TimeInterval = 1.4
    static let revealPause: TimeInterval = 0.08
    static let liftDuration: TimeInterval = 0.42
    /// Reduce Motion keeps the result relationship while collapsing the
    /// physical feed and lift into a short fade with an 8pt displacement.
    static let reducedMotionDuration: TimeInterval = 0.2
    static let reducedMotionDisplacement: CGFloat = 8
    static let initialPaperTail: CGFloat = 18
    static let initialPaperScale: CGFloat = 0.84
    static let settledPaperScale: CGFloat = 1
    static func contentOpacity(for progress: CGFloat) -> CGFloat {
        min(1, max(0, (progress - 0.18) / 0.52))
    }

    static func revealHeight(for progress: CGFloat, paperHeight: CGFloat) -> CGFloat {
        let clampedProgress = min(1, max(0, progress))
        return initialPaperTail + clampedProgress * max(0, paperHeight - initialPaperTail)
    }

    static func paperScale(for liftProgress: CGFloat) -> CGFloat {
        let clampedProgress = min(1, max(0, liftProgress))
        return initialPaperScale + clampedProgress * (settledPaperScale - initialPaperScale)
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
    /// Kept as the existing call-site API. In V0.4 this is invoked by the
    /// tappable result thumbnail rather than a separate “查看” button.
    let onView: (V02Receipt) -> Void
    let onReturn: () -> Void
    var resumesFromSavedResult = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.scenePhase) private var scenePhase
    @State private var phase: V02ReceiptGenerationPhase = .preparing
    @State private var revealProgress: CGFloat = 0
    @State private var liftProgress: CGFloat = 0
    @State private var resultOpacity: CGFloat = 0
    @State private var didStart = false
    @State private var didAnnounceSuccess = false
    @State private var animationTask: Task<Void, Never>?

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                if phase == .settled {
                    settledResult(in: proxy.size)
                } else {
                    ZStack(alignment: .top) {
                        generationTopChrome
                        generationStage(in: proxy.size)
                    }
                        // The stage is deliberately one accessibility element;
                        // individual animation frames must never be announced.
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("正在生成构思小票")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear { startAnimationIfNeeded() }
        .onDisappear {
            animationTask?.cancel()
            animationTask = nil
            didStart = false
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase != .active, phase == .printing {
                settleResult(announcesSuccess: false)
            } else if newPhase == .active, phase == .settled {
                announceSuccessIfNeeded()
            }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: phase == .settled)
    }

    /// The collection workbench removes its root header while the generation
    /// overlay is presented. Keep the shared NOTE1 top geometry visible for
    /// the printer storyboard without introducing a second navigational model.
    private var generationTopChrome: some View {
        ZStack {
            HStack(spacing: 4) {
                generationChromeButton(systemName: "line.3.horizontal")
                Spacer(minLength: 0)
                generationChromeButton(systemName: "clock.arrow.circlepath")
                generationChromeButton(systemName: "magnifyingglass")
            }

            HStack(spacing: 7) {
                Text("NOTE1")
                    .noteFont(size: 16, weight: .semibold, design: .rounded, relativeTo: .headline)
                    .tracking(4)
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
            }
            .foregroundStyle(NoteTheme.ink)
            .accessibilityHidden(true)
        }
        .padding(.horizontal, NoteTheme.horizontalPadding)
        .frame(height: V02NavigationLayoutPolicy.pageHeaderHeight)
        .background(NoteTheme.canvasTop.opacity(0.96))
        .accessibilityHidden(true)
    }

    private func generationChromeButton(systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(NoteTheme.ink)
            .frame(width: NoteTheme.controlVisualSize, height: NoteTheme.controlVisualSize)
            .background {
                if reduceTransparency {
                    Circle().fill(NoteTheme.canvasTop)
                } else {
                    Circle().fill(.ultraThinMaterial)
                }
            }
            .overlay {
                Circle()
                    .stroke(NoteTheme.divider.opacity(0.74), lineWidth: 1)
            }
    }

    private func generationStage(in size: CGSize) -> some View {
        let paperHeight: CGFloat = 500
        let paperWidth = min(max(size.width - 96, 220), 276)
        let printerWidth = min(max(size.width - 58, 264), 330)
        let stageHeight = max(520, min(650, size.height - 150))
        let printerHeight: CGFloat = 146
        let outletY: CGFloat = 106
        let settledY: CGFloat = 34
        let effectiveRevealProgress = reduceMotion ? 1 : revealProgress
        let revealHeight = V02ReceiptGenerationPolicy.revealHeight(
            for: effectiveRevealProgress,
            paperHeight: paperHeight
        )
        let paperTravel = reduceMotion
            ? V02ReceiptGenerationPolicy.reducedMotionDisplacement
            : outletY - settledY
        let paperStartY = reduceMotion ? settledY + paperTravel : outletY
        let paperY = paperStartY - liftProgress * paperTravel
        let paperScale = reduceMotion
            ? V02ReceiptGenerationPolicy.settledPaperScale
            : V02ReceiptGenerationPolicy.paperScale(for: liftProgress)

        return ZStack(alignment: .top) {
            // The paper stays behind the printer until the lift starts. The
            // narrow outlet and the stable printer front then mask the join.
            receiptPaper(
                width: paperWidth,
                height: paperHeight,
                revealHeight: revealHeight,
                scale: paperScale
            )
            .offset(y: paperY)
            .opacity(reduceMotion ? resultOpacity : 1)
            .zIndex(liftProgress > 0.001 ? 4 : 1)
            .accessibilityHidden(true)

            V02ReceiptGenerationPrinter(
                width: printerWidth,
                height: printerHeight,
                reduceTransparency: reduceTransparency
            )
            .opacity(reduceMotion ? resultOpacity : 1 - liftProgress)
            .zIndex(3)
            .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity, minHeight: stageHeight, maxHeight: stageHeight, alignment: .top)
        .clipped()
        .padding(.horizontal, 20)
        .padding(.top, 78)
        .opacity(phase == .preparing ? 0.96 : 1)
        .animation(.easeOut(duration: 0.12), value: phase)
    }

    private func settledResult(in size: CGSize) -> some View {
        let paperWidth = min(max(size.width - 84, 238), 282)
        let thumbnailHeight = min(500, max(360, size.height * 0.58))

        return ZStack {
            // Once the receipt is settled the generation layer becomes a
            // quiet result surface. The underlying page controls stay out of
            // this result content; the root shell still owns the navigation
            // layer during the printing storyboard.
            NoteTheme.background
                .ignoresSafeArea()

            VStack(spacing: 12) {
                successBanner
                    .opacity(resultOpacity)
                    .transition(.opacity)

                Spacer(minLength: 4)

                Button {
                    onView(receipt)
                } label: {
                    receiptPaper(
                        width: paperWidth,
                        height: 500,
                        revealHeight: 500,
                        scale: V02ReceiptGenerationPolicy.settledPaperScale
                    )
                    .frame(width: paperWidth, height: thumbnailHeight, alignment: .top)
                    .clipped()
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(receiptThumbnailAccessibilityLabel)
                .accessibilityHint("双击查看完整小票")
                .accessibilityIdentifier("v02.receipt.generation.thumbnail")
                .opacity(resultOpacity)

                Spacer(minLength: 8)

                Button("返回构思集") {
                    onReturn()
                }
                .noteFont(size: 15, weight: .semibold, relativeTo: .subheadline)
                .foregroundStyle(NoteTheme.ink)
                .frame(maxWidth: 300, minHeight: 48)
                .noteGlass(cornerRadius: 24, castsShadow: false)
                .buttonStyle(PressScaleButtonStyle())
                .accessibilityIdentifier("v02.receipt.generation.return")
            }
            .padding(.horizontal, NoteTheme.horizontalPadding)
            .padding(.top, 12)
            .padding(.bottom, 4)
        }
        .accessibilityElement(children: .contain)
    }

    private var successBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 16, weight: .semibold))
            Text("已生成并保存小票册")
                .noteFont(size: 14, weight: .semibold, relativeTo: .subheadline)
        }
        .foregroundStyle(NoteTheme.ink)
        .padding(.horizontal, 18)
        .frame(minHeight: 44)
        .noteGlass(cornerRadius: 22, castsShadow: false)
        // The explicit announcement below is the sole VoiceOver success
        // announcement. Keeping this visual toast hidden avoids a duplicate.
        .accessibilityHidden(true)
        .accessibilityIdentifier("v02.receipt.generation.success")
    }

    private var receiptThumbnailAccessibilityLabel: String {
        "\(receipt.snapshot.collectionName)小票，\(receipt.statistics.roundTitle)"
    }

    private func receiptPaper(
        width: CGFloat,
        height: CGFloat,
        revealHeight: CGFloat,
        scale: CGFloat
    ) -> some View {
        V02ReceiptPaper(
            store: store,
            receipt: receipt,
            template: V02ReceiptTemplate.recommended(for: receipt, resources: store.state.resources),
            minimumHeight: height
        )
        .frame(width: width)
        .frame(height: max(2, revealHeight), alignment: .top)
        .clipped()
        .scaleEffect(scale, anchor: .top)
    }

    private func startAnimationIfNeeded() {
        guard !didStart else { return }

        // If the app was interrupted after persistence, the saved receipt is
        // authoritative. Resume directly to its thumbnail instead of feeding
        // or committing a second time.
        if resumesFromSavedResult || phase == .printing {
            recoverToSettledResult()
            return
        }
        guard phase == .preparing else { return }
        didStart = true
        phase = .printing

        if reduceMotion {
            withAnimation(.easeInOut(duration: V02ReceiptGenerationPolicy.reducedMotionDuration)) {
                revealProgress = 1
                liftProgress = 1
                resultOpacity = 1
            }
            animationTask = Task { @MainActor in
                try? await Task.sleep(for: .seconds(V02ReceiptGenerationPolicy.reducedMotionDuration))
                guard !Task.isCancelled else { return }
                settleResult(announcesSuccess: scenePhase == .active)
            }
            return
        }

        withAnimation(.easeInOut(duration: V02ReceiptGenerationPolicy.outletRevealDuration)) {
            revealProgress = 1
        }
        animationTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(V02ReceiptGenerationPolicy.outletRevealDuration))
            guard !Task.isCancelled, didStart, phase == .printing else { return }
            try? await Task.sleep(for: .seconds(V02ReceiptGenerationPolicy.revealPause))
            guard !Task.isCancelled, didStart, phase == .printing else { return }
            withAnimation(.easeOut(duration: V02ReceiptGenerationPolicy.liftDuration)) {
                liftProgress = 1
                resultOpacity = 1
            }
            try? await Task.sleep(for: .seconds(V02ReceiptGenerationPolicy.liftDuration))
            guard !Task.isCancelled else { return }
            settleResult(announcesSuccess: scenePhase == .active)
        }
    }

    private func recoverToSettledResult() {
        didStart = true
        withAnimation(.easeInOut(duration: V02ReceiptGenerationPolicy.reducedMotionDuration)) {
            revealProgress = 1
            liftProgress = 1
            resultOpacity = 1
        }
        animationTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(V02ReceiptGenerationPolicy.reducedMotionDuration))
            guard !Task.isCancelled else { return }
            settleResult(announcesSuccess: scenePhase == .active)
        }
    }

    private func settleResult(announcesSuccess: Bool) {
        animationTask?.cancel()
        animationTask = nil
        revealProgress = 1
        liftProgress = 1
        resultOpacity = 1
        phase = .settled
        if announcesSuccess {
            announceSuccessIfNeeded()
        }
    }

    private func announceSuccessIfNeeded() {
        guard !didAnnounceSuccess else { return }
        didAnnounceSuccess = true
        UIAccessibility.post(
            notification: .announcement,
            argument: "已生成并保存小票册"
        )
    }
}

/// A quiet, stable printer body. The paper layer is fed behind this front
/// surface, so the dark slot remains the visual anchor throughout the feed.
private struct V02ReceiptGenerationPrinter: View {
    let width: CGFloat
    let height: CGFloat
    let reduceTransparency: Bool

    var body: some View {
        ZStack(alignment: .top) {
            printerSurface

            HStack(spacing: 7) {
                Circle()
                    .fill(NoteTheme.receiptInk.opacity(0.68))
                    .frame(width: 5, height: 5)
                Circle()
                    .fill(NoteTheme.receiptInk.opacity(0.32))
                    .frame(width: 5, height: 5)
                Spacer()
                Image(systemName: "printer.fill")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(NoteTheme.receiptInk.opacity(0.42))
            }
            .padding(.horizontal, 22)
            .padding(.top, 22)

            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(NoteTheme.receiptInk.opacity(0.88))
                .frame(width: min(width - 86, 178), height: 9)
                .overlay(alignment: .trailing) {
                    HStack(spacing: 4) {
                        Circle().fill(Color.white.opacity(0.85)).frame(width: 3, height: 3)
                        Circle().fill(Color.white.opacity(0.42)).frame(width: 3, height: 3)
                    }
                    .padding(.trailing, 10)
                }
                .padding(.top, height * 0.62)
        }
        .frame(width: width, height: height)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var printerSurface: some View {
        if reduceTransparency {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(NoteTheme.canvasTop)
                .overlay {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(NoteTheme.divider, lineWidth: 1)
                }
        } else {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(Color.white.opacity(0.72), lineWidth: 1)
                }
        }
    }
}
