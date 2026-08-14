import Combine
import Foundation

enum V02SearchScope: CaseIterable, Hashable {
    case all, inspirations, collections, receipts

    var title: String {
        switch self {
        case .all: "全部"
        case .inspirations: "灵感"
        case .collections: "构思集"
        case .receipts: "小票"
        }
    }
}

enum V02SearchResult: Identifiable {
    case inspiration(V02Inspiration)
    case collection(V02ThinkingCollection)
    case receipt(V02Receipt)

    var id: UUID {
        switch self {
        case .inspiration(let item): item.id
        case .collection(let item): item.id
        case .receipt(let item): item.id
        }
    }
}

enum V02CardPreviewEntry: Identifiable {
    case inspiration(V02Inspiration)

    var id: UUID {
        switch self {
        case .inspiration(let inspiration): inspiration.id
        }
    }
}

enum StoreError: LocalizedError {
    case attachmentTooLarge(name: String)
    case emptyIdea
    case invalidOperation(String)
    case persistenceUnavailable
    case persistenceWriteFailed(String)

    var errorDescription: String? {
        switch self {
        case .attachmentTooLarge(let name):
            "附件「\(name)」超过 100 MB。"
        case .emptyIdea:
            "灵感需要包含文字或附件。"
        case .invalidOperation(let message):
            message
        case .persistenceUnavailable:
            "本机数据暂时无法读取。为保护原记录，NOTE1 已暂停写入。"
        case .persistenceWriteFailed(let message):
            "本机数据没有保存成功：\(message)"
        }
    }
}

@MainActor
final class V02Store: ObservableObject {
    @Published private(set) var state: V02DomainState
    @Published private(set) var lastError: String?
    @Published private(set) var isReadOnly = false

    private let fileManager: FileManager
    private let storageDirectory: URL
    private let databaseURL: URL
    private let resourcesDirectory: URL
    nonisolated static let maximumResourceSize = 100 * 1_024 * 1_024

    init(
        fileManager: FileManager = .default,
        storageDirectory: URL? = nil
    ) {
        self.fileManager = fileManager
        let applicationSupport = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? fileManager.temporaryDirectory
        let base = storageDirectory ?? applicationSupport
            .appendingPathComponent("NOTE1-V02", isDirectory: true)
        self.storageDirectory = base
        databaseURL = base.appendingPathComponent("note1-v02-data.json")
        resourcesDirectory = base.appendingPathComponent("Resources", isDirectory: true)
        state = V02DomainState()

        do {
            try fileManager.createDirectory(
                at: base,
                withIntermediateDirectories: true
            )
            try fileManager.createDirectory(
                at: resourcesDirectory,
                withIntermediateDirectories: true
            )
            try load()
        } catch {
            lastError = error.localizedDescription
            isReadOnly = true
        }
    }

    var visibleInspirations: [V02Inspiration] {
        state.inspirations
            .filter { $0.cardFlowState == .visible }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    var activeCollections: [V02ThinkingCollection] {
        state.collections.filter { $0.currentRoundID != nil }
    }

    var cardPreviewEntries: [V02CardPreviewEntry] {
        state.inspirations
            .filter { $0.collectionID == nil && $0.cardFlowState == .visible }
            .map(V02CardPreviewEntry.inspiration)
    }

    func search(
        _ rawQuery: String,
        scope: V02SearchScope = .all
    ) -> [V02SearchResult] {
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }
        var results: [V02SearchResult] = []
        if scope == .all || scope == .inspirations {
            results += state.inspirations.filter {
                $0.text.localizedStandardContains(query) || resourcesMatch($0.resourceIDs, query: query)
            }.map(V02SearchResult.inspiration)
        }
        if scope == .all || scope == .collections {
            results += state.collections.filter {
                $0.name.localizedStandardContains(query)
            }.map(V02SearchResult.collection)
        }
        if scope == .all || scope == .receipts {
            results += state.receipts.filter { receipt in
                receipt.snapshot.collectionName.localizedStandardContains(query) ||
                    receipt.snapshot.members.contains {
                        $0.text.localizedStandardContains(query) || resourcesMatch($0.resourceIDs, query: query)
                    }
            }.map(V02SearchResult.receipt)
        }
        return results
    }

