import Combine
import Foundation

enum ItemStatus: String, Codable, Hashable, Sendable {
    case active
    case completed
}

struct Idea: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var content: String
    var status: ItemStatus
    var groupID: UUID?
    let createdAt: Date
    var updatedAt: Date
    var activityAt: Date
    var completedAt: Date?
    var addedToGroupAt: Date?
}

struct IdeaGroup: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var name: String
    var status: ItemStatus
    let createdAt: Date
    var updatedAt: Date
    var activityAt: Date
    var completedAt: Date?
}

struct Attachment: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let ideaID: UUID
    var name: String
    var mimeType: String
    var size: Int64
    let relativePath: String
    let createdAt: Date
}

struct AttachmentInput: Hashable, Sendable {
    let name: String
    let mimeType: String
    let data: Data

    init(name: String, mimeType: String = "application/octet-stream", data: Data) {
        self.name = name
        self.mimeType = mimeType.isEmpty ? "application/octet-stream" : mimeType
        self.data = data
    }
}

enum ReviewItem: Identifiable, Codable, Hashable, Sendable {
    case idea(Idea)
    case group(IdeaGroup)

    enum Kind: String, Codable, Hashable, Sendable {
        case idea
        case group
    }

    var id: UUID {
        switch self {
        case .idea(let idea):
            idea.id
        case .group(let group):
            group.id
        }
    }

    var kind: Kind {
        switch self {
        case .idea:
            .idea
        case .group:
            .group
        }
    }

    var status: ItemStatus {
        switch self {
        case .idea(let idea):
            idea.status
        case .group(let group):
            group.status
        }
    }

    var activityAt: Date {
        switch self {
        case .idea(let idea):
            idea.activityAt
        case .group(let group):
            group.activityAt
        }
    }

    var completedAt: Date? {
        switch self {
        case .idea(let idea):
            idea.completedAt
        case .group(let group):
            group.completedAt
        }
    }
}

private struct NoteStoreIndexes {
    let reviewItems: [ReviewItem]
    let recentActiveIdeas: [Idea]
    let completedItems: [ReviewItem]
    let allRecordItems: [ReviewItem]
    let activeGroups: [IdeaGroup]
    let ideasByID: [UUID: Idea]
    let groupsByID: [UUID: IdeaGroup]
    let attachmentsByIdeaID: [UUID: [Attachment]]
    let ideasByGroupID: [UUID: [Idea]]

    init(
        ideas: [Idea] = [],
        groups: [IdeaGroup] = [],
        attachments: [Attachment] = []
    ) {
        let ungroupedActiveIdeas = ideas
            .filter { $0.status == .active && $0.groupID == nil }
            .map(ReviewItem.idea)
        let activeGroupItems = groups
            .filter { $0.status == .active }
            .map(ReviewItem.group)
        reviewItems = (ungroupedActiveIdeas + activeGroupItems)
            .sorted { $0.activityAt > $1.activityAt }

        recentActiveIdeas = Array(
            ideas
                .filter { $0.status == .active }
                .sorted { $0.activityAt > $1.activityAt }
                .prefix(5)
        )

        let ungroupedCompletedIdeas = ideas
            .filter { $0.status == .completed && $0.groupID == nil }
            .map(ReviewItem.idea)
        let completedGroups = groups
            .filter { $0.status == .completed }
            .map(ReviewItem.group)
        completedItems = (ungroupedCompletedIdeas + completedGroups)
            .sorted {
                ($0.completedAt ?? .distantPast) >
                    ($1.completedAt ?? .distantPast)
            }
        allRecordItems = (reviewItems + completedItems)
            .sorted { $0.activityAt > $1.activityAt }
        activeGroups = groups
            .filter { $0.status == .active }
            .sorted { $0.activityAt > $1.activityAt }
        ideasByID = Dictionary(uniqueKeysWithValues: ideas.map { ($0.id, $0) })
        groupsByID = Dictionary(uniqueKeysWithValues: groups.map { ($0.id, $0) })
        attachmentsByIdeaID = Dictionary(
            grouping: attachments,
            by: \.ideaID
        ).mapValues {
            $0.sorted { $0.createdAt < $1.createdAt }
        }
        ideasByGroupID = Dictionary(
            grouping: ideas.compactMap { idea in
                idea.groupID.map { ($0, idea) }
            },
            by: \.0
        ).mapValues {
            $0.map(\.1).sorted {
                ($0.addedToGroupAt ?? $0.createdAt) <
                    ($1.addedToGroupAt ?? $1.createdAt)
            }
        }
    }
}

enum NoteStoreError: LocalizedError {
    case attachmentTooLarge(name: String)
    case emptyIdea
    case emptyGroupName
    case itemNotFound
    case invalidOperation(String)
    case persistenceUnavailable
    case persistenceWriteFailed(String)

