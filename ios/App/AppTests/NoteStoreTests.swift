import XCTest
@testable import App

@MainActor
final class NoteStoreTests: XCTestCase {
    private var directory: URL!
    private var store: NoteStore!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("NOTE1Tests-\(UUID().uuidString)", isDirectory: true)
        store = NoteStore(storageDirectory: directory)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
        store = nil
        directory = nil
    }

    func testPersistsIdeasAndLimitsRecentIdeas() throws {
        for index in 1...6 {
            _ = try store.createIdea(content: "灵感 \(index)")
        }

        XCTAssertEqual(store.recentActiveIdeas.count, 5)
        XCTAssertEqual(store.recentActiveIdeas.first?.content, "灵感 6")

        let reloaded = NoteStore(storageDirectory: directory)
        XCTAssertEqual(reloaded.ideas.count, 6)
        XCTAssertEqual(reloaded.reviewItems.count, 6)
    }

    func testReviewGestureLocksVerticalAxisWithoutCompletion() {
        let axis = ReviewGestureClassifier.axis(
            for: CGSize(width: 34, height: -112)
        )

        XCTAssertEqual(axis, .vertical)
        XCTAssertFalse(
            ReviewGestureClassifier.shouldComplete(
                axis: axis,
                translation: CGSize(width: 34, height: -112),
                predictedEndTranslation: CGSize(width: 172, height: -260)
            )
        )
        XCTAssertTrue(
            ReviewGestureClassifier.shouldPage(
                axis: axis,
                translation: CGSize(width: 34, height: -112),
                predictedEndTranslation: CGSize(width: 172, height: -260)
            )
        )
    }

    func testReviewGestureRequiresClearHorizontalIntentAndHigherThreshold() {
        XCTAssertNil(
            ReviewGestureClassifier.axis(
                for: CGSize(width: 28, height: 25)
            )
        )

        let axis = ReviewGestureClassifier.axis(
            for: CGSize(width: 96, height: 24)
        )
        XCTAssertEqual(axis, .horizontal)
        XCTAssertFalse(
            ReviewGestureClassifier.shouldComplete(
                axis: axis,
                translation: CGSize(width: 96, height: 24),
                predictedEndTranslation: CGSize(width: 130, height: 36)
            )
        )
        XCTAssertTrue(
            ReviewGestureClassifier.shouldComplete(
                axis: axis,
                translation: CGSize(width: 116, height: 24),
                predictedEndTranslation: CGSize(width: 200, height: 36)
            )
        )
    }

    func testGroupDropOnlyUsesVisibleTargetFrames() {
        let groupID = UUID()
        let groupFrame = CGRect(x: 20, y: 100, width: 120, height: 62)
        let newFrame = CGRect(x: 150, y: 100, width: 120, height: 62)

        XCTAssertEqual(
            ReviewGroupDropClassifier.target(
                at: CGPoint(x: 80, y: 131),
                groupFrames: [groupID: groupFrame],
                newFrame: newFrame
            ),
            .group(groupID)
        )
        XCTAssertEqual(
            ReviewGroupDropClassifier.target(
                at: CGPoint(x: 210, y: 131),
                groupFrames: [groupID: groupFrame],
                newFrame: newFrame
            ),
            .new
        )
        XCTAssertNil(
            ReviewGroupDropClassifier.target(
                at: CGPoint(x: 210, y: 92),
                groupFrames: [groupID: groupFrame],
                newFrame: newFrame
            )
        )
    }

    func testHistoryBackGestureRequiresRightwardEdgeIntent() {
        XCTAssertTrue(
            EdgeBackGestureClassifier.shouldNavigateBack(
                startX: 12,
                translation: CGSize(width: 92, height: 18),
                predictedEndTranslation: CGSize(width: 150, height: 24)
            )
        )
        XCTAssertFalse(
            EdgeBackGestureClassifier.shouldNavigateBack(
                startX: 44,
                translation: CGSize(width: 120, height: 12),
                predictedEndTranslation: CGSize(width: 190, height: 18)
            )
        )
        XCTAssertFalse(
            EdgeBackGestureClassifier.shouldNavigateBack(
                startX: 12,
                translation: CGSize(width: 70, height: 82),
                predictedEndTranslation: CGSize(width: 95, height: 140)
            )
        )
    }

    func testGroupCompletionAndRestoreCascade() throws {
        let idea = try store.createIdea(content: "放进想法组")
        let group = try store.createGroup(name: "产品灵感", initialIdeaID: idea.id)

        try store.complete(.group(group))
        XCTAssertEqual(store.group(id: group.id)?.status, .completed)
        XCTAssertEqual(store.idea(id: idea.id)?.status, .completed)
        XCTAssertEqual(store.completedItems.count, 1)

        let completedGroup = try XCTUnwrap(store.group(id: group.id))
        try store.restore(.group(completedGroup))
        XCTAssertEqual(store.group(id: group.id)?.status, .active)
        XCTAssertEqual(store.idea(id: idea.id)?.status, .active)
    }

    func testLegacyExistingGroupNameMigratesToChinese() throws {
        let group = try store.createGroup(name: "Existing group")

        let reloaded = NoteStore(storageDirectory: directory)

        XCTAssertEqual(reloaded.group(id: group.id)?.name, "灵感组")
    }

    func testHistorySearchesAttachmentNames() throws {
        let attachment = AttachmentInput(
            name: "企业架构草图.pdf",
            mimeType: "application/pdf",
            data: Data("test".utf8)
        )
        let idea = try store.createIdea(content: "", attachmentInputs: [attachment])

        XCTAssertEqual(store.recordItems(matching: "架构").first?.id, idea.id)
    }

    func testPDFAttachmentKeepsPreviewableLocalFile() throws {
        let input = AttachmentInput(
            name: "预览测试.pdf",
            mimeType: "application/pdf",
            data: Data("%PDF-1.4\n%%EOF".utf8)
        )
        let idea = try store.createIdea(
            content: "PDF 预览",
            attachmentInputs: [input]
        )

        let attachment = try XCTUnwrap(store.attachments(for: idea.id).first)
        let url = store.attachmentURL(attachment)

        XCTAssertEqual(attachment.mimeType, "application/pdf")
        XCTAssertEqual(url.pathExtension.lowercased(), "pdf")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        XCTAssertEqual(try Data(contentsOf: url), input.data)
    }

    func testOnlyCompletedContentCanBeDeleted() throws {
        let idea = try store.createIdea(content: "先完成再删除")

        XCTAssertThrowsError(try store.deleteCompleted(.idea(idea)))
        try store.complete(.idea(idea))

        let completed = try XCTUnwrap(store.idea(id: idea.id))
        try store.deleteCompleted(.idea(completed))
        XCTAssertNil(store.idea(id: idea.id))
    }

    func testRecordIndexFiltersCurrentAndCompletedWithoutDuplicatingGroupIdeas() throws {
        let standalone = try store.createIdea(content: "当前独立灵感")
        let grouped = try store.createIdea(content: "组内灵感")
        let group = try store.createGroup(name: "当前想法组", initialIdeaID: grouped.id)
        let completedIdea = try store.createIdea(content: "已完成灵感")
        try store.complete(.idea(completedIdea))

        XCTAssertEqual(Set(store.recordItems(status: .active).map(\.id)), [
            standalone.id,
            group.id
        ])
        XCTAssertEqual(store.recordItems(status: .completed).map(\.id), [
            completedIdea.id
        ])
        XCTAssertEqual(store.recordItems().count, 3)
        XCTAssertFalse(store.recordItems().contains { $0.id == grouped.id })
    }

    func testRecordIndexSearchesGroupContentsAndAttachmentsAcrossStatuses() throws {
        let grouped = try store.createIdea(content: "火星计划明细")
        let group = try store.createGroup(name: "远期想法", initialIdeaID: grouped.id)
        let attached = try store.createIdea(
            content: "",
            attachmentInputs: [
                AttachmentInput(
                    name: "月球路线.pdf",
                    mimeType: "application/pdf",
                    data: Data("test".utf8)
                )
            ]
        )
        try store.complete(.idea(attached))

        XCTAssertEqual(store.recordItems(matching: "火星").map(\.id), [group.id])
        XCTAssertEqual(
            store.recordItems(status: .completed, matching: "月球").map(\.id),
            [attached.id]
        )
        XCTAssertTrue(store.recordItems(status: .active, matching: "月球").isEmpty)
    }

    func testBatchDeleteCompletedRecordsPreservesCurrentRecords() throws {
        let current = try store.createIdea(content: "当前记录")
        let first = try store.createIdea(content: "已完成一")
        let second = try store.createIdea(content: "已完成二")
        try store.complete(.idea(first))
        try store.complete(.idea(second))

        let completed = store.recordItems(status: .completed)
        try store.deleteCompleted(completed)

        XCTAssertEqual(store.recordItems().map(\.id), [current.id])
        XCTAssertNotNil(store.idea(id: current.id))
        XCTAssertNil(store.idea(id: first.id))
        XCTAssertNil(store.idea(id: second.id))
    }

    func testHistoryBatchDeleteCanRemoveCurrentAndCompletedRecords() throws {
        let current = try store.createIdea(content: "当前记录")
        let grouped = try store.createIdea(content: "组内记录")
        let group = try store.createGroup(name: "当前想法组", initialIdeaID: grouped.id)
        let completed = try store.createIdea(content: "已完成记录")
        try store.complete(.idea(completed))

        try store.deleteRecords([
            .idea(current),
            .group(group),
            .idea(try XCTUnwrap(store.idea(id: completed.id)))
        ])

        XCTAssertTrue(store.recordItems().isEmpty)
        XCTAssertNil(store.idea(id: current.id))
        XCTAssertNil(store.idea(id: grouped.id))
        XCTAssertNil(store.group(id: group.id))
    }
}
