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

enum V02GroupTargetPolicy {
    static func activeTarget(at point: CGPoint, frames: [String: CGRect]) -> String? {
        // When the transparent halos overlap at the center line, prefer the
        // existing-collection target. The visible targets remain distinct;
        // this only makes a straight vertical release deterministic.
        if let existing = frames["existing"], existing.contains(point) {
            return "existing"
        }
        return frames.first(where: { $0.value.contains(point) })?.key
    }

    static func commitTarget(finalActiveTarget: String?) -> String? {
        finalActiveTarget
    }
}

enum V02GroupOperationPolicy {
    /// The long-press affordance always exposes the two operation types. The
    /// active-collection count is resolved by the follow-up panel: creation
    /// reports the five-collection limit and the existing-list panel can show
    /// an empty or full state without changing the source affordance.
    static func targetIDs(activeCollectionCount _: Int) -> [String] {
        ["new", "existing"]
    }

    static func canAccept(memberCount: Int) -> Bool {
        memberCount < 10
    }

    static func capacityLabel(memberCount: Int) -> String {
        canAccept(memberCount: memberCount) ? "\(memberCount)/10" : "已满 10 条"
    }
}

enum V02CollectionOperationPolicy {
    static func showsEmptyState(activeCollectionCount: Int) -> Bool {
        activeCollectionCount <= 0
    }

    static func canCreate(activeCollectionCount: Int) -> Bool {
        max(0, activeCollectionCount) < V02DomainEngine.maximumActiveCollections
    }

    static func canAddMember(memberCount: Int) -> Bool {
        max(0, memberCount) < V02DomainEngine.maximumMembersPerCollection
    }
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