    var errorDescription: String? {
        switch self {
        case .attachmentTooLarge(let name):
            "附件“\(name)”超过 25 MB。"
        case .emptyIdea:
            "想法需要包含文字或附件。"
        case .emptyGroupName:
            "灵感组名称不能为空。"
        case .itemNotFound:
            "没有找到对应内容。"
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
final class NoteStore: ObservableObject {
    nonisolated static let maximumAttachmentSize = 25 * 1_024 * 1_024

    @Published private(set) var ideas: [Idea] = []
    @Published private(set) var groups: [IdeaGroup] = []
    @Published private(set) var attachments: [Attachment] = []
    @Published private(set) var lastPersistenceError: String?
    @Published private(set) var isReadOnlyBecausePersistenceFailed = false

    private struct StoredData: Codable {
        static let currentVersion = 2

        var version: Int
        var ideas: [Idea]
        var groups: [IdeaGroup]
        var attachments: [Attachment]

        init(
            version: Int = Self.currentVersion,
            ideas: [Idea],
            groups: [IdeaGroup],
            attachments: [Attachment]
        ) {
            self.version = version
            self.ideas = ideas
            self.groups = groups
            self.attachments = attachments
        }

        private enum CodingKeys: String, CodingKey {
            case version
            case ideas
            case groups
            case attachments
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
            ideas = try container.decode([Idea].self, forKey: .ideas)
            groups = try container.decode([IdeaGroup].self, forKey: .groups)
            attachments = try container.decode([Attachment].self, forKey: .attachments)
        }
    }

    private let fileManager: FileManager
    private let storageDirectory: URL
    private let attachmentsDirectory: URL
    private let databaseURL: URL
    private var indexes = NoteStoreIndexes()

    init(
        fileManager: FileManager = .default,
        storageDirectory customStorageDirectory: URL? = nil
    ) {
        self.fileManager = fileManager

        let baseDirectory: URL
        if let customStorageDirectory {
            baseDirectory = customStorageDirectory
        } else {
            baseDirectory = fileManager.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first!
                .appendingPathComponent("NOTE1", isDirectory: true)
        }

        storageDirectory = baseDirectory
        attachmentsDirectory = baseDirectory.appendingPathComponent(
            "Attachments",
            isDirectory: true
        )
        databaseURL = baseDirectory.appendingPathComponent("note1-data.json")

        do {
            try prepareDirectories()
            try load()
        } catch {
            lastPersistenceError = error.localizedDescription
            isReadOnlyBecausePersistenceFailed = true
        }
    }

    var reviewItems: [ReviewItem] {
        indexes.reviewItems
    }

    var activeReviewItems: [ReviewItem] {
        reviewItems
    }

    var recentActiveIdeas: [Idea] {
        indexes.recentActiveIdeas
    }

    var completedItems: [ReviewItem] {
        indexes.completedItems
    }

    /// The complete, user-visible record index. Ideas that belong to a group are
    /// represented by their group so the history screen does not show duplicates.
    var allRecordItems: [ReviewItem] {
        indexes.allRecordItems
    }

    /// Returns the record index for History's status filter and local query.
    /// Passing `nil` includes both current and completed records.
    func recordItems(
        status: ItemStatus? = nil,
        matching rawQuery: String = ""
    ) -> [ReviewItem] {
        let source: [ReviewItem]
        switch status {
        case .active:
            source = reviewItems
        case .completed:
            source = completedItems
        case nil:
            source = allRecordItems
        }

        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return source }
        return source.filter { itemMatches($0, query: query) }
    }

    var activeGroups: [IdeaGroup] {
        indexes.activeGroups
    }

    func idea(id: UUID) -> Idea? {
        indexes.ideasByID[id]
    }

    func group(id: UUID) -> IdeaGroup? {
        indexes.groupsByID[id]
    }

    func attachments(for ideaID: UUID) -> [Attachment] {
        indexes.attachmentsByIdeaID[ideaID] ?? []
    }

    func ideas(in groupID: UUID) -> [Idea] {
        indexes.ideasByGroupID[groupID] ?? []
    }

    func attachmentURL(_ attachment: Attachment) -> URL {
        attachmentsDirectory.appendingPathComponent(attachment.relativePath)
    }

    func exportBackupData(
        service: any NoteBackupServicing = JSONNoteBackupService()
    ) async throws -> Data {
        let snapshotIdeas = ideas
        let snapshotGroups = groups
        let attachmentLocations = attachments.map {
            ($0, attachmentURL($0))
        }

        return try await Task.detached(priority: .userInitiated) {
            let fileManager = FileManager.default
            var backupAttachments: [NoteBackupAttachment] = []
            backupAttachments.reserveCapacity(attachmentLocations.count)

            for (attachment, url) in attachmentLocations {
                guard fileManager.fileExists(atPath: url.path) else {
                    throw NoteBackupError.missingAttachment(attachment.name)
                }
                let values = try url.resourceValues(forKeys: [.fileSizeKey])
                if let fileSize = values.fileSize,
                   fileSize > Self.maximumAttachmentSize {
                    throw NoteStoreError.attachmentTooLarge(name: attachment.name)
                }
                let data = try Data(contentsOf: url, options: [.mappedIfSafe])
                backupAttachments.append(
                    NoteBackupAttachment(metadata: attachment, data: data)
                )
            }

            return try service.encode(
                NoteBackupPayload(
                    ideas: snapshotIdeas,
                    groups: snapshotGroups,
                    attachments: backupAttachments
                )
            )
        }.value
    }

    func validateBackupData(
        _ data: Data,
        service: any NoteBackupServicing = JSONNoteBackupService()
    ) async throws {
        _ = try await Task.detached(priority: .userInitiated) {
            try service.decode(data)
        }.value
    }

    func restoreBackupData(
        _ data: Data,
        service: any NoteBackupServicing = JSONNoteBackupService()
    ) async throws {
        guard !isReadOnlyBecausePersistenceFailed else {
            throw NoteStoreError.persistenceUnavailable
        }
        let payload = try await Task.detached(priority: .userInitiated) {
            try service.decode(data)
        }.value
        try await restore(payload)
    }

    @discardableResult
    func createIdea(
        content: String,
        attachmentInputs: [AttachmentInput] = [],
        groupID: UUID? = nil
    ) throws -> Idea {
        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedContent.isEmpty || !attachmentInputs.isEmpty else {
            throw NoteStoreError.emptyIdea
        }
        try validateAttachmentInputs(attachmentInputs)

        let now = Date()
        var updatedGroups = groups
        if let groupID {
            guard let groupIndex = updatedGroups.firstIndex(where: { $0.id == groupID }) else {
                throw NoteStoreError.itemNotFound
            }
            guard updatedGroups[groupIndex].status == .active else {
                throw NoteStoreError.invalidOperation("不能向已完成的灵感组添加内容。")
            }
            updatedGroups[groupIndex].updatedAt = now
            updatedGroups[groupIndex].activityAt = now
        }

        let idea = Idea(
            id: UUID(),
            content: content,
            status: .active,
            groupID: groupID,
            createdAt: now,
            updatedAt: now,
            activityAt: now,
            completedAt: nil,
            addedToGroupAt: groupID == nil ? nil : now
        )
        let newAttachments = try writeAttachments(
            attachmentInputs,
            for: idea.id,
            createdAt: now
        )

        do {
            try commit(
                ideas: ideas + [idea],
                groups: updatedGroups,
                attachments: attachments + newAttachments
            )
        } catch {
            removeAttachmentFiles(newAttachments)
            throw error
        }
        return idea
    }

    func updateIdea(
        id: UUID,
        content: String,
        newAttachments: [AttachmentInput] = [],
        removingAttachmentIDs: Set<UUID> = []
    ) throws {
        guard let ideaIndex = ideas.firstIndex(where: { $0.id == id }) else {
            throw NoteStoreError.itemNotFound
        }
        try validateAttachmentInputs(newAttachments)

        let retainedExistingAttachments = attachments.filter {
            $0.ideaID != id || !removingAttachmentIDs.contains($0.id)
        }
        let removedAttachments = attachments.filter {
            $0.ideaID == id && removingAttachmentIDs.contains($0.id)
        }
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                retainedExistingAttachments.contains(where: { $0.ideaID == id }) ||
                !newAttachments.isEmpty else {
            throw NoteStoreError.emptyIdea
        }

        let now = Date()
        let writtenAttachments = try writeAttachments(
            newAttachments,
            for: id,
            createdAt: now
        )
        var updatedIdeas = ideas
        updatedIdeas[ideaIndex].content = content
        updatedIdeas[ideaIndex].updatedAt = now
        updatedIdeas[ideaIndex].activityAt = now

        do {
            try commit(
                ideas: updatedIdeas,
                groups: groups,
                attachments: retainedExistingAttachments + writtenAttachments
            )
            removeAttachmentFiles(removedAttachments)
        } catch {
            removeAttachmentFiles(writtenAttachments)
            throw error
        }
    }

    @discardableResult
    func createGroup(name: String, initialIdeaID: UUID? = nil) throws -> IdeaGroup {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw NoteStoreError.emptyGroupName
        }

        let now = Date()
        let group = IdeaGroup(
            id: UUID(),
            name: trimmedName,
            status: .active,
            createdAt: now,
            updatedAt: now,
            activityAt: now,
            completedAt: nil
        )
        var updatedIdeas = ideas
        if let initialIdeaID {
            guard let ideaIndex = updatedIdeas.firstIndex(where: {
                $0.id == initialIdeaID && $0.status == .active
            }) else {
                throw NoteStoreError.itemNotFound
            }
            updatedIdeas[ideaIndex].groupID = group.id
            updatedIdeas[ideaIndex].addedToGroupAt = now
            updatedIdeas[ideaIndex].updatedAt = now
            updatedIdeas[ideaIndex].activityAt = now
        }

        try commit(
            ideas: updatedIdeas,
            groups: groups + [group],
            attachments: attachments
        )
        return group
    }

    func renameGroup(id: UUID, name: String) throws {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw NoteStoreError.emptyGroupName
        }
        guard let index = groups.firstIndex(where: { $0.id == id }) else {
            throw NoteStoreError.itemNotFound
        }
        guard groups[index].status == .active else {
            throw NoteStoreError.invalidOperation("请先恢复灵感组，再修改名称。")
        }

        let now = Date()
        var updatedGroups = groups
        updatedGroups[index].name = trimmedName
        updatedGroups[index].updatedAt = now
        updatedGroups[index].activityAt = now
        try commit(ideas: ideas, groups: updatedGroups, attachments: attachments)
    }

