import Foundation
import UniformTypeIdentifiers

@MainActor
enum AttachmentImporter {
    static func input(from url: URL) throws -> AttachmentInput {
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let values = try url.resourceValues(forKeys: [.fileSizeKey, .contentTypeKey])
        if let fileSize = values.fileSize,
           fileSize > NoteStore.maximumAttachmentSize {
            throw NoteStoreError.attachmentTooLarge(name: url.lastPathComponent)
        }

        return AttachmentInput(
            name: url.lastPathComponent,
            mimeType: values.contentType?.preferredMIMEType
                ?? "application/octet-stream",
            data: try Data(contentsOf: url)
        )
    }
}
