import SwiftUI

enum V02CardDeckPolicy {
    static let pageThreshold: CGFloat = 92

    static func tuckPromptOpacity(for horizontalOffset: CGFloat) -> Double {
        guard horizontalOffset < -36 else { return 0 }
        return Double(min(max((-horizontalOffset - 36) / 88, 0), 1))
    }

    static func acceptsHorizontalTuck(startX: CGFloat, translation: CGSize) -> Bool {
        startX > 24 && translation.width < 0
    }

    static func pageDirection(
        axis: ReviewDragAxis?,
        translation: CGSize,
        predictedEndTranslation: CGSize
    ) -> Int? {
        guard ReviewGestureClassifier.shouldPage(
            axis: axis,
            translation: translation,
            predictedEndTranslation: predictedEndTranslation
        ) else { return nil }
        return (predictedEndTranslation.height == 0
            ? translation.height
            : predictedEndTranslation.height) < 0 ? 1 : -1
    }
}

/// Card-preview papers should follow the amount of content instead of making
/// every sparse card occupy the same tall rectangle. The deck still keeps a
/// stable upper bound so long text and gesture physics remain predictable.
enum V02CardPreviewLayoutPolicy {
    static let compactHeight: CGFloat = 276
    static let maximumHeight: CGFloat = 360
    private static let textCharactersPerLine = 18
    private static let maximumTextLines = 7

    static func deckHeight(for entry: V02CardPreviewEntry) -> CGFloat {
        switch entry {
        case .collection:
            return compactHeight
        case .inspiration(let inspiration):
            let characterCount = max(inspiration.text.trimmingCharacters(in: .whitespacesAndNewlines).count, 1)
            let lineCount = min(
                maximumTextLines,
                max(1, (characterCount + textCharactersPerLine - 1) / textCharactersPerLine)
            )
            let attachmentAllowance: CGFloat = inspiration.resourceIDs.isEmpty ? 0 : 26
            return min(
                maximumHeight,
                max(compactHeight, 164 + CGFloat(lineCount) * 24 + attachmentAllowance)
            )
        }
    }
}

enum V02CardPositionPolicy {
    static func resolvedIndex(preferredID: UUID?, currentIndex: Int, ids: [UUID]) -> Int? {
        guard !ids.isEmpty else { return nil }
        if let preferredID, let index = ids.firstIndex(of: preferredID) { return index }
        return min(max(currentIndex, 0), ids.count - 1)
    }
}

enum V02TuckPolicy {
    static let commitDelay: TimeInterval = 0.23
    static func mayBegin(isTucking: Bool) -> Bool { !isTucking }
}