    func assignIdea(_ ideaID: UUID, to groupID: UUID) throws {
        guard let ideaIndex = ideas.firstIndex(where: { $0.id == ideaID }),
              let groupIndex = groups.firstIndex(where: { $0.id == groupID }) else {
            throw NoteStoreError.itemNotFound
        }
        guard groups[groupIndex].status == .active else {
            throw NoteStoreError.invalidOperation("不能向已完成的灵感组添加内容。")
        }
        guard ideas[ideaIndex].status == .active else {
            throw NoteStoreError.invalidOperation("请先恢复灵感，再将它加入灵感组。")
        }

        let now = Date()
        var updatedIdeas = ideas
        var updatedGroups = groups
        updatedIdeas[ideaIndex].groupID = groupID
        updatedIdeas[ideaIndex].addedToGroupAt = now
        updatedIdeas[ideaIndex].updatedAt = now
        updatedIdeas[ideaIndex].activityAt = now
        updatedGroups[groupIndex].updatedAt = now
        updatedGroups[groupIndex].activityAt = now
        try commit(
            ideas: updatedIdeas,
            groups: updatedGroups,
            attachments: attachments
        )
    }

    func removeIdeaFromGroup(_ ideaID: UUID) throws {
        guard let ideaIndex = ideas.firstIndex(where: { $0.id == ideaID }) else {
            throw NoteStoreError.itemNotFound
        }
        guard ideas[ideaIndex].status == .active else {
            throw NoteStoreError.invalidOperation("已完成灵感不能单独移出灵感组。")
        }

        let now = Date()
        var updatedIdeas = ideas
        updatedIdeas[ideaIndex].groupID = nil
        updatedIdeas[ideaIndex].addedToGroupAt = nil
        updatedIdeas[ideaIndex].updatedAt = now
        updatedIdeas[ideaIndex].activityAt = now
        try commit(ideas: updatedIdeas, groups: groups, attachments: attachments)
    }

    func complete(_ item: ReviewItem) throws {
        try setCompleted(item, completed: true)
    }

    func restore(_ item: ReviewItem) throws {
        try setCompleted(item, completed: false)
    }

    func restore(_ items: [ReviewItem]) throws {
        try setCompleted(items, completed: false)
    }

    func setCompleted(_ item: ReviewItem, completed: Bool) throws {
        try setCompleted([item], completed: completed)
    }

    func setCompleted(_ items: [ReviewItem], completed: Bool) throws {
        let now = Date()
        let targetStatus: ItemStatus = completed ? .completed : .active
        let completedAt: Date? = completed ? now : nil
        var updatedIdeas = ideas
        var updatedGroups = groups

        for item in items {
            switch item.kind {
            case .idea:
                guard let index = updatedIdeas.firstIndex(where: { $0.id == item.id }) else {
                    throw NoteStoreError.itemNotFound
                }
                guard updatedIdeas[index].groupID == nil else {
                    throw NoteStoreError.invalidOperation(
                        "灵感组内的灵感需随整个灵感组一起完成或恢复。"
                    )
                }
                updatedIdeas[index].status = targetStatus
                updatedIdeas[index].completedAt = completedAt
                updatedIdeas[index].updatedAt = now
                updatedIdeas[index].activityAt = now

            case .group:
                guard let groupIndex = updatedGroups.firstIndex(where: {
                    $0.id == item.id
                }) else {
                    throw NoteStoreError.itemNotFound
                }
                updatedGroups[groupIndex].status = targetStatus
                updatedGroups[groupIndex].completedAt = completedAt
                updatedGroups[groupIndex].updatedAt = now
                updatedGroups[groupIndex].activityAt = now

                for ideaIndex in updatedIdeas.indices
                where updatedIdeas[ideaIndex].groupID == item.id {
                    updatedIdeas[ideaIndex].status = targetStatus
                    updatedIdeas[ideaIndex].completedAt = completedAt
                    updatedIdeas[ideaIndex].updatedAt = now
                    updatedIdeas[ideaIndex].activityAt = now
                }
            }
        }

        try commit(
            ideas: updatedIdeas,
            groups: updatedGroups,
            attachments: attachments
        )
    }

    func deleteCompleted(_ item: ReviewItem) throws {
        try deleteCompleted([item])
    }

    func deleteCompleted(_ items: [ReviewItem]) throws {
        guard items.allSatisfy({ $0.status == .completed }) else {
            throw NoteStoreError.invalidOperation("只有已完成记录可使用此删除入口。")
        }
        try deleteRecords(items)
    }

    func deleteRecords(_ items: [ReviewItem]) throws {
        var deletedIdeaIDs = Set<UUID>()
        var deletedGroupIDs = Set<UUID>()

        for item in items {
            switch item.kind {
            case .idea:
                guard let idea = ideas.first(where: { $0.id == item.id }) else {
                    throw NoteStoreError.itemNotFound
                }
                guard idea.groupID == nil else {
                    throw NoteStoreError.invalidOperation(
                        "灵感组内的灵感需随整个灵感组删除。"
                    )
                }
                deletedIdeaIDs.insert(idea.id)

            case .group:
                guard let group = groups.first(where: { $0.id == item.id }) else {
                    throw NoteStoreError.itemNotFound
                }
                deletedGroupIDs.insert(group.id)
                ideas
                    .filter { $0.groupID == group.id }
                    .forEach { deletedIdeaIDs.insert($0.id) }
            }
        }

        let deletedAttachments = attachments.filter {
            deletedIdeaIDs.contains($0.ideaID)
        }
        try commit(
            ideas: ideas.filter { !deletedIdeaIDs.contains($0.id) },
            groups: groups.filter { !deletedGroupIDs.contains($0.id) },
            attachments: attachments.filter {
                !deletedIdeaIDs.contains($0.ideaID)
            }
        )
        removeAttachmentFiles(deletedAttachments)
    }