    private func resourcesMatch(_ resourceIDs: [UUID], query: String) -> Bool {
        resourceIDs.contains { resourceID in
            state.resources.first(where: { $0.id == resourceID })?.filename.localizedStandardContains(query) == true
        }
    }

    func resourceURL(_ resource: V02AttachmentResource) -> URL {
        resourcesDirectory.appendingPathComponent(resource.relativePath)
    }

    /// Resolves a frozen receipt attachment without requiring the mutable
    /// resource metadata to still be present in the active store.
    func resourceURL(relativePath: String) -> URL {
        resourcesDirectory.appendingPathComponent(relativePath)
    }

    var temporaryVoiceDirectory: URL {
        storageDirectory.appendingPathComponent("TemporaryVoice", isDirectory: true)
    }

    func exportBackupData(now: Date = .now) throws -> Data {
        let backupState = stateWithOnlyReferencedResources(state)
        let resources = try backupState.resources.map { resource in
            let url = resourceURL(resource)
            guard fileManager.fileExists(atPath: url.path) else {
                throw V02BackupError.missingResource(resource.filename)
            }
            let data = try Data(contentsOf: url, options: [.mappedIfSafe])
            return V02BackupResource(metadata: resource, data: data)
        }
        return try V02BackupService.encode(
            V02BackupPayload(exportedAt: now, state: backupState, resources: resources)
        )
    }

    func validateBackupData(_ data: Data) throws {
        _ = try V02BackupService.decode(data)
    }

    func restoreBackupData(_ data: Data) throws {
        guard !isReadOnly else { throw StoreError.persistenceUnavailable }
        let payload = try V02BackupService.decode(data)
        try replaceLocalData(with: payload)
    }

    func persistVoiceRecording(at temporaryURL: URL) throws -> V02AttachmentResource {
        let data = try Data(contentsOf: temporaryURL, options: [.mappedIfSafe])
        let resource = try saveVoiceInspirationAudio(
            filename: temporaryURL.lastPathComponent,
            m4aData: data
        )
        try? fileManager.removeItem(at: temporaryURL)
        return resource
    }

    func discardUnreferencedResource(_ resourceID: UUID) throws {
        guard let resource = state.resources.first(where: { $0.id == resourceID }) else {
            throw V02DomainError.resourceNotFound
        }
        let usedByInspiration = state.inspirations.contains { $0.resourceIDs.contains(resourceID) }
        let usedByReceipt = state.receipts.contains { receipt in
            receipt.snapshot.members.contains { $0.resourceIDs.contains(resourceID) }
        }
        let usedByTrash = state.trash.contains { entry in
            switch entry.object {
            case .inspiration(let inspiration):
                inspiration.resourceIDs.contains(resourceID)
            case .receipt(let receipt):
                receipt.snapshot.members.contains { $0.resourceIDs.contains(resourceID) }
            }
        }
        guard !usedByInspiration && !usedByReceipt && !usedByTrash else {
            throw StoreError.invalidOperation("仍被灵感、构思小票或回收站引用的附件不能清理。")
        }
        try transact { state in state.resources.removeAll { $0.id == resourceID } }
        try? fileManager.removeItem(at: resourceURL(resource))
    }

    @discardableResult
    func createResource(
        input: AttachmentInput,
        source: V02ResourceSource,
        now: Date = .now
    ) throws -> V02AttachmentResource {
        guard input.data.count <= Self.maximumResourceSize else {
            throw StoreError.attachmentTooLarge(name: input.name)
        }
        let id = UUID()
        let extensionPart = URL(fileURLWithPath: input.name).pathExtension
        let relativePath = extensionPart.isEmpty ? id.uuidString : "\(id.uuidString).\(extensionPart)"
        let resource = V02AttachmentResource(
            id: id,
            source: source,
            filename: input.name,
            mimeType: input.mimeType,
            relativePath: relativePath,
            size: Int64(input.data.count),
            createdAt: now
        )
        let url = resourceURL(resource)
        try input.data.write(to: url, options: .atomic)
        do {
            try transact { state in state.resources.append(resource) }
        } catch {
            try? fileManager.removeItem(at: url)
            throw error
        }
        return resource
    }

