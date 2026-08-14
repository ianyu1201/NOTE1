import XCTest
import UIKit
import PDFKit
@testable import App

@MainActor
final class NoteStoreTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("NOTE1Tests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
        directory = nil
    }

    private func stableDomainSnapshot(_ state: V02DomainState) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(state)
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
        XCTAssertGreaterThanOrEqual(sparseHeight, 460)
        XCTAssertGreaterThanOrEqual(longHeight, sparseHeight)
        XCTAssertLessThanOrEqual(longHeight, V02CardPreviewLayoutPolicy.maximumHeight)
    }

    func testV02CardPreviewAndWorkbenchShareAvailablePageHeightPolicy() {
        let fixture = V02Inspiration(
            id: UUID(),
            text: "短内容",
            cardFlowState: .visible,
            collectionID: nil,
            createdAt: .now,
            updatedAt: .now,
            resourceIDs: []
        )
        XCTAssertEqual(
            V02CardPreviewLayoutPolicy.pageHeight(for: 640),
            640
        )
        XCTAssertEqual(
            V02CardPreviewLayoutPolicy.pageHeight(for: 480),
            V02CardPreviewLayoutPolicy.compactHeight
        )
        XCTAssertEqual(
            V02CardPreviewLayoutPolicy.previewPageHeight(for: 640, entry: .inspiration(fixture)),
            V02CardPreviewLayoutPolicy.compactHeight
        )
        XCTAssertEqual(
            V02CardPreviewLayoutPolicy.previewPageHeight(for: 480, entry: .inspiration(fixture)),
            V02CardPreviewLayoutPolicy.compactHeight
        )
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

    func testV03CardGestureBoundariesResistOrCancelWithoutMutation() {
        XCTAssertEqual(
            V02CardDeckPolicy.displayedVerticalTranslation(index: 0, count: 2, translation: 100),
            24,
            accuracy: 0.001
        )
        XCTAssertEqual(
            V02CardDeckPolicy.displayedVerticalTranslation(index: 1, count: 2, translation: -100),
            -24,
            accuracy: 0.001
        )
        XCTAssertEqual(
            V02CardDeckPolicy.displayedVerticalTranslation(index: 0, count: 2, translation: -100),
            -100,
            accuracy: 0.001
        )
    }

    func testV02CollectionPresentationCoversEmptyAndActiveStates() {
        XCTAssertTrue(V02CollectionOperationPolicy.showsEmptyState(activeCollectionCount: 0))
        XCTAssertFalse(V02CollectionOperationPolicy.showsEmptyState(activeCollectionCount: 1))
        XCTAssertFalse(V02CollectionOperationPolicy.showsEmptyState(activeCollectionCount: 6))
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

    func testV02CollectionNameCounterAllowsAtLeastSixActiveCollections() throws {
        var state = V02DomainState()
        let collections = try (0 ..< 6).map { _ in
            try V02DomainEngine.createCollection(in: &state)
        }
        XCTAssertEqual(collections.map(\.name), [
            "构思集（1）", "构思集（2）", "构思集（3）", "构思集（4）", "构思集（5）", "构思集（6）"
        ])
        for collection in collections {
            _ = try V02DomainEngine.startRound(
                collectionID: collection.id,
                in: &state
            )
        }
        XCTAssertEqual(state.collections.count, 6)
        XCTAssertEqual(state.collections.filter { $0.currentRoundID != nil }.count, 6)
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

    func testV02CorruptedDatabaseEntersReadOnlyModeWithoutOverwritingFile() throws {
        let v02Directory = directory.appendingPathComponent("v02-corrupted")
        try FileManager.default.createDirectory(
            at: v02Directory,
            withIntermediateDirectories: true
        )
        let databaseURL = v02Directory.appendingPathComponent("note1-v02-data.json")
        let corruptedData = Data("not-json".utf8)
        try corruptedData.write(to: databaseURL)

        let store = V02Store(storageDirectory: v02Directory)

        XCTAssertTrue(store.isReadOnly)
        XCTAssertNotNil(store.lastError)
        XCTAssertThrowsError(try store.createInspiration(text: "不能覆盖原文件")) {
            guard case StoreError.persistenceUnavailable = $0 else {
                return XCTFail("Expected persistenceUnavailable, got \($0)")
            }
        }
        XCTAssertEqual(try Data(contentsOf: databaseURL), corruptedData)
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

    func testV04EffectiveEditCountsOneChangedSessionInsteadOfAutosaves() throws {
        let store = V02Store(storageDirectory: directory.appendingPathComponent("effective-edit-session"))
        let base = Date(timeIntervalSince1970: 1_720_000_000)
        let inspiration = try store.createInspiration(text: "初稿", now: base)
        let collection = try store.createCollectionAndRound(name: "编辑计数")
        try store.assign(inspiration.id, to: collection.id)

        try store.updateInspiration(
            inspiration.id,
            text: "自动保存一",
            recordsEffectiveEdit: false
        )
        try store.updateInspiration(
            inspiration.id,
            text: "自动保存二",
            recordsEffectiveEdit: false
        )
        try store.finishInspirationEditSession(
            inspiration.id,
            originalText: "初稿",
            finalText: "最终稿",
            now: base.addingTimeInterval(60)
        )

        let roundID = try XCTUnwrap(store.activeCollections.first?.currentRoundID)
        var round = try XCTUnwrap(store.state.rounds.first(where: { $0.id == roundID }))
        XCTAssertEqual(round.effectiveEditCount, 1)
        XCTAssertEqual(round.events.count(where: { $0.kind == .inspirationEdited }), 1)
        XCTAssertEqual(
            store.state.inspirations.first(where: { $0.id == inspiration.id })?.updatedAt,
            base.addingTimeInterval(60)
        )

        try store.finishInspirationEditSession(
            inspiration.id,
            originalText: "最终稿",
            finalText: "最终稿",
            now: base.addingTimeInterval(120)
        )
        round = try XCTUnwrap(store.state.rounds.first(where: { $0.id == roundID }))
        XCTAssertEqual(round.effectiveEditCount, 1)
        XCTAssertEqual(round.events.count(where: { $0.kind == .inspirationEdited }), 1)
        XCTAssertEqual(
            store.state.inspirations.first(where: { $0.id == inspiration.id })?.updatedAt,
            base.addingTimeInterval(60)
        )

        XCTAssertThrowsError(
            try store.finishInspirationEditSession(
                inspiration.id,
                originalText: "最终稿",
                finalText: "   "
            )
        )
        XCTAssertEqual(store.state.inspirations.first?.text, "最终稿")
        XCTAssertEqual(
            store.state.rounds.first(where: { $0.id == roundID })?.effectiveEditCount,
            1
        )

        let receipt = try store.endRound(roundID)
        XCTAssertEqual(receipt.snapshot.effectiveEditCount, 1)
        XCTAssertEqual(receipt.snapshot.members.first?.text, "最终稿")
    }

    func testV04UnchangedFinishedEditSessionDoesNotWriteAnyDomainOrDatabaseState() throws {
        let storageDirectory = directory.appendingPathComponent("unchanged-edit-session")
        let store = V02Store(storageDirectory: storageDirectory)
        let base = Date(timeIntervalSince1970: 1_720_100_000)
        let inspiration = try store.createInspiration(text: "未修改正文", now: base)
        let collection = try store.createCollectionAndRound(name: "无变化会话", now: base)
        try store.assign(inspiration.id, to: collection.id)

        let databaseURL = storageDirectory.appendingPathComponent("note1-v02-data.json")
        let sentinelModificationDate = Date(timeIntervalSince1970: 1_600_000_000)
        try FileManager.default.setAttributes(
            [.modificationDate: sentinelModificationDate],
            ofItemAtPath: databaseURL.path
        )
        let before = try stableDomainSnapshot(store.state)
        let beforeUpdatedAt = try XCTUnwrap(
            store.state.inspirations.first(where: { $0.id == inspiration.id })?.updatedAt
        )
        let beforeRound = try XCTUnwrap(store.state.rounds.first(where: { $0.collectionID == collection.id }))

        try store.finishInspirationEditSession(
            inspiration.id,
            originalText: "未修改正文",
            finalText: "未修改正文",
            now: base.addingTimeInterval(3_600)
        )

        XCTAssertEqual(try stableDomainSnapshot(store.state), before)
        XCTAssertEqual(
            store.state.inspirations.first(where: { $0.id == inspiration.id })?.updatedAt,
            beforeUpdatedAt
        )
        let afterRound = try XCTUnwrap(store.state.rounds.first(where: { $0.id == beforeRound.id }))
        XCTAssertEqual(afterRound.events.count, beforeRound.events.count)
        XCTAssertEqual(afterRound.effectiveEditCount, beforeRound.effectiveEditCount)
        let attributes = try FileManager.default.attributesOfItem(atPath: databaseURL.path)
        XCTAssertEqual(attributes[.modificationDate] as? Date, sentinelModificationDate)
    }

    func testV04OpeningAndCancellingEndConfirmationPreservesSnapshotAndAccessibilitySurfaces() throws {
        let store = V02Store(storageDirectory: directory.appendingPathComponent("confirmation-cancel"))
        let base = Date(timeIntervalSince1970: 1_720_200_000)
        let inspiration = try store.createInspiration(text: "只打开确认", now: base)
        let collection = try store.createCollectionAndRound(name: "取消无副作用", now: base)
        try store.assign(inspiration.id, to: collection.id)
        let before = try stableDomainSnapshot(store.state)
        let beforeUpdatedAt = try XCTUnwrap(
            store.state.inspirations.first(where: { $0.id == inspiration.id })?.updatedAt
        )

        var isConfirmationPresented = true
        XCTAssertTrue(V04EndRoundAccessibilityPolicy.hidesWorkbench(isPresented: isConfirmationPresented))
        XCTAssertTrue(V04EndRoundAccessibilityPolicy.showsConfirmation(isPresented: isConfirmationPresented))
        try store.finishInspirationEditSession(
            inspiration.id,
            originalText: "只打开确认",
            finalText: "只打开确认",
            now: base.addingTimeInterval(7_200)
        )
        isConfirmationPresented = false

        XCTAssertFalse(V04EndRoundAccessibilityPolicy.hidesWorkbench(isPresented: isConfirmationPresented))
        XCTAssertFalse(V04EndRoundAccessibilityPolicy.showsConfirmation(isPresented: isConfirmationPresented))
        XCTAssertEqual(try stableDomainSnapshot(store.state), before)
        XCTAssertEqual(
            store.state.inspirations.first(where: { $0.id == inspiration.id })?.updatedAt,
            beforeUpdatedAt
        )
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
        XCTAssertTrue(V02ReceiptGesturePolicy.canStartExtraction(at: CGPoint(x: 120, y: 24)))
        XCTAssertFalse(V02ReceiptGesturePolicy.canStartExtraction(at: CGPoint(x: 120, y: 24.1)))
        XCTAssertFalse(V02ReceiptGesturePolicy.canStartExtraction(at: CGPoint(x: 120, y: 420)))
    }

    func testV03ReceiptGestureBoundariesResistAndNeverLoop() {
        XCTAssertNil(V02ReceiptGesturePolicy.horizontalTarget(index: 0, count: 3, translation: 71.9))
        XCTAssertNil(V02ReceiptGesturePolicy.horizontalTarget(index: 1, count: 3, translation: -71.9))
        XCTAssertEqual(V02ReceiptGesturePolicy.horizontalTarget(index: 1, count: 3, translation: -72), 2)
        XCTAssertEqual(
            V02ReceiptGesturePolicy.horizontalTarget(
                index: 1,
                count: 3,
                translation: -40,
                predictedEndTranslation: -120
            ),
            2
        )
        XCTAssertNil(V02ReceiptGesturePolicy.horizontalTarget(index: 0, count: 3, translation: 180))
        XCTAssertNil(V02ReceiptGesturePolicy.horizontalTarget(index: 2, count: 3, translation: -180))
        XCTAssertEqual(
            V02ReceiptGesturePolicy.displayedHorizontalTranslation(index: 0, count: 3, translation: 100),
            24,
            accuracy: 0.001
        )
        XCTAssertEqual(
            V02ReceiptGesturePolicy.displayedHorizontalTranslation(index: 2, count: 3, translation: -100),
            -24,
            accuracy: 0.001
        )
        XCTAssertEqual(
            V02ReceiptGesturePolicy.displayedHorizontalTranslation(index: 1, count: 3, translation: -100),
            -100,
            accuracy: 0.001
        )
        XCTAssertFalse(V02ReceiptGesturePolicy.shouldExtract(95.9))
        XCTAssertTrue(V02ReceiptGesturePolicy.shouldExtract(96))
        XCTAssertTrue(V02ReceiptGesturePolicy.shouldExtract(70, predictedEndTranslation: 140))
    }

    func testV03ReceiptLayoutExpandsForContentAndDynamicType() {
        let short = V02ReceiptLayoutPolicy.estimatedPaperHeight(
            memberCount: 1,
            textLineCount: 1,
            hasAttachments: false,
            hasPhotoStrip: false,
            textScale: 1
        )
        XCTAssertGreaterThanOrEqual(short, V02ReceiptLayoutPolicy.minimumPaperHeight)
        XCTAssertEqual(short, 468)
        XCTAssertLessThanOrEqual(short, 480)

        let longDefault = V02ReceiptLayoutPolicy.estimatedPaperHeight(
            memberCount: 4,
            textLineCount: 8,
            hasAttachments: true,
            hasPhotoStrip: true,
            textScale: 1
        )
        let longAccessible = V02ReceiptLayoutPolicy.estimatedPaperHeight(
            memberCount: 4,
            textLineCount: 8,
            hasAttachments: true,
            hasPhotoStrip: true,
            textScale: 1.8
        )
        XCTAssertGreaterThan(longDefault, short)
        XCTAssertGreaterThan(longAccessible, longDefault)
        XCTAssertGreaterThanOrEqual(V02ReceiptTypographyPolicy.sequenceMarkerWidth, 24)
        XCTAssertLessThanOrEqual(V02ReceiptTypographyPolicy.sequenceMarkerMaximumScale, 1.5)
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
        XCTAssertEqual(V02ReceiptGenerationPolicy.outletRevealDuration, 1.4, accuracy: 0.001)
        XCTAssertEqual(V02ReceiptGenerationPolicy.revealPause, 0.08, accuracy: 0.001)
        XCTAssertEqual(V02ReceiptGenerationPolicy.liftDuration, 0.42, accuracy: 0.001)
        XCTAssertEqual(V02ReceiptGenerationPolicy.reducedMotionDuration, 0.2, accuracy: 0.001)
        XCTAssertLessThanOrEqual(V02ReceiptGenerationPolicy.reducedMotionDisplacement, 8)
        XCTAssertEqual(V02ReceiptGenerationPolicy.initialPaperScale, 0.84, accuracy: 0.001)
        XCTAssertEqual(V02ReceiptGenerationPolicy.settledPaperScale, 1, accuracy: 0.001)
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
        let attachmentID = UUID()
        let receipt = V02Receipt(
            id: UUID(), roundID: UUID(), collectionID: UUID(), createdAt: now,
            snapshot: .init(collectionName: "分享测试", startedAt: now, endedAt: now, effectiveEditCount: 0,
                            members: [.init(
                                inspirationID: UUID(),
                                text: "可导出内容",
                                resourceIDs: [attachmentID],
                                attachments: [.init(
                                    id: attachmentID,
                                    filename: "现场参考.txt",
                                    mimeType: "text/plain",
                                    relativePath: "现场参考.txt",
                                    size: 12,
                                    createdAt: now
                                )]
                            )])
        )
        let pdfURL = try V02ReceiptExportFile.write(receipt, format: .pdf)
        let markdownURL = try V02ReceiptExportFile.write(receipt, format: .markdown)
        let textURL = try V02ReceiptExportFile.write(receipt, format: .plainText)
        defer {
            try? FileManager.default.removeItem(at: pdfURL)
            try? FileManager.default.removeItem(at: markdownURL)
            try? FileManager.default.removeItem(at: textURL)
        }

        XCTAssertTrue(try Data(contentsOf: pdfURL).starts(with: Data("%PDF".utf8)))
        let markdown = try String(contentsOf: markdownURL)
        let plainText = try String(contentsOf: textURL)
        XCTAssertEqual(pdfURL.pathExtension, "pdf")
        XCTAssertEqual(markdownURL.pathExtension, "md")
        XCTAssertEqual(textURL.pathExtension, "txt")
        XCTAssertTrue(markdown.contains("# 分享测试"))
        XCTAssertTrue(markdown.contains("现场参考.txt"))
        XCTAssertTrue(markdown.contains("text/plain"))
        XCTAssertTrue(plainText.contains("分享测试"))
        XCTAssertTrue(plainText.contains("现场参考.txt"))
        XCTAssertTrue(plainText.contains("text/plain"))
    }

    func testV03ReceiptExportLabelsLegacyAttachmentReferencesAccurately() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let receipt = V02Receipt(
            id: UUID(), roundID: UUID(), collectionID: UUID(), createdAt: now,
            snapshot: .init(
                collectionName: "旧小票",
                startedAt: now,
                endedAt: now,
                effectiveEditCount: 0,
                members: [.init(
                    inspirationID: UUID(),
                    text: "仍有附件引用",
                    resourceIDs: [UUID(), UUID()],
                    attachments: []
                )]
            )
        )

        XCTAssertTrue(V02ReceiptExport.plainText(for: receipt).contains("附件：2 个（旧小票未保留附件元数据）"))
        XCTAssertTrue(V02ReceiptExport.markdown(for: receipt).contains("附件：2 个（旧小票未保留附件元数据）"))
        let pdfText = try XCTUnwrap(PDFDocument(data: V02ReceiptExport.pdfData(for: receipt))?.string)
        let compactPDFText = pdfText.components(separatedBy: .whitespacesAndNewlines).joined()
        XCTAssertTrue(compactPDFText.contains("附件：2个（旧小票未保留附件元数据）"))
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

    func testV02AssignMovesOneCardAtomicallyBetweenCollections() throws {
        let store = V02Store(storageDirectory: directory.appendingPathComponent("atomic-move"))
        let source = try store.createCollectionAndRound(name: "来源构思集")
        let target = try store.createCollectionAndRound(name: "目标构思集")
        let inspiration = try store.createInspiration(text: "待移动灵感")
        try store.assign(inspiration.id, to: source.id)

        try store.assign(inspiration.id, to: target.id)

        let sourceRoundID = try XCTUnwrap(store.state.collections.first(where: { $0.id == source.id })?.currentRoundID)
        let targetRoundID = try XCTUnwrap(store.state.collections.first(where: { $0.id == target.id })?.currentRoundID)
        let sourceRound = try XCTUnwrap(store.state.rounds.first(where: { $0.id == sourceRoundID }))
        let targetRound = try XCTUnwrap(store.state.rounds.first(where: { $0.id == targetRoundID }))
        XCTAssertFalse(sourceRound.memberIDs.contains(inspiration.id))
        XCTAssertEqual(targetRound.memberIDs, [inspiration.id])
        XCTAssertEqual(store.state.inspirations.first(where: { $0.id == inspiration.id })?.collectionID, target.id)

        XCTAssertEqual(
            sourceRound.events.filter { $0.inspirationID == inspiration.id }.map(\.kind),
            [.memberAdded, .memberRemoved]
        )
        XCTAssertEqual(
            targetRound.events.filter { $0.inspirationID == inspiration.id }.map(\.kind),
            [.memberAdded]
        )
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

    func testV02UndoEndRoundAllowsRestoringAlongsideSixActiveCollections() throws {
        let store = V02Store(storageDirectory: directory.appendingPathComponent("undo-collection-unbounded"))
        let inspiration = try store.createInspiration(text: "撤回后恢复的灵感")
        let original = try store.createCollectionAndRound(name: "已结束构思集")
        try store.assign(inspiration.id, to: original.id)
        let originalRoundID = try XCTUnwrap(store.state.collections.first(where: { $0.id == original.id })?.currentRoundID)
        let receipt = try store.endRound(originalRoundID)
        for index in 0..<6 {
            _ = try store.createCollectionAndRound(name: "活动构思集 \(index + 1)")
        }

        XCTAssertNoThrow(try store.undoEndRound(receipt.id))
        XCTAssertTrue(store.state.receipts.isEmpty)
        XCTAssertEqual(store.activeCollections.count, 7)
        XCTAssertEqual(store.state.inspirations.first?.collectionID, original.id)
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

    func testV02CreateInspirationInCollectionAllowsAtLeastElevenMembers() throws {
        let store = V02Store(storageDirectory: directory.appendingPathComponent("create-in-collection"))
        let collection = try store.createCollectionAndRound()
        for index in 0..<11 {
            _ = try store.createInspiration(text: "成员 \(index)", in: collection.id)
        }

        let roundID = try XCTUnwrap(store.state.collections.first(where: { $0.id == collection.id })?.currentRoundID)
        let round = try XCTUnwrap(store.state.rounds.first(where: { $0.id == roundID }))
        XCTAssertEqual(round.memberIDs.count, 11)
        XCTAssertEqual(store.state.inspirations.count, 11)
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

    func testV02CardPreviewShowsOnlyIndependentInspirations() throws {
        let store = V02Store(storageDirectory: directory.appendingPathComponent("card-preview"))
        let independent = try store.createInspiration(text: "独立卡片")
        let grouped = try store.createInspiration(text: "组内卡片")
        let collection = try store.createCollectionAndRound()
        try store.assign(grouped.id, to: collection.id)

        XCTAssertEqual(store.cardPreviewEntries.count, 1)
        XCTAssertEqual(store.cardPreviewEntries.first?.id, independent.id)
        XCTAssertFalse(store.cardPreviewEntries.contains { $0.id == grouped.id })
    }

    func testV02TuckAndReturnRoundTripsCardPreviewEntry() throws {
        let v02Directory = directory.appendingPathComponent("card-preview-return")
        let store = V02Store(storageDirectory: v02Directory)
        let inspiration = try store.createInspiration(text: "可撤回卡片")

        try store.tuckAway(inspiration.id)
        XCTAssertTrue(store.cardPreviewEntries.isEmpty)

        try store.returnToCardFlow(inspiration.id)
        XCTAssertEqual(store.cardPreviewEntries.map(\.id), [inspiration.id])

        let reloaded = V02Store(storageDirectory: v02Directory)
        XCTAssertEqual(reloaded.cardPreviewEntries.map(\.id), [inspiration.id])
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

    func testV04PrimaryNavigationUsesFourFullWidthCellsAndEveryPageAddsInspiration() {
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
        XCTAssertTrue(V02NavigationLayoutPolicy.showsFloatingComposer(on: .cards, isOverlayPresented: false))
        XCTAssertTrue(V02NavigationLayoutPolicy.showsFloatingComposer(on: .collections, isOverlayPresented: false))
        XCTAssertTrue(V02NavigationLayoutPolicy.showsFloatingComposer(on: .receipts, isOverlayPresented: false))
        XCTAssertFalse(V02NavigationLayoutPolicy.showsFloatingComposer(on: .cards, isOverlayPresented: true))
        for page in V02PrimaryPage.allCases {
            XCTAssertEqual(V02NavigationLayoutPolicy.composerLabel(for: page), "新增灵感")
        }
    }

    func testV03PageHeadersShareOneGeometryAndPrimaryBrandTitle() {
        XCTAssertEqual(V02PrimaryHeaderPolicy.title, "NOTE1")
        XCTAssertEqual(V02PrimaryHeaderPolicy.titleWidth, 120)
        XCTAssertEqual(V02PrimaryHeaderPolicy.titleTracking, 5)
        XCTAssertEqual(V02PrimaryHeaderPolicy.actionSpacing, 4)
        XCTAssertEqual(V02NavigationLayoutPolicy.pageHeaderHeight, NoteTheme.controlSize + 8)
        XCTAssertEqual(NoteTheme.topBarHeight, 56)
        XCTAssertEqual(NoteTheme.controlSize, 48)
        XCTAssertEqual(NoteTheme.controlVisualSize, 46)
    }

    func testV03PrimaryContentSharesOneCanvasGrid() {
        XCTAssertEqual(V02PrimaryContentLayoutPolicy.horizontalInset, 22)
        XCTAssertEqual(V02PrimaryContentLayoutPolicy.topSpacing, 8)
        XCTAssertEqual(V02PrimaryContentLayoutPolicy.stackedPaperBackOffset, 9)
        XCTAssertEqual(V02PrimaryContentLayoutPolicy.stackedPaperMiddleOffset, 5)
    }

    func testV03PrimaryContextTypographyRemainsReadableAndBounded() {
        XCTAssertGreaterThanOrEqual(V02PrimaryTypographyPolicy.contextLabelSize, 14)
        XCTAssertGreaterThanOrEqual(V02PrimaryTypographyPolicy.contextLabelMaximumScale, 1)
        XCTAssertLessThanOrEqual(V02PrimaryTypographyPolicy.contextLabelMaximumScale, 1.5)
    }

    func testV03GlassSurfacesUseOpaqueAccessibleFallback() {
        XCTAssertFalse(V02GlassSurfacePolicy.usesOpaqueSurface(reduceTransparency: false))
        XCTAssertTrue(V02GlassSurfacePolicy.usesOpaqueSurface(reduceTransparency: true))
        XCTAssertGreaterThanOrEqual(V02GlassSurfacePolicy.reducedTransparencyBorderOpacity, 0.50)
        XCTAssertGreaterThan(V02GlassSurfacePolicy.reducedTransparencyShadowOpacity, 0)
    }

    func testV02AppSheetUsesStableMutuallyExclusiveIdentities() {
        func makeReceipt(collectionName: String) -> V02Receipt {
            V02Receipt(
                id: UUID(),
                roundID: UUID(),
                collectionID: UUID(),
                createdAt: .now,
                snapshot: V02ReceiptSnapshot(
                    collectionName: collectionName,
                    startedAt: .now,
                    endedAt: .now,
                    effectiveEditCount: 0,
                    members: []
                )
            )
        }

        let firstReceipt = makeReceipt(collectionName: "第一张")
        let secondReceipt = makeReceipt(collectionName: "第二张")
        let identities = [
            V02AppSheet.composer.id,
            V02AppSheet.settings.id,
            V02AppSheet.trash.id,
            V02AppSheet.search.id,
            V02AppSheet.history.id,
            V02AppSheet.receipt(firstReceipt).id,
            V02AppSheet.receipt(secondReceipt).id
        ]

        XCTAssertEqual(Set(identities).count, identities.count)
        XCTAssertEqual(V02AppSheet.composer.id, "composer")
        XCTAssertTrue(V02AppSheet.receipt(firstReceipt).id.hasSuffix(firstReceipt.id.uuidString))
    }

    func testV02SearchScopeOrderMatchesPrimarySearchCopy() {
        XCTAssertEqual(V02SearchScope.allCases, [.all, .inspirations, .collections, .receipts])
        XCTAssertEqual(V02SearchScope.allCases.map(\.title), ["全部", "灵感", "构思集", "小票"])
    }

    func testV03HistoryCenterUsesOneGlobalScopeOrderAndReverseChronology() {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let collectionID = UUID()
        let tucked = V02Inspiration(
            id: UUID(),
            text: "已收起的独立灵感",
            cardFlowState: .tuckedAway,
            collectionID: nil,
            createdAt: base,
            updatedAt: base.addingTimeInterval(10),
            resourceIDs: []
        )
        let tuckedCollectionMember = V02Inspiration(
            id: UUID(),
            text: "构思集成员不重复进入已收起",
            cardFlowState: .tuckedAway,
            collectionID: collectionID,
            createdAt: base,
            updatedAt: base.addingTimeInterval(40),
            resourceIDs: []
        )
        let visible = V02Inspiration(
            id: UUID(),
            text: "仍在卡片流",
            cardFlowState: .visible,
            collectionID: nil,
            createdAt: base,
            updatedAt: base.addingTimeInterval(50),
            resourceIDs: []
        )
        let collection = V02ThinkingCollection(
            id: collectionID,
            name: "历史测试",
            createdAt: base,
            currentRoundID: nil
        )
        let endedRound = V02ThinkingRound(
            id: UUID(),
            collectionID: collectionID,
            state: .ended,
            startedAt: base,
            endedAt: base.addingTimeInterval(20),
            memberIDs: [tuckedCollectionMember.id],
            effectiveEditCount: 0,
            roundNumber: 1
        )
        let activeRound = V02ThinkingRound(
            id: UUID(),
            collectionID: collectionID,
            state: .thinking,
            startedAt: base.addingTimeInterval(60),
            endedAt: nil,
            memberIDs: [],
            effectiveEditCount: 0,
            roundNumber: 2
        )
        let receipt = V02Receipt(
            id: UUID(),
            roundID: endedRound.id,
            collectionID: collectionID,
            createdAt: base.addingTimeInterval(30),
            snapshot: .init(
                collectionName: collection.name,
                startedAt: base,
                endedAt: base.addingTimeInterval(20),
                effectiveEditCount: 0,
                members: [],
                roundNumber: 1
            )
        )

        var state = V02DomainState()
        state.inspirations = [tucked, tuckedCollectionMember, visible]
        state.collections = [collection]
        state.rounds = [endedRound, activeRound]
        state.receipts = [receipt]

        XCTAssertEqual(
            V02HistoryScope.allCases.map(\.title),
            ["全部", "已收起", "构思历程", "小票"]
        )
        XCTAssertEqual(
            V02HistoryCenterPolicy.entries(state: state).map(\.id),
            ["receipt.\(receipt.id.uuidString)", "round.\(endedRound.id.uuidString)", "inspiration.\(tucked.id.uuidString)"]
        )
        XCTAssertEqual(
            V02HistoryCenterPolicy.entries(state: state, scope: .tuckedAway).map(\.id),
            ["inspiration.\(tucked.id.uuidString)"]
        )
        XCTAssertEqual(
            V02HistoryCenterPolicy.entries(state: state, scope: .thinkingHistory).map(\.id),
            ["round.\(endedRound.id.uuidString)"]
        )
        XCTAssertEqual(
            V02HistoryCenterPolicy.entries(state: state, scope: .receipts).map(\.id),
            ["receipt.\(receipt.id.uuidString)"]
        )
    }

    func testV03RoundNumberIsMonotonicAndIndependentFromEditCountOrReceiptDeletion() throws {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        var state = V02DomainState()
        let inspiration = V02Inspiration(
            id: UUID(),
            text: "轮次测试",
            cardFlowState: .visible,
            collectionID: nil,
            createdAt: base,
            updatedAt: base,
            resourceIDs: []
        )
        state.inspirations = [inspiration]
        let collection = try V02DomainEngine.createCollection(in: &state, now: base)
        let firstRound = try V02DomainEngine.startRound(collectionID: collection.id, in: &state, now: base)
        try V02DomainEngine.assign(
            inspirationID: inspiration.id,
            to: collection.id,
            in: &state,
            now: base
        )
        let firstReceipt = try V02DomainEngine.endRound(
            roundID: firstRound.id,
            in: &state,
            now: base.addingTimeInterval(10)
        )
        try V02DomainEngine.deleteReceipt(firstReceipt.id, in: &state, now: base.addingTimeInterval(11))

        let secondRound = try V02DomainEngine.continueRound(
            collectionID: collection.id,
            in: &state,
            now: base.addingTimeInterval(20)
        )
        let secondIndex = try XCTUnwrap(state.rounds.firstIndex { $0.id == secondRound.id })
        state.rounds[secondIndex].effectiveEditCount = 12
        let secondReceipt = try V02DomainEngine.endRound(
            roundID: secondRound.id,
            in: &state,
            now: base.addingTimeInterval(30)
        )
        try V02DomainEngine.deleteReceipt(secondReceipt.id, in: &state, now: base.addingTimeInterval(31))

        let thirdRound = try V02DomainEngine.continueRound(
            collectionID: collection.id,
            in: &state,
            now: base.addingTimeInterval(40)
        )

        XCTAssertEqual(firstReceipt.snapshot.roundNumber, 1)
        XCTAssertEqual(secondReceipt.snapshot.roundNumber, 2)
        XCTAssertEqual(secondReceipt.snapshot.effectiveEditCount, 12)
        XCTAssertEqual(secondReceipt.statistics.roundTitle, "第 2 轮构思")
        XCTAssertEqual(thirdRound.roundNumber, 3)
        XCTAssertEqual(state.collections.first?.nextRoundNumber, 4)
    }

    func testV03ReceiptStatisticsUseFrozenTextAndAttachmentUnion() {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let firstAttachmentID = UUID()
        let secondAttachmentID = UUID()
        let snapshot = V02ReceiptSnapshot(
            collectionName: "统计测试",
            startedAt: base,
            endedAt: base.addingTimeInterval(90),
            effectiveEditCount: 4,
            members: [
                .init(
                    inspirationID: UUID(),
                    text: "你好",
                    resourceIDs: [firstAttachmentID],
                    attachments: [
                        .init(
                            id: firstAttachmentID,
                            filename: "one.jpg",
                            mimeType: "image/jpeg",
                            relativePath: "one.jpg",
                            size: 10,
                            createdAt: base
                        ),
                        .init(
                            id: secondAttachmentID,
                            filename: "two.pdf",
                            mimeType: "application/pdf",
                            relativePath: "two.pdf",
                            size: 20,
                            createdAt: base
                        )
                    ]
                ),
                .init(inspirationID: UUID(), text: "NOTE1", resourceIDs: [])
            ],
            roundNumber: 3
        )

        XCTAssertEqual(snapshot.statistics.roundNumber, 3)
        XCTAssertEqual(snapshot.statistics.inspirationCount, 2)
        XCTAssertEqual(snapshot.statistics.attachmentCount, 2)
        XCTAssertEqual(snapshot.statistics.finalTextCount, 7)
        XCTAssertEqual(snapshot.statistics.effectiveEditCount, 4)
        XCTAssertEqual(snapshot.statistics.duration, 90)
        XCTAssertTrue(snapshot.statistics.compactText.contains("第 3 轮构思"))
        XCTAssertTrue(snapshot.statistics.detailText.contains("最终文字数量：7 字"))
    }

    func testV03CoreOfflineJourneySurvivesRestartBackupAndRestore() throws {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let sourceDirectory = directory.appendingPathComponent("v03-core-journey-source")
        let restoredDirectory = directory.appendingPathComponent("v03-core-journey-restored")
        let source = V02Store(storageDirectory: sourceDirectory)
        let attachmentData = Data("NOTE1 attachment".utf8)
        let attachment = try source.createResource(
            input: AttachmentInput(
                name: "核心闭环.txt",
                mimeType: "text/plain",
                data: attachmentData
            ),
            source: .importedAttachment,
            now: base
        )
        let inspiration = try source.createInspiration(
            text: "第一轮原始灵感",
            resourceIDs: [attachment.id],
            now: base.addingTimeInterval(1)
        )

        try source.tuckAway(inspiration.id, now: base.addingTimeInterval(2))
        XCTAssertEqual(
            V02HistoryCenterPolicy.entries(state: source.state, scope: .tuckedAway).map(\.id),
            ["inspiration.\(inspiration.id.uuidString)"]
        )
        try source.returnToCardFlow(inspiration.id, now: base.addingTimeInterval(3))
        XCTAssertTrue(V02HistoryCenterPolicy.entries(state: source.state, scope: .tuckedAway).isEmpty)

        let collection = try source.createCollectionAndRoundAndAssign(
            inspirationID: inspiration.id,
            name: "完整功能闭环",
            now: base.addingTimeInterval(4)
        )
        XCTAssertTrue(source.cardPreviewEntries.isEmpty)
        try source.updateInspiration(
            inspiration.id,
            text: "第一轮已编辑",
            now: base.addingTimeInterval(5)
        )
        let firstRoundID = try XCTUnwrap(
            source.activeCollections.first(where: { $0.id == collection.id })?.currentRoundID
        )
        let firstReceipt = try source.endRound(firstRoundID, now: base.addingTimeInterval(6))

        let secondRound = try source.continueThinking(
            in: collection.id,
            now: base.addingTimeInterval(7)
        )
        try source.updateInspiration(
            inspiration.id,
            text: "第二轮结论",
            now: base.addingTimeInterval(8)
        )
        let secondReceipt = try source.endRound(secondRound.id, now: base.addingTimeInterval(9))

        XCTAssertEqual(firstReceipt.snapshot.members.map(\.text), ["第一轮已编辑"])
        XCTAssertEqual(secondReceipt.snapshot.members.map(\.text), ["第二轮结论"])
        XCTAssertEqual(firstReceipt.snapshot.roundNumber, 1)
        XCTAssertEqual(secondReceipt.snapshot.roundNumber, 2)
        XCTAssertEqual(secondReceipt.statistics.attachmentCount, 1)
        XCTAssertTrue(V02ReceiptExport.markdown(for: secondReceipt).contains("第 2 轮构思"))
        XCTAssertEqual(source.search("第一轮已编辑", scope: .receipts).count, 1)
        XCTAssertEqual(source.search("第二轮结论", scope: .receipts).count, 1)

        let trashIDs = try source.deleteInspiration(
            inspiration.id,
            now: base.addingTimeInterval(10)
        )
        XCTAssertEqual(trashIDs.count, 1)
        XCTAssertTrue(source.state.inspirations.isEmpty)
        XCTAssertEqual(source.state.receipts.count, 2)

        let backupData = try source.exportBackupData(now: base.addingTimeInterval(11))
        let target = V02Store(storageDirectory: restoredDirectory)
        try target.restoreBackupData(backupData)
        let reloaded = V02Store(storageDirectory: restoredDirectory)

        XCTAssertEqual(Set(reloaded.state.receipts.map { $0.snapshot.roundNumber }), Set([1, 2]))
        XCTAssertEqual(reloaded.state.trash.count, 1)
        let restoredAttachment = try XCTUnwrap(reloaded.state.resources.first { $0.id == attachment.id })
        XCTAssertEqual(try Data(contentsOf: reloaded.resourceURL(restoredAttachment)), attachmentData)
        XCTAssertEqual(
            V02HistoryCenterPolicy.entries(state: reloaded.state, scope: .receipts).count,
            2
        )

        let trashEntryID = try XCTUnwrap(reloaded.state.trash.first?.id)
        try reloaded.restoreTrash(trashEntryID, now: base.addingTimeInterval(12))
        let restoredInspiration = try XCTUnwrap(reloaded.state.inspirations.first)
        XCTAssertEqual(restoredInspiration.id, inspiration.id)
        XCTAssertEqual(restoredInspiration.text, "第二轮结论")
        XCTAssertNil(restoredInspiration.collectionID)
        XCTAssertEqual(reloaded.cardPreviewEntries.map(\.id), [inspiration.id])
    }

    func testV03LegacyOrphanReceiptsMigrateAcrossActiveAndTrashBuckets() throws {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let collectionID = UUID()
        func makeReceipt(offset: TimeInterval) -> V02Receipt {
            V02Receipt(
                id: UUID(),
                roundID: UUID(),
                collectionID: collectionID,
                createdAt: base.addingTimeInterval(offset + 5),
                snapshot: .init(
                    collectionName: "已删除构思集",
                    startedAt: base.addingTimeInterval(offset),
                    endedAt: base.addingTimeInterval(offset + 5),
                    effectiveEditCount: 0,
                    members: []
                )
            )
        }
        let earlierTrashReceipt = makeReceipt(offset: 10)
        let laterActiveReceipt = makeReceipt(offset: 20)
        var legacyState = V02DomainState()
        legacyState.receipts = [laterActiveReceipt]
        legacyState.trash = [
            V02TrashEntry(
                id: UUID(),
                object: .receipt(earlierTrashReceipt),
                deletedAt: base.addingTimeInterval(30)
            )
        ]

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let encoded = try encoder.encode(legacyState)
        let object = try JSONSerialization.jsonObject(with: encoded)
        func strippingRoundFields(from value: Any) -> Any {
            if let dictionary = value as? [String: Any] {
                return dictionary.reduce(into: [String: Any]()) { result, pair in
                    guard pair.key != "roundNumber", pair.key != "nextRoundNumber" else { return }
                    result[pair.key] = strippingRoundFields(from: pair.value)
                }
            }
            if let array = value as? [Any] {
                return array.map(strippingRoundFields(from:))
            }
            return value
        }
        let legacyData = try JSONSerialization.data(withJSONObject: strippingRoundFields(from: object))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let migrated = try decoder.decode(V02DomainState.self, from: legacyData)

        XCTAssertEqual(migrated.receipts.first?.snapshot.roundNumber, 2)
        guard let migratedTrashObject = migrated.trash.first?.object,
              case .receipt(let migratedTrashReceipt) = migratedTrashObject else {
            return XCTFail("回收站中的旧小票应保持可解码")
        }
        XCTAssertEqual(migratedTrashReceipt.snapshot.roundNumber, 1)
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

    func testV03UserFacingBackupCopyDoesNotExposeLegacyVersionLabels() {
        let copy = [
            V02BackupCopy.defaultFilename,
            V02BackupCopy.restoreConfirmation,
            V02BackupCopy.oversizedResource,
            V02BackupCopy.unsupportedVersion(99),
            V02BackupCopy.invalidArchive("无法读取文件内容。"),
            V02BackupError.unsupportedVersion(99).localizedDescription,
            V02BackupError.invalidArchive("无法读取文件内容。").localizedDescription
        ]

        XCTAssertEqual(V02BackupCopy.defaultFilename, "NOTE1-本机备份")
        for text in copy {
            XCTAssertFalse(text.contains("V0.2"))
            XCTAssertFalse(text.contains("当前版本"))
        }
    }

    func testV03InspirationBatchActionsUseStandardTerminology() {
        XCTAssertEqual(V02InspirationSelectionCopy.returnToCardFlow, "放回卡片流")
        XCTAssertEqual(V02InspirationSelectionCopy.assignToCollection, "归入构思集")
    }

    func testV03SecondaryTextContrastMeetsBodyTextFloor() {
        XCTAssertGreaterThanOrEqual(
            V02ColorContrastPolicy.minimumSecondaryTextContrast,
            4.5,
            "Secondary labels must remain readable on the darkest canvas stop."
        )
    }

    func testV04ReceiptExtractionUsesOnlyTopTwentyFourPointsAndFrozenThresholds() {
        XCTAssertEqual(V02ReceiptGesturePolicy.extractionHandleHeight, 24)
        XCTAssertTrue(V02ReceiptGesturePolicy.canStartExtraction(at: CGPoint(x: 120, y: 24)))
        XCTAssertFalse(V02ReceiptGesturePolicy.canStartExtraction(at: CGPoint(x: 120, y: 24.1)))
        XCTAssertFalse(V02ReceiptGesturePolicy.shouldExtract(95.9))
        XCTAssertTrue(V02ReceiptGesturePolicy.shouldExtract(96))
        XCTAssertTrue(V02ReceiptGesturePolicy.shouldExtract(70, predictedEndTranslation: 140))
    }

    func testV04ReceiptSwitchTransitionKeepsCurrentAndTargetConnectedToDrag() {
        let layout = V04ReceiptSwitchTransitionPolicy.layout(
            translation: -120,
            extent: 360,
            hasTarget: true,
            reduceMotion: false
        )

        XCTAssertEqual(layout.currentOffset, -120, accuracy: 0.001)
        XCTAssertEqual(layout.targetOffset, 240, accuracy: 0.001)
        XCTAssertLessThan(layout.currentScale, 1)
        XCTAssertLessThan(layout.targetScale, 1)
        XCTAssertGreaterThan(layout.targetScale, layout.currentScale)

        let reduced = V04ReceiptSwitchTransitionPolicy.layout(
            translation: -120,
            extent: 360,
            hasTarget: true,
            reduceMotion: true
        )
        XCTAssertLessThanOrEqual(abs(reduced.currentOffset), 16)
        XCTAssertLessThanOrEqual(abs(reduced.targetOffset), 16)
        XCTAssertEqual(reduced.currentScale, 1, accuracy: 0.001)
        XCTAssertEqual(reduced.targetScale, 1, accuracy: 0.001)
    }

    func testV04EndRoundConfirmationOwnsAccessibilityTreeOnlyWhilePresented() {
        XCTAssertFalse(V04EndRoundAccessibilityPolicy.hidesWorkbench(isPresented: false))
        XCTAssertTrue(V04EndRoundAccessibilityPolicy.hidesWorkbench(isPresented: true))
        XCTAssertTrue(V04EndRoundAccessibilityPolicy.showsConfirmation(isPresented: true))
        XCTAssertFalse(V04EndRoundAccessibilityPolicy.showsConfirmation(isPresented: false))
    }

    func testV04ReceiptTabUsesMiniatureReceiptSemanticSymbol() {
        XCTAssertEqual(V02PrimaryPage.receipts.symbol, "receipt")
        XCTAssertNotEqual(V02PrimaryPage.receipts.symbol, "ticket")
    }

    func testV04AssignmentUndoRestoresSameInspirationAndOriginalCollection() throws {
        let store = V02Store(storageDirectory: directory.appendingPathComponent("assignment-undo"))
        let original = try store.createCollectionAndRound(name: "原构思集")
        let target = try store.createCollectionAndRound(name: "目标构思集")
        let inspiration = try store.createInspiration(text: "保持同一对象")
        try store.assign(inspiration.id, to: original.id)

        let undo = try store.assignWithUndo(inspiration.id, to: target.id)
        XCTAssertEqual(undo.inspirationID, inspiration.id)
        XCTAssertEqual(undo.originalCollectionID, original.id)

        try store.undoAssignment(undo)
        XCTAssertEqual(store.state.inspirations.first(where: { $0.id == inspiration.id })?.id, inspiration.id)
        XCTAssertEqual(store.state.inspirations.first(where: { $0.id == inspiration.id })?.collectionID, original.id)

        let independent = try store.createInspiration(text: "原本未归入")
        let independentUndo = try store.assignWithUndo(independent.id, to: target.id)
        try store.undoAssignment(independentUndo)
        XCTAssertEqual(store.state.inspirations.first(where: { $0.id == independent.id })?.id, independent.id)
        XCTAssertNil(store.state.inspirations.first(where: { $0.id == independent.id })?.collectionID)

        let newTargetInspiration = try store.createInspiration(text: "新建目标后撤回")
        let collectionIDsBeforeCreate = Set(store.state.collections.map(\.id))
        let newTargetUndo = try store.createCollectionAndRoundAndAssignWithUndo(
            inspirationID: newTargetInspiration.id,
            name: "短时目标"
        )
        try store.undoAssignment(newTargetUndo)
        XCTAssertNil(store.state.inspirations.first(where: { $0.id == newTargetInspiration.id })?.collectionID)
        XCTAssertEqual(Set(store.state.collections.map(\.id)), collectionIDsBeforeCreate)
    }
}