    private func itemMatches(_ item: ReviewItem, query: String) -> Bool {
        switch item {
        case .group(let group):
            return group.name.localizedStandardContains(query) ||
                (indexes.ideasByGroupID[group.id] ?? [])
                    .contains { ideaMatches($0, query: query) }
        case .idea(let idea):
            return ideaMatches(idea, query: query)
        }
    }

    private func ideaMatches(_ idea: Idea, query: String) -> Bool {
        idea.content.localizedStandardContains(query) ||
            (indexes.attachmentsByIdeaID[idea.id] ?? []).contains {
                $0.name.localizedStandardContains(query)
            }
    }

    private func prepareDirectories() throws {
        try fileManager.createDirectory(
            at: storageDirectory,
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(
            at: attachmentsDirectory,
            withIntermediateDirectories: true
        )
    }

    private func load() throws {
        guard fileManager.fileExists(atPath: databaseURL.path) else { return }
        let data = try Data(contentsOf: databaseURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let storedData = try decoder.decode(StoredData.self, from: data)
        let needsLegacyPlaceholderMigration = storedData.version < 2
        let migratedGroups = needsLegacyPlaceholderMigration
            ? storedData.groups.map { group in
                guard group.name == "Existing group" else { return group }
                var migrated = group
                migrated.name = "灵感组"
                return migrated
            }
            : storedData.groups

        if storedData.version < StoredData.currentVersion {
            try commit(
                ideas: storedData.ideas,
                groups: migratedGroups,
                attachments: storedData.attachments
            )
        } else {
            rebuildIndexes(
                ideas: storedData.ideas,
                groups: storedData.groups,
                attachments: storedData.attachments
            )
            ideas = storedData.ideas
            groups = storedData.groups
            attachments = storedData.attachments
            lastPersistenceError = nil
        }
    }

    private func commit(
        ideas newIdeas: [Idea],
        groups newGroups: [IdeaGroup],
        attachments newAttachments: [Attachment]
    ) throws {
        guard !isReadOnlyBecausePersistenceFailed else {
            throw NoteStoreError.persistenceUnavailable
        }
        let storedData = StoredData(
            ideas: newIdeas,
            groups: newGroups,
            attachments: newAttachments
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(storedData)
        do {
            try data.write(to: databaseURL, options: [.atomic])
        } catch {
            let message = error.localizedDescription
            lastPersistenceError = message
            throw NoteStoreError.persistenceWriteFailed(message)
        }

        rebuildIndexes(
            ideas: newIdeas,
            groups: newGroups,
            attachments: newAttachments
        )
        ideas = newIdeas
        groups = newGroups
        attachments = newAttachments
        lastPersistenceError = nil
    }

    private func restore(_ payload: NoteBackupPayload) async throws {
        let currentDatabaseURL = databaseURL
        let currentAttachmentsDirectory = attachmentsDirectory
        let operationID = UUID().uuidString
        let stagingDirectory = storageDirectory.appendingPathComponent(
            ".Restore-\(operationID)",
            isDirectory: true
        )
        let stagingAttachments = stagingDirectory.appendingPathComponent(
            "Attachments",
            isDirectory: true
        )
        let stagingDatabase = stagingDirectory.appendingPathComponent(
            "note1-data.json"
        )
        let recoveryDirectory = storageDirectory.appendingPathComponent(
            ".Recovery-\(operationID)",
            isDirectory: true
        )
        let recoveryAttachments = recoveryDirectory.appendingPathComponent(
            "Attachments",
            isDirectory: true
        )
        let recoveryDatabase = recoveryDirectory.appendingPathComponent(
            "note1-data.json"
        )

        do {
            try await Task.detached(priority: .userInitiated) {
                let fileManager = FileManager.default
                do {
                    try fileManager.createDirectory(
                        at: stagingAttachments,
                        withIntermediateDirectories: true
                    )
                    for entry in payload.attachments {
                        try entry.data.write(
                            to: stagingAttachments.appendingPathComponent(
                                entry.metadata.relativePath
                            ),
                            options: [.atomic]
                        )
                    }

                    let storedData = StoredData(
                        ideas: payload.ideas,
                        groups: payload.groups,
                        attachments: payload.attachments.map(\.metadata)
                    )
                    let encoder = JSONEncoder()
                    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                    encoder.dateEncodingStrategy = .iso8601
                    try encoder.encode(storedData).write(
                        to: stagingDatabase,
                        options: [.atomic]
                    )
                    try fileManager.createDirectory(
                        at: recoveryDirectory,
                        withIntermediateDirectories: true
                    )
                } catch {
                    try? fileManager.removeItem(at: stagingDirectory)
                    try? fileManager.removeItem(at: recoveryDirectory)
                    throw NoteBackupError.restoreFailed(
                        error.localizedDescription
                    )
                }

                var movedCurrentDatabase = false
                var movedCurrentAttachments = false
                do {
                    if fileManager.fileExists(atPath: currentDatabaseURL.path) {
                        try fileManager.moveItem(
                            at: currentDatabaseURL,
                            to: recoveryDatabase
                        )
                        movedCurrentDatabase = true
                    }
                    if fileManager.fileExists(
                        atPath: currentAttachmentsDirectory.path
                    ) {
                        try fileManager.moveItem(
                            at: currentAttachmentsDirectory,
                            to: recoveryAttachments
                        )
                        movedCurrentAttachments = true
                    }

                    try fileManager.moveItem(
                        at: stagingAttachments,
                        to: currentAttachmentsDirectory
                    )
                    try fileManager.moveItem(
                        at: stagingDatabase,
                        to: currentDatabaseURL
                    )
                } catch {
                    let replacementError = error
                    var rollbackFailed = false
                    do {
                        if fileManager.fileExists(atPath: currentDatabaseURL.path) {
                            try fileManager.removeItem(at: currentDatabaseURL)
                        }
                        if fileManager.fileExists(
                            atPath: currentAttachmentsDirectory.path
                        ) {
                            try fileManager.removeItem(
                                at: currentAttachmentsDirectory
                            )
                        }
                        if movedCurrentDatabase {
                            try fileManager.moveItem(
                                at: recoveryDatabase,
                                to: currentDatabaseURL
                            )
                        }
                        if movedCurrentAttachments {
                            try fileManager.moveItem(
                                at: recoveryAttachments,
                                to: currentAttachmentsDirectory
                            )
                        } else {
                            try fileManager.createDirectory(
                                at: currentAttachmentsDirectory,
                                withIntermediateDirectories: true
                            )
                        }
                    } catch {
                        rollbackFailed = true
                    }
                    try? fileManager.removeItem(at: stagingDirectory)
                    if rollbackFailed {
                        throw NoteBackupError.restoreRecoveryFailed
                    }
                    try? fileManager.removeItem(at: recoveryDirectory)
                    throw NoteBackupError.restoreFailed(
                        replacementError.localizedDescription
                    )
                }

                try? fileManager.removeItem(at: stagingDirectory)
                try? fileManager.removeItem(at: recoveryDirectory)
            }.value
        } catch {
            if case NoteBackupError.restoreRecoveryFailed = error {
                isReadOnlyBecausePersistenceFailed = true
                lastPersistenceError = error.localizedDescription
            }
            throw error
        }

        let restoredAttachments = payload.attachments.map(\.metadata)
        rebuildIndexes(
            ideas: payload.ideas,
            groups: payload.groups,
            attachments: restoredAttachments
        )
        ideas = payload.ideas
        groups = payload.groups
        attachments = restoredAttachments
        lastPersistenceError = nil
    }

    private func validateAttachmentInputs(_ inputs: [AttachmentInput]) throws {
        for input in inputs where input.data.count > Self.maximumAttachmentSize {
            throw NoteStoreError.attachmentTooLarge(name: input.name)
        }
    }

    private func rebuildIndexes(
        ideas: [Idea],
        groups: [IdeaGroup],
        attachments: [Attachment]
    ) {
        indexes = NoteStoreIndexes(
            ideas: ideas,
            groups: groups,
            attachments: attachments
        )
    }

    private func writeAttachments(
        _ inputs: [AttachmentInput],
        for ideaID: UUID,
        createdAt: Date
    ) throws -> [Attachment] {
        var writtenAttachments: [Attachment] = []

        do {
            for input in inputs {
                let attachmentID = UUID()
                let fileExtension = URL(fileURLWithPath: input.name).pathExtension
                let relativePath = fileExtension.isEmpty
                    ? attachmentID.uuidString
                    : "\(attachmentID.uuidString).\(fileExtension)"
                let destinationURL = attachmentsDirectory
                    .appendingPathComponent(relativePath)
                try input.data.write(to: destinationURL, options: [.atomic])
                writtenAttachments.append(
                    Attachment(
                        id: attachmentID,
                        ideaID: ideaID,
                        name: input.name,
                        mimeType: input.mimeType,
                        size: Int64(input.data.count),
                        relativePath: relativePath,
                        createdAt: createdAt
                    )
                )
            }
            return writtenAttachments
        } catch {
            removeAttachmentFiles(writtenAttachments)
            throw error
        }
    }

    private func removeAttachmentFiles(_ attachments: [Attachment]) {
        for attachment in attachments {
            try? fileManager.removeItem(at: attachmentURL(attachment))
        }
    }
}

// MARK: - V0.2 domain foundation

/// The V0.2 model is intentionally separate from the V0.1 store above.  A
/// later app-shell migration can therefore opt into the new data version
/// without attempting to reinterpret existing personal test data.
enum V02CardFlowState: String, Codable, Sendable {
    case visible
    case tuckedAway
}

enum V02RoundState: String, Codable, Sendable {
    case thinking
    case ended
}

enum V02ResourceSource: String, Codable, Sendable {
    case importedAttachment
    case voiceInspiration
}

struct V02Inspiration: Identifiable, Codable, Sendable {
    let id: UUID
    var text: String
    var cardFlowState: V02CardFlowState
    var collectionID: UUID?
    let createdAt: Date
    var updatedAt: Date
    var resourceIDs: [UUID]
}

struct V02ThinkingCollection: Identifiable, Codable, Sendable {
    let id: UUID
    var name: String
    let createdAt: Date
    var currentRoundID: UUID?
}

enum V02RoundEventKind: String, Codable, Sendable {
    case started
    case memberAdded
    case memberRemoved
    case inspirationEdited
    case ended
}

struct V02RoundEvent: Identifiable, Codable, Sendable {
    let id: UUID
    let kind: V02RoundEventKind
    let occurredAt: Date
    let inspirationID: UUID?
}

struct V02ThinkingRound: Identifiable, Codable, Sendable {
    let id: UUID
    let collectionID: UUID
    var state: V02RoundState
    let startedAt: Date
    var endedAt: Date?
    var memberIDs: [UUID]
    var effectiveEditCount: Int
    var events: [V02RoundEvent]

    init(
        id: UUID,
        collectionID: UUID,
        state: V02RoundState,
        startedAt: Date,
        endedAt: Date?,
        memberIDs: [UUID],
        effectiveEditCount: Int,
        events: [V02RoundEvent] = []
    ) {
        self.id = id
        self.collectionID = collectionID
        self.state = state
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.memberIDs = memberIDs
        self.effectiveEditCount = effectiveEditCount
        self.events = events
    }

    private enum CodingKeys: String, CodingKey {
        case id, collectionID, state, startedAt, endedAt, memberIDs, effectiveEditCount, events
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try values.decode(UUID.self, forKey: .id),
            collectionID: try values.decode(UUID.self, forKey: .collectionID),
            state: try values.decode(V02RoundState.self, forKey: .state),
            startedAt: try values.decode(Date.self, forKey: .startedAt),
            endedAt: try values.decodeIfPresent(Date.self, forKey: .endedAt),
            memberIDs: try values.decode([UUID].self, forKey: .memberIDs),
            effectiveEditCount: try values.decode(Int.self, forKey: .effectiveEditCount),
            events: try values.decodeIfPresent([V02RoundEvent].self, forKey: .events) ?? []
        )
    }
}

struct V02AttachmentResource: Identifiable, Codable, Sendable {
    let id: UUID
    let source: V02ResourceSource
    let filename: String
    let mimeType: String
    let relativePath: String
    let size: Int64
    let createdAt: Date
}

struct V02ReceiptSnapshot: Codable, Sendable {
    /// Metadata frozen at receipt creation so a receipt remains self-describing
    /// even when its source inspiration is later edited or removed.
    struct Attachment: Codable, Sendable, Hashable {
        let id: UUID
        let source: V02ResourceSource
        let filename: String
        let mimeType: String
        let relativePath: String
        let size: Int64
        let createdAt: Date

        init(resource: V02AttachmentResource) {
            id = resource.id
            source = resource.source
            filename = resource.filename
            mimeType = resource.mimeType
            relativePath = resource.relativePath
            size = resource.size
            createdAt = resource.createdAt
        }

        init(
            id: UUID,
            source: V02ResourceSource = .importedAttachment,
            filename: String,
            mimeType: String,
            relativePath: String,
            size: Int64,
            createdAt: Date = .now
        ) {
            self.id = id
            self.source = source
            self.filename = filename
            self.mimeType = mimeType
            self.relativePath = relativePath
            self.size = size
            self.createdAt = createdAt
        }
    }

    struct Member: Codable, Sendable {
        let inspirationID: UUID
        let text: String
        let resourceIDs: [UUID]
        let attachments: [Attachment]

        init(
            inspirationID: UUID,
            text: String,
            resourceIDs: [UUID],
            attachments: [Attachment] = []
        ) {
            self.inspirationID = inspirationID
            self.text = text
            self.resourceIDs = resourceIDs
            self.attachments = attachments
        }

        private enum CodingKeys: String, CodingKey {
            case inspirationID, text, resourceIDs, attachments
        }

        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            self.init(
                inspirationID: try values.decode(UUID.self, forKey: .inspirationID),
                text: try values.decode(String.self, forKey: .text),
                resourceIDs: try values.decode([UUID].self, forKey: .resourceIDs),
                attachments: try values.decodeIfPresent([Attachment].self, forKey: .attachments) ?? []
            )
        }
    }

    let collectionName: String
    let startedAt: Date
    let endedAt: Date
    let effectiveEditCount: Int
    let members: [Member]
    let events: [V02RoundEvent]

    init(
        collectionName: String,
        startedAt: Date,
        endedAt: Date,
        effectiveEditCount: Int,
        members: [Member],
        events: [V02RoundEvent] = []
    ) {
        self.collectionName = collectionName
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.effectiveEditCount = effectiveEditCount
        self.members = members
        self.events = events
    }

    private enum CodingKeys: String, CodingKey {
        case collectionName, startedAt, endedAt, effectiveEditCount, members, events
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            collectionName: try values.decode(String.self, forKey: .collectionName),
            startedAt: try values.decode(Date.self, forKey: .startedAt),
            endedAt: try values.decode(Date.self, forKey: .endedAt),
            effectiveEditCount: try values.decode(Int.self, forKey: .effectiveEditCount),
            members: try values.decode([Member].self, forKey: .members),
            events: try values.decodeIfPresent([V02RoundEvent].self, forKey: .events) ?? []
        )
    }
}

