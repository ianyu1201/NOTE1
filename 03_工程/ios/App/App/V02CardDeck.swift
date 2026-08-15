import SwiftUI

enum V02CardDeckPolicy {
    static let pageThreshold: CGFloat = 92
    static let boundaryResistance: CGFloat = 0.24

    static func displayedVerticalTranslation(index: Int, count: Int, translation: CGFloat) -> CGFloat {
        guard count > 0 else { return 0 }
        let hasTarget = translation > 0 ? index > 0 : index + 1 < count
        return hasTarget ? translation : translation * boundaryResistance
    }

    static func tuckPromptOpacity(for horizontalOffset: CGFloat) -> Double {
        guard horizontalOffset < -36 else { return 0 }
        return Double(min(max((-horizontalOffset - 36) / 88, 0), 1))
    }

    static func tuckBackgroundOpacity(for horizontalOffset: CGFloat) -> Double {
        let progress = tuckPromptOpacity(for: horizontalOffset)
        return progress * 0.16
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

/// Card-preview papers keep a readable minimum height for compact viewports.
/// The standalone preview reserves a small internal bleed area so the paper's
/// rounded edge and shadow never sit on the drag viewport's clipping boundary.
enum V02CardPreviewLayoutPolicy {
    /// The confirmed card-preview composition gives the primary paper enough
    /// height to own the first screen, including sparse collection cards. A
    /// A 480pt floor keeps the paper visually primary on the 368pt × 800pt
    /// compact viewport while preserving visible canvas above the navigation.
    static let compactHeight: CGFloat = 480
    static let maximumHeight: CGFloat = 540
    static let previewMinimumHeight: CGFloat = 340
    static let previewControlsReserve: CGFloat = 108
    static let previewCardToControlsSpacing: CGFloat = 12
    static let previewControlSpacing: CGFloat = 8
    static let previewControlBottomPadding: CGFloat = 14
    static let previewPaperVerticalInset: CGFloat = 18
    static let previewEdgeHintHeight: CGFloat = 28
    private static let textCharactersPerLine = 18
    private static let maximumTextLines = 7

    /// Both the standalone card-preview page and the collection workbench
    /// use the available page body above the shared TabView as their paper
    /// height. The compact floor only protects unusually short containers.
    static func pageHeight(for availableHeight: CGFloat) -> CGFloat {
        max(availableHeight, compactHeight)
    }

    /// Standalone card preview keeps a visible band of canvas around the paper.
    /// The workbench continues to use the full available page height because it
    /// owns an editor and action row rather than a single-focus review surface.
    static func previewPageHeight(for availableHeight: CGFloat, entry: V02CardPreviewEntry) -> CGFloat {
        let centeredCardRegion = max(
            availableHeight - previewControlsReserve,
            previewMinimumHeight
        )
        return min(centeredCardRegion, deckHeight(for: entry))
    }

    static func previewPaperHeight(for viewportHeight: CGFloat) -> CGFloat {
        max(viewportHeight - previewPaperVerticalInset * 2, 0)
    }

    static func deckHeight(for entry: V02CardPreviewEntry) -> CGFloat {
        switch entry {
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let cards: [Card]
    @Binding var index: Int
    let deckHeight: CGFloat
    let paperCornerRadius: CGFloat
    let paperHorizontalPadding: CGFloat
    let paperVerticalInset: CGFloat
    let usesCompactEdgeHints: Bool
    let edgeHintHeight: CGFloat
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
        horizontalPadding: CGFloat = V02PrimaryContentLayoutPolicy.horizontalInset,
        verticalPaperInset: CGFloat = 0,
        usesCompactEdgeHints: Bool = false,
        edgeHintHeight: CGFloat = 28,
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
        paperVerticalInset = verticalPaperInset
        self.usesCompactEdgeHints = usesCompactEdgeHints
        self.edgeHintHeight = edgeHintHeight
        self.showsLayeredPaper = showsLayeredPaper
        self.isGestureEnabled = isGestureEnabled
        self.tuckPrompt = tuckPrompt
        self.content = content
        self.onTuck = onTuck
    }

    var body: some View {
        GeometryReader { proxy in
            let resolvedIndex = min(max(index, 0), max(cards.count - 1, 0))
            let displayedVerticalOffset = V02CardDeckPolicy.displayedVerticalTranslation(
                index: resolvedIndex,
                count: cards.count,
                translation: verticalOffset
            )
            let verticalProgress = min(abs(displayedVerticalOffset) / max(proxy.size.height, 1), 1)
            ZStack {
                if horizontalOffset < -36, onTuck != nil, !cards.isEmpty {
                    RoundedRectangle(cornerRadius: paperCornerRadius, style: .continuous)
                        .fill(NoteTheme.secondaryInk.opacity(V02CardDeckPolicy.tuckBackgroundOpacity(for: horizontalOffset)))
                        .padding(.horizontal, paperHorizontalPadding)
                        .accessibilityHidden(true)
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
                    adjacentPaperHint(atTop: true)
                        .scaleEffect(0.974)
                        .offset(y: -4 + max(displayedVerticalOffset, 0) * 0.08)
                        .opacity((verticalOffset > 0 ? 1 : 0.56) * (1 - verticalProgress * 0.7))
                }
                if resolvedIndex + 1 < cards.count {
                    adjacentPaperHint(atTop: false)
                        .scaleEffect(0.974)
                        .offset(y: 4 + min(displayedVerticalOffset, 0) * 0.08)
                        .opacity((verticalOffset < 0 ? 1 : 0.56) * (1 - verticalProgress * 0.7))
                }
                if verticalOffset > 0, resolvedIndex > 0 {
                    paper(cards[resolvedIndex - 1])
                        .background(V04ObjectTransitionSurfacePolicy.style(for: V04ObjectTransitionSurfacePolicy.cardNeighbourHost))
                        .offset(y: -proxy.size.height + displayedVerticalOffset)
                        .scaleEffect(0.985 + verticalProgress * 0.015)
                        .opacity(0.72 + verticalProgress * 0.28)
                        .accessibilityHidden(true)
                }
                if verticalOffset < 0, resolvedIndex + 1 < cards.count {
                    paper(cards[resolvedIndex + 1])
                        .background(V04ObjectTransitionSurfacePolicy.style(for: V04ObjectTransitionSurfacePolicy.cardNeighbourHost))
                        .offset(y: proxy.size.height + displayedVerticalOffset)
                        .scaleEffect(0.985 + verticalProgress * 0.015)
                        .opacity(0.72 + verticalProgress * 0.28)
                        .accessibilityHidden(true)
                }
                if !cards.isEmpty {
                    if showsLayeredPaper {
                        paperLayer
                            .offset(
                                x: V02PrimaryContentLayoutPolicy.stackedPaperBackOffset,
                                y: V02PrimaryContentLayoutPolicy.stackedPaperBackOffset
                            )
                            .opacity(0.34)
                        paperLayer
                            .offset(
                                x: V02PrimaryContentLayoutPolicy.stackedPaperMiddleOffset,
                                y: V02PrimaryContentLayoutPolicy.stackedPaperMiddleOffset
                            )
                            .opacity(0.54)
                    }
                    if onTuck != nil {
                        deckPaper(
                            cards[resolvedIndex],
                            resolvedIndex: resolvedIndex,
                            height: proxy.size.height,
                            displayedVerticalOffset: displayedVerticalOffset
                        )
                            .accessibilityAction(named: tuckPrompt(cards[resolvedIndex])) {
                                if let onTuck { onTuck(cards[resolvedIndex]) }
                            }
                    } else {
                        deckPaper(
                            cards[resolvedIndex],
                            resolvedIndex: resolvedIndex,
                            height: proxy.size.height,
                            displayedVerticalOffset: displayedVerticalOffset
                        )
                            .accessibilityHint("向上下拖动切换卡片")
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(V04ObjectTransitionSurfacePolicy.style(for: V04ObjectTransitionSurfacePolicy.cardDragHost))
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
            .background(
                V04ObjectTransitionSurfacePolicy.style(for: V04ObjectTransitionSurfacePolicy.cardObject),
                in: RoundedRectangle(cornerRadius: paperCornerRadius, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: paperCornerRadius, style: .continuous)
                    .stroke(NoteTheme.paperBorder, lineWidth: 1)
            }
            .overlay(alignment: .top) {
                Capsule()
                    .fill(NoteTheme.ink.opacity(0.09))
                    .frame(width: 62, height: 2)
                    .padding(.top, 10)
                    .accessibilityHidden(true)
            }
            // Keep the paper separated from the continuous canvas without a
            // full-width shadow band below the card edge.
            .shadow(color: NoteTheme.ink.opacity(0.055), radius: 12, y: 5)
            .padding(.horizontal, paperHorizontalPadding)
            .padding(.vertical, paperVerticalInset)
    }

    @ViewBuilder
    private func deckPaper(
        _ card: Card,
        resolvedIndex: Int,
        height: CGFloat,
        displayedVerticalOffset: CGFloat
    ) -> some View {
        if isGestureEnabled {
            deckPaperBase(card, resolvedIndex: resolvedIndex, displayedVerticalOffset: displayedVerticalOffset)
                .highPriorityGesture(deckGesture(height: height))
        } else {
            deckPaperBase(card, resolvedIndex: resolvedIndex, displayedVerticalOffset: displayedVerticalOffset)
        }
    }

    private func deckPaperBase(
        _ card: Card,
        resolvedIndex: Int,
        displayedVerticalOffset: CGFloat
    ) -> some View {
        paper(card)
            .offset(x: horizontalOffset, y: displayedVerticalOffset)
            .rotationEffect(.degrees(Double(horizontalOffset / 26)))
            .accessibilityElement(children: .contain)
            .accessibilityValue("第 \(resolvedIndex + 1) 张，共 \(cards.count) 张")
            .accessibilityAction(named: "上一张") { page(by: -1) }
            .accessibilityAction(named: "下一张") { page(by: 1) }
    }

    private var paperLayer: some View {
        RoundedRectangle(cornerRadius: paperCornerRadius, style: .continuous)
            .fill(V04ObjectTransitionSurfacePolicy.style(for: V04ObjectTransitionSurfacePolicy.cardObject))
            .overlay {
                RoundedRectangle(cornerRadius: paperCornerRadius, style: .continuous)
                    .stroke(NoteTheme.paperBorder, lineWidth: 1)
            }
            .shadow(color: NoteTheme.ink.opacity(0.05), radius: 12, y: 7)
            .padding(.horizontal, paperHorizontalPadding)
            .padding(.vertical, paperVerticalInset)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private func adjacentPaperHint(atTop: Bool) -> some View {
        if usesCompactEdgeHints {
            VStack(spacing: 0) {
                if !atTop { Spacer(minLength: 0) }
                RoundedRectangle(cornerRadius: paperCornerRadius, style: .continuous)
                    .fill(V04ObjectTransitionSurfacePolicy.style(for: V04ObjectTransitionSurfacePolicy.cardObject))
                    .overlay {
                        RoundedRectangle(cornerRadius: paperCornerRadius, style: .continuous)
                            .stroke(NoteTheme.paperBorder, lineWidth: 1)
                    }
                    .frame(height: edgeHintHeight)
                    .padding(.horizontal, paperHorizontalPadding + 5)
                if atTop { Spacer(minLength: 0) }
            }
            .padding(.vertical, max(paperVerticalInset - 10, 0))
            .accessibilityHidden(true)
        } else {
            RoundedRectangle(cornerRadius: paperCornerRadius, style: .continuous)
                .fill(V04ObjectTransitionSurfacePolicy.style(for: V04ObjectTransitionSurfacePolicy.cardObject))
                .overlay {
                    RoundedRectangle(cornerRadius: paperCornerRadius, style: .continuous)
                        .stroke(NoteTheme.paperBorder, lineWidth: 1)
                }
                .shadow(color: NoteTheme.ink.opacity(0.07), radius: 14, y: 8)
                .padding(.horizontal, paperHorizontalPadding)
                .padding(.vertical, paperVerticalInset)
                .accessibilityHidden(true)
        }
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
                        withAnimation(NoteMotion.settle(reduceMotion: reduceMotion)) { verticalOffset = 0 }
                        return
                    }
                    let duration = reduceMotion ? 0.12 : 0.24
                    withAnimation(reduceMotion ? .easeOut(duration: duration) : .smooth(duration: duration)) {
                        verticalOffset = reduceMotion
                            ? (direction > 0 ? -24 : 24)
                            : (direction > 0 ? -height : height)
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.01) {
                        index = target
                        verticalOffset = 0
                    }
                } else {
                    withAnimation(NoteMotion.settle(reduceMotion: reduceMotion)) {
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
