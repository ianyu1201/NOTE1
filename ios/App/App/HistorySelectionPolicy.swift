import Foundation

enum HistorySelectionPolicy {
    static func visibleSelection(
        _ selection: Set<UUID>,
        visibleItemIDs: [UUID]
    ) -> Set<UUID> {
        selection.intersection(Set(visibleItemIDs))
    }
}
