import XCTest
@testable import App

@MainActor
final class AttachmentImporterTests: XCTestCase {
    func testOversizedFileIsRejectedBeforeImport() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("NOTE1-Oversized-\(UUID().uuidString).bin")
        XCTAssertTrue(FileManager.default.createFile(atPath: url.path, contents: nil))
        defer { try? FileManager.default.removeItem(at: url) }

        let handle = try FileHandle(forWritingTo: url)
        try handle.truncate(
            atOffset: UInt64(NoteStore.maximumAttachmentSize + 1)
        )
        try handle.close()

        XCTAssertThrowsError(try AttachmentImporter.input(from: url)) { error in
            guard case NoteStoreError.attachmentTooLarge = error else {
                return XCTFail("应返回附件过大错误，实际为：\(error)")
            }
        }
    }
}
