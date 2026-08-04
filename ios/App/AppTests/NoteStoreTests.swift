import XCTest
import UIKit
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

    func testReviewGestureOnlyCompletesWithClearLeftwardIntent() {
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
                translation: CGSize(width: -96, height: 24),
                predictedEndTranslation: CGSize(width: -130, height: 36)
            )
        )
        XCTAssertTrue(
            ReviewGestureClassifier.shouldComplete(
                axis: axis,
                translation: CGSize(width: -116, height: 24),
                predictedEndTranslation: CGSize(width: -200, height: 36)
            )
        )
        XCTAssertFalse(
            ReviewGestureClassifier.shouldComplete(
                axis: axis,
                translation: CGSize(width: 160, height: 24),
                predictedEndTranslation: CGSize(width: 260, height: 36)
            )
        )
    }

    func testV02CardDeckKeepsTheLeadingEdgeForPrimaryPageNavigation() {
        XCTAssertFalse(
            V02CardDeckPolicy.acceptsHorizontalTuck(
                startX: 18,
                translation: CGSize(width: -180, height: 4)
            )
        )
        XCTAssertTrue(
            V02CardDeckPolicy.acceptsHorizontalTuck(
                startX: 72,
                translation: CGSize(width: -180, height: 4)
            )
        )
        XCTAssertFalse(
            V02CardDeckPolicy.acceptsHorizontalTuck(
                startX: 72,
                translation: CGSize(width: 180, height: 4)
            )
        )
    }

    func testV02CardDeckPagesOnlyAfterVerticalThreshold() {
        let axis = ReviewGestureClassifier.axis(for: CGSize(width: 8, height: -108))
        XCTAssertEqual(
            V02CardDeckPolicy.pageDirection(
                axis: axis,
                translation: CGSize(width: 8, height: -108),
                predictedEndTranslation: CGSize(width: 10, height: -140)
            ),
            1
        )
        XCTAssertNil(
            V02CardDeckPolicy.pageDirection(
                axis: .vertical,
                translation: CGSize(width: 5, height: 38),
                predictedEndTranslation: CGSize(width: 5, height: 52)
            )
        )
    }

    func testV02CardPreviewKeepsStableFirstScreenHeightAndCapsLongText() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let sparse = V02Inspiration(
            id: UUID(),
            text: "短",
            cardFlowState: .visible,
            collectionID: nil,
            createdAt: now,
            updatedAt: now,
            resourceIDs: []
        )
        let long = V02Inspiration(
            id: UUID(),
            text: String(repeating: "长", count: 180),
            cardFlowState: .visible,
            collectionID: nil,
            createdAt: now,
            updatedAt: now,
            resourceIDs: []
        )

        let sparseHeight = V02CardPreviewLayoutPolicy.deckHeight(for: .inspiration(sparse))
        let longHeight = V02CardPreviewLayoutPolicy.deckHeight(for: .inspiration(long))

        XCTAssertEqual(sparseHeight, V02CardPreviewLayoutPolicy.compactHeight)
        XCTAssertGreaterThanOrEqual(longHeight, sparseHeight)
        XCTAssertLessThanOrEqual(longHeight, V02CardPreviewLayoutPolicy.maximumHeight)
    }

    func testV02CollectionPreviewUsesStableFirstScreenPaperFloor() {
        let collection = V02ThinkingCollection(
            id: UUID(),
            name: "构思集（1）",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            currentRoundID: UUID()
        )

        let collectionHeight = V02CardPreviewLayoutPolicy.deckHeight(
            for: .collection(collection, memberCount: 1)
        )

        XCTAssertEqual(collectionHeight, V02CardPreviewLayoutPolicy.collectionHeight)
        XCTAssertEqual(collectionHeight, V02CardPreviewLayoutPolicy.compactHeight)
    }

    func testV02CardPositionRestoresIdentityAndFallsBackSafely() {
        let first = UUID(), second = UUID(), third = UUID()
        XCTAssertEqual(V02CardPositionPolicy.resolvedIndex(preferredID: second, currentIndex: 0, ids: [first, second, third]), 1)
        XCTAssertEqual(V02CardPositionPolicy.resolvedIndex(preferredID: second, currentIndex: 0, ids: [third, first]), 0)
        XCTAssertEqual(V02CardPositionPolicy.resolvedIndex(preferredID: second, currentIndex: 9, ids: [third, second, first]), 1)
        XCTAssertNil(V02CardPositionPolicy.resolvedIndex(preferredID: first, currentIndex: 0, ids: []))
    }

    func testV02TuckPolicyRejectsDuplicateCommitWhileExiting() {
        XCTAssertTrue(V02TuckPolicy.mayBegin(isTucking: false))
        XCTAssertFalse(V02TuckPolicy.mayBegin(isTucking: true))
        XCTAssertEqual(V02TuckPolicy.commitDelay, 0.23)
    }

    func testV02GroupTargetUsesOnlyTheFinalLiveHit() {
        let first = CGRect(x: 0, y: 0, width: 80, height: 80)
        let second = CGRect(x: 100, y: 100, width: 80, height: 80)
        let frames = ["group": first, "new": second]
        XCTAssertEqual(V02GroupTargetPolicy.activeTarget(at: CGPoint(x: 40, y: 40), frames: frames), "group")
        XCTAssertNil(V02GroupTargetPolicy.activeTarget(at: CGPoint(x: 90, y: 90), frames: frames))
        XCTAssertEqual(V02GroupTargetPolicy.activeTarget(at: CGPoint(x: 40, y: 40), frames: frames), "group")
        XCTAssertEqual(V02GroupTargetPolicy.commitTarget(finalActiveTarget: "group"), "group")
        XCTAssertNil(V02GroupTargetPolicy.commitTarget(finalActiveTarget: nil))
    }

    func testV02GroupOperationTargetsRespectZeroFiveAndCapacityRules() {
        XCTAssertEqual(V02GroupOperationPolicy.targetIDs(activeCollectionCount: 0), ["new"])
        XCTAssertEqual(V02GroupOperationPolicy.targetIDs(activeCollectionCount: 3), ["new", "existing"])
        XCTAssertEqual(V02GroupOperationPolicy.targetIDs(activeCollectionCount: 5), ["existing"])
        XCTAssertTrue(V02GroupOperationPolicy.canAccept(memberCount: 9))
        XCTAssertFalse(V02GroupOperationPolicy.canAccept(memberCount: 10))
        XCTAssertEqual(V02GroupOperationPolicy.capacityLabel(memberCount: 9), "9/10")
        XCTAssertEqual(V02GroupOperationPolicy.capacityLabel(memberCount: 10), "已满 10 条")
    }

    func testV02CollectionPresentationCoversZeroOneFiveAndMemberCapacity() {
        XCTAssertTrue(V02CollectionOperationPolicy.showsEmptyState(activeCollectionCount: 0))
        XCTAssertFalse(V02CollectionOperationPolicy.showsEmptyState(activeCollectionCount: 1))
        XCTAssertTrue(V02CollectionOperationPolicy.canCreate(activeCollectionCount: 4))
        XCTAssertFalse(V02CollectionOperationPolicy.canCreate(activeCollectionCount: 5))
        XCTAssertTrue(V02CollectionOperationPolicy.canAddMember(memberCount: 9))
        XCTAssertFalse(V02CollectionOperationPolicy.canAddMember(memberCount: 10))
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

    func testReviewPositionRestoresPreferredItemAndFallsBackToNeighbor() {
        let first = UUID()
        let second = UUID()
        let third = UUID()

        XCTAssertEqual(
            ReviewPositionPolicy.resolvedIndex(
                preferredItemID: second,
                currentIndex: 0,
                itemIDs: [first, second, third]
            ),
            1
        )
        XCTAssertEqual(
            ReviewPositionPolicy.resolvedIndex(
                preferredItemID: second,
                currentIndex: 1,
                itemIDs: [first, third]
            ),
            1
        )
        XCTAssertNil(
            ReviewPositionPolicy.resolvedIndex(
                preferredItemID: second,
                currentIndex: 1,
                itemIDs: []
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

    func testV02RoundCreatesOneImmutableReceiptAndRejectsDuplicateEnd() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        var state = V02DomainState()
        let collection = try V02DomainEngine.createCollection(
            in: &state,
            now: now
        )
        let inspiration = V02Inspiration(
            id: UUID(),
            text: "最初的文字",
            cardFlowState: .visible,
            collectionID: nil,
            createdAt: now,
            updatedAt: now,
            resourceIDs: []
        )
        state.inspirations.append(inspiration)
        let round = try V02DomainEngine.startRound(
            collectionID: collection.id,
            in: &state,
            now: now
        )
        try V02DomainEngine.assign(
            inspirationID: inspiration.id,
            to: collection.id,
            in: &state,
            now: now
        )

        let receipt = try V02DomainEngine.endRound(
            roundID: round.id,
            in: &state,
            now: now.addingTimeInterval(60)
        )
        state.inspirations[0].text = "之后修改的文字"

        XCTAssertEqual(receipt.snapshot.collectionName, "构思集（1）")
        XCTAssertEqual(receipt.snapshot.members.map(\.text), ["最初的文字"])
        XCTAssertEqual(receipt.snapshot.events.map(\.kind), [.started, .memberAdded, .ended])
        XCTAssertEqual(receipt.snapshot.events.last?.occurredAt, now.addingTimeInterval(60))
        XCTAssertEqual(state.receipts.count, 1)
        XCTAssertThrowsError(
            try V02DomainEngine.endRound(roundID: round.id, in: &state)
        )
    }

    func testV02CollectionCapacityAndNameCounterAreDomainConstraints() throws {
        var state = V02DomainState()
        let collections = try (0 ..< 5).map { _ in
            try V02DomainEngine.createCollection(in: &state)
        }
        XCTAssertEqual(collections.map(\.name), [
            "构思集（1）", "构思集（2）", "构思集（3）", "构思集（4）", "构思集（5）"
        ])
        for collection in collections {
            _ = try V02DomainEngine.startRound(
                collectionID: collection.id,
                in: &state
            )
        }
        XCTAssertThrowsError(try V02DomainEngine.createCollection(in: &state)) {
            XCTAssertEqual($0 as? V02DomainError, .collectionLimit)
        }
    }

    func testV02CollectionNameTrimsWhitespaceAndUsesDefaultForBlankInput() throws {
        var state = V02DomainState()

        let named = try V02DomainEngine.createCollection(in: &state, name: "  设计方向  ")
        let blank = try V02DomainEngine.createCollection(in: &state, name: " \n\t ")

        XCTAssertEqual(named.name, "设计方向")
        XCTAssertEqual(blank.name, "构思集（2）")
    }

    func testV02StorePersistsAndDoesNotWriteEmptyInspirations() throws {
        let v02Directory = directory.appendingPathComponent("v02")
        let store = V02Store(storageDirectory: v02Directory)
        XCTAssertThrowsError(try store.createInspiration(text: ""))

        let created = try store.createInspiration(text: "本机保存")
        let collection = try store.createCollectionAndRound()
        try store.assign(created.id, to: collection.id)

        let reloaded = V02Store(storageDirectory: v02Directory)
        XCTAssertEqual(reloaded.state.inspirations.map(\.text), ["本机保存"])
        XCTAssertEqual(reloaded.activeCollections.map(\.id), [collection.id])
        XCTAssertEqual(reloaded.state.rounds.first?.memberIDs, [created.id])
    }

    func testV02CreateCollectionAndAssignIsAtomic() throws {
        let v02Directory = directory.appendingPathComponent("v02-atomic")
        let store = V02Store(storageDirectory: v02Directory)
        let inspiration = try store.createInspiration(text: "待归入")

        let created = try store.createCollectionAndRoundAndAssign(inspirationID: inspiration.id)
        XCTAssertEqual(store.activeCollections.map(\.id), [created.id])
        XCTAssertEqual(store.state.inspirations.first?.collectionID, created.id)

        let activeCount = store.activeCollections.count
        XCTAssertThrowsError(
            try store.createCollectionAndRoundAndAssign(inspirationID: UUID())
        )
        XCTAssertEqual(store.activeCollections.count, activeCount)
    }

    func testV02ContinueThinkingKeepsOldReceiptSnapshotAndRestoresMembers() throws {
        let v02Directory = directory.appendingPathComponent("continue")
        let store = V02Store(storageDirectory: v02Directory)
        let inspiration = try store.createInspiration(text: "第一轮")
        let collection = try store.createCollectionAndRound()
        try store.assign(inspiration.id, to: collection.id)
        let firstRound = try XCTUnwrap(store.activeCollections.first?.currentRoundID)
        let receipt = try store.endRound(firstRound)

        _ = try store.continueThinking(in: collection.id)
        try store.updateInspiration(inspiration.id, text: "第二轮修改")

        XCTAssertEqual(receipt.snapshot.members.map(\.text), ["第一轮"])
        XCTAssertEqual(store.state.receipts.count, 1)
        XCTAssertEqual(store.activeCollections.map(\.id), [collection.id])
        XCTAssertEqual(store.state.inspirations.first?.collectionID, collection.id)
    }

    func testV02TrashRestoresAnIndependentInspirationAndExpiresAtThirtyDays() throws {
        let v02Directory = directory.appendingPathComponent("trash")
        let store = V02Store(storageDirectory: v02Directory)
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let resource = try store.saveVoiceInspirationAudio(filename: "expired.m4a", m4aData: Data([0, 1]))
        let resourceURL = store.resourceURL(resource)
        let inspiration = try store.createInspiration(text: "可以恢复", resourceIDs: [resource.id], now: now)
        try store.deleteInspiration(inspiration.id, now: now)
        let entry = try XCTUnwrap(store.state.trash.first)
        try store.restoreTrash(entry.id, now: now.addingTimeInterval(10))
        XCTAssertEqual(store.state.inspirations.first?.collectionID, nil)
        XCTAssertEqual(store.state.inspirations.first?.cardFlowState, .visible)

        try store.deleteInspiration(inspiration.id, now: now)
        try store.purgeExpiredTrash(now: now.addingTimeInterval(30 * 24 * 60 * 60))
        XCTAssertTrue(store.state.trash.isEmpty)
        XCTAssertTrue(store.state.resources.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: resourceURL.path))
    }

    func testV02PermanentTrashDeleteKeepsResourceUntilLastReferenceIsGone() throws {
        let store = V02Store(storageDirectory: directory.appendingPathComponent("permanent-trash"))
        let resource = try store.saveVoiceInspirationAudio(filename: "shared.m4a", m4aData: Data([0, 1]))
        let resourceURL = store.resourceURL(resource)
        let inspiration = try store.createInspiration(text: "共享附件", resourceIDs: [resource.id])
        let collection = try store.createCollectionAndRound()
        try store.assign(inspiration.id, to: collection.id)
        let receipt = try store.endRound(try XCTUnwrap(store.activeCollections.first?.currentRoundID))
        try store.deleteInspiration(inspiration.id)
        try store.deleteReceipt(receipt.id)

        let inspirationEntry = try XCTUnwrap(store.state.trash.first { entry in
            if case .inspiration = entry.object { return true }
            return false
        })
        let receiptEntry = try XCTUnwrap(store.state.trash.first { entry in
            if case .receipt = entry.object { return true }
            return false
        })
        try store.permanentlyDeleteTrash([inspirationEntry.id])
        XCTAssertEqual(store.state.resources.map(\.id), [resource.id])
        XCTAssertTrue(FileManager.default.fileExists(atPath: resourceURL.path))

        try store.permanentlyDeleteTrash([receiptEntry.id])
        XCTAssertTrue(store.state.resources.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: resourceURL.path))
    }

    func testV02BackupRestoresTrashReceiptsAndReferencedResources() throws {
        let source = V02Store(storageDirectory: directory.appendingPathComponent("backup-source"))
        let resource = try source.saveVoiceInspirationAudio(filename: "backup.m4a", m4aData: Data([0, 1, 2]))
        let inspiration = try source.createInspiration(text: "备份内容", resourceIDs: [resource.id])
        let collection = try source.createCollectionAndRound(name: "备份构思集")
        try source.assign(inspiration.id, to: collection.id)
        let receipt = try source.endRound(try XCTUnwrap(source.activeCollections.first?.currentRoundID))
        try source.deleteInspiration(inspiration.id)
        try source.deleteReceipt(receipt.id)
        let backup = try source.exportBackupData()

        let target = V02Store(storageDirectory: directory.appendingPathComponent("backup-target"))
        _ = try target.createInspiration(text: "将被恢复替换")
        try target.restoreBackupData(backup)

        XCTAssertEqual(target.state.inspirations.count, 0)
        XCTAssertEqual(target.state.receipts.count, 0)
        XCTAssertEqual(target.state.trash.count, 2)
        XCTAssertEqual(target.state.resources.map(\.id), [resource.id])
        let restoredResource = try XCTUnwrap(target.state.resources.first)
        XCTAssertEqual(try Data(contentsOf: target.resourceURL(restoredResource)), Data([0, 1, 2]))
    }

    func testV02BackupRejectsReceiptAttachmentSnapshotMismatch() throws {
        let source = V02Store(storageDirectory: directory.appendingPathComponent("invalid-receipt-snapshot"))
        let resource = try source.saveVoiceInspirationAudio(filename: "snapshot.m4a", m4aData: Data([0, 1, 2]))
        let inspiration = try source.createInspiration(text: "需要冻结附件", resourceIDs: [resource.id])
        let collection = try source.createCollectionAndRound()
        try source.assign(inspiration.id, to: collection.id)
        _ = try source.endRound(try XCTUnwrap(source.state.rounds.first(where: { $0.collectionID == collection.id && $0.state == .thinking })?.id))

        let backupData = try source.exportBackupData()
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var payload = try decoder.decode(V02BackupPayload.self, from: backupData)
        var state = payload.state
        let receiptIndex = try XCTUnwrap(state.receipts.indices.first)
        let member = try XCTUnwrap(state.receipts[receiptIndex].snapshot.members.first)
        let forged = V02ReceiptSnapshot.Attachment(
            id: resource.id,
            source: .importedAttachment,
            filename: "被篡改.m4a",
            mimeType: resource.mimeType,
            relativePath: resource.relativePath,
            size: resource.size,
            createdAt: resource.createdAt
        )
        let forgedMember = V02ReceiptSnapshot.Member(
            inspirationID: member.inspirationID,
            text: member.text,
            resourceIDs: member.resourceIDs,
            attachments: [forged]
        )
        let snapshot = state.receipts[receiptIndex].snapshot
        let forgedSnapshot = V02ReceiptSnapshot(
            collectionName: snapshot.collectionName,
            startedAt: snapshot.startedAt,
            endedAt: snapshot.endedAt,
            effectiveEditCount: snapshot.effectiveEditCount,
            members: [forgedMember],
            events: snapshot.events
        )
        let receipt = state.receipts[receiptIndex]
        state.receipts[receiptIndex] = V02Receipt(
            id: receipt.id,
            roundID: receipt.roundID,
            collectionID: receipt.collectionID,
            createdAt: receipt.createdAt,
            snapshot: forgedSnapshot
        )
        payload = V02BackupPayload(exportedAt: payload.exportedAt, state: state, resources: payload.resources)

        XCTAssertThrowsError(try V02BackupService.encode(payload))
    }

    func testV02InvalidBackupDoesNotChangeCurrentData() throws {
        let store = V02Store(storageDirectory: directory.appendingPathComponent("invalid-v02-backup"))
        let original = try store.createInspiration(text: "保留原数据")

        XCTAssertThrowsError(try store.restoreBackupData(Data("not-a-backup".utf8)))
        XCTAssertEqual(store.state.inspirations.map(\.id), [original.id])
        XCTAssertEqual(store.state.inspirations.first?.text, "保留原数据")
    }

    func testV02DeletedMemberDoesNotBreakLaterContinueThinking() throws {
        let store = V02Store(storageDirectory: directory.appendingPathComponent("deleted-member"))
        let inspiration = try store.createInspiration(text: "将被删除")
        let collection = try store.createCollectionAndRound()
        try store.assign(inspiration.id, to: collection.id)
        let firstRound = try XCTUnwrap(store.activeCollections.first?.currentRoundID)
        _ = try store.endRound(firstRound)
        try store.deleteInspiration(inspiration.id)

        XCTAssertFalse(store.state.collections.contains { $0.id == collection.id })
        XCTAssertThrowsError(try store.continueThinking(in: collection.id))
    }

    func testV02ResourceWritesBeforeBeingReferencedAndSurvivesReload() throws {
        let path = directory.appendingPathComponent("resources")
        let store = V02Store(storageDirectory: path)
        let resource = try store.createResource(
            input: AttachmentInput(name: "reference.pdf", mimeType: "application/pdf", data: Data("pdf".utf8)),
            source: .importedAttachment
        )
        let inspiration = try store.createInspiration(text: "带附件", resourceIDs: [resource.id])
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.resourceURL(resource).path))

        let reloaded = V02Store(storageDirectory: path)
        XCTAssertEqual(reloaded.state.resources.map(\.id), [resource.id])
        XCTAssertEqual(reloaded.state.inspirations.first?.id, inspiration.id)
        XCTAssertThrowsError(try reloaded.createInspiration(text: "错误引用", resourceIDs: [UUID()]))
    }

    func testV02ReceiptExportAlwaysUsesTheFrozenSnapshot() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let receipt = V02Receipt(
            id: UUID(), roundID: UUID(), collectionID: UUID(), createdAt: now,
            snapshot: .init(collectionName: "文章构思", startedAt: now, endedAt: now, effectiveEditCount: 1,
                            members: [.init(inspirationID: UUID(), text: "固定内容", resourceIDs: [])])
        )
        XCTAssertTrue(V02ReceiptExport.plainText(for: receipt).contains("固定内容"))
        XCTAssertTrue(V02ReceiptExport.markdown(for: receipt).contains("# 文章构思"))
        XCTAssertTrue(V02ReceiptExport.pdfData(for: receipt).starts(with: Data("%PDF".utf8)))
    }

    func testV02ReceiptTemplateFallsBackToClassicWithoutPhotosAndUsesFilmForThreePhotos() throws {
        let store = V02Store(storageDirectory: directory.appendingPathComponent("receipt-template"))
        let receipt = V02Receipt(
            id: UUID(), roundID: UUID(), collectionID: UUID(), createdAt: .now,
            snapshot: .init(collectionName: "视觉构思", startedAt: .now, endedAt: .now, effectiveEditCount: 0,
                            members: [.init(inspirationID: UUID(), text: "只有文字", resourceIDs: [])])
        )
        XCTAssertEqual(V02ReceiptTemplate.recommended(for: receipt, resources: store.state.resources), .classic)

        let photos = try (0..<3).map { index in
            try store.createResource(
                input: AttachmentInput(name: "photo-\(index).jpg", mimeType: "image/jpeg", data: Data([0x00])),
                source: .importedAttachment
            )
        }
        let visualReceipt = V02Receipt(
            id: UUID(), roundID: UUID(), collectionID: UUID(), createdAt: .now,
            snapshot: .init(collectionName: "视觉构思", startedAt: .now, endedAt: .now, effectiveEditCount: 0,
                            members: [.init(inspirationID: UUID(), text: "三张照片", resourceIDs: photos.map(\.id))])
        )
        XCTAssertEqual(V02ReceiptTemplate.recommended(for: visualReceipt, resources: store.state.resources), .film)
    }

    func testV02ReceiptGesturePolicyLocksAxesAndCommitsOnlyValidTargets() {
        XCTAssertEqual(V02ReceiptGesturePolicy.axis(for: .init(width: 8, height: 7)), .none)
        XCTAssertEqual(V02ReceiptGesturePolicy.axis(for: .init(width: -40, height: 12)), .horizontal)
        XCTAssertEqual(V02ReceiptGesturePolicy.axis(for: .init(width: 10, height: 48)), .downward)
        XCTAssertEqual(V02ReceiptGesturePolicy.axis(for: .init(width: 35, height: 35)), .none)
        XCTAssertEqual(V02ReceiptGesturePolicy.horizontalTarget(index: 1, count: 3, translation: -100), 2)
        XCTAssertEqual(V02ReceiptGesturePolicy.candidateIndex(index: 1, count: 3, translation: -12), 2)
        XCTAssertEqual(V02ReceiptGesturePolicy.candidateIndex(index: 1, count: 3, translation: 12), 0)
        XCTAssertNil(V02ReceiptGesturePolicy.candidateIndex(index: 0, count: 3, translation: 12))
        XCTAssertEqual(V02ReceiptGesturePolicy.horizontalTarget(index: 0, count: 3, translation: 100), nil)
        XCTAssertNil(V02ReceiptGesturePolicy.horizontalTarget(index: 1, count: 3, translation: 30))
        XCTAssertEqual(V02ReceiptGesturePolicy.normalizedProgress(translation: 90, extent: 360), 0.25, accuracy: 0.001)
        XCTAssertEqual(V02ReceiptGesturePolicy.normalizedProgress(translation: 500, extent: 360), 1, accuracy: 0.001)
        XCTAssertEqual(V02ReceiptGesturePolicy.normalizedProgress(translation: 10, extent: 0), 1, accuracy: 0.001)
        XCTAssertFalse(V02ReceiptGesturePolicy.shouldExtract(70))
        XCTAssertTrue(V02ReceiptGesturePolicy.shouldExtract(120))
        XCTAssertTrue(V02ReceiptGesturePolicy.canStartExtraction(at: CGPoint(x: 120, y: 72)))
        XCTAssertTrue(V02ReceiptGesturePolicy.canStartExtraction(at: CGPoint(x: 120, y: 96)))
        XCTAssertFalse(V02ReceiptGesturePolicy.canStartExtraction(at: CGPoint(x: 120, y: 97)))
        XCTAssertFalse(V02ReceiptGesturePolicy.canStartExtraction(at: CGPoint(x: 120, y: 420)))
    }

    func testV02ReceiptCandidateAndProgressAreAvailableBeforeCommitThreshold() {
        XCTAssertEqual(V02ReceiptGesturePolicy.candidateIndex(index: 0, count: 2, translation: -8), 1)
        XCTAssertNil(V02ReceiptGesturePolicy.horizontalTarget(index: 0, count: 2, translation: -8))
        XCTAssertEqual(V02ReceiptGesturePolicy.normalizedProgress(translation: -8, extent: 368), 8.0 / 368.0, accuracy: 0.001)
        XCTAssertEqual(V02ReceiptGesturePolicy.normalizedProgress(translation: 184, extent: 368), 0.5, accuracy: 0.001)
    }

    func testV02ReceiptGenerationPolicyRevealsContentAfterPaperStarts() {
        XCTAssertEqual(V02ReceiptGenerationPolicy.contentOpacity(for: 0), 0, accuracy: 0.001)
        XCTAssertEqual(V02ReceiptGenerationPolicy.contentOpacity(for: 0.18), 0, accuracy: 0.001)
        XCTAssertGreaterThan(V02ReceiptGenerationPolicy.contentOpacity(for: 0.6), 0)
        XCTAssertEqual(V02ReceiptGenerationPolicy.contentOpacity(for: 1), 1, accuracy: 0.001)
        XCTAssertLessThan(V02ReceiptGenerationPolicy.reducedMotionDuration, V02ReceiptGenerationPolicy.normalDuration)
        XCTAssertEqual(V02ReceiptGenerationPolicy.undoWindow, 2, accuracy: 0.001)
    }

    func testV02ReceiptGenerationReservesPrimaryNavigationLayer() {
        XCTAssertEqual(
            V02ReceiptGenerationLayoutPolicy.bottomPadding(navigationHeight: 72),
            90,
            accuracy: 0.001
        )
        XCTAssertLessThan(
            V02ReceiptGenerationLayoutPolicy.generationZIndex,
            V02ReceiptGenerationLayoutPolicy.primaryNavigationZIndex
        )
        XCTAssertLessThan(
            V02ReceiptGenerationLayoutPolicy.primaryNavigationZIndex,
            V02ReceiptGenerationLayoutPolicy.composerZIndex
        )
    }

    func testV02ReceiptExportWritesIndividuallyShareableFiles() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let receipt = V02Receipt(
            id: UUID(), roundID: UUID(), collectionID: UUID(), createdAt: now,
            snapshot: .init(collectionName: "分享测试", startedAt: now, endedAt: now, effectiveEditCount: 0,
                            members: [.init(inspirationID: UUID(), text: "可导出内容", resourceIDs: [])])
        )
        let pdfURL = try V02ReceiptExportFile.write(receipt, format: .pdf)
        let markdownURL = try V02ReceiptExportFile.write(receipt, format: .markdown)
        defer {
            try? FileManager.default.removeItem(at: pdfURL)
            try? FileManager.default.removeItem(at: markdownURL)
        }

        XCTAssertTrue(try Data(contentsOf: pdfURL).starts(with: Data("%PDF".utf8)))
        XCTAssertTrue(try String(contentsOf: markdownURL).contains("# 分享测试"))
    }

    func testV02PDFExportCarriesSnapshotImagesWhenAResolverIsProvided() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("NOTE1PDF-(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let image = UIGraphicsImageRenderer(size: CGSize(width: 40, height: 20)).image { context in
            UIColor.systemBlue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 40, height: 20))
        }
        let relativePath = "snapshot.png"
        let imageURL = directory.appendingPathComponent(relativePath)
        try XCTUnwrap(image.pngData()).write(to: imageURL, options: .atomic)

        let resource = V02AttachmentResource(
            id: UUID(),
            source: .importedAttachment,
            filename: "参考图.png",
            mimeType: "image/png",
            relativePath: relativePath,
            size: 12,
            createdAt: .now
        )
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let receipt = V02Receipt(
            id: UUID(),
            roundID: UUID(),
            collectionID: UUID(),
            createdAt: now,
            snapshot: .init(
                collectionName: "图片导出",
                startedAt: now,
                endedAt: now.addingTimeInterval(60),
                effectiveEditCount: 0,
                members: [.init(
                    inspirationID: UUID(),
                    text: "带图片的灵感",
                    resourceIDs: [resource.id],
                    attachments: [.init(resource: resource)]
                )]
            )
        )

        let pdf = V02ReceiptExport.pdfData(for: receipt) { path in
            path == relativePath ? imageURL : nil
        }
        XCTAssertTrue(pdf.range(of: Data("/Subtype /Image".utf8)) != nil)
    }

    func testV02SearchFindsFrozenReceiptContentAfterOriginalIsEdited() throws {
        let store = V02Store(storageDirectory: directory.appendingPathComponent("search"))
        let inspiration = try store.createInspiration(text: "原始火星")
        let collection = try store.createCollectionAndRound(name: "行星")
        try store.assign(inspiration.id, to: collection.id)
        let roundID = try XCTUnwrap(store.activeCollections.first?.currentRoundID)
        _ = try store.endRound(roundID)
        try store.updateInspiration(inspiration.id, text: "改成金星")

        XCTAssertEqual(store.search("火星", scope: .receipts).count, 1)
        XCTAssertTrue(store.search("火星", scope: .inspirations).isEmpty)
        XCTAssertEqual(store.search("行星", scope: .collections).count, 1)
    }

    func testV02SearchFindsAttachmentFilenameInInspirationAndReceipt() throws {
        let store = V02Store(storageDirectory: directory.appendingPathComponent("attachment-search"))
        let resource = try store.createResource(
            input: AttachmentInput(name: "会议录音.m4a", mimeType: "audio/mp4", data: Data([0, 1])),
            source: .importedAttachment
        )
        let inspiration = try store.createInspiration(text: "不含关键词", resourceIDs: [resource.id])
        let collection = try store.createCollectionAndRound()
        try store.assign(inspiration.id, to: collection.id)
        _ = try store.endRound(try XCTUnwrap(store.activeCollections.first?.currentRoundID))

        XCTAssertEqual(store.search("会议录音", scope: .inspirations).count, 1)
        XCTAssertEqual(store.search("会议录音", scope: .receipts).count, 1)
    }

    func testV02BatchAssignIsAtomicWhenCapacityIsInsufficient() throws {
        let store = V02Store(storageDirectory: directory.appendingPathComponent("batch"))
        let collection = try store.createCollectionAndRound()
        for index in 0..<9 {
            let item = try store.createInspiration(text: "已有 \(index)")
            try store.assign(item.id, to: collection.id)
        }
        let first = try store.createInspiration(text: "候选一")
        let second = try store.createInspiration(text: "候选二")
        XCTAssertThrowsError(try store.batchAssign([first.id, second.id], to: collection.id))
        XCTAssertNil(store.state.inspirations.first(where: { $0.id == first.id })?.collectionID)
        XCTAssertNil(store.state.inspirations.first(where: { $0.id == second.id })?.collectionID)
    }

    func testV02BatchDeleteMovesEverySelectedInspirationToTrash() throws {
        let store = V02Store(storageDirectory: directory.appendingPathComponent("batch-delete"))
        let first = try store.createInspiration(text: "第一条")
        let second = try store.createInspiration(text: "第二条")
        try store.batchDeleteInspirations([first.id, second.id])

        XCTAssertTrue(store.state.inspirations.isEmpty)
        XCTAssertEqual(store.state.trash.count, 2)
    }

    func testV02DeleteCollectionMovesMembersToTrashWithoutChangingReceipt() throws {
        let store = V02Store(storageDirectory: directory.appendingPathComponent("delete-collection"))
        let inspiration = try store.createInspiration(text: "要删除的构思")
        let collection = try store.createCollectionAndRound(name: "临时构思集")
        try store.assign(inspiration.id, to: collection.id)
        let round = try XCTUnwrap(
            store.state.rounds.first(where: { $0.collectionID == collection.id && $0.state == .thinking })
        )
        let receipt = try store.endRound(round.id)

        try store.deleteCollection(collection.id)

        XCTAssertTrue(store.state.collections.isEmpty)
        XCTAssertTrue(store.state.rounds.isEmpty)
        XCTAssertTrue(store.state.inspirations.isEmpty)
        XCTAssertEqual(store.state.receipts.map(\.id), [receipt.id])
        let trashed = try XCTUnwrap(store.state.trash.first)
        guard case .inspiration(let restored) = trashed.object else {
            return XCTFail("构思集成员应作为独立灵感进入回收站")
        }
        XCTAssertNil(restored.collectionID)
    }

    func testV02UndoEndRoundRestoresCollectionAndRemovesOnlyNewReceipt() throws {
        let store = V02Store(storageDirectory: directory.appendingPathComponent("undo-end-round"))
        let inspiration = try store.createInspiration(text: "待撤回")
        let collection = try store.createCollectionAndRound(name: "撤回构思集")
        try store.assign(inspiration.id, to: collection.id)
        let roundID = try XCTUnwrap(store.activeCollections.first?.currentRoundID)
        let receipt = try store.endRound(roundID)

        try store.undoEndRound(receipt.id)

        XCTAssertTrue(store.state.receipts.isEmpty)
        XCTAssertEqual(store.activeCollections.map(\.id), [collection.id])
        XCTAssertEqual(store.state.rounds.first?.state, .thinking)
        XCTAssertNil(store.state.rounds.first?.endedAt)
        XCTAssertEqual(store.state.inspirations.first?.collectionID, collection.id)
        XCTAssertEqual(store.state.inspirations.first?.cardFlowState, .visible)
    }

    func testV02UndoOnlyAllowsTheLatestReceiptAndDoesNotDuplicateEndEvents() throws {
        let store = V02Store(storageDirectory: directory.appendingPathComponent("undo-latest-receipt"))
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let inspiration = try store.createInspiration(text: "可重复结束", now: now)
        let collection = try store.createCollectionAndRound(name: "撤回顺序", now: now)
        try store.assign(inspiration.id, to: collection.id)

        let firstRoundID = try XCTUnwrap(store.activeCollections.first?.currentRoundID)
        let firstReceipt = try store.endRound(firstRoundID, now: now.addingTimeInterval(10))
        _ = try store.continueThinking(in: collection.id, now: now.addingTimeInterval(20))
        let secondRoundID = try XCTUnwrap(store.activeCollections.first?.currentRoundID)
        let secondReceipt = try store.endRound(secondRoundID, now: now.addingTimeInterval(30))

        XCTAssertThrowsError(try store.undoEndRound(firstReceipt.id, now: now.addingTimeInterval(31)))
        XCTAssertEqual(store.state.receipts.map(\.id), [firstReceipt.id, secondReceipt.id])
        XCTAssertTrue(store.activeCollections.isEmpty)

        try store.undoEndRound(secondReceipt.id, now: now.addingTimeInterval(32))
        let reopenedRoundID = try XCTUnwrap(store.activeCollections.first?.currentRoundID)
        let reopenedReceipt = try store.endRound(reopenedRoundID, now: now.addingTimeInterval(40))
        XCTAssertEqual(reopenedReceipt.snapshot.events.filter { $0.kind == .ended }.count, 1)
    }

    func testV02UndoEndRoundMovesMembersOutOfAnotherActiveRound() throws {
        let store = V02Store(storageDirectory: directory.appendingPathComponent("undo-round-ownership"))
        let inspiration = try store.createInspiration(text: "撤回后仍只能属于一轮")
        let original = try store.createCollectionAndRound(name: "原构思集")
        try store.assign(inspiration.id, to: original.id)
        let originalRoundID = try XCTUnwrap(store.state.collections.first(where: { $0.id == original.id })?.currentRoundID)
        let receipt = try store.endRound(originalRoundID)

        let other = try store.createCollectionAndRound(name: "另一构思集")
        try store.assign(inspiration.id, to: other.id)
        try store.undoEndRound(receipt.id)

        let originalRound = try XCTUnwrap(store.state.rounds.first(where: { $0.collectionID == original.id && $0.state == .thinking }))
        let otherRound = try XCTUnwrap(store.state.rounds.first(where: { $0.collectionID == other.id && $0.state == .thinking }))
        XCTAssertEqual(originalRound.memberIDs, [inspiration.id])
        XCTAssertTrue(otherRound.memberIDs.isEmpty)
        XCTAssertEqual(store.state.inspirations.first?.collectionID, original.id)
    }

    func testV02UndoEndRoundRespectsActiveCollectionLimit() throws {
        let store = V02Store(storageDirectory: directory.appendingPathComponent("undo-collection-limit"))
        let inspiration = try store.createInspiration(text: "不能恢复成第六个活动构思集")
        let original = try store.createCollectionAndRound(name: "已结束构思集")
        try store.assign(inspiration.id, to: original.id)
        let originalRoundID = try XCTUnwrap(store.state.collections.first(where: { $0.id == original.id })?.currentRoundID)
        let receipt = try store.endRound(originalRoundID)
        for index in 0..<V02DomainEngine.maximumActiveCollections {
            _ = try store.createCollectionAndRound(name: "活动构思集 \(index + 1)")
        }

        XCTAssertThrowsError(try store.undoEndRound(receipt.id)) { error in
            XCTAssertEqual(error as? V02DomainError, .collectionLimit)
        }
        XCTAssertEqual(store.state.receipts.map(\.id), [receipt.id])
        XCTAssertEqual(store.activeCollections.count, V02DomainEngine.maximumActiveCollections)
    }

    func testV02DeletingIndependentInspirationDoesNotRemoveEmptyDraftCollection() throws {
        let store = V02Store(storageDirectory: directory.appendingPathComponent("delete-independent"))
        let emptyCollection = try store.createCollectionAndRound(name: "保留空构思集")
        let inspiration = try store.createInspiration(text: "独立灵感")

        _ = try store.deleteInspiration(inspiration.id)

        XCTAssertTrue(store.state.collections.contains { $0.id == emptyCollection.id })
        XCTAssertTrue(store.state.rounds.contains { $0.collectionID == emptyCollection.id && $0.state == .thinking })
    }

    func testV02ContinueThinkingMovesMembersOutOfAnotherActiveRound() throws {
        let store = V02Store(storageDirectory: directory.appendingPathComponent("continue-round-ownership"))
        let inspiration = try store.createInspiration(text: "只能属于一个活动轮次")
        let original = try store.createCollectionAndRound(name: "原构思集")
        try store.assign(inspiration.id, to: original.id)
        let originalRoundID = try XCTUnwrap(store.activeCollections.first(where: { $0.id == original.id })?.currentRoundID)
        _ = try store.endRound(originalRoundID)

        let other = try store.createCollectionAndRound(name: "另一构思集")
        try store.assign(inspiration.id, to: other.id)
        _ = try store.continueThinking(in: original.id)

        let originalRound = try XCTUnwrap(store.state.rounds.first(where: { $0.collectionID == original.id && $0.state == .thinking }))
        let otherRound = try XCTUnwrap(store.state.rounds.first(where: { $0.collectionID == other.id && $0.state == .thinking }))
        XCTAssertEqual(originalRound.memberIDs, [inspiration.id])
        XCTAssertTrue(otherRound.memberIDs.isEmpty)
        XCTAssertEqual(store.state.inspirations.first?.collectionID, original.id)
    }

    func testV02BatchDeleteReceiptsIsAtomicWhenOneReceiptIsMissing() throws {
        let store = V02Store(storageDirectory: directory.appendingPathComponent("batch-delete-receipts"))
        func makeReceipt(_ text: String, offset: TimeInterval) throws -> V02Receipt {
            let inspiration = try store.createInspiration(
                text: text,
                now: Date(timeIntervalSince1970: 1_700_000_000 + offset)
            )
            let collection = try store.createCollectionAndRound(
                name: text,
                now: Date(timeIntervalSince1970: 1_700_000_000 + offset)
            )
            try store.assign(inspiration.id, to: collection.id)
            let roundID = try XCTUnwrap(store.activeCollections.first(where: { $0.id == collection.id })?.currentRoundID)
            return try store.endRound(roundID, now: Date(timeIntervalSince1970: 1_700_000_000 + offset + 1))
        }

        let first = try makeReceipt("第一张", offset: 0)
        let second = try makeReceipt("第二张", offset: 10)
        XCTAssertThrowsError(try store.batchDeleteReceipts([first.id, UUID()]))
        XCTAssertEqual(Set(store.state.receipts.map(\.id)), [first.id, second.id])
        XCTAssertTrue(store.state.trash.isEmpty)

        let entryIDs = try store.batchDeleteReceipts([first.id, second.id])
        XCTAssertEqual(entryIDs.count, 2)
        XCTAssertTrue(store.state.receipts.isEmpty)
        XCTAssertEqual(store.state.trash.count, 2)
    }

    func testV02RenameCollectionPersistsWithoutChangingDefaultNameCounter() throws {
        let store = V02Store(storageDirectory: directory.appendingPathComponent("rename-collection"))
        let first = try store.createCollectionAndRound()
        try store.renameCollection(first.id, name: "文章构思")
        let second = try store.createCollectionAndRound()

        XCTAssertEqual(store.state.collections.first(where: { $0.id == first.id })?.name, "文章构思")
        XCTAssertEqual(second.name, "构思集（2）")
    }

    func testV02CreateInspirationInCollectionIsAtomicAtCapacity() throws {
        let store = V02Store(storageDirectory: directory.appendingPathComponent("create-in-collection"))
        let collection = try store.createCollectionAndRound()
        for index in 0..<V02DomainEngine.maximumMembersPerCollection {
            _ = try store.createInspiration(text: "成员 \(index)", in: collection.id)
        }

        XCTAssertThrowsError(try store.createInspiration(text: "不应写入", in: collection.id))
        XCTAssertEqual(store.state.inspirations.count, V02DomainEngine.maximumMembersPerCollection)
        XCTAssertFalse(store.state.inspirations.contains { $0.text == "不应写入" })
    }

    func testV02CreateInspirationInMissingOrEndedCollectionReportsTheActualConstraint() throws {
        let store = V02Store(storageDirectory: directory.appendingPathComponent("create-in-invalid-collection"))
        XCTAssertThrowsError(try store.createInspiration(text: "不存在", in: UUID())) { error in
            XCTAssertEqual(error as? V02DomainError, .collectionNotFound)
        }

        let collection = try store.createCollectionAndRound()
        let roundID = try XCTUnwrap(store.state.collections.first(where: { $0.id == collection.id })?.currentRoundID)
        _ = try store.createInspiration(text: "结束前的灵感", in: collection.id)
        _ = try store.endRound(roundID)
        XCTAssertThrowsError(try store.createInspiration(text: "不能加入已结束构思集", in: collection.id)) { error in
            XCTAssertEqual(error as? V02DomainError, .activeRoundRequired)
        }
    }

    func testV02EmptyRoundCannotGenerateAnEmptyReceipt() throws {
        let store = V02Store(storageDirectory: directory.appendingPathComponent("empty-round"))
        let collection = try store.createCollectionAndRound()
        let roundID = try XCTUnwrap(store.activeCollections.first?.currentRoundID)

        XCTAssertThrowsError(try store.endRound(roundID)) { error in
            XCTAssertEqual(error as? V02DomainError, .emptyRound)
        }
        XCTAssertTrue(store.state.receipts.isEmpty)
        XCTAssertEqual(store.activeCollections.map(\.id), [collection.id])
    }

    func testV02RemovingOriginalAttachmentKeepsReceiptReferenceUntilReceiptIsGone() throws {
        let store = V02Store(storageDirectory: directory.appendingPathComponent("remove-attachment"))
        let resource = try store.saveVoiceInspirationAudio(filename: "keep.m4a", m4aData: Data([0, 1]))
        let resourceURL = store.resourceURL(resource)
        let inspiration = try store.createInspiration(text: "带录音", resourceIDs: [resource.id])
        let collection = try store.createCollectionAndRound()
        try store.assign(inspiration.id, to: collection.id)
        let receipt = try store.endRound(try XCTUnwrap(store.activeCollections.first?.currentRoundID))

        try store.removeResource(resource.id, from: inspiration.id)
        XCTAssertTrue(FileManager.default.fileExists(atPath: resourceURL.path))
        XCTAssertNotNil(store.state.resources.first(where: { $0.id == resource.id }))

        try store.deleteReceipt(receipt.id)
        try store.permanentlyDeleteTrash(Set(store.state.trash.map(\.id)))
        XCTAssertFalse(FileManager.default.fileExists(atPath: resourceURL.path))
    }

    func testV02ReceiptSnapshotFreezesAttachmentMetadataForLongDetail() throws {
        let store = V02Store(storageDirectory: directory.appendingPathComponent("frozen-detail-attachments"))
        let resource = try store.createResource(
            input: AttachmentInput(
                name: "会议记录.pdf",
                mimeType: "application/pdf",
                data: Data([0x25, 0x50, 0x44, 0x46])
            ),
            source: .importedAttachment
        )
        let inspiration = try store.createInspiration(text: "保留这份附件快照", resourceIDs: [resource.id])
        let collection = try store.createCollectionAndRound(name: "详情票")
        try store.assign(inspiration.id, to: collection.id)
        let roundID = try XCTUnwrap(store.activeCollections.first(where: { $0.id == collection.id })?.currentRoundID)
        let receipt = try store.endRound(roundID)

        let attachment = try XCTUnwrap(receipt.snapshot.members.first?.attachments.first)
        XCTAssertEqual(attachment.id, resource.id)
        XCTAssertEqual(attachment.filename, "会议记录.pdf")
        XCTAssertEqual(attachment.mimeType, "application/pdf")
        XCTAssertEqual(attachment.size, 4)
        XCTAssertEqual(attachment.relativePath, resource.relativePath)

        // Removing the source link must not erase the long receipt's metadata.
        try store.removeResource(resource.id, from: inspiration.id)
        let persistedReceipt = try XCTUnwrap(store.state.receipts.first)
        let persistedAttachment = try XCTUnwrap(persistedReceipt.snapshot.members.first?.attachments.first)
        XCTAssertEqual(persistedAttachment.filename, "会议记录.pdf")
        XCTAssertEqual(persistedAttachment.mimeType, "application/pdf")
        XCTAssertEqual(persistedAttachment.relativePath, resource.relativePath)
    }

    func testV02ReceiptDetailKeepsBothRealTemplatesAndSecondaryExportFormats() {
        XCTAssertEqual(Set(V02ReceiptTemplate.allCases), [.classic, .film])
        XCTAssertEqual(
            V02ReceiptExportFormat.allCases.map(\.fileExtension),
            ["pdf", "md", "txt"]
        )
    }

    func testV02EditorImportsResourcesWithoutBreakingTheInspirationReference() throws {
        let store = V02Store(storageDirectory: directory.appendingPathComponent("editor-import"))
        let inspiration = try store.createInspiration(text: "编辑中的灵感")

        try store.addImportedResources([
            AttachmentInput(name: "会议.pdf", mimeType: "application/pdf", data: Data([1, 2, 3]))
        ], to: inspiration.id)

        let saved = try XCTUnwrap(store.state.inspirations.first(where: { $0.id == inspiration.id }))
        let resourceID = try XCTUnwrap(saved.resourceIDs.first)
        let resource = try XCTUnwrap(store.state.resources.first(where: { $0.id == resourceID }))
        XCTAssertEqual(resource.filename, "会议.pdf")
        XCTAssertEqual(resource.source.rawValue, V02ResourceSource.importedAttachment.rawValue)
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.resourceURL(resource).path))
    }

    func testV02EditorImportRollsBackResourcesWhenTheInspirationIsMissing() throws {
        let store = V02Store(storageDirectory: directory.appendingPathComponent("editor-import-rollback"))
        XCTAssertThrowsError(try store.addImportedResources([
            AttachmentInput(name: "orphan.pdf", mimeType: "application/pdf", data: Data([4, 5]))
        ], to: UUID()))
        XCTAssertTrue(store.state.resources.isEmpty)
    }

    func testV02EditorImportRejectsOversizedInputWithoutWritingAResource() throws {
        let store = V02Store(storageDirectory: directory.appendingPathComponent("editor-import-size"))
        let inspiration = try store.createInspiration(text: "大小校验")
        XCTAssertThrowsError(try store.addImportedResources([
            AttachmentInput(name: "too-large.bin", data: Data(repeating: 0, count: V02Store.maximumResourceSize + 1))
        ], to: inspiration.id))
        XCTAssertTrue(store.state.resources.isEmpty)
        XCTAssertTrue(try XCTUnwrap(store.state.inspirations.first).resourceIDs.isEmpty)
    }

    func testV02BatchRestoreAndEmptyTrashAreAtomicAndCleanResources() throws {
        let store = V02Store(storageDirectory: directory.appendingPathComponent("batch-trash"))
        let resource = try store.saveVoiceInspirationAudio(filename: "batch.m4a", m4aData: Data([0, 1]))
        let resourceURL = store.resourceURL(resource)
        let first = try store.createInspiration(text: "第一条", resourceIDs: [resource.id])
        let second = try store.createInspiration(text: "第二条")
        try store.batchDeleteInspirations([first.id, second.id])
        let entries = Set(store.state.trash.map(\.id))

        try store.restoreTrash(entries)
        XCTAssertEqual(Set(store.state.inspirations.map(\.id)), [first.id, second.id])
        XCTAssertTrue(store.state.trash.isEmpty)

        try store.batchDeleteInspirations([first.id, second.id])
        try store.emptyTrash()
        XCTAssertTrue(store.state.trash.isEmpty)
        XCTAssertTrue(store.state.resources.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: resourceURL.path))
    }

    func testV02CardPreviewUsesOneCollectionCardInsteadOfDuplicatingMembers() throws {
        let store = V02Store(storageDirectory: directory.appendingPathComponent("card-preview"))
        let independent = try store.createInspiration(text: "独立卡片")
        let grouped = try store.createInspiration(text: "组内卡片")
        let collection = try store.createCollectionAndRound()
        try store.assign(grouped.id, to: collection.id)

        XCTAssertEqual(store.cardPreviewEntries.count, 2)
        XCTAssertTrue(store.cardPreviewEntries.contains { entry in
            if case .inspiration(let inspiration) = entry { return inspiration.id == independent.id }
            return false
        })
        XCTAssertTrue(store.cardPreviewEntries.contains { entry in
            if case .collection(let cardCollection, let memberCount) = entry {
                return cardCollection.id == collection.id && memberCount == 1
            }
            return false
        })
    }

    func testV02VoiceAudioKeepsItsDistinctSourceType() throws {
        let store = V02Store(storageDirectory: directory.appendingPathComponent("voice"))
        let voice = try store.saveVoiceInspirationAudio(filename: "voice.m4a", m4aData: Data([0, 1]))
        XCTAssertEqual(voice.source, .voiceInspiration)
        XCTAssertThrowsError(try store.saveVoiceInspirationAudio(filename: "voice.mp3", m4aData: Data()))
    }

    func testV02DiscardingUnreferencedVoiceResourceRemovesItsFile() throws {
        let store = V02Store(storageDirectory: directory.appendingPathComponent("discard-voice"))
        let resource = try store.saveVoiceInspirationAudio(filename: "draft.m4a", m4aData: Data([0, 1]))
        let url = store.resourceURL(resource)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        try store.discardUnreferencedResource(resource.id)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        XCTAssertTrue(store.state.resources.isEmpty)
    }

    func testV02DiscardDoesNotRemoveResourceReferencedByTrash() throws {
        let store = V02Store(storageDirectory: directory.appendingPathComponent("retain-trash-resource"))
        let resource = try store.saveVoiceInspirationAudio(filename: "retained.m4a", m4aData: Data([0, 1]))
        let url = store.resourceURL(resource)
        let inspiration = try store.createInspiration(text: "有录音", resourceIDs: [resource.id])
        try store.deleteInspiration(inspiration.id)

        XCTAssertThrowsError(try store.discardUnreferencedResource(resource.id))
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        XCTAssertEqual(store.state.resources.map(\.id), [resource.id])
    }

    func testV02PrimaryNavigationUsesFourFullWidthCellsAndReceiptPageHidesComposer() {
        XCTAssertEqual(V02PrimaryPage.allCases.count, 4)
        XCTAssertGreaterThanOrEqual(V02NavigationLayoutPolicy.cellMinHeight, 44)
        XCTAssertGreaterThanOrEqual(V02NavigationLayoutPolicy.barHeight, V02NavigationLayoutPolicy.cellMinHeight)
        XCTAssertGreaterThanOrEqual(V02NavigationLayoutPolicy.primaryContentSpacing, 0)
        XCTAssertGreaterThan(
            V02NavigationLayoutPolicy.primaryContentBottomPadding,
            V02NavigationLayoutPolicy.primaryContentSpacing
        )
        XCTAssertGreaterThanOrEqual(
            V02NavigationLayoutPolicy.primaryContentBottomPadding,
            V02NavigationLayoutPolicy.floatingComposerBottomPadding + NoteTheme.floatingComposerSize
        )
        XCTAssertEqual(V02NavigationLayoutPolicy.cardOperationGap, 24)
        XCTAssertEqual(
            V02NavigationLayoutPolicy.floatingComposerBottomPadding,
            NoteTheme.navigationHeight + V02NavigationLayoutPolicy.composerBottomGap
        )
        XCTAssertEqual(
            V02NavigationLayoutPolicy.workbenchFloatingComposerBottomPadding,
            V02NavigationLayoutPolicy.floatingComposerBottomPadding
        )
        XCTAssertEqual(
            V02NavigationLayoutPolicy.transientBannerBottomPadding,
            NoteTheme.navigationHeight + V02NavigationLayoutPolicy.composerBottomGap
        )
        XCTAssertTrue(V02NavigationLayoutPolicy.showsFloatingComposer(on: .inspirations, isOverlayPresented: false))
        XCTAssertTrue(V02NavigationLayoutPolicy.showsFloatingComposer(on: .collections, isOverlayPresented: false))
        XCTAssertFalse(V02NavigationLayoutPolicy.showsFloatingComposer(on: .receipts, isOverlayPresented: false))
        XCTAssertFalse(V02NavigationLayoutPolicy.showsFloatingComposer(on: .cards, isOverlayPresented: true))
        XCTAssertEqual(V02NavigationLayoutPolicy.composerLabel(for: .inspirations), "记录灵感")
        XCTAssertEqual(V02NavigationLayoutPolicy.composerLabel(for: .cards), "新增卡片")
        XCTAssertEqual(V02NavigationLayoutPolicy.composerLabel(for: .collections), "新建构思集")
    }

    func testV02SearchScopeOrderMatchesPrimarySearchCopy() {
        XCTAssertEqual(V02SearchScope.allCases, [.all, .inspirations, .collections, .receipts])
        XCTAssertEqual(V02SearchScope.allCases.map(\.title), ["全部", "灵感", "构思集", "小票"])
    }

    func testV02TuckAnimationGuardsDuplicateCommitUntilVisualExit() {
        XCTAssertTrue(V02TuckPolicy.commitDelay >= 0.22)
        XCTAssertTrue(V02TuckPolicy.mayBegin(isTucking: false))
        XCTAssertFalse(V02TuckPolicy.mayBegin(isTucking: true))
    }

    func testV02TuckPromptFadesInOnlyAfterLeftwardIntent() {
        XCTAssertEqual(V02CardDeckPolicy.tuckPromptOpacity(for: 0), 0, accuracy: 0.001)
        XCTAssertEqual(V02CardDeckPolicy.tuckPromptOpacity(for: -36), 0, accuracy: 0.001)
        XCTAssertGreaterThan(V02CardDeckPolicy.tuckPromptOpacity(for: -80), 0)
        XCTAssertEqual(V02CardDeckPolicy.tuckPromptOpacity(for: -160), 1, accuracy: 0.001)
        XCTAssertEqual(V02CardDeckPolicy.tuckBackgroundOpacity(for: -36), 0, accuracy: 0.001)
        XCTAssertGreaterThan(V02CardDeckPolicy.tuckBackgroundOpacity(for: -80), 0)
        XCTAssertLessThanOrEqual(V02CardDeckPolicy.tuckBackgroundOpacity(for: -160), 0.161)
        XCTAssertFalse(V02CardDeckPolicy.acceptsHorizontalTuck(startX: 20, translation: CGSize(width: -120, height: 0)))
        XCTAssertTrue(V02CardDeckPolicy.acceptsHorizontalTuck(startX: 80, translation: CGSize(width: -120, height: 0)))
    }
}
