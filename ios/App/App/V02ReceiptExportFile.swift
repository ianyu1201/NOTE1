import Foundation

enum V02ReceiptExportFormat: CaseIterable {
    case pdf
    case markdown
    case plainText

    var title: String {
        switch self {
        case .pdf: "导出 PDF"
        case .markdown: "导出 Markdown"
        case .plainText: "导出纯文本"
        }
    }

    var fileExtension: String {
        switch self {
        case .pdf: "pdf"
        case .markdown: "md"
        case .plainText: "txt"
        }
    }
}

enum V02ReceiptExportFile {
    static func write(
        _ receipt: V02Receipt,
        format: V02ReceiptExportFormat,
        resourceURL: ((String) -> URL?)? = nil
    ) throws -> URL {
        let name = safeFilename(receipt.snapshot.collectionName)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("NOTE1-\(name)-\(receipt.id.uuidString).\(format.fileExtension)")
        let data: Data
        switch format {
        case .pdf: data = V02ReceiptExport.pdfData(for: receipt, resourceURL: resourceURL)
        case .markdown: data = Data(V02ReceiptExport.markdown(for: receipt).utf8)
        case .plainText: data = Data(V02ReceiptExport.plainText(for: receipt).utf8)
        }
        try data.write(to: url, options: .atomic)
        return url
    }

    static func writePDFs(
        _ receipts: [V02Receipt],
        resourceURL: ((String) -> URL?)? = nil
    ) throws -> [URL] {
        try receipts.map { try write($0, format: .pdf, resourceURL: resourceURL) }
    }

    private static func safeFilename(_ value: String) -> String {
        let invalid = CharacterSet(charactersIn: "/:\\?%*|\"<>")
        let cleaned = value.components(separatedBy: invalid).joined(separator: "-")
        return cleaned.isEmpty ? "构思小票" : cleaned
    }
}
