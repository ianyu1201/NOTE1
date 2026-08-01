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
