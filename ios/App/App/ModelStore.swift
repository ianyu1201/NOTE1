import Foundation

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

// MARK: - V0.2 domain foundation

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
        let trimmedName = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        let collectionName = trimmedName.flatMap { $0.isEmpty ? nil : $0 } ?? defaultName
        let collection = V02ThinkingCollection(id: UUID(), name: collectionName, createdAt: now, currentRoundID: nil)
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