struct V02Receipt: Identifiable, Codable, Sendable {
    let id: UUID
    let roundID: UUID
    let collectionID: UUID
    let createdAt: Date
    let snapshot: V02ReceiptSnapshot
}

enum V02TrashObject: Codable, Sendable {
    case inspiration(V02Inspiration)
    case receipt(V02Receipt)

    private enum CodingKeys: String, CodingKey { case kind, inspiration, receipt }
    private enum Kind: String, Codable { case inspiration, receipt }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(Kind.self, forKey: .kind) {
        case .inspiration: self = .inspiration(try c.decode(V02Inspiration.self, forKey: .inspiration))
        case .receipt: self = .receipt(try c.decode(V02Receipt.self, forKey: .receipt))
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .inspiration(let item):
            try c.encode(Kind.inspiration, forKey: .kind)
            try c.encode(item, forKey: .inspiration)
        case .receipt(let item):
            try c.encode(Kind.receipt, forKey: .kind)
            try c.encode(item, forKey: .receipt)
        }
    }
}

struct V02TrashEntry: Identifiable, Codable, Sendable {
    let id: UUID
    let object: V02TrashObject
    let deletedAt: Date
}

enum V02DomainError: LocalizedError, Equatable {
    case collectionLimit
    case collectionCapacity
    case inspirationNotFound
    case collectionNotFound
    case roundNotFound
    case activeRoundRequired
    case duplicateReceipt
    case emptyRound
    case invalidMemberOrder
    case trashEntryNotFound
    case resourceNotFound