/// Shared V0.2 paper deck. The current card follows the finger while the
/// neighbouring papers progressively reveal before the page index changes.
struct V02CardDeck<Card: Identifiable, CardContent: View>: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let cards: [Card]
    @Binding var index: Int
    let deckHeight: CGFloat
    let paperCornerRadius: CGFloat
    let paperHorizontalPadding: CGFloat
    let showsLayeredPaper: Bool
    let isGestureEnabled: Bool
    let tuckPrompt: (Card) -> String
    let content: (Card) -> CardContent
    let onTuck: ((Card) -> Void)?

    @State private var axis: ReviewDragAxis?
    @State private var verticalOffset: CGFloat = 0
    @State private var horizontalOffset: CGFloat = 0
    @State private var isTucking = false

    init(
        cards: [Card],
        index: Binding<Int>,
        height: CGFloat = 408,
        cornerRadius: CGFloat = 30,
        horizontalPadding: CGFloat = 32,
        showsLayeredPaper: Bool = false,
        isGestureEnabled: Bool = true,
        tuckPrompt: @escaping (Card) -> String = { _ in "收起" },
        @ViewBuilder content: @escaping (Card) -> CardContent,
        onTuck: ((Card) -> Void)? = nil
    ) {
        self.cards = cards
        _index = index
        deckHeight = height
        paperCornerRadius = cornerRadius
        paperHorizontalPadding = horizontalPadding
        self.showsLayeredPaper = showsLayeredPaper
        self.isGestureEnabled = isGestureEnabled
        self.tuckPrompt = tuckPrompt
        self.content = content
        self.onTuck = onTuck
    }

    var body: some View {
        GeometryReader { proxy in
            let resolvedIndex = min(max(index, 0), max(cards.count - 1, 0))
            ZStack {
                if horizontalOffset < -36, onTuck != nil, !cards.isEmpty {
                    HStack {
                        Spacer()
                        Label(tuckPrompt(cards[resolvedIndex]), systemImage: "archivebox.fill")
                            .noteFontCapped(size: 17, maximumScale: 1.2, weight: .semibold)
                            .foregroundStyle(NoteTheme.secondaryInk)
                            .padding(.trailing, 38)
                            .opacity(V02CardDeckPolicy.tuckPromptOpacity(for: horizontalOffset))
                    }
                }
                if resolvedIndex > 0 {
                    paperEdge
                        .scaleEffect(0.974)
                        .offset(y: -20 + max(verticalOffset, 0) * 0.16)
                        .opacity(verticalOffset > 0 ? 1 : 0.56)
                }
                if resolvedIndex + 1 < cards.count {
                    paperEdge
                        .scaleEffect(0.974)
                        .offset(y: 28 + min(verticalOffset, 0) * 0.16)
                        .opacity(verticalOffset < 0 ? 1 : 0.56)
                }
                if !cards.isEmpty {
                    if showsLayeredPaper {
                        paperLayer
                            .offset(x: 13, y: 8)
                            .opacity(0.34)
                        paperLayer
                            .offset(x: 7, y: 4)
                            .opacity(0.54)
                    }
                    if onTuck != nil {
                        deckPaper(cards[resolvedIndex], resolvedIndex: resolvedIndex, height: proxy.size.height)
                            .accessibilityAction(named: tuckPrompt(cards[resolvedIndex])) {
                                if let onTuck { onTuck(cards[resolvedIndex]) }
                            }
                    } else {
                        deckPaper(cards[resolvedIndex], resolvedIndex: resolvedIndex, height: proxy.size.height)
                            .accessibilityHint("向上下拖动切换卡片")
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
        }
        // Keep the operation slot and page indicator visible at the largest
        // sizes. The paper itself remains readable through wrapping; extra
        // vertical space belongs to the scrollable page, not the fixed deck.
        .frame(height: dynamicTypeSize.isAccessibilitySize ? max(deckHeight, 520) : deckHeight)
        .onChange(of: cards.map(\.id)) { _, ids in
            index = min(index, max(ids.count - 1, 0))
        }
    }

    private func paper(_ card: Card) -> some View {
        content(card)
            .padding(26)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(NoteTheme.paper.opacity(0.94), in: RoundedRectangle(cornerRadius: paperCornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: paperCornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(0.92), lineWidth: 1)
            }
            .shadow(color: NoteTheme.ink.opacity(0.10), radius: 22, y: 12)
            .padding(.horizontal, paperHorizontalPadding)
    }

    @ViewBuilder
    private func deckPaper(_ card: Card, resolvedIndex: Int, height: CGFloat) -> some View {
        if isGestureEnabled {
            deckPaperBase(card, resolvedIndex: resolvedIndex, height: height)
                .highPriorityGesture(deckGesture(height: height))
        } else {
            deckPaperBase(card, resolvedIndex: resolvedIndex, height: height)
        }
    }

    private func deckPaperBase(_ card: Card, resolvedIndex: Int, height: CGFloat) -> some View {
        paper(card)
            .offset(x: horizontalOffset, y: verticalOffset)
            .rotationEffect(.degrees(Double(horizontalOffset / 26)))
            .accessibilityElement(children: .contain)
            .accessibilityValue("第 \(resolvedIndex + 1) 张，共 \(cards.count) 张")
            .accessibilityAction(named: "上一张") { page(by: -1) }
            .accessibilityAction(named: "下一张") { page(by: 1) }
    }

    private var paperLayer: some View {
        RoundedRectangle(cornerRadius: paperCornerRadius, style: .continuous)
            .fill(NoteTheme.paper.opacity(0.84))
            .overlay {
                RoundedRectangle(cornerRadius: paperCornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(0.84), lineWidth: 1)
            }
            .shadow(color: NoteTheme.ink.opacity(0.05), radius: 12, y: 7)
            .padding(.horizontal, paperHorizontalPadding)
            .accessibilityHidden(true)
    }

    private var paperEdge: some View {
        RoundedRectangle(cornerRadius: paperCornerRadius, style: .continuous)
            .fill(NoteTheme.paper.opacity(0.82))
            .overlay {
                RoundedRectangle(cornerRadius: paperCornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(0.98), lineWidth: 1)
            }
            .shadow(color: NoteTheme.ink.opacity(0.07), radius: 14, y: 8)
            .padding(.horizontal, paperHorizontalPadding)
            .accessibilityHidden(true)
    }

    private func deckGesture(height: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                guard V02TuckPolicy.mayBegin(isTucking: isTucking) else { return }
                if axis == nil {
                    axis = ReviewGestureClassifier.axis(for: value.translation)
                }
                switch axis {
                case .vertical:
                    verticalOffset = value.translation.height
                case .horizontal:
                    if V02CardDeckPolicy.acceptsHorizontalTuck(
                        startX: value.startLocation.x,
                        translation: value.translation
                    ) {
                        horizontalOffset = value.translation.width
                    }
                case nil:
                    break
                }
            }
            .onEnded { value in
                guard V02TuckPolicy.mayBegin(isTucking: isTucking) else { return }
                let resolvedIndex = min(max(index, 0), max(cards.count - 1, 0))
                defer { axis = nil }
                if ReviewGestureClassifier.shouldComplete(
                    axis: axis,
                    translation: value.translation,
                    predictedEndTranslation: value.predictedEndTranslation
                ), V02CardDeckPolicy.acceptsHorizontalTuck(
                    startX: value.startLocation.x,
                    translation: value.translation
                ), let onTuck, !cards.isEmpty {
                    isTucking = true
                    withAnimation(.easeOut(duration: 0.22)) { horizontalOffset = -height }
                    let outgoing = cards[resolvedIndex]
                    DispatchQueue.main.asyncAfter(deadline: .now() + V02TuckPolicy.commitDelay) {
                        onTuck(outgoing)
                        horizontalOffset = 0
                        isTucking = false
                    }
                    return
                }
                if let direction = V02CardDeckPolicy.pageDirection(
                    axis: axis,
                    translation: value.translation,
                    predictedEndTranslation: value.predictedEndTranslation
                ), !cards.isEmpty {
                    let target = min(max(resolvedIndex + direction, 0), cards.count - 1)
                    guard target != resolvedIndex else {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) { verticalOffset = 0 }
                        return
                    }
                    withAnimation(.easeOut(duration: 0.15)) {
                        verticalOffset = direction > 0 ? -height : height
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
                        index = target
                        verticalOffset = 0
                    }
                } else {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                        verticalOffset = 0
                        horizontalOffset = 0
                    }
                }
            }
    }

    private func page(by direction: Int) {
        guard !cards.isEmpty else { return }
        index = min(max(index + direction, 0), cards.count - 1)
    }
}