    @discardableResult
    func saveVoiceInspirationAudio(
        filename: String,
        m4aData: Data,
        now: Date = .now
    ) throws -> V02AttachmentResource {
        guard filename.lowercased().hasSuffix(".m4a") else {
            throw StoreError.invalidOperation("语音灵感需保存为本机 M4A 录音。")
        }
        return try createResource(
            input: AttachmentInput(name: filename, mimeType: "audio/mp4", data: m4aData),
            source: .voiceInspiration,
            now: now
        )
    }

    func createInspiration(
        text: String,
        resourceIDs: [UUID] = [],
        now: Date = .now
    ) throws -> V02Inspiration {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !resourceIDs.isEmpty else {
            throw StoreError.emptyIdea
        }
        guard Set(resourceIDs).count == resourceIDs.count,
              resourceIDs.allSatisfy({ resourceID in state.resources.contains { $0.id == resourceID } }) else {
            throw V02DomainError.resourceNotFound
        }
        let inspiration = V02Inspiration(
            id: UUID(),
            text: text,
            cardFlowState: .visible,
            collectionID: nil,
            createdAt: now,
            updatedAt: now,
            resourceIDs: resourceIDs
        )
        try transact { state in
            state.inspirations.append(inspiration)
        }
        return inspiration
    }

    @discardableResult
    func createInspiration(
        text: String,
        resourceIDs: [UUID] = [],
        in collectionID: UUID,
        now: Date = .now
    ) throws -> V02Inspiration {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !resourceIDs.isEmpty else {
            throw StoreError.emptyIdea
        }
        let inspiration = V02Inspiration(
            id: UUID(), text: text, cardFlowState: .visible, collectionID: collectionID,
            createdAt: now, updatedAt: now, resourceIDs: resourceIDs
        )
        try transact { state in
            guard Set(resourceIDs).count == resourceIDs.count,
                  resourceIDs.allSatisfy({ resourceID in state.resources.contains { $0.id == resourceID } }) else {
                throw V02DomainError.resourceNotFound
            }
            guard let collection = state.collections.first(where: { $0.id == collectionID }) else {
                throw V02DomainError.collectionNotFound
            }
            guard let roundIndex = state.rounds.firstIndex(where: { $0.id == collection.currentRoundID && $0.state == .thinking }) else {
                throw V02DomainError.activeRoundRequired
            }
            state.inspirations.append(inspiration)
            state.rounds[roundIndex].memberIDs.append(inspiration.id)
            state.rounds[roundIndex].events.append(.init(id: UUID(), kind: .memberAdded, occurredAt: now, inspirationID: inspiration.id))
        }
        return inspiration
    }

    func updateInspiration(
        _ id: UUID,
        text: String,
        recordsEffectiveEdit: Bool = true,
        now: Date = .now
    ) throws {
        try transact { state in
            guard let index = state.inspirations.firstIndex(where: { $0.id == id }) else {
                throw V02DomainError.inspirationNotFound
            }
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !state.inspirations[index].resourceIDs.isEmpty else {
                throw StoreError.emptyIdea
            }
            if recordsEffectiveEdit,
               state.inspirations[index].text != text,
               let collectionID = state.inspirations[index].collectionID,
               let roundID = state.collections.first(where: { $0.id == collectionID })?.currentRoundID,
               let roundIndex = state.rounds.firstIndex(where: { $0.id == roundID }) {
                state.rounds[roundIndex].effectiveEditCount += 1
                state.rounds[roundIndex].events.append(.init(id: UUID(), kind: .inspirationEdited, occurredAt: now, inspirationID: id))
            }
            state.inspirations[index].text = text
            state.inspirations[index].updatedAt = now
        }
    }

    func finishInspirationEditSession(
        _ id: UUID,
        originalText: String,
        finalText: String,
        now: Date = .now
    ) throws {
        try transact { state in
            guard let index = state.inspirations.firstIndex(where: { $0.id == id }) else {
                throw V02DomainError.inspirationNotFound
            }
            guard !finalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || !state.inspirations[index].resourceIDs.isEmpty else {
                throw StoreError.emptyIdea
            }
            let changedDuringSession = originalText != finalText
            state.inspirations[index].text = finalText
            state.inspirations[index].updatedAt = now
            guard changedDuringSession,
                  let collectionID = state.inspirations[index].collectionID,
                  let roundID = state.collections.first(where: { $0.id == collectionID })?.currentRoundID,
                  let roundIndex = state.rounds.firstIndex(where: { $0.id == roundID }) else { return }
            state.rounds[roundIndex].effectiveEditCount += 1
            state.rounds[roundIndex].events.append(
                .init(id: UUID(), kind: .inspirationEdited, occurredAt: now, inspirationID: id)
            )
        }
    }