    var errorDescription: String? {
        switch self {
        case .collectionLimit: "当前版本最多支持 5 个构思集。"
        case .collectionCapacity: "当前版本每个构思集最多支持 10 条灵感。"
        case .inspirationNotFound, .collectionNotFound, .roundNotFound: "没有找到对应内容。"
        case .activeRoundRequired: "当前构思集没有可结束的构思轮次。"
        case .duplicateReceipt: "本轮构思已经生成构思小票。"
        case .emptyRound: "请先在构思集中保留至少一条灵感，再结束本轮构思。"
        case .invalidMemberOrder: "构思集内的灵感顺序无效。"
        case .trashEntryNotFound: "回收站中没有找到对应内容。"
        case .resourceNotFound: "没有找到对应附件资源。"
        }
    }
}

struct V02DomainState: Codable, Sendable {
    static let currentVersion = 3
    var version = Self.currentVersion
    var nextCollectionNumber = 1
    var inspirations: [V02Inspiration] = []
    var collections: [V02ThinkingCollection] = []
    var rounds: [V02ThinkingRound] = []
    var resources: [V02AttachmentResource] = []
    var receipts: [V02Receipt] = []
    var trash: [V02TrashEntry] = []
}

/// Pure transaction engine. Persistence owns one `V02DomainState` value and
/// only replaces it after the operation below has returned successfully.
struct V02DomainEngine {
    static let maximumActiveCollections = 5
    static let maximumMembersPerCollection = 10
    static let trashRetention: TimeInterval = 30 * 24 * 60 * 60

    static func createCollection(
        in state: inout V02DomainState,
        name: String? = nil,
        now: Date = .now
    ) throws -> V02ThinkingCollection {
        let activeCount = state.collections.filter { $0.currentRoundID != nil }.count
        guard activeCount < maximumActiveCollections else { throw V02DomainError.collectionLimit }
        let defaultName = "构思集（\(state.nextCollectionNumber)）"
        state.nextCollectionNumber += 1
        let collection = V02ThinkingCollection(id: UUID(), name: name?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? name!.trimmingCharacters(in: .whitespacesAndNewlines) : defaultName, createdAt: now, currentRoundID: nil)
        state.collections.append(collection)
        return collection
    }

    static func startRound(
        collectionID: UUID,
        in state: inout V02DomainState,
        memberIDs: [UUID] = [],
        now: Date = .now
    ) throws -> V02ThinkingRound {
        guard let index = state.collections.firstIndex(where: { $0.id == collectionID }) else { throw V02DomainError.collectionNotFound }
        guard state.collections[index].currentRoundID == nil else { throw V02DomainError.activeRoundRequired }
        guard memberIDs.count <= maximumMembersPerCollection else { throw V02DomainError.collectionCapacity }
        let round = V02ThinkingRound(
            id: UUID(), collectionID: collectionID, state: .thinking, startedAt: now, endedAt: nil,
            memberIDs: memberIDs, effectiveEditCount: 0,
            events: [.init(id: UUID(), kind: .started, occurredAt: now, inspirationID: nil)] + memberIDs.map {
                .init(id: UUID(), kind: .memberAdded, occurredAt: now, inspirationID: $0)
            }
        )
        state.rounds.append(round)
        state.collections[index].currentRoundID = round.id
        return round
    }

