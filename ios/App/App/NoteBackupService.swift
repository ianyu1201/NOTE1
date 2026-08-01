import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct NoteBackupPayload: Codable, Equatable, Sendable {
    static let currentVersion = 1

    var version: Int
    var exportedAt: Date
    var ideas: [Idea]
    var groups: [IdeaGroup]
    var attachments: [NoteBackupAttachment]

    init(
        version: Int = Self.currentVersion,
        exportedAt: Date = Date(),
        ideas: [Idea],
        groups: [IdeaGroup],
        attachments: [NoteBackupAttachment]
    ) {
        self.version = version
        self.exportedAt = exportedAt
        self.ideas = ideas
        self.groups = groups
        self.attachments = attachments
    }
}

struct NoteBackupAttachment: Codable, Equatable, Sendable {
    var metadata: Attachment
    var data: Data
}

enum NoteBackupError: LocalizedError {
    case archiveTooLarge
    case unsupportedVersion(Int)
    case invalidArchive(String)
    case missingAttachment(String)
    case restoreFailed(String)
    case restoreRecoveryFailed

    var errorDescription: String? {
        switch self {
        case .archiveTooLarge:
            "备份文件超过 NOTE1 当前支持的 512 MB。"
        case .unsupportedVersion(let version):
            "这个备份来自不兼容的版本（\(version)）。"
        case .invalidArchive(let message):
            "备份文件无效：\(message)"
        case .missingAttachment(let name):
            "附件“\(name)”不存在，未生成不完整备份。"
        case .restoreFailed(let message):
            "恢复失败，原数据已保留：\(message)"
        case .restoreRecoveryFailed:
            "恢复失败且未能自动回滚。为保护本机数据，NOTE1 已暂停写入；请不要删除 App。"
        }
    }
}

protocol NoteBackupServicing: Sendable {
    func encode(_ payload: NoteBackupPayload) throws -> Data
    func decode(_ data: Data) throws -> NoteBackupPayload
}

struct JSONNoteBackupService: NoteBackupServicing {
    static let maximumArchiveSize = 512 * 1_024 * 1_024
    static let maximumAttachmentSize = 25 * 1_024 * 1_024

    func encode(_ payload: NoteBackupPayload) throws -> Data {
        try validate(payload)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(payload)
        guard data.count <= Self.maximumArchiveSize else {
            throw NoteBackupError.archiveTooLarge
        }
        return data
    }

    func decode(_ data: Data) throws -> NoteBackupPayload {
        guard data.count <= Self.maximumArchiveSize else {
            throw NoteBackupError.archiveTooLarge
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let payload: NoteBackupPayload
        do {
            payload = try decoder.decode(NoteBackupPayload.self, from: data)
        } catch {
            throw NoteBackupError.invalidArchive("无法读取文件内容。")
        }
        try validate(payload)
        return payload
    }

    private func validate(_ payload: NoteBackupPayload) throws {
        guard payload.version == NoteBackupPayload.currentVersion else {
            throw NoteBackupError.unsupportedVersion(payload.version)
        }

        let ideaIDs = payload.ideas.map(\.id)
        let groupIDs = payload.groups.map(\.id)
        let attachmentIDs = payload.attachments.map(\.metadata.id)
        guard Set(ideaIDs).count == ideaIDs.count else {
            throw NoteBackupError.invalidArchive("存在重复的灵感 ID。")
        }
        guard Set(groupIDs).count == groupIDs.count else {
            throw NoteBackupError.invalidArchive("存在重复的灵感组 ID。")
        }
        guard Set(ideaIDs).isDisjoint(with: Set(groupIDs)) else {
            throw NoteBackupError.invalidArchive("灵感和灵感组使用了相同的 ID。")
        }
        guard Set(attachmentIDs).count == attachmentIDs.count else {
            throw NoteBackupError.invalidArchive("存在重复的附件 ID。")
        }

        let ideaIDSet = Set(ideaIDs)
        let groupsByID = Dictionary(
            uniqueKeysWithValues: payload.groups.map { ($0.id, $0) }
        )
        for idea in payload.ideas {
            guard let groupID = idea.groupID else { continue }
            guard let group = groupsByID[groupID] else {
                throw NoteBackupError.invalidArchive("灵感引用了不存在的灵感组。")
            }
            guard idea.status == group.status else {
                throw NoteBackupError.invalidArchive("灵感组和组内灵感状态不一致。")
            }
        }

        var paths = Set<String>()
        var totalAttachmentBytes = 0
        for entry in payload.attachments {
            let attachment = entry.metadata
            guard ideaIDSet.contains(attachment.ideaID) else {
                throw NoteBackupError.invalidArchive("附件引用了不存在的灵感。")
            }
            guard attachment.size == Int64(entry.data.count) else {
                throw NoteBackupError.invalidArchive("附件大小信息不一致。")
            }
            guard entry.data.count <= Self.maximumAttachmentSize else {
                throw NoteStoreError.attachmentTooLarge(name: attachment.name)
            }
            let safeName = URL(fileURLWithPath: attachment.relativePath)
                .lastPathComponent
            guard !safeName.isEmpty,
                  safeName == attachment.relativePath,
                  safeName != ".",
                  safeName != ".." else {
                throw NoteBackupError.invalidArchive("附件路径不安全。")
            }
            guard paths.insert(safeName).inserted else {
                throw NoteBackupError.invalidArchive("附件路径重复。")
            }
            totalAttachmentBytes += entry.data.count
            guard totalAttachmentBytes <= Self.maximumArchiveSize else {
                throw NoteBackupError.archiveTooLarge
            }
        }
    }
}

extension UTType {
    static let note1Backup = UTType(
        exportedAs: "com.yusiyuan.note1.backup",
        conformingTo: .json
    )
}

struct NoteBackupDocument: FileDocument {
    static var readableContentTypes: [UTType] {
        [.note1Backup, .json]
    }

    var data: Data

    init(data: Data = Data()) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw NoteBackupError.invalidArchive("文件没有可读取的内容。")
        }
        self.data = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
