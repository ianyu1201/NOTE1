import SwiftUI
import UIKit

enum V02ReceiptTemplate: String, CaseIterable, Identifiable {
    case classic = "经典票"
    case film = "胶卷票"

    var id: String { rawValue }

    static func recommended(for receipt: V02Receipt, resources: [V02AttachmentResource]) -> Self {
        let memberIDs = receipt.snapshot.members.map(\.resourceIDs)
        let photoCount = memberIDs.joined().filter { id in
            resources.first(where: { $0.id == id })?.mimeType.hasPrefix("image/") == true
        }.count
        let membersWithPhotos = memberIDs.filter { ids in
            ids.contains { id in resources.first(where: { $0.id == id })?.mimeType.hasPrefix("image/") == true }
        }.count
        return photoCount >= 3 || membersWithPhotos * 2 > memberIDs.count ? .film : .classic
    }
}

struct V02ReceiptPaper: View {
    enum Presentation { case preview, detail }

    @ObservedObject var store: V02Store
    let receipt: V02Receipt
    let template: V02ReceiptTemplate
    var presentation: Presentation = .preview
    var minimumHeight: CGFloat? = nil

    private var isPreview: Bool { presentation == .preview }
    private var resolvedTemplate: V02ReceiptTemplate {
        template == .film && photoResources.isEmpty ? .classic : template
    }
    private var photoResources: [V02AttachmentResource] {
        receipt.snapshot.members.flatMap(\.resourceIDs).compactMap { id in
            if let metadata = receipt.snapshot.members
                .flatMap(\.attachments)
                .first(where: { $0.id == id }),
               metadata.mimeType.hasPrefix("image/") {
                return V02AttachmentResource(
                    id: metadata.id,
                    source: metadata.source,
                    filename: metadata.filename,
                    mimeType: metadata.mimeType,
                    relativePath: metadata.relativePath,
                    size: metadata.size,
                    createdAt: metadata.createdAt
                )
            }
            guard let resource = store.state.resources.first(where: { $0.id == id }),
                  resource.mimeType.hasPrefix("image/") else { return nil }
            return resource
        }
    }
    private var memberText: String {
        receipt.snapshot.members
            .map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: isPreview ? 10 : 16) {
            header
            V02ReceiptPerforationLine()
            if resolvedTemplate == .film {
                filmContent
            } else {
                classicContent
            }
            V02ReceiptPerforationLine()
            HStack {
                Text("本轮构思已结束")
                Spacer()
                Text("\(receipt.snapshot.members.count) 条灵感")
            }
            .noteFont(size: 12, weight: .medium, relativeTo: .caption)
            .foregroundStyle(NoteTheme.secondaryInk)
        }
        .padding(.horizontal, isPreview ? 20 : 24)
        .padding(.bottom, isPreview ? 18 : 24)
        .padding(.top, isPreview ? 48 : 24)
        .frame(minHeight: minimumHeight ?? (isPreview ? 258 : nil), alignment: .topLeading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(paperSurface)
        .overlay { ticketNotches.clipShape(V02ReceiptPaperShape()) }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(resolvedTemplate.rawValue)，\(receipt.snapshot.collectionName)，\(receipt.snapshot.members.count) 条灵感")
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("NOTE1 · \(receipt.id.uuidString.prefix(6))")
                    .noteFont(size: 11, weight: .semibold, relativeTo: .caption)
                    .foregroundStyle(NoteTheme.secondaryInk)
                Text(receipt.snapshot.collectionName)
                    .noteFont(size: isPreview ? 22 : 28, weight: .semibold, design: .rounded, relativeTo: .title2)
                    .lineLimit(isPreview ? 1 : nil)
            }
            Spacer(minLength: 8)
            Text(resolvedTemplate.rawValue)
                .noteFont(size: 11, weight: .semibold, relativeTo: .caption)
                .foregroundStyle(NoteTheme.ink)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(NoteTheme.background.opacity(0.88), in: Capsule())
        }
    }

    private var classicContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            receiptSummary
            memberTimeline
            attachmentSummary
            receiptMetrics
        }
    }

    private var filmContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            V02ReceiptPhotoStrip(resources: photoResources, store: store, compact: isPreview)
            receiptSummary
            memberTimeline
            attachmentSummary
            receiptMetrics
        }
    }

    private var receiptSummary: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("回顾 · \(receipt.statistics.roundTitle)")
            Text("\(receipt.snapshot.startedAt.formatted(date: .numeric, time: .omitted)) – \(receipt.snapshot.endedAt.formatted(date: .numeric, time: .omitted))")
        }
        .noteFont(size: 11, relativeTo: .caption)
        .foregroundStyle(NoteTheme.secondaryInk)
    }

    private var memberTimeline: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("灵感时间线")
                    .noteFont(size: 13, weight: .semibold, relativeTo: .subheadline)
                Spacer()
                Text("共 \(receipt.snapshot.members.count) 条")
                    .noteFont(size: 11, relativeTo: .caption)
                    .foregroundStyle(NoteTheme.secondaryInk)
            }
            if receipt.snapshot.members.isEmpty {
                Text("这一轮构思留下了一张可以带走的存根。")
                    .noteFont(size: isPreview ? 14 : 16, relativeTo: .body)
            } else {
                ForEach(Array(receipt.snapshot.members.enumerated()), id: \.element.inspirationID) { offset, member in
                    HStack(alignment: .top, spacing: 8) {
                        Text(String(format: "%02d", offset + 1))
                            .noteFont(size: 10, weight: .semibold, relativeTo: .caption)
                            .foregroundStyle(NoteTheme.secondaryInk)
                            .frame(width: 20, alignment: .leading)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(member.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "未命名灵感" : member.text)
                                .noteFont(size: isPreview ? 13 : 16, relativeTo: .body)
                                .lineSpacing(isPreview ? 2 : 4)
                            if !member.attachments.isEmpty {
                                Text("\(member.attachments.count) 个附件")
                                    .noteFont(size: 10, relativeTo: .caption)
                                    .foregroundStyle(NoteTheme.secondaryInk)
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var attachmentSummary: some View {
        let attachments = receipt.snapshot.members.flatMap(\.attachments)
        if !attachments.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("附件")
                        .noteFont(size: 13, weight: .semibold, relativeTo: .subheadline)
                    Spacer()
                    Text("共 \(attachments.count) 个")
                        .noteFont(size: 11, relativeTo: .caption)
                        .foregroundStyle(NoteTheme.secondaryInk)
                }
                HStack(spacing: 7) {
                    ForEach(Array(attachments.prefix(4).enumerated()), id: \.offset) { _, attachment in
                        Image(systemName: attachmentSymbol(for: attachment))
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(NoteTheme.secondaryInk)
                            .frame(width: 34, height: 34)
                            .background(NoteTheme.background.opacity(0.62), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    }
                }
            }
        }
    }

    private var receiptMetrics: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("\(receipt.statistics.inspirationCount) 条灵感 · 附件 \(receipt.statistics.attachmentCount) 个 · 文字 \(receipt.statistics.finalTextCount) 字")
            Text("开始 \(receipt.snapshot.startedAt.formatted(date: .omitted, time: .shortened)) · 持续 \(receipt.statistics.duration.formattedDuration) · 有效编辑 \(receipt.statistics.effectiveEditCount) 次")
        }
        .noteFont(size: 13, relativeTo: .caption)
        .foregroundStyle(NoteTheme.secondaryInk)
    }

    private func attachmentSymbol(for attachment: V02ReceiptSnapshot.Attachment) -> String {
        if attachment.mimeType.hasPrefix("image/") { return "photo" }
        if attachment.mimeType.hasPrefix("audio/") { return "waveform" }
        if attachment.mimeType == "application/pdf" { return "doc.richtext" }
        return "doc"
    }

    private var paperSurface: some View {
        V02ReceiptPaperShape()
            .fill(NoteTheme.paper.opacity(isPreview ? 0.86 : 0.92))
            .overlay {
                V02ReceiptPaperShape()
                    .stroke(Color.white.opacity(isPreview ? 0.84 : 0.9), lineWidth: 1)
            }
            .shadow(color: NoteTheme.ink.opacity(0.13), radius: 18, y: 10)
    }

    private var ticketNotches: some View {
        GeometryReader { proxy in
            ZStack {
                Circle()
                    .fill(NoteTheme.background)
                    .frame(width: 14, height: 14)
                    .position(x: 0, y: proxy.size.height * 0.66)
                Circle()
                    .fill(NoteTheme.background)
                    .frame(width: 14, height: 14)
                    .position(x: proxy.size.width, y: proxy.size.height * 0.66)
            }
        }
        .allowsHitTesting(false)
    }
}