    static func assign(
        inspirationID: UUID,
        to collectionID: UUID,
        in state: inout V02DomainState,
        now: Date = .now
    ) throws {
        guard let inspirationIndex = state.inspirations.firstIndex(where: { $0.id == inspirationID }) else { throw V02DomainError.inspirationNotFound }
        guard let collection = state.collections.first(where: { $0.id == collectionID }),
              let roundID = collection.currentRoundID,
              let roundIndex = state.rounds.firstIndex(where: { $0.id == roundID && $0.state == .thinking }) else { throw V02DomainError.activeRoundRequired }
        let existing = state.rounds[roundIndex].memberIDs
        guard existing.contains(inspirationID) || existing.count < maximumMembersPerCollection else { throw V02DomainError.collectionCapacity }
        if let oldID = state.inspirations[inspirationIndex].collectionID,
           let oldRound = state.collections.first(where: { $0.id == oldID })?.currentRoundID,
           let oldIndex = state.rounds.firstIndex(where: { $0.id == oldRound }) {
            state.rounds[oldIndex].memberIDs.removeAll { $0 == inspirationID }
            state.rounds[oldIndex].events.append(.init(id: UUID(), kind: .memberRemoved, occurredAt: now, inspirationID: inspirationID))
        }
        if !state.rounds[roundIndex].memberIDs.contains(inspirationID) {
            state.rounds[roundIndex].memberIDs.append(inspirationID)
            state.rounds[roundIndex].events.append(.init(id: UUID(), kind: .memberAdded, occurredAt: now, inspirationID: inspirationID))
        }
        state.inspirations[inspirationIndex].collectionID = collectionID
        state.inspirations[inspirationIndex].updatedAt = now
    }

    @discardableResult
    static func endRound(
        roundID: UUID,
        in state: inout V02DomainState,
        now: Date = .now
    ) throws -> V02Receipt {
        guard let index = state.rounds.firstIndex(where: { $0.id == roundID }) else { throw V02DomainError.roundNotFound }
        guard state.rounds[index].state == .thinking else { throw V02DomainError.duplicateReceipt }
        let round = state.rounds[index]
        guard !round.memberIDs.isEmpty else { throw V02DomainError.emptyRound }
        guard let collectionIndex = state.collections.firstIndex(where: { $0.id == round.collectionID }) else { throw V02DomainError.collectionNotFound }
        guard state.collections[collectionIndex].currentRoundID == roundID else { throw V02DomainError.activeRoundRequired }
        let members = try round.memberIDs.map { id -> V02ReceiptSnapshot.Member in
            guard let item = state.inspirations.first(where: { $0.id == id }) else { throw V02DomainError.inspirationNotFound }
            let attachments = item.resourceIDs.compactMap { resourceID in
                state.resources.first(where: { $0.id == resourceID })
            }.map(V02ReceiptSnapshot.Attachment.init(resource:))
            return .init(
                inspirationID: item.id,
                text: item.text,
                resourceIDs: item.resourceIDs,
                attachments: attachments
            )
        }
        state.rounds[index].events.append(.init(id: UUID(), kind: .ended, occurredAt: now, inspirationID: nil))
        let receipt = V02Receipt(id: UUID(), roundID: round.id, collectionID: round.collectionID, createdAt: now, snapshot: .init(collectionName: state.collections[collectionIndex].name, startedAt: round.startedAt, endedAt: now, effectiveEditCount: round.effectiveEditCount, members: members, events: state.rounds[index].events))
        state.rounds[index].state = .ended
        state.rounds[index].endedAt = now
        state.collections[collectionIndex].currentRoundID = nil
        state.receipts.append(receipt)
        return receipt
    }

    static func continueRound(
        collectionID: UUID,
        in state: inout V02DomainState,
        now: Date = .now
    ) throws -> V02ThinkingRound {
        guard let collectionIndex = state.collections.firstIndex(where: { $0.id == collectionID }) else {
            throw V02DomainError.collectionNotFound
        }
        guard state.collections[collectionIndex].currentRoundID == nil else {
            throw V02DomainError.activeRoundRequired
        }
        let activeCount = state.collections.filter { $0.currentRoundID != nil }.count
        guard activeCount < maximumActiveCollections else { throw V02DomainError.collectionLimit }
        guard let previous = state.rounds
            .filter({ $0.collectionID == collectionID && $0.state == .ended })
            .sorted(by: { ($0.endedAt ?? .distantPast) > ($1.endedAt ?? .distantPast) })
            .first else { throw V02DomainError.roundNotFound }
        guard previous.memberIDs.allSatisfy({ memberID in
            state.inspirations.contains { $0.id == memberID }
        }) else {
            throw V02DomainError.inspirationNotFound
        }
        // A member can have been moved into another active collection after
        // this receipt was created. Continuing the old collection must move
        // that member out of the other active round first, otherwise the same
        // inspiration would exist in two live rounds.
        for memberID in previous.memberIDs {
            guard let inspirationIndex = state.inspirations.firstIndex(where: { $0.id == memberID }) else { continue }
            guard let oldCollectionID = state.inspirations[inspirationIndex].collectionID,
                  oldCollectionID != collectionID,
                  let oldRoundID = state.collections.first(where: { $0.id == oldCollectionID })?.currentRoundID,
                  let oldRoundIndex = state.rounds.firstIndex(where: { $0.id == oldRoundID && $0.state == .thinking }) else { continue }
            state.rounds[oldRoundIndex].memberIDs.removeAll { $0 == memberID }
            state.rounds[oldRoundIndex].events.append(.init(id: UUID(), kind: .memberRemoved, occurredAt: now, inspirationID: memberID))
        }
        let round = V02ThinkingRound(
            id: UUID(),
            collectionID: collectionID,
            state: .thinking,
            startedAt: now,
            endedAt: nil,
            memberIDs: previous.memberIDs,
            effectiveEditCount: 0,
            events: [.init(id: UUID(), kind: .started, occurredAt: now, inspirationID: nil)] + previous.memberIDs.map {
                .init(id: UUID(), kind: .memberAdded, occurredAt: now, inspirationID: $0)
            }
        )
        state.rounds.append(round)
        state.collections[collectionIndex].currentRoundID = round.id
        for index in state.inspirations.indices where previous.memberIDs.contains(state.inspirations[index].id) {
            state.inspirations[index].collectionID = collectionID
            state.inspirations[index].cardFlowState = .visible
            state.inspirations[index].updatedAt = now
        }
        return round
    }

