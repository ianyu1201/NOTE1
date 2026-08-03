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

    /// A4 portrait export. Text is drawn block by block and continues onto a
    /// new page before a block would overflow the printable content column.
    static func pdfData(for receipt: V02Receipt) -> Data {
        let page = CGRect(x: 0, y: 0, width: 595, height: 842)
        let inset: CGFloat = 72
        let renderer = UIGraphicsPDFRenderer(bounds: page)
        return renderer.pdfData { context in
            var y = inset
            context.beginPage()
            draw("NOTE1", font: .boldSystemFont(ofSize: 12), at: CGPoint(x: inset, y: y))
            y += 28
            draw(receipt.snapshot.collectionName, font: .boldSystemFont(ofSize: 21), at: CGPoint(x: inset, y: y))
            y += 32
            draw(statistics(for: receipt), font: .systemFont(ofSize: 12), at: CGPoint(x: inset, y: y))
            y += 30
            let timelineText = "时间路线：\n\(timeline(for: receipt))"
            let timelineRect = CGRect(x: inset, y: y, width: page.width - inset * 2, height: 100)
            (timelineText as NSString).draw(in: timelineRect, withAttributes: [.font: UIFont.systemFont(ofSize: 11), .foregroundColor: UIColor.secondaryLabel])
            y += 86
            for (index, member) in receipt.snapshot.members.enumerated() {
                let text = "\(index + 1). \(member.text)"
                let rect = CGRect(x: inset, y: y, width: page.width - inset * 2, height: 120)
                let height = (text as NSString).boundingRect(
                    with: CGSize(width: rect.width, height: .greatestFiniteMagnitude),
                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                    attributes: [.font: UIFont.systemFont(ofSize: 14)],
                    context: nil
                ).height + 20
                if y + height > page.height - inset {
                    context.beginPage()
                    y = inset
                }
                (text as NSString).draw(
                    in: CGRect(x: inset, y: y, width: rect.width, height: height),
                    withAttributes: [.font: UIFont.systemFont(ofSize: 14), .foregroundColor: UIColor.label]
                )
                y += height + 16
            }
        }
    }

    private static func draw(_ text: String, font: UIFont, at point: CGPoint) {
        (text as NSString).draw(at: point, withAttributes: [.font: font, .foregroundColor: UIColor.label])
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
