import SwiftUI

enum V02ReceiptGestureAxis: Equatable { case none, horizontal, downward }

enum V02ReceiptGesturePolicy {
    static let lockDistance: CGFloat = 12
    static let horizontalThreshold: CGFloat = 72
    static let horizontalPredictedThreshold: CGFloat = 120
    static let downwardThreshold: CGFloat = 96
    static let downwardPredictedThreshold: CGFloat = 140
    /// Only the first 24pt of the latest-paper preview owns the downward
    /// extraction gesture. Keeping this edge narrow leaves the rest of the
    /// paper free for ordinary vertical reading/scrolling.
    static let extractionHandleHeight: CGFloat = 24
    static let boundaryResistance: CGFloat = 0.24

    static func axis(for translation: CGSize) -> V02ReceiptGestureAxis {
        let x = abs(translation.width)
        let y = abs(translation.height)
        guard max(x, y) >= lockDistance else { return .none }
        if x > y * 1.25 { return .horizontal }
        if translation.height > 0, y > x * 1.25 { return .downward }
        return .none
    }

    static func horizontalTarget(
        index: Int,
        count: Int,
        translation: CGFloat,
        predictedEndTranslation: CGFloat? = nil
    ) -> Int? {
        let predicted = predictedEndTranslation ?? translation
        guard abs(translation) >= horizontalThreshold
                || abs(predicted) >= horizontalPredictedThreshold else { return nil }
        let direction = abs(translation) > 0.5 ? translation : predicted
        let target = direction < 0 ? index + 1 : index - 1
        return (0..<count).contains(target) ? target : nil
    }

    static func candidateIndex(index: Int, count: Int, translation: CGFloat) -> Int? {
        guard abs(translation) > 0.5 else { return nil }
        let candidate = translation < 0 ? index + 1 : index - 1
        return (0..<count).contains(candidate) ? candidate : nil
    }

    static func displayedHorizontalTranslation(index: Int, count: Int, translation: CGFloat) -> CGFloat {
        candidateIndex(index: index, count: count, translation: translation) == nil
            ? translation * boundaryResistance
            : translation
    }

    static func normalizedProgress(translation: CGFloat, extent: CGFloat) -> CGFloat {
        min(abs(translation) / max(extent, 1), 1)
    }

    static func shouldExtract(
        _ translation: CGFloat,
        predictedEndTranslation: CGFloat? = nil
    ) -> Bool {
        translation >= downwardThreshold
            || (predictedEndTranslation ?? translation) >= downwardPredictedThreshold
    }

    static func canStartExtraction(at location: CGPoint) -> Bool {
        location.y >= 0 && location.y <= extractionHandleHeight
    }
}

/// The two papers involved in a horizontal receipt switch share one layout
/// calculation. This keeps the current paper and its neighbour connected to
/// the finger throughout the gesture instead of waiting for the end event and
/// cross-fading between unrelated snapshots.
struct V04ReceiptSwitchTransitionLayout: Equatable {
    let currentOffset: CGFloat
    let targetOffset: CGFloat
    let currentScale: CGFloat
    let targetScale: CGFloat
}

enum V04ReceiptSwitchTransitionPolicy {
    /// A small amount of scale is enough to establish depth without making
    /// the receipt look like it is shrinking away from the reader.
    private static let currentScaleTravel: CGFloat = 0.08
    private static let targetScaleBase: CGFloat = 0.96
    private static let targetScaleTravel: CGFloat = 0.05
    private static let maximumTargetScale: CGFloat = 0.99
    private static let reducedMotionTravel: CGFloat = 16

    static func layout(
        translation: CGFloat,
        extent: CGFloat,
        hasTarget: Bool,
        reduceMotion: Bool
    ) -> V04ReceiptSwitchTransitionLayout {
        let safeExtent = max(abs(extent), 1)
        let progress = min(abs(translation) / safeExtent, 1)

        if reduceMotion {
            // Reduce Motion retains the relationship between the two papers,
            // but limits travel to a short displacement and removes scaling.
            let travel = min(abs(translation), reducedMotionTravel)
            let direction: CGFloat = translation < 0 ? -1 : (translation > 0 ? 1 : 0)
            let currentOffset = direction * travel
            let targetOffset = hasTarget ? -currentOffset : 0
            return V04ReceiptSwitchTransitionLayout(
                currentOffset: currentOffset,
                targetOffset: targetOffset,
                currentScale: 1,
                targetScale: 1
            )
        }

        guard hasTarget else {
            // At the first/last receipt, resist the attempted move rather than
            // exposing a phantom target or allowing the deck to loop.
            return V04ReceiptSwitchTransitionLayout(
                currentOffset: translation * V02ReceiptGesturePolicy.boundaryResistance,
                targetOffset: 0,
                currentScale: 1,
                targetScale: 1
            )
        }

        let direction: CGFloat = translation < 0 ? -1 : (translation > 0 ? 1 : 0)
        let currentOffset = translation
        // The neighbour starts one viewport away and therefore arrives at the
        // centre as the current receipt leaves it.
        let targetOffset = translation + (direction * safeExtent * -1)
        let currentScale = 1 - (currentScaleTravel * progress)
        let targetScale = min(
            maximumTargetScale,
            targetScaleBase + (targetScaleTravel * progress)
        )
        return V04ReceiptSwitchTransitionLayout(
            currentOffset: currentOffset,
            targetOffset: targetOffset,
            currentScale: currentScale,
            targetScale: targetScale
        )
    }
}

enum V02ReceiptLayoutPolicy {
    static let minimumPaperHeight: CGFloat = 460
    static let baseTextHeight: CGFloat = 420
    static let memberRowHeight: CGFloat = 28
    static let textLineHeight: CGFloat = 20
    static let attachmentBlockHeight: CGFloat = 58
    static let photoStripHeight: CGFloat = 110

    static func estimatedPaperHeight(
        memberCount: Int,
        textLineCount: Int,
        hasAttachments: Bool,
        hasPhotoStrip: Bool,
        textScale: CGFloat
    ) -> CGFloat {
        let safeMemberCount = CGFloat(max(memberCount, 1))
        let safeLineCount = CGFloat(max(textLineCount, 1))
        let safeScale = max(textScale, 1)
        let scalableHeight = baseTextHeight
            + safeMemberCount * memberRowHeight
            + safeLineCount * textLineHeight
            + (hasAttachments ? attachmentBlockHeight : 0)
        let estimatedHeight = scalableHeight * safeScale
            + (hasPhotoStrip ? photoStripHeight : 0)
        return max(estimatedHeight, minimumPaperHeight)
    }
}
