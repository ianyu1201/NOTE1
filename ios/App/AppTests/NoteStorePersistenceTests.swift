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

    func testCompleteBackupRestoresRelationshipsStatusesAndAttachments() async throws {
        let sourceDirectory = directory.appendingPathComponent(
            "Source",
            isDirectory: true
        )
        let source = NoteStore(storageDirectory: sourceDirectory)
        let idea = try source.createIdea(
            content: "需要完整保留",
            attachmentInputs: [
                AttachmentInput(
                    name: "证据.pdf",
                    mimeType: "application/pdf",
                    data: Data("backup-pdf".utf8)
                )
            ]
        )
        let group = try source.createGroup(
            name: "长期思考",
            initialIdeaID: idea.id
        )
        try source.complete(.group(group))
        let backup = try await source.exportBackupData()

        let targetDirectory = directory.appendingPathComponent(
            "Target",
            isDirectory: true
        )
        let target = NoteStore(storageDirectory: targetDirectory)
        _ = try target.createIdea(content: "恢复后应被替换")
        try await target.restoreBackupData(backup)

        XCTAssertEqual(target.ideas.count, 1)
        XCTAssertEqual(target.groups.count, 1)
        XCTAssertEqual(target.idea(id: idea.id)?.groupID, group.id)
        XCTAssertEqual(target.idea(id: idea.id)?.status, .completed)
        let restoredAttachment = try XCTUnwrap(
            target.attachments(for: idea.id).first
        )
        XCTAssertEqual(
            try Data(contentsOf: target.attachmentURL(restoredAttachment)),
            Data("backup-pdf".utf8)
        )

        let reloaded = NoteStore(storageDirectory: targetDirectory)
        XCTAssertEqual(reloaded.idea(id: idea.id)?.groupID, group.id)
        XCTAssertEqual(reloaded.completedItems.map(\.id), [group.id])
    }

    func testInvalidBackupDoesNotChangeCurrentData() async throws {
        let store = NoteStore(storageDirectory: directory)
        let current = try store.createIdea(content: "原数据")
        let databaseURL = directory.appendingPathComponent("note1-data.json")
        let originalDatabase = try Data(contentsOf: databaseURL)

        do {
            try await store.restoreBackupData(Data("{broken".utf8))
            XCTFail("应拒绝无效备份")
        } catch {}

        XCTAssertEqual(store.ideas.map(\.id), [current.id])
        XCTAssertEqual(try Data(contentsOf: databaseURL), originalDatabase)
    }

    func testExportRefusesToCreateIncompleteBackupWhenAttachmentIsMissing() async throws {
        let store = NoteStore(storageDirectory: directory)
        let idea = try store.createIdea(
            content: "附件不能悄悄丢失",
            attachmentInputs: [
                AttachmentInput(
                    name: "必须存在.txt",
                    mimeType: "text/plain",
                    data: Data("content".utf8)
                )
            ]
        )
        let attachment = try XCTUnwrap(store.attachments(for: idea.id).first)
        try FileManager.default.removeItem(at: store.attachmentURL(attachment))

        do {
            _ = try await store.exportBackupData()
            XCTFail("应拒绝不完整备份")
        } catch {
            guard case NoteBackupError.missingAttachment = error else {
                return XCTFail("应拒绝不完整备份，实际为：\(error)")
            }
        }
    }

    func testBackupRejectsUnsafeAttachmentPath() throws {
        let now = Date()
        let idea = Idea(
            id: UUID(),
            content: "路径安全",
            status: .active,
            groupID: nil,
            createdAt: now,
            updatedAt: now,
            activityAt: now,
            completedAt: nil,
            addedToGroupAt: nil
        )
        let data = Data("unsafe".utf8)
        let attachment = Attachment(
            id: UUID(),
            ideaID: idea.id,
            name: "越界.txt",
            mimeType: "text/plain",
            size: Int64(data.count),
            relativePath: "../越界.txt",
            createdAt: now
        )
        let payload = NoteBackupPayload(
            ideas: [idea],
            groups: [],
            attachments: [
                NoteBackupAttachment(
                    metadata: attachment,
                    data: data
                )
            ]
        )

        XCTAssertThrowsError(try JSONNoteBackupService().encode(payload))
    }

    func testBackupRejectsIdeaAndGroupSharingTheSameID() throws {
        let id = UUID()
        let now = Date()
        let payload = NoteBackupPayload(
            ideas: [
                Idea(
                    id: id,
                    content: "重复 ID",
                    status: .active,
                    groupID: nil,
                    createdAt: now,
                    updatedAt: now,
                    activityAt: now,
                    completedAt: nil,
                    addedToGroupAt: nil
                )
            ],
            groups: [
                IdeaGroup(
                    id: id,
                    name: "冲突灵感组",
                    status: .active,
                    createdAt: now,
                    updatedAt: now,
                    activityAt: now,
                    completedAt: nil
                )
            ],
            attachments: []
        )

        XCTAssertThrowsError(try JSONNoteBackupService().encode(payload)) {
            error in
            guard case NoteBackupError.invalidArchive = error else {
                return XCTFail("应拒绝跨类型重复 ID，实际为：\(error)")
            }
        }
    }

    func testReviewPositionPreferenceRoundTripsAndClears() throws {
        let suiteName = "NOTE1ReviewPositionTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let itemID = UUID()

        ReviewPositionPreference.save(itemID, defaults: defaults)
        XCTAssertEqual(
            ReviewPositionPreference.load(defaults: defaults),
            itemID
        )

        ReviewPositionPreference.save(nil, defaults: defaults)
        XCTAssertNil(ReviewPositionPreference.load(defaults: defaults))
    }

    func testShortcutDraftIsConsumedOnlyOnce() throws {
        let suiteName = "NOTE1ShortcutDraftTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        AppShortcutDraftStore.save("从快捷指令记录", defaults: defaults)

        XCTAssertEqual(
            AppShortcutDraftStore.consume(defaults: defaults),
            "从快捷指令记录"
        )
        XCTAssertNil(AppShortcutDraftStore.consume(defaults: defaults))
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
