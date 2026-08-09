import SwiftUI

enum V02ReceiptGestureAxis: Equatable { case none, horizontal, downward }

enum V02ReceiptGesturePolicy {
    static let lockDistance: CGFloat = 16
    static let horizontalThreshold: CGFloat = 88
    static let downwardThreshold: CGFloat = 104
    static let extractionHandleHeight: CGFloat = 96

    static func axis(for translation: CGSize) -> V02ReceiptGestureAxis {
        let x = abs(translation.width), y = abs(translation.height)
        guard max(x, y) >= lockDistance else { return .none }
        if x > y * 1.25 { return .horizontal }
        if translation.height > 0, y > x * 1.25 { return .downward }
        return .none
    }

    static func horizontalTarget(index: Int, count: Int, translation: CGFloat) -> Int? {
        guard abs(translation) >= horizontalThreshold else { return nil }
        let target = translation < 0 ? index + 1 : index - 1
        return (0..<count).contains(target) ? target : nil
    }

    static func candidateIndex(index: Int, count: Int, translation: CGFloat) -> Int? {
        guard abs(translation) > 0.5 else { return nil }
        let candidate = translation < 0 ? index + 1 : index - 1
        return (0..<count).contains(candidate) ? candidate : nil
    }

    static func normalizedProgress(translation: CGFloat, extent: CGFloat) -> CGFloat {
        min(abs(translation) / max(extent, 1), 1)
    }

    static func shouldExtract(_ translation: CGFloat) -> Bool { translation >= downwardThreshold }

    static func canStartExtraction(at location: CGPoint) -> Bool {
        location.y <= extractionHandleHeight
    }
}

/// P0-C2 会在此容器加入统一的水平/向下手势状态；C1 先固定层级与纸边，避免正文穿透。
struct V02ReceiptDeck: View {
    @ObservedObject var store: V02Store
    let receipts: [V02Receipt]
    @Binding var index: Int
    let isSelecting: Bool
    @Binding var selectedIDs: Set<UUID>
    let openReceipt: (V02Receipt) -> Void
    let minimumPaperHeight: CGFloat
    let templateFor: (V02Receipt) -> V02ReceiptTemplate
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var translation: CGSize = .zero
    @State private var axis: V02ReceiptGestureAxis = .none
    @State private var gestureStartedAtEdge = false
    @State private var gestureStartedAtExtractionHandle = false

    private var currentReceipt: V02Receipt? {
        guard receipts.indices.contains(index) else { return nil }
        return receipts[index]
    }

