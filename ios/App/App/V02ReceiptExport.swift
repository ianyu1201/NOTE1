import Foundation
import UIKit

enum V02ReceiptExport {
    static func plainText(for receipt: V02Receipt) -> String {
        let header = "NOTE1 · \(receipt.id.uuidString.prefix(8))\n\(receipt.snapshot.collectionName)\n\(receipt.snapshot.startedAt.formatted(date: .numeric, time: .shortened)) – \(receipt.snapshot.endedAt.formatted(date: .numeric, time: .shortened))\n\(statistics(for: receipt))\n"
        let content = receipt.snapshot.members.enumerated().map { index, member in
            "\(index + 1). \(member.text)"
        }.joined(separator: "\n\n")
        return "\(header)\n时间路线\n\(timeline(for: receipt))\n\n\(content)"
    }

    static func markdown(for receipt: V02Receipt) -> String {
        let header = "# \(receipt.snapshot.collectionName)\n\n- 编号：NOTE1-\(receipt.id.uuidString.prefix(8))\n- 开始：\(receipt.snapshot.startedAt.formatted(date: .numeric, time: .shortened))\n- 结束：\(receipt.snapshot.endedAt.formatted(date: .numeric, time: .shortened))\n- \(statistics(for: receipt))\n"
        let content = receipt.snapshot.members.enumerated().map { index, member in
            "## \(index + 1)\n\n\(member.text)"
        }.joined(separator: "\n\n")
        return "\(header)\n## 时间路线\n\n\(timeline(for: receipt))\n\n\(content)"
    }

    /// A4 portrait export. The receipt snapshot is the only content source;
    /// the optional resolver supplies local attachment files without making
    /// the export layer depend on a particular store directory.
    static func pdfData(
        for receipt: V02Receipt,
        resourceURL: ((String) -> URL?)? = nil
    ) -> Data {
        let page = CGRect(x: 0, y: 0, width: 595, height: 842)
        let inset: CGFloat = 72
        let renderer = UIGraphicsPDFRenderer(bounds: page)
        return renderer.pdfData { context in
            var writer = PDFPageWriter(context: context, page: page, inset: inset)
            writer.beginPage()
            writer.drawText("NOTE1", font: .boldSystemFont(ofSize: 12), spacingAfter: 16)
            writer.drawText(receipt.snapshot.collectionName, font: .boldSystemFont(ofSize: 21), spacingAfter: 10)
            writer.drawText(statistics(for: receipt), font: .systemFont(ofSize: 12), color: .secondaryLabel, spacingAfter: 18)
            writer.drawText("时间路线", font: .boldSystemFont(ofSize: 14), spacingAfter: 5)
            for event in receipt.snapshot.events {
                writer.drawText(
                    "· \(event.occurredAt.formatted(date: .omitted, time: .shortened)) \(eventDescription(event))",
                    font: .systemFont(ofSize: 11),
                    color: .secondaryLabel,
                    spacingAfter: 3
                )
            }
            writer.drawRule(spacing: 16)
            for (index, member) in receipt.snapshot.members.enumerated() {
                writer.drawText(
                    "\(index + 1). \(member.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "未命名灵感" : member.text)",
                    font: .boldSystemFont(ofSize: 15),
                    spacingAfter: 8
                )
                if member.attachments.isEmpty {
                    writer.drawText("无附件", font: .systemFont(ofSize: 11), color: .secondaryLabel, spacingAfter: 14)
                } else {
                    for attachment in member.attachments {
                        writer.drawAttachment(attachment, resourceURL: resourceURL, spacingAfter: 10)
                    }
                }
                writer.drawRule(spacing: 14)
            }
        }
    }

    private static func eventDescription(_ event: V02RoundEvent) -> String {
        switch event.kind {
        case .started: return "开始构思"
        case .memberAdded: return "加入灵感"
        case .memberRemoved: return "移出灵感"
        case .inspirationEdited: return "编辑灵感"
        case .ended: return "结束本轮构思"
        }
    }

    private static func statistics(for receipt: V02Receipt) -> String {
        let duration = max(0, Int(receipt.snapshot.endedAt.timeIntervalSince(receipt.snapshot.startedAt)) / 60)
        let attachments = receipt.snapshot.members.flatMap(\.resourceIDs).count
        let characters = receipt.snapshot.members.reduce(0) { $0 + $1.text.count }
        return "本轮构思已结束，\(receipt.snapshot.members.count) 条灵感 · \(duration) 分钟 · 有效编辑 \(receipt.snapshot.effectiveEditCount) 次 · 附件 \(attachments) 个 · 文字 \(characters) 字"
    }