    func addImportedResources(
        _ inputs: [AttachmentInput],
        to inspirationID: UUID,
        now: Date = .now
    ) throws {
        guard !inputs.isEmpty else { return }
        var created: [V02AttachmentResource] = []
        do {
            for input in inputs {
                created.append(try createResource(input: input, source: .importedAttachment, now: now))
            }
            try transact { state in
                guard let index = state.inspirations.firstIndex(where: { $0.id == inspirationID }) else {
                    throw V02DomainError.inspirationNotFound
                }
                state.inspirations[index].resourceIDs.append(contentsOf: created.map(\.id))
                state.inspirations[index].updatedAt = now
            }
        } catch {
            for resource in created { try? discardUnreferencedResource(resource.id) }
            throw error
        }
    }

    func renameCollection(_ id: UUID, name: String) throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw StoreError.invalidOperation("构思集名称不能为空。") }
        try transact { state in
            guard let index = state.collections.firstIndex(where: { $0.id == id }) else {
                throw V02DomainError.collectionNotFound
            }
            state.collections[index].name = trimmed
        }
    }

    func tuckAway(_ id: UUID, now: Date = .now) throws {
        try transact { state in
            guard let index = state.inspirations.firstIndex(where: { $0.id == id }) else {
                throw V02DomainError.inspirationNotFound
            }
            state.inspirations[index].cardFlowState = .tuckedAway
            state.inspirations[index].updatedAt = now
        }
    }

    func returnToCardFlow(_ id: UUID, now: Date = .now) throws {
        try transact { state in
            guard let index = state.inspirations.firstIndex(where: { $0.id == id }) else {
                throw V02DomainError.inspirationNotFound
            }
            state.inspirations[index].cardFlowState = .visible
            state.inspirations[index].updatedAt = now
        }
    }

    func batchReturnToCardFlow(_ ids: Set<UUID>, now: Date = .now) throws {
        try transact { state in
            guard !ids.isEmpty,
                  ids.allSatisfy({ id in state.inspirations.contains { $0.id == id && $0.cardFlowState == .tuckedAway } }) else {
                throw V02DomainError.inspirationNotFound
            }
            for index in state.inspirations.indices where ids.contains(state.inspirations[index].id) {
                state.inspirations[index].cardFlowState = .visible
                state.inspirations[index].updatedAt = now
            }
        }
    }

    @discardableResult
    func createCollectionAndRound(
        name: String? = nil,
        now: Date = .now
    ) throws -> V02ThinkingCollection {
        var created: V02ThinkingCollection?
        try transact { state in
            let collection = try V02DomainEngine.createCollection(
                in: &state,
                name: name,
                now: now
            )
            _ = try V02DomainEngine.startRound(
                collectionID: collection.id,
                in: &state,
                now: now
            )
            created = collection
        }
        guard let created else {
            throw StoreError.invalidOperation("构思集创建未完成。")
        }
        return created
    }

    @discardableResult
    func createCollectionAndRoundAndAssign(
        inspirationID: UUID,
        name: String? = nil,
        now: Date = .now
    ) throws -> V02ThinkingCollection {
        var created: V02ThinkingCollection?
        try transact { state in
            let collection = try V02DomainEngine.createCollection(
                in: &state,
                name: name,
                now: now
            )
            _ = try V02DomainEngine.startRound(
                collectionID: collection.id,
                in: &state,
                now: now
            )
            try V02DomainEngine.assign(
                inspirationID: inspirationID,
                to: collection.id,
                in: &state,
                now: now
            )
            created = collection
        }
        guard let created else {
            throw StoreError.invalidOperation("构思集创建未完成。")
        }
        return created
    }

    func assign(_ inspirationID: UUID, to collectionID: UUID) throws {
        try transact { state in
            try V02DomainEngine.assign(
                inspirationID: inspirationID,
                to: collectionID,
                in: &state
            )
        }
    }

    func batchAssign(_ inspirationIDs: Set<UUID>, to collectionID: UUID) throws {
        try transact { state in
            guard !inspirationIDs.isEmpty,
                  let collection = state.collections.first(where: { $0.id == collectionID }),
                  let roundID = collection.currentRoundID,
                  state.rounds.contains(where: { $0.id == roundID && $0.state == .thinking }),
                  inspirationIDs.allSatisfy({ id in state.inspirations.contains { $0.id == id && ($0.collectionID == nil || $0.collectionID == collectionID) } }) else {
                throw V02DomainError.inspirationNotFound
            }
            for id in inspirationIDs {
                try V02DomainEngine.assign(inspirationID: id, to: collectionID, in: &state)
            }
        }
    }

    func removeFromCollection(_ inspirationID: UUID) throws {
        try transact { state in
            try V02DomainEngine.removeFromCollection(
                inspirationID: inspirationID,
                in: &state
            )
        }
    }

    func reorderMembers(_ memberIDs: [UUID], in roundID: UUID) throws {
        try transact { state in
            try V02DomainEngine.reorderMembers(
                memberIDs,
                in: roundID,
                state: &state
            )
        }
    }

    @discardableResult
    func continueThinking(
        in collectionID: UUID,
        now: Date = .now
    ) throws -> V02ThinkingRound {
        var round: V02ThinkingRound?
        try transact { state in
            round = try V02DomainEngine.continueRound(
                collectionID: collectionID,
                in: &state,
                now: now
            )
        }
        guard let round else {
            throw StoreError.invalidOperation("继续构思未完成。")
        }
        return round
    }

    @discardableResult
    func endRound(_ roundID: UUID, now: Date = .now) throws -> V02Receipt {
        var receipt: V02Receipt?
        try transact { state in
            receipt = try V02DomainEngine.endRound(
                roundID: roundID,
                in: &state,
                now: now
            )
        }
        guard let receipt else {
            throw StoreError.invalidOperation("构思小票生成未完成。")
        }
        return receipt
    }

    func undoEndRound(_ receiptID: UUID, now: Date = .now) throws {
        try transact { state in
            try V02DomainEngine.undoEndRound(receiptID: receiptID, in: &state, now: now)
        }
    }

    func purgeExpiredTrash(now: Date = .now) throws {
        var removedResources: [V02AttachmentResource] = []
        try transact { state in
            V02DomainEngine.purgeExpiredTrash(in: &state, now: now)
            removedResources = removeUnreferencedResources(from: &state)
        }
        removeResourceFiles(removedResources)
    }

    @discardableResult
    func deleteInspiration(_ id: UUID, now: Date = .now) throws -> Set<UUID> {
        try batchDeleteInspirations([id], now: now)
    }

    @discardableResult
    func batchDeleteInspirations(_ ids: Set<UUID>, now: Date = .now) throws -> Set<UUID> {
        var entryIDs = Set<UUID>()
        try transact { state in
            guard !ids.isEmpty,
                  ids.allSatisfy({ id in state.inspirations.contains { $0.id == id } }) else {
                throw V02DomainError.inspirationNotFound
            }
            let existingIDs = Set(state.trash.map(\.id))
            for id in ids { try V02DomainEngine.deleteInspiration(id, in: &state, now: now) }
            entryIDs = Set(state.trash.map(\.id)).subtracting(existingIDs)
        }
        return entryIDs
    }

    @discardableResult
    func deleteReceipt(_ id: UUID, now: Date = .now) throws -> Set<UUID> {
        try batchDeleteReceipts([id], now: now)
    }

    @discardableResult
    func batchDeleteReceipts(_ ids: Set<UUID>, now: Date = .now) throws -> Set<UUID> {
        var entryIDs = Set<UUID>()
        try transact { state in
            guard !ids.isEmpty,
                  ids.allSatisfy({ id in state.receipts.contains { $0.id == id } }) else {
                throw V02DomainError.roundNotFound
            }
            let existingIDs = Set(state.trash.map(\.id))
            for id in ids {
                try V02DomainEngine.deleteReceipt(id, in: &state, now: now)
            }
            entryIDs = Set(state.trash.map(\.id)).subtracting(existingIDs)
        }
        return entryIDs
    }

    func deleteCollection(_ id: UUID, now: Date = .now) throws {
        try transact { state in
            try V02DomainEngine.deleteCollection(id, in: &state, now: now)
        }
    }

    func restoreTrash(_ entryID: UUID, now: Date = .now) throws {
        try transact { state in
            try V02DomainEngine.restoreTrash(entryID, in: &state, now: now)
        }
    }

    func restoreTrash(_ entryIDs: Set<UUID>, now: Date = .now) throws {
        try transact { state in
            guard entryIDs.allSatisfy({ target in state.trash.contains(where: { $0.id == target }) }) else {
                throw V02DomainError.trashEntryNotFound
            }
            for entryID in entryIDs {
                try V02DomainEngine.restoreTrash(entryID, in: &state, now: now)
            }
        }
    }

    func permanentlyDeleteTrash(_ entryIDs: Set<UUID>) throws {
        var removedResources: [V02AttachmentResource] = []
        try transact { state in
            try V02DomainEngine.permanentlyDeleteTrash(entryIDs, in: &state)
            removedResources = removeUnreferencedResources(from: &state)
        }
        removeResourceFiles(removedResources)
    }

    func emptyTrash() throws {
        try permanentlyDeleteTrash(Set(state.trash.map(\.id)))
    }

    func removeResource(_ resourceID: UUID, from inspirationID: UUID, now: Date = .now) throws {
        var removedResources: [V02AttachmentResource] = []
        try transact { state in
            guard let inspirationIndex = state.inspirations.firstIndex(where: { $0.id == inspirationID }),
                  state.inspirations[inspirationIndex].resourceIDs.contains(resourceID) else {
                throw V02DomainError.resourceNotFound
            }
            guard state.inspirations[inspirationIndex].resourceIDs.count > 1 ||
                    !state.inspirations[inspirationIndex].text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw StoreError.emptyIdea
            }
            state.inspirations[inspirationIndex].resourceIDs.removeAll { $0 == resourceID }
            state.inspirations[inspirationIndex].updatedAt = now
            removedResources = removeUnreferencedResources(from: &state)
        }
        removeResourceFiles(removedResources)
    }

    private func load() throws {
        guard fileManager.fileExists(atPath: databaseURL.path) else { return }
        let data = try Data(contentsOf: databaseURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let loaded = try decoder.decode(V02DomainState.self, from: data)
        guard loaded.version == V02DomainState.currentVersion else {
            throw StoreError.invalidOperation("当前本机数据版本不兼容。")
        }
        state = loaded
    }

    private func transact(_ operation: (inout V02DomainState) throws -> Void) throws {
        guard !isReadOnly else { throw StoreError.persistenceUnavailable }
        var candidate = state
        try operation(&candidate)
        try persist(candidate)
        state = candidate
        lastError = nil
    }

    private func referencedResourceIDs(in state: V02DomainState) -> Set<UUID> {
        Set(
            state.inspirations.flatMap(\.resourceIDs) +
            state.receipts.flatMap { $0.snapshot.members.flatMap(\.resourceIDs) } +
            state.trash.flatMap { entry in
                switch entry.object {
                case .inspiration(let inspiration): inspiration.resourceIDs
                case .receipt(let receipt): receipt.snapshot.members.flatMap(\.resourceIDs)
                }
            }
        )
    }

    private func removeUnreferencedResources(from state: inout V02DomainState) -> [V02AttachmentResource] {
        let ids = referencedResourceIDs(in: state)
        let removed = state.resources.filter { !ids.contains($0.id) }
        state.resources.removeAll { !ids.contains($0.id) }
        return removed
    }

    private func removeResourceFiles(_ resources: [V02AttachmentResource]) {
        for resource in resources {
            try? fileManager.removeItem(at: resourceURL(resource))
        }
    }

    private func stateWithOnlyReferencedResources(_ state: V02DomainState) -> V02DomainState {
        var copy = state
        let ids = referencedResourceIDs(in: copy)
        copy.resources.removeAll { !ids.contains($0.id) }
        return copy
    }

    private func replaceLocalData(with payload: V02BackupPayload) throws {
        let operationID = UUID().uuidString
        let stagingDirectory = storageDirectory.appendingPathComponent("Restore-\(operationID)", isDirectory: true)
        let recoveryDirectory = storageDirectory.appendingPathComponent("Recovery-\(operationID)", isDirectory: true)
        let stagedDatabaseURL = stagingDirectory.appendingPathComponent(databaseURL.lastPathComponent)
        let stagedResourcesDirectory = stagingDirectory.appendingPathComponent("Resources", isDirectory: true)
        let recoveryDatabaseURL = recoveryDirectory.appendingPathComponent(databaseURL.lastPathComponent)
        let recoveryResourcesDirectory = recoveryDirectory.appendingPathComponent("Resources", isDirectory: true)
        var hadDatabase = false
        var hadResources = false
        do {
            try fileManager.createDirectory(at: stagedResourcesDirectory, withIntermediateDirectories: true)
            for resource in payload.resources {
                try resource.data.write(
                    to: stagedResourcesDirectory.appendingPathComponent(resource.metadata.relativePath),
                    options: .atomic
                )
            }
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(payload.state).write(to: stagedDatabaseURL, options: .atomic)

            try fileManager.createDirectory(at: recoveryDirectory, withIntermediateDirectories: true)
            hadDatabase = fileManager.fileExists(atPath: databaseURL.path)
            hadResources = fileManager.fileExists(atPath: resourcesDirectory.path)
            do {
                if hadDatabase { try fileManager.moveItem(at: databaseURL, to: recoveryDatabaseURL) }
                if hadResources { try fileManager.moveItem(at: resourcesDirectory, to: recoveryResourcesDirectory) }
            } catch {
                if hadDatabase,
                   !fileManager.fileExists(atPath: databaseURL.path),
                   fileManager.fileExists(atPath: recoveryDatabaseURL.path) {
                    try? fileManager.moveItem(at: recoveryDatabaseURL, to: databaseURL)
                }
                throw V02BackupError.restoreFailed(error.localizedDescription)
            }
            do {
                try fileManager.moveItem(at: stagedDatabaseURL, to: databaseURL)
                try fileManager.moveItem(at: stagedResourcesDirectory, to: resourcesDirectory)
            } catch {
                try? fileManager.removeItem(at: databaseURL)
                try? fileManager.removeItem(at: resourcesDirectory)
                if hadDatabase { try? fileManager.moveItem(at: recoveryDatabaseURL, to: databaseURL) }
                if hadResources { try? fileManager.moveItem(at: recoveryResourcesDirectory, to: resourcesDirectory) }
                throw V02BackupError.restoreFailed(error.localizedDescription)
            }
            try? fileManager.removeItem(at: stagingDirectory)
            try? fileManager.removeItem(at: recoveryDirectory)
            state = payload.state
            lastError = nil
        } catch let error as V02BackupError {
            try? fileManager.removeItem(at: stagingDirectory)
            if hadDatabase,
               !fileManager.fileExists(atPath: databaseURL.path),
               fileManager.fileExists(atPath: recoveryDatabaseURL.path) {
                try? fileManager.moveItem(at: recoveryDatabaseURL, to: databaseURL)
            }
            if hadResources,
               !fileManager.fileExists(atPath: resourcesDirectory.path),
               fileManager.fileExists(atPath: recoveryResourcesDirectory.path) {
                try? fileManager.moveItem(at: recoveryResourcesDirectory, to: resourcesDirectory)
            }
            try? fileManager.removeItem(at: recoveryDirectory)
            throw error
        } catch {
            try? fileManager.removeItem(at: stagingDirectory)
            if hadDatabase,
               !fileManager.fileExists(atPath: databaseURL.path),
               fileManager.fileExists(atPath: recoveryDatabaseURL.path) {
                try? fileManager.moveItem(at: recoveryDatabaseURL, to: databaseURL)
            }
            if hadResources,
               !fileManager.fileExists(atPath: resourcesDirectory.path),
               fileManager.fileExists(atPath: recoveryResourcesDirectory.path) {
                try? fileManager.moveItem(at: recoveryResourcesDirectory, to: resourcesDirectory)
            }
            try? fileManager.removeItem(at: recoveryDirectory)
            throw V02BackupError.restoreFailed(error.localizedDescription)
        }
    }

    private func persist(_ candidate: V02DomainState) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        do {
            try encoder.encode(candidate).write(to: databaseURL, options: .atomic)
        } catch {
            lastError = error.localizedDescription
            throw StoreError.persistenceWriteFailed(error.localizedDescription)
        }
    }
}
