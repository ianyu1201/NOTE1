import XCTest
@testable import App

@MainActor
final class NoteStorePersistenceTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "NOTE1PersistenceTests-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
        directory = nil
    }

    func testCorruptedDatabaseEntersReadOnlyModeWithoutOverwritingFile() throws {
        let databaseURL = directory.appendingPathComponent("note1-data.json")
        let corruptedData = Data("{not-valid-json".utf8)
        try corruptedData.write(to: databaseURL)

        let store = NoteStore(storageDirectory: directory)

        XCTAssertTrue(store.isReadOnlyBecausePersistenceFailed)
        XCTAssertNotNil(store.lastPersistenceError)
        XCTAssertThrowsError(try store.createIdea(content: "不能覆盖原数据"))
        XCTAssertEqual(try Data(contentsOf: databaseURL), corruptedData)
    }

    func testVersionOnePlaceholderGroupNameMigratesOnce() throws {
        let group = makeGroup(name: "Existing group")
        try writeStoredData(version: 1, groups: [group])

        let migrated = NoteStore(storageDirectory: directory)
        XCTAssertEqual(migrated.group(id: group.id)?.name, "灵感组")

        let reloaded = NoteStore(storageDirectory: directory)
        XCTAssertEqual(reloaded.group(id: group.id)?.name, "灵感组")
    }

    func testCurrentVersionPreservesUserGroupNamedExistingGroup() throws {
        let store = NoteStore(storageDirectory: directory)
        let group = try store.createGroup(name: "Existing group")

        let reloaded = NoteStore(storageDirectory: directory)

        XCTAssertEqual(reloaded.group(id: group.id)?.name, "Existing group")
    }

    func testWriteFailureIsReportedWithoutChangingInMemoryData() throws {
        let store = NoteStore(storageDirectory: directory)
        try FileManager.default.createDirectory(
            at: directory.appendingPathComponent("note1-data.json"),
            withIntermediateDirectories: true
        )

        XCTAssertThrowsError(try store.createIdea(content: "无法写入")) { error in
            guard case NoteStoreError.persistenceWriteFailed = error else {
                return XCTFail("应返回持久化写入错误，实际为：\(error)")
            }
        }

        XCTAssertNotNil(store.lastPersistenceError)
        XCTAssertTrue(store.ideas.isEmpty)
        XCTAssertFalse(store.isReadOnlyBecausePersistenceFailed)
    }

    private func makeGroup(name: String) -> IdeaGroup {
        let now = Date()
        return IdeaGroup(
            id: UUID(),
            name: name,
            status: .active,
            createdAt: now,
            updatedAt: now,
            activityAt: now,
            completedAt: nil
        )
    }

    private func writeStoredData(version: Int, groups: [IdeaGroup]) throws {
        let storedData = LegacyStoredData(
            version: version,
            ideas: [],
            groups: groups,
            attachments: []
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(storedData).write(
            to: directory.appendingPathComponent("note1-data.json"),
            options: [.atomic]
        )
    }
}

private struct LegacyStoredData: Codable {
    let version: Int
    let ideas: [Idea]
    let groups: [IdeaGroup]
    let attachments: [Attachment]
}