    private static func timeline(for receipt: V02Receipt) -> String {
        receipt.snapshot.events.map { event in
            let action: String
            switch event.kind {
            case .started: action = "开始构思"
            case .memberAdded: action = "加入灵感"
            case .memberRemoved: action = "移出灵感"
            case .inspirationEdited: action = "编辑灵感"
            case .ended: action = "结束本轮构思"
            }
            return "- \(event.occurredAt.formatted(date: .omitted, time: .shortened)) \(action)"
        }.joined(separator: "\n")
    }
}

private struct PDFPageWriter {
    let context: UIGraphicsPDFRendererContext
    let page: CGRect
    let inset: CGFloat
    var y: CGFloat

    init(context: UIGraphicsPDFRendererContext, page: CGRect, inset: CGFloat) {
        self.context = context
        self.page = page
        self.inset = inset
        y = inset
    }

    var contentWidth: CGFloat { page.width - inset * 2 }
    var bottom: CGFloat { page.height - inset }

    mutating func beginPage() {
        context.beginPage()
        y = inset
    }

    mutating func drawText(
        _ text: String,
        font: UIFont,
        color: UIColor = .label,
        spacingAfter: CGFloat
    ) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color
        ]
        var remaining = text
        while !remaining.isEmpty {
            let availableHeight = bottom - y
            if availableHeight < font.lineHeight {
                beginPage()
                continue
            }
            let chunk = fittingPrefix(of: remaining, attributes: attributes, maxHeight: availableHeight)
            let measured = measuredHeight(for: chunk, attributes: attributes, minimum: font.lineHeight)
            (chunk as NSString).draw(
                in: CGRect(x: inset, y: y, width: contentWidth, height: measured),
                withAttributes: attributes
            )
            y += measured
            remaining.removeFirst(chunk.count)
            if !remaining.isEmpty {
                y += 2
            }
        }
        y += spacingAfter
    }

    mutating func drawRule(spacing: CGFloat) {
        ensureSpace(1 + spacing)
        UIColor.separator.setStroke()
        let path = UIBezierPath()
        path.move(to: CGPoint(x: inset, y: y))
        path.addLine(to: CGPoint(x: page.width - inset, y: y))
        path.lineWidth = 0.5
        path.stroke()
        y += 1 + spacing
    }

    mutating func drawAttachment(
        _ attachment: V02ReceiptSnapshot.Attachment,
        resourceURL: ((String) -> URL?)?,
        spacingAfter: CGFloat
    ) {
        let metadata = "附件：\(attachment.filename) · \(attachment.mimeType) · \(ByteCountFormatter.string(fromByteCount: attachment.size, countStyle: .file))"
        drawText(metadata, font: .systemFont(ofSize: 10), color: .secondaryLabel, spacingAfter: 5)
        guard attachment.mimeType.hasPrefix("image/"),
              let url = resourceURL?(attachment.relativePath),
              let image = UIImage(contentsOfFile: url.path),
              image.size.width > 0,
              image.size.height > 0 else {
            y += spacingAfter
            return
        }
        let maxHeight: CGFloat = 240
        let scale = min(contentWidth / image.size.width, maxHeight / image.size.height, 1)
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        ensureSpace(size.height + spacingAfter)
        image.draw(in: CGRect(x: inset, y: y, width: size.width, height: size.height))
        y += size.height + spacingAfter
    }

    private mutating func ensureSpace(_ requiredHeight: CGFloat) {
        guard y + requiredHeight > bottom else { return }
        beginPage()
    }

    private func measuredHeight(
        for text: String,
        attributes: [NSAttributedString.Key: Any],
        minimum: CGFloat
    ) -> CGFloat {
        max(
            (text as NSString).boundingRect(
                with: CGSize(width: contentWidth, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: attributes,
                context: nil
            ).height,
            minimum
        )
    }

    private func fittingPrefix(
        of text: String,
        attributes: [NSAttributedString.Key: Any],
        maxHeight: CGFloat
    ) -> String {
        let characters = Array(text)
        var low = 1
        var high = characters.count
        var best = String(characters.prefix(1))
        while low <= high {
            let middle = (low + high) / 2
            let candidate = String(characters.prefix(middle))
            if measuredHeight(for: candidate, attributes: attributes, minimum: 0) <= maxHeight {
                best = candidate
                low = middle + 1
            } else {
                high = middle - 1
            }
        }
        return best
    }
}
