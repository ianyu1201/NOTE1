import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct V02BackupPayload: Codable, Sendable {
    static let currentVersion = 1

    let version: Int
    let exportedAt: Date
    let state: V02DomainState
    let resources: [V02BackupResource]

    init(
        version: Int = Self.currentVersion,
        exportedAt: Date = .now,
        state: V02DomainState,
        resources: [V02BackupResource]
    ) {
        self.version = version
        self.exportedAt = exportedAt
        self.state = state
        self.resources = resources
    }
}

struct V02BackupResource: Codable, Sendable {
    let metadata: V02AttachmentResource
    let data: Data
}

enum V02BackupError: LocalizedError {
    case archiveTooLarge
    case unsupportedVersion(Int)
    case invalidArchive(String)
    case missingResource(String)
    case restoreFailed(String)

    var errorDescription: String? {
        switch self {
        case .archiveTooLarge:
            "备份文件超过 NOTE1 当前支持的 512 MB。"
        case .unsupportedVersion(let version):
            "这个 V0.2 备份来自不兼容的版本（\(version)）。"
        case .invalidArchive(let message):
            "V0.2 备份文件无效：\(message)"
        case .missingResource(let filename):
            "附件“\(filename)”不存在，未生成不完整备份。"
        case .restoreFailed(let message):
            "恢复失败，原有本机数据已保留：\(message)"
        }
    }
}

enum V02BackupService {
    static let maximumArchiveSize = 512 * 1_024 * 1_024

    static func encode(_ payload: V02BackupPayload) throws -> Data {
        try validate(payload)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(payload)
        guard data.count <= maximumArchiveSize else { throw V02BackupError.archiveTooLarge }
        return data
    }

    static func decode(_ data: Data) throws -> V02BackupPayload {
        guard data.count <= maximumArchiveSize else { throw V02BackupError.archiveTooLarge }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let payload: V02BackupPayload
        do {
            payload = try decoder.decode(V02BackupPayload.self, from: data)
        } catch {
            throw V02BackupError.invalidArchive("无法读取文件内容。")
        }
        try validate(payload)
        return payload
    }

    private static func validate(_ payload: V02BackupPayload) throws {
        guard payload.version == V02BackupPayload.currentVersion else {
            throw V02BackupError.unsupportedVersion(payload.version)
        }
        guard payload.state.version == V02DomainState.currentVersion else {
            throw V02BackupError.invalidArchive("数据模型版本不兼容。")
        }
        let metadata = payload.resources.map(\.metadata)
        let resourceIDs = metadata.map(\.id)
        guard Set(resourceIDs).count == resourceIDs.count else {
            throw V02BackupError.invalidArchive("存在重复的附件 ID。")
        }
        guard Set(payload.state.resources.map(\.id)) == Set(resourceIDs) else {
            throw V02BackupError.invalidArchive("附件元数据与数据内容不一致。")
        }
        let resourceIDSet = Set(resourceIDs)
        let referencedIDs = Set(
            payload.state.inspirations.flatMap(\.resourceIDs) +
            payload.state.receipts.flatMap { $0.snapshot.members.flatMap(\.resourceIDs) } +
            payload.state.trash.flatMap { entry in
                switch entry.object {
                case .inspiration(let inspiration): inspiration.resourceIDs
                case .receipt(let receipt): receipt.snapshot.members.flatMap(\.resourceIDs)
                }
            }
        )
        guard referencedIDs.isSubset(of: resourceIDSet) else {
            throw V02BackupError.invalidArchive("有内容引用了不存在的附件。")
        }
        var paths = Set<String>()
        var totalSize = 0
        for resource in payload.resources {
            guard resource.metadata.size == Int64(resource.data.count) else {
                throw V02BackupError.invalidArchive("附件大小信息不一致。")
            }
            guard resource.data.count <= V02Store.maximumResourceSize else {
                throw V02BackupError.invalidArchive("单个附件超过 V0.2 上限。")
            }
            let safePath = URL(fileURLWithPath: resource.metadata.relativePath).lastPathComponent
            guard !safePath.isEmpty, safePath == resource.metadata.relativePath,
                  safePath != ".", safePath != "..", paths.insert(safePath).inserted else {
                throw V02BackupError.invalidArchive("附件路径不安全或重复。")
            }
            totalSize += resource.data.count
            guard totalSize <= maximumArchiveSize else { throw V02BackupError.archiveTooLarge }
        }
    }
}

extension UTType {
    static let note1V02Backup = UTType(
        exportedAs: "com.yusiyuan.note1.v02-backup",
        conformingTo: .json
    )
}

struct V02BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.note1V02Backup, .json] }
    let data: Data

    init(data: Data = Data()) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw V02BackupError.invalidArchive("文件没有可读取的内容。")
        }
        self.data = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
