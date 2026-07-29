import XCTest
@testable import App

final class HistorySelectionPolicyTests: XCTestCase {
    func testSelectionIsLimitedToVisibleRecords() {
        let visibleID = UUID()
        let hiddenID = UUID()

        let selection = HistorySelectionPolicy.visibleSelection(
            [visibleID, hiddenID],
            visibleItemIDs: [visibleID]
        )

        XCTAssertEqual(selection, [visibleID])
    }
}