    static func undoEndRound(
        receiptID: UUID,
        in state: inout V02DomainState,
        now: Date = .now
    ) throws {
        guard let receiptIndex = state.receipts.firstIndex(where: { $0.id == receiptID }) else {
            throw V02DomainError.roundNotFound
        }
        let receipt = state.receipts[receiptIndex]
        let latestReceiptForCollection = state.receipts
            .filter { $0.collectionID == receipt.collectionID }
            .max { $0.createdAt < $1.createdAt }
        guard latestReceiptForCollection?.id == receiptID else {
            throw V02DomainError.roundNotFound
        }
        guard let roundIndex = state.rounds.firstIndex(where: { $0.id == receipt.roundID && $0.state == .ended }),
              let collectionIndex = state.collections.firstIndex(where: { $0.id == receipt.collectionID }),
              state.collections[collectionIndex].currentRoundID == nil else {
            throw V02DomainError.roundNotFound
        }
        let activeCount = state.collections.filter { $0.currentRoundID != nil }.count
        guard activeCount < maximumActiveCollections else {
            throw V02DomainError.collectionLimit
        }
        state.receipts.remove(at: receiptIndex)
        state.rounds[roundIndex].state = .thinking
        state.rounds[roundIndex].endedAt = nil
        if state.rounds[roundIndex].events.last?.kind == .ended {
            state.rounds[roundIndex].events.removeLast()
        }
        state.collections[collectionIndex].currentRoundID = state.rounds[roundIndex].id
        // The receipt can be undone after a member was assigned to another
        // active collection. Move it out of that live round first so one
        // inspiration never belongs to two active rounds at once.
        for memberID in state.rounds[roundIndex].memberIDs {
            guard let inspirationIndex = state.inspirations.firstIndex(where: { $0.id == memberID }) else { continue }
            guard let oldCollectionID = state.inspirations[inspirationIndex].collectionID,
                  oldCollectionID != receipt.collectionID,
                  let oldRoundID = state.collections.first(where: { $0.id == oldCollectionID })?.currentRoundID,
                  let oldRoundIndex = state.rounds.firstIndex(where: { $0.id == oldRoundID && $0.state == .thinking }) else { continue }
            state.rounds[oldRoundIndex].memberIDs.removeAll { $0 == memberID }
            state.rounds[oldRoundIndex].events.append(.init(id: UUID(), kind: .memberRemoved, occurredAt: now, inspirationID: memberID))
        }
        for index in state.inspirations.indices where state.rounds[roundIndex].memberIDs.contains(state.inspirations[index].id) {
            state.inspirations[index].collectionID = receipt.collectionID
            state.inspirations[index].cardFlowState = .visible
            state.inspirations[index].updatedAt = now
        }
    }

    static func removeFromCollection(
        inspirationID: UUID,
        in state: inout V02DomainState,
        now: Date = .now
    ) throws {
        guard let inspirationIndex = state.inspirations.firstIndex(where: { $0.id == inspirationID }),
              let collectionID = state.inspirations[inspirationIndex].collectionID,
              let roundID = state.collections.first(where: { $0.id == collectionID })?.currentRoundID,
              let roundIndex = state.rounds.firstIndex(where: { $0.id == roundID && $0.state == .thinking }) else {
            throw V02DomainError.inspirationNotFound
        }
        state.rounds[roundIndex].memberIDs.removeAll { $0 == inspirationID }
        state.rounds[roundIndex].events.append(.init(id: UUID(), kind: .memberRemoved, occurredAt: now, inspirationID: inspirationID))
        state.inspirations[inspirationIndex].collectionID = nil
        state.inspirations[inspirationIndex].cardFlowState = .visible
        state.inspirations[inspirationIndex].updatedAt = now
    }

    static func reorderMembers(
        _ memberIDs: [UUID],
        in roundID: UUID,
        state: inout V02DomainState
    ) throws {
        guard let index = state.rounds.firstIndex(where: { $0.id == roundID && $0.state == .thinking }) else {
            throw V02DomainError.roundNotFound
        }
        guard Set(memberIDs) == Set(state.rounds[index].memberIDs), memberIDs.count == state.rounds[index].memberIDs.count else {
            throw V02DomainError.invalidMemberOrder
        }
        state.rounds[index].memberIDs = memberIDs
    }

    static func purgeExpiredTrash(in state: inout V02DomainState, now: Date = .now) {
        state.trash.removeAll { now.timeIntervalSince($0.deletedAt) >= trashRetention }
    }

    static func deleteInspiration(
        _ inspirationID: UUID,
        in state: inout V02DomainState,
        now: Date = .now
    ) throws {
        guard let index = state.inspirations.firstIndex(where: { $0.id == inspirationID }) else {
            throw V02DomainError.inspirationNotFound
        }
        let ownedCollectionID = state.inspirations[index].collectionID
        var deleted = state.inspirations.remove(at: index)
        deleted.collectionID = nil
        deleted.cardFlowState = .visible
        state.trash.append(.init(id: UUID(), object: .inspiration(deleted), deletedAt: now))
        for index in state.rounds.indices {
            state.rounds[index].memberIDs.removeAll { $0 == inspirationID }
        }
        // Only the collection that owned the deleted inspiration may become
        // empty as a result of this transaction. Do not sweep unrelated empty
        // draft collections when deleting an independent inspiration.
        if let collectionID = ownedCollectionID,
           !state.inspirations.contains(where: { $0.collectionID == collectionID }) {
            state.rounds.removeAll { $0.collectionID == collectionID }
            state.collections.removeAll { $0.id == collectionID }
        }
    }

    static func deleteReceipt(
        _ receiptID: UUID,
        in state: inout V02DomainState,
        now: Date = .now
    ) throws {
        guard let index = state.receipts.firstIndex(where: { $0.id == receiptID }) else {
            throw V02DomainError.roundNotFound
        }
        let receipt = state.receipts.remove(at: index)
        state.trash.append(.init(id: UUID(), object: .receipt(receipt), deletedAt: now))
    }

    static func deleteCollection(
        _ collectionID: UUID,
        in state: inout V02DomainState,
        now: Date = .now
    ) throws {
        guard state.collections.contains(where: { $0.id == collectionID }) else {
            throw V02DomainError.collectionNotFound
        }

        let deletedInspirations = state.inspirations
            .filter { $0.collectionID == collectionID }
            .map { inspiration -> V02Inspiration in
                var independent = inspiration
                independent.collectionID = nil
                independent.cardFlowState = .visible
                return independent
            }
        state.inspirations.removeAll { $0.collectionID == collectionID }
        state.trash.append(contentsOf: deletedInspirations.map {
            .init(id: UUID(), object: .inspiration($0), deletedAt: now)
        })
        state.rounds.removeAll { $0.collectionID == collectionID }
        state.collections.removeAll { $0.id == collectionID }
    }

    static func restoreTrash(
        _ entryID: UUID,
        in state: inout V02DomainState,
        now: Date = .now
    ) throws {
        guard let index = state.trash.firstIndex(where: { $0.id == entryID }) else {
            throw V02DomainError.trashEntryNotFound
        }
        let entry = state.trash.remove(at: index)
        switch entry.object {
        case .inspiration(var inspiration):
            guard !state.inspirations.contains(where: { $0.id == inspiration.id }) else {
                throw V02DomainError.inspirationNotFound
            }
            inspiration.collectionID = nil
            inspiration.cardFlowState = .visible
            inspiration.updatedAt = now
            state.inspirations.append(inspiration)
        case .receipt(let receipt):
            guard !state.receipts.contains(where: { $0.id == receipt.id }) else {
                throw V02DomainError.roundNotFound
            }
            state.receipts.append(receipt)
        }
    }

    static func permanentlyDeleteTrash(
        _ entryIDs: Set<UUID>,
        in state: inout V02DomainState
    ) throws {
        guard entryIDs.allSatisfy({ target in state.trash.contains(where: { $0.id == target }) }) else {
            throw V02DomainError.trashEntryNotFound
        }
        state.trash.removeAll { entryIDs.contains($0.id) }
    }
}
