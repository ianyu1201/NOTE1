import SwiftUI

enum ReviewDragAxis: Equatable {
    case horizontal
    case vertical
}

enum ReviewGestureClassifier {
    static func axis(for translation: CGSize) -> ReviewDragAxis? {
        let horizontal = abs(translation.width)
        let vertical = abs(translation.height)
        guard max(horizontal, vertical) >= 14 else { return nil }

        if horizontal >= vertical * 1.35 {
            return .horizontal
        }
        if vertical >= horizontal * 1.18 {
            return .vertical
        }
        return nil
    }

    static func shouldComplete(
        axis: ReviewDragAxis?,
        translation: CGSize,
        predictedEndTranslation: CGSize
    ) -> Bool {
        guard axis == .horizontal else { return false }
        return translation.width < -110
            || predictedEndTranslation.width < -190
    }

    static func shouldPage(
        axis: ReviewDragAxis?,
        translation: CGSize,
        predictedEndTranslation: CGSize
    ) -> Bool {
        guard axis == .vertical else { return false }
        return abs(translation.height) > 64
            || abs(predictedEndTranslation.height) > 96
    }
}

enum ReviewInteractionTiming {
    static let undoBannerDuration: TimeInterval = 3
}

enum ReviewPositionPolicy {
    static func resolvedIndex(
        preferredItemID: UUID?,
        currentIndex: Int,
        itemIDs: [UUID]
    ) -> Int? {
        guard !itemIDs.isEmpty else { return nil }
        if let preferredItemID,
           let preferredIndex = itemIDs.firstIndex(of: preferredItemID) {
            return preferredIndex
        }
        return min(max(currentIndex, 0), itemIDs.count - 1)
    }
}

enum V02CollectionOperationPolicy {
    static func showsEmptyState(activeCollectionCount: Int) -> Bool {
        activeCollectionCount <= 0
    }
}
