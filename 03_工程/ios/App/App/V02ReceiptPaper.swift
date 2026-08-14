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

enum V02ReceiptTypographyPolicy {
    static let sequenceMarkerMaximumScale: CGFloat = 1.4
    static let sequenceMarkerWidth: CGFloat = 24
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
    var body: some View {
        VStack(alignment: .leading, spacing: isPreview ? 10 : 16) {
            header
            V02ThermalReceiptRule(style: .double)
            if resolvedTemplate == .film {
                filmContent
            } else {
                classicContent
            }
            V02ThermalReceiptRule(style: .double)
            VStack(spacing: 3) {
                Text("构思小票 · 本机快照")
                Text("本轮构思已结束 · \(receipt.snapshot.members.count) 条灵感")
            }
            .noteFont(size: 11, weight: .medium, design: .monospaced, relativeTo: .caption)
            .foregroundStyle(NoteTheme.receiptSecondaryInk)
            .frame(maxWidth: .infinity, alignment: .center)
            .multilineTextAlignment(.center)
        }
        .padding(.horizontal, isPreview ? 20 : 24)
        .padding(.bottom, isPreview ? 18 : 24)
        .padding(.top, isPreview ? 42 : 24)
        .frame(minHeight: minimumHeight ?? (isPreview ? 258 : nil), alignment: .topLeading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(NoteTheme.receiptInk)
        .background(paperSurface)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(resolvedTemplate.rawValue)，\(receipt.snapshot.collectionName)，\(receipt.snapshot.members.count) 条灵感")
    }

    private var header: some View {
        VStack(spacing: isPreview ? 3 : 5) {
            Text("NOTE1")
                .noteFont(size: isPreview ? 23 : 30, weight: .black, design: .monospaced, relativeTo: .title2)
                .tracking(isPreview ? 2.4 : 3.2)
            Text("构 思 小 票")
                .noteFont(size: 11, weight: .bold, design: .monospaced, relativeTo: .caption)
            Text(receipt.snapshot.collectionName)
                .noteFont(size: isPreview ? 17 : 22, weight: .bold, design: .monospaced, relativeTo: .headline)
                .lineLimit(isPreview ? 1 : nil)
            Text("\(receipt.statistics.roundTitle) · \(resolvedTemplate.rawValue)")
                .noteFont(size: 11, weight: .medium, design: .monospaced, relativeTo: .caption)
                .foregroundStyle(NoteTheme.receiptSecondaryInk)
            Text(receipt.snapshot.endedAt.formatted(date: .numeric, time: .shortened))
                .noteFont(size: 11, design: .monospaced, relativeTo: .caption)
                .foregroundStyle(NoteTheme.receiptSecondaryInk)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .multilineTextAlignment(.center)
    }

    private var classicContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            receiptSummary
            V02ThermalReceiptRule()
            memberTimeline
            attachmentSummary
            V02ThermalReceiptRule()
            receiptMetrics
        }
    }

