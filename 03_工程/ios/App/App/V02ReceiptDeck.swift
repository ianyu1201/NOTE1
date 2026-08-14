import SwiftUI

enum V02ReceiptGestureAxis: Equatable { case none, horizontal, downward }

enum V02ReceiptGesturePolicy {
    static let lockDistance: CGFloat = 12
    static let horizontalThreshold: CGFloat = 72
    static let horizontalPredictedThreshold: CGFloat = 120
    static let downwardThreshold: CGFloat = 96
    static let downwardPredictedThreshold: CGFloat = 140
    static let extractionHandleHeight: CGFloat = 96
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
        location.y <= extractionHandleHeight
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
