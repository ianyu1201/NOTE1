import SwiftUI

struct GroupButtonFrameKey: PreferenceKey {
    static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}

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
        return abs(translation.width) > 110
            || abs(predictedEndTranslation.width) > 190
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

struct GroupTargetFramesKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(
        value: inout [String: CGRect],
        nextValue: () -> [String: CGRect]
    ) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

enum ReviewGroupDropTarget: Equatable {
    case group(UUID)
    case new
}

struct ReviewGroupDropClassifier {
    static func target(
        at location: CGPoint,
        groupFrames: [UUID: CGRect],
        newFrame: CGRect?
    ) -> ReviewGroupDropTarget? {
        if let group = groupFrames.first(where: { $0.value.contains(location) }) {
            return .group(group.key)
        }
        if newFrame?.contains(location) == true {
            return .new
        }
        return nil
    }
}