    private var filmContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            V02ReceiptPhotoStrip(resources: photoResources, store: store, compact: isPreview)
            receiptSummary
            V02ThermalReceiptRule()
            memberTimeline
            attachmentSummary
            V02ThermalReceiptRule()
            receiptMetrics
        }
    }

    private var receiptSummary: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("本轮构思")
                    .fontWeight(.bold)
                Spacer(minLength: 8)
                Text(receipt.statistics.duration.formattedDuration)
                    .fontWeight(.bold)
            }
            Text("\(receipt.snapshot.startedAt.formatted(date: .numeric, time: .shortened)) – \(receipt.snapshot.endedAt.formatted(date: .numeric, time: .shortened))")
                .monospacedDigit()
        }
        .noteFont(size: 11, design: .monospaced, relativeTo: .caption)
    }

    private var memberTimeline: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("灵感时间线")
                    .noteFont(size: 13, weight: .bold, design: .monospaced, relativeTo: .subheadline)
                Spacer()
                Text("共 \(receipt.snapshot.members.count) 条")
                    .noteFont(size: 11, design: .monospaced, relativeTo: .caption)
                    .foregroundStyle(NoteTheme.receiptSecondaryInk)
            }
            if receipt.snapshot.members.isEmpty {
                Text("这一轮构思留下了一张可以带走的存根。")
                    .noteFont(size: isPreview ? 14 : 16, design: .monospaced, relativeTo: .body)
            } else {
                ForEach(Array(receipt.snapshot.members.enumerated()), id: \.element.inspirationID) { offset, member in
                    HStack(alignment: .top, spacing: 8) {
                        Text(String(format: "%02d", offset + 1))
                            .noteFontCapped(
                                size: 10,
                                maximumScale: V02ReceiptTypographyPolicy.sequenceMarkerMaximumScale,
                                weight: .bold,
                                design: .monospaced,
                                relativeTo: .caption
                            )
                            .foregroundStyle(NoteTheme.receiptSecondaryInk)
                            .frame(width: V02ReceiptTypographyPolicy.sequenceMarkerWidth, alignment: .leading)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(member.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "未命名灵感" : member.text)
                                .noteFont(size: isPreview ? 13 : 16, design: .monospaced, relativeTo: .body)
                                .lineSpacing(isPreview ? 2 : 4)
                            if !member.attachments.isEmpty {
                                Text("\(member.attachments.count) 个附件")
                                    .noteFont(size: 10, design: .monospaced, relativeTo: .caption)
                                    .foregroundStyle(NoteTheme.receiptSecondaryInk)
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
                        .noteFont(size: 13, weight: .bold, design: .monospaced, relativeTo: .subheadline)
                    Spacer()
                    Text("共 \(attachments.count) 个")
                        .noteFont(size: 11, design: .monospaced, relativeTo: .caption)
                        .foregroundStyle(NoteTheme.receiptSecondaryInk)
                }
                HStack(spacing: 7) {
                    ForEach(Array(attachments.prefix(4).enumerated()), id: \.offset) { _, attachment in
                        Image(systemName: attachmentSymbol(for: attachment))
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(NoteTheme.receiptSecondaryInk)
                            .frame(width: 34, height: 34)
                            .background(NoteTheme.receiptInk.opacity(0.045), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    }
                }
            }
        }
    }

    private var receiptMetrics: some View {
        VStack(alignment: .leading, spacing: 5) {
            metricRow(label: "灵感", value: "\(receipt.statistics.inspirationCount) 条")
            metricRow(label: "附件", value: "\(receipt.statistics.attachmentCount) 个")
            metricRow(label: "最终文字", value: "\(receipt.statistics.finalTextCount) 字")
            metricRow(label: "有效编辑", value: "\(receipt.statistics.effectiveEditCount) 次")
        }
        .noteFont(size: 12, design: .monospaced, relativeTo: .caption)
        .monospacedDigit()
    }

    private func metricRow(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
            Spacer(minLength: 12)
            Text(value)
                .fontWeight(.semibold)
        }
    }

    private func attachmentSymbol(for attachment: V02ReceiptSnapshot.Attachment) -> String {
        if attachment.mimeType.hasPrefix("image/") { return "photo" }
        if attachment.mimeType.hasPrefix("audio/") { return "waveform" }
        if attachment.mimeType == "application/pdf" { return "doc.richtext" }
        return "doc"
    }

    private var paperSurface: some View {
        V02ReceiptPaperSurface(strokeOpacity: isPreview ? 0.9 : 1)
    }
}

/// A paper-only surface shared by previews and full receipt reading. The
/// texture is deliberately generated from fixed arithmetic rather than an
/// image asset so every render stays deterministic and cheap.
struct V02ReceiptPaperSurface: View {
    var strokeOpacity: Double = 1

