import XCTest
@testable import App

@MainActor
final class NoteStoreGroupTests: XCTestCase {
    private var directory: URL!
    private var store: NoteStore!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "NOTE1GroupTests-\(UUID().uuidString)",
                isDirectory: true
            )
        store = NoteStore(storageDirectory: directory)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
        store = nil
        directory = nil
    }

    func testCreatingIdeaInsideActiveGroupUsesOneCommittedRelationship() throws {
        let group = try store.createGroup(name: "产品灵感")

        let idea = try store.createIdea(
            content: "组内新增",
            groupID: group.id
        )

        XCTAssertEqual(store.idea(id: idea.id)?.groupID, group.id)
        XCTAssertEqual(store.reviewItems.map(\.id), [group.id])

        let reloaded = NoteStore(storageDirectory: directory)
        XCTAssertEqual(reloaded.idea(id: idea.id)?.groupID, group.id)
    }

    func testCompletedGroupRejectsNewIdeaWithoutCreatingOrphan() throws {
        let group = try store.createGroup(name: "已完成组")
        try store.complete(.group(group))
        let originalIdeaCount = store.ideas.count

        XCTAssertThrowsError(
            try store.createIdea(content: "不能新增", groupID: group.id)
        )

        XCTAssertEqual(store.ideas.count, originalIdeaCount)
        XCTAssertTrue(store.reviewItems.isEmpty)
    }

    func testCompletedGroupMustBeRestoredBeforeRename() throws {
        let group = try store.createGroup(name: "原名称")
        try store.complete(.group(group))

        XCTAssertThrowsError(try store.renameGroup(id: group.id, name: "新名称"))
        XCTAssertEqual(store.group(id: group.id)?.name, "原名称")
    }
}