    var body: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width, 1)
            let edgeInset = min(32, width * 0.08)
            let extractionDistance = max(proxy.size.height * 1.25, 1)
            let horizontalProgress = V02ReceiptGesturePolicy.normalizedProgress(translation: translation.width, extent: width)
            let downwardProgress = V02ReceiptGesturePolicy.normalizedProgress(translation: max(translation.height, 0), extent: extractionDistance)
            ZStack(alignment: .top) {
            if let next = receipts[safe: index + 2] {
                V02ReceiptPaperEdge(template: templateFor(next))
                    .offset(x: translation.width * 0.025)
                    .offset(y: 12 - horizontalProgress * 5 - downwardProgress * 10)
                    .scaleEffect(0.98 + horizontalProgress * 0.02 + downwardProgress * 0.02)
                    .opacity(0.72 + horizontalProgress * 0.28)
                    .zIndex(0)
                    .accessibilityHidden(true)
            }
            if let next = receipts[safe: index + 1] {
                V02ReceiptPaperEdge(template: templateFor(next))
                    .offset(x: translation.width * 0.045)
                    .offset(y: 6 - horizontalProgress * 3 - downwardProgress * 6)
                    .scaleEffect(0.99 + horizontalProgress * 0.01 + downwardProgress * 0.01)
                    .opacity(0.82 + horizontalProgress * 0.18)
                    .zIndex(1)
                    .accessibilityHidden(true)
            }
            if axis == .horizontal,
               let targetIndex = V02ReceiptGesturePolicy.candidateIndex(index: index, count: receipts.count, translation: translation.width),
               receipts.indices.contains(targetIndex) {
                V02ReceiptPaper(
                    store: store,
                    receipt: receipts[targetIndex],
                    template: templateFor(receipts[targetIndex]),
                    minimumHeight: max(proxy.size.height - 20, minimumPaperHeight)
                )
                .offset(x: (translation.width < 0 ? width * 0.92 : -width * 0.92) + translation.width * 0.92, y: 26 - horizontalProgress * 6)
                .rotationEffect(.degrees((translation.width < 0 ? 1.8 : -1.8) * Double(1 - horizontalProgress)))
                .scaleEffect(0.97 + horizontalProgress * 0.03)
                .opacity(0.72 + horizontalProgress * 0.28)
                .zIndex(2)
                .accessibilityHidden(true)
            }
            if let receipt = currentReceipt {
                VStack(spacing: 0) {
                    V02ReceiptPaper(
                        store: store,
                        receipt: receipt,
                        template: templateFor(receipt),
                        minimumHeight: max(proxy.size.height - 20, minimumPaperHeight)
                    )
                    .overlay(alignment: .topTrailing) {
                        if isSelecting {
                            Button {
                                if selectedIDs.contains(receipt.id) { selectedIDs.remove(receipt.id) }
                                else { selectedIDs.insert(receipt.id) }
                            } label: {
                                Image(systemName: selectedIDs.contains(receipt.id) ? "checkmark.square.fill" : "square")
                                    .font(.system(size: 20, weight: .semibold))
                                    .foregroundStyle(selectedIDs.contains(receipt.id) ? NoteTheme.receiptInk : NoteTheme.receiptSecondaryInk)
                                    .padding(12)
                                    .background(Color.white.opacity(0.76), in: Circle())
                            }
                            .buttonStyle(.plain)
                            .padding(10)
                            .accessibilityLabel(selectedIDs.contains(receipt.id) ? "取消选择小票" : "选择小票")
                        }
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    if !isSelecting { openReceipt(receipt) }
                }
                .simultaneousGesture(isSelecting ? nil : DragGesture(minimumDistance: 10)
                    .onChanged { value in
                        if value.startLocation.x < edgeInset || value.startLocation.x > width - edgeInset {
                            gestureStartedAtEdge = true
                            return
                        }
                        guard !gestureStartedAtEdge else { return }
                        if axis == .none {
                            let proposedAxis = V02ReceiptGesturePolicy.axis(for: value.translation)
                            if proposedAxis == .downward {
                                gestureStartedAtExtractionHandle = V02ReceiptGesturePolicy.canStartExtraction(at: value.startLocation)
                                guard gestureStartedAtExtractionHandle else { return }
                            }
                            axis = proposedAxis
                        }
                        translation = value.translation
                    }
                    .onEnded { value in
                        guard !gestureStartedAtEdge else {
                            gestureStartedAtEdge = false
                            gestureStartedAtExtractionHandle = false
                            axis = .none
                            translation = .zero
                            return
                        }
                        let locked = axis
                        switch locked {
                        case .horizontal:
                            if let target = V02ReceiptGesturePolicy.horizontalTarget(index: index, count: receipts.count, translation: value.translation.width) {
                                let duration = reduceMotion ? 0.12 : 0.32
                                withAnimation(reduceMotion ? .easeOut(duration: duration) : .smooth(duration: duration)) {
                                    translation.width = reduceMotion
                                        ? (value.translation.width < 0 ? -24 : 24)
                                        : (value.translation.width < 0 ? -width : width)
                                }
                                DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.01) {
                                    index = target
                                    translation = .zero
                                    axis = .none
                                    gestureStartedAtExtractionHandle = false
                                }
                            } else {
                                withAnimation(NoteMotion.settle(reduceMotion: reduceMotion)) {
                                    translation = .zero
                                    axis = .none
                                    gestureStartedAtExtractionHandle = false
                                }
                            }
                        case .downward:
                            if gestureStartedAtExtractionHandle,
                               V02ReceiptGesturePolicy.shouldExtract(value.translation.height) {
                                withAnimation(.easeIn(duration: reduceMotion ? 0.16 : 0.28)) { translation.height = extractionDistance }
                                DispatchQueue.main.asyncAfter(deadline: .now() + (reduceMotion ? 0.18 : 0.3)) {
                                    openReceipt(receipt)
                                    translation = .zero
                                    axis = .none
                                    gestureStartedAtExtractionHandle = false
                                }
                            } else {
                                withAnimation(NoteMotion.settle(reduceMotion: reduceMotion)) {
                                    translation = .zero
                                    axis = .none
                                    gestureStartedAtExtractionHandle = false
                                }
                            }
                        case .none:
                            withAnimation(NoteMotion.settle(reduceMotion: reduceMotion)) {
                                translation = .zero
                                axis = .none
                                gestureStartedAtExtractionHandle = false
                            }
                        }
                    }
                )
                .accessibilityIdentifier("v02.receipt.current")
                .accessibilityAddTraits(.isButton)
                .accessibilityHint("点按查看小票；向下抽取可进入详情。")
                .accessibilityAdjustableAction { direction in
                    switch direction {
                    case .increment:
                        guard index + 1 < receipts.count else { return }
                        index += 1
                    case .decrement:
                        guard index > 0 else { return }
                        index -= 1
                    @unknown default: break
                    }
                }
                .accessibilityAction(named: "抽取查看") { openReceipt(receipt) }
                .offset(x: axis == .horizontal ? translation.width * (reduceMotion ? 0.18 : 0.86) : 0, y: 20 + (axis == .downward ? translation.height * (reduceMotion ? 0.28 : 0.7) : 0))
                .rotationEffect(.degrees(axis == .horizontal && !reduceMotion ? Double(translation.width / width) * 3.2 : 0))
                .scaleEffect(1 - horizontalProgress * 0.025 - downwardProgress * 0.08)
                .opacity(1 - horizontalProgress * 0.035 - downwardProgress * 0.12)
                .zIndex(3)
            }
            V02TicketClip()
                .padding(.horizontal, 24)
                .zIndex(4)
                .accessibilityHidden(true)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .frame(maxWidth: .infinity, minHeight: minimumPaperHeight + 20)
    }
}

private struct V02ReceiptPaperEdge: View {
    let template: V02ReceiptTemplate

    var body: some View {
        V02ReceiptPaperShape()
            .fill(template == .film ? NoteTheme.receiptInk.opacity(0.13) : NoteTheme.receiptPaper.opacity(0.82))
            .overlay(alignment: .top) {
                HStack(spacing: 4) {
                    ForEach(0..<26, id: \.self) { _ in Circle().fill(NoteTheme.background.opacity(0.9)).frame(width: 4, height: 4) }
                }
                .padding(.top, 7)
            }
            .overlay {
                V02ReceiptPaperShape()
                    .stroke(NoteTheme.receiptDivider, lineWidth: 1)
            }
            .frame(maxHeight: .infinity)
            .shadow(color: NoteTheme.receiptInk.opacity(0.07), radius: 12, y: 7)
    }
}

private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