/// 连续齿边的票据轮廓。它只定义纸张边缘，不承载任何图标语义。
struct V02ReceiptPaperShape: Shape {
    func path(in rect: CGRect) -> Path {
        let corner: CGFloat = 18
        let tooth: CGFloat = 11
        let count = max(8, Int((rect.width - corner * 2) / tooth))
        let spacing = (rect.width - corner * 2) / CGFloat(count)
        var path = Path()
        path.move(to: CGPoint(x: corner, y: 0))
        for item in 0..<count {
            let x = corner + CGFloat(item) * spacing
            path.addQuadCurve(to: CGPoint(x: x + spacing, y: 0), control: CGPoint(x: x + spacing / 2, y: 3.5))
        }
        path.addQuadCurve(to: CGPoint(x: rect.width, y: corner), control: CGPoint(x: rect.width, y: 0))
        path.addLine(to: CGPoint(x: rect.width, y: rect.height - corner))
        path.addQuadCurve(to: CGPoint(x: rect.width - corner, y: rect.height), control: CGPoint(x: rect.width, y: rect.height))
        for item in stride(from: count - 1, through: 0, by: -1) {
            let x = corner + CGFloat(item) * spacing
            path.addQuadCurve(to: CGPoint(x: x, y: rect.height), control: CGPoint(x: x + spacing / 2, y: rect.height - 3.5))
        }
        path.addQuadCurve(to: CGPoint(x: 0, y: rect.height - corner), control: CGPoint(x: 0, y: rect.height))
        path.addLine(to: CGPoint(x: 0, y: corner))
        path.addQuadCurve(to: CGPoint(x: corner, y: 0), control: CGPoint(x: 0, y: 0))
        return path
    }
}

private struct V02ReceiptPerforationLine: View {
    var body: some View {
        Rectangle()
            .fill(NoteTheme.secondaryInk.opacity(0.36))
            .frame(height: 1)
            .overlay {
                HStack(spacing: 4) {
                    ForEach(0..<22, id: \.self) { _ in Circle().fill(Color.white.opacity(0.86)).frame(width: 3, height: 3) }
                }
            }
    }
}

private struct V02ReceiptPhotoStrip: View {
    let resources: [V02AttachmentResource]
    @ObservedObject var store: V02Store
    let compact: Bool

    var body: some View {
        if !resources.isEmpty {
            HStack(spacing: 6) {
                ForEach(resources.prefix(compact ? 3 : 6)) { resource in
                    if let image = UIImage(contentsOfFile: store.resourceURL(resource).path) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(maxWidth: .infinity, minHeight: compact ? 94 : 176, maxHeight: compact ? 94 : 176)
                            .clipped()
                    }
                }
            }
            .padding(6)
            .background(NoteTheme.ink.opacity(0.9), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        }
    }
}