    var body: some View {
        V02ReceiptPaperShape()
            .fill(V04ObjectTransitionSurfacePolicy.style(for: V04ObjectTransitionSurfacePolicy.receiptObject))
            .overlay {
                V02ReceiptPaperTexture()
                    .clipShape(V02ReceiptPaperShape())
            }
            .overlay {
                V02ReceiptPaperShape()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.018),
                                .clear,
                                NoteTheme.receiptInk.opacity(0.008),
                                .clear,
                                Color.white.opacity(0.012)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .clipShape(V02ReceiptPaperShape())
            }
            .overlay {
                V02ReceiptPaperShape()
                    .stroke(NoteTheme.receiptDivider.opacity(strokeOpacity), lineWidth: 1)
            }
            .shadow(color: NoteTheme.receiptInk.opacity(0.035), radius: 2, y: 1)
            .shadow(color: NoteTheme.receiptInk.opacity(0.09), radius: 12, y: 7)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

private struct V02ReceiptPaperTexture: View {
    var body: some View {
        Canvas(opaque: false, colorMode: .linear, rendersAsynchronously: false) { context, size in
            guard size.width > 0, size.height > 0 else { return }

            var horizontalFibers = Path()
            let rowSpacing: CGFloat = 14
            let rowCount = Int(size.height / rowSpacing) + 2
            for row in 0..<rowCount {
                let y = CGFloat(row) * rowSpacing + CGFloat((row * 7) % 5) - 1
                var x = CGFloat((row * 17) % 23) - 12
                var segment = 0
                while x < size.width {
                    let length = 17 + CGFloat((row * 11 + segment * 7) % 19)
                    let yDrift = CGFloat((row + segment * 3) % 3) - 1
                    horizontalFibers.move(to: CGPoint(x: x, y: y + yDrift))
                    horizontalFibers.addLine(to: CGPoint(x: min(x + length, size.width), y: y + yDrift))
                    x += length + 13 + CGFloat((row * 5 + segment * 11) % 17)
                    segment += 1
                }
            }
            context.stroke(
                horizontalFibers,
                with: .color(NoteTheme.receiptInk.opacity(0.018)),
                style: StrokeStyle(lineWidth: 0.35, lineCap: .round)
            )

            var verticalFibers = Path()
            let columnSpacing: CGFloat = 31
            let columnCount = Int(size.width / columnSpacing) + 2
            for column in 0..<columnCount {
                let x = CGFloat(column) * columnSpacing + CGFloat((column * 13) % 11) - 5
                var y = CGFloat((column * 19) % 27) - 16
                var segment = 0
                while y < size.height {
                    let length = 11 + CGFloat((column * 7 + segment * 5) % 15)
                    verticalFibers.move(to: CGPoint(x: x, y: y))
                    verticalFibers.addLine(to: CGPoint(x: x, y: min(y + length, size.height)))
                    y += length + 35 + CGFloat((column * 3 + segment * 13) % 21)
                    segment += 1
                }
            }
            context.stroke(
                verticalFibers,
                with: .color(NoteTheme.receiptInk.opacity(0.010)),
                style: StrokeStyle(lineWidth: 0.3, lineCap: .round)
            )
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// 连续齿边的票据轮廓。它只定义纸张边缘，不承载任何图标语义。
struct V02ReceiptPaperShape: Shape {
    func path(in rect: CGRect) -> Path {
        let corner: CGFloat = 8
        let tooth: CGFloat = 9
        let count = max(8, Int((rect.width - corner * 2) / tooth))
        let spacing = (rect.width - corner * 2) / CGFloat(count)
        var path = Path()
        path.move(to: CGPoint(x: corner, y: 0))
        for item in 0..<count {
            let x = corner + CGFloat(item) * spacing
            path.addQuadCurve(to: CGPoint(x: x + spacing, y: 0), control: CGPoint(x: x + spacing / 2, y: 2.8))
        }
        path.addQuadCurve(to: CGPoint(x: rect.width, y: corner), control: CGPoint(x: rect.width, y: 0))
        path.addLine(to: CGPoint(x: rect.width, y: rect.height - corner))
        path.addQuadCurve(to: CGPoint(x: rect.width - corner, y: rect.height), control: CGPoint(x: rect.width, y: rect.height))
        for item in stride(from: count - 1, through: 0, by: -1) {
            let x = corner + CGFloat(item) * spacing
            path.addQuadCurve(to: CGPoint(x: x, y: rect.height), control: CGPoint(x: x + spacing / 2, y: rect.height - 2.8))
        }
        path.addQuadCurve(to: CGPoint(x: 0, y: rect.height - corner), control: CGPoint(x: 0, y: rect.height))
        path.addLine(to: CGPoint(x: 0, y: corner))
        path.addQuadCurve(to: CGPoint(x: corner, y: 0), control: CGPoint(x: 0, y: 0))
        return path
    }
}

enum V02ThermalReceiptRuleStyle: Equatable { case double, dashed }

struct V02ThermalReceiptRule: View {
    var style: V02ThermalReceiptRuleStyle = .dashed

    var body: some View {
        Group {
            if style == .double {
                VStack(spacing: 3) {
                    Rectangle().frame(height: 1.5)
                    Rectangle().frame(height: 0.75)
                }
                .foregroundStyle(NoteTheme.receiptInk.opacity(0.86))
            } else {
                GeometryReader { proxy in
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: 0.5))
                        path.addLine(to: CGPoint(x: proxy.size.width, y: 0.5))
                    }
                    .stroke(
                        NoteTheme.receiptSecondaryInk.opacity(0.58),
                        style: StrokeStyle(lineWidth: 1, lineCap: .butt, dash: [5, 4])
                    )
                }
            }
        }
        .frame(height: style == .double ? 5.25 : 1)
        .accessibilityHidden(true)
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
            .background(NoteTheme.receiptInk.opacity(0.94), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(Color.white.opacity(0.22), lineWidth: 1)
            }
        }
    }
}
