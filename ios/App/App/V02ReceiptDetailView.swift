import SwiftUI
import UIKit

/// The detail screen deliberately keeps the receipt as the primary object. It
/// is a long, scrollable paper rather than a generic white information list.
struct V02ReceiptDetailView: View {
    @ObservedObject var store: V02Store
    let receipt: V02Receipt
    let export: ((V02Receipt, V02ReceiptExportFormat) -> Void)?
    let onDelete: ((Set<UUID>) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var template: V02ReceiptTemplate
    @State private var error: UserFacingAlert?
    @State private var shareURLs: [URL] = []
    @State private var selectedPreview: ReceiptAttachment?
    @State private var selectedImage: ReceiptAttachment?
    @State private var searchQuery = ""
    @State private var isSearching = false
    @State private var isConfirmingDelete = false
    @FocusState private var searchFocused: Bool

    init(
        store: V02Store,
        receipt: V02Receipt,
        export: ((V02Receipt, V02ReceiptExportFormat) -> Void)? = nil,
        onDelete: ((Set<UUID>) -> Void)? = nil
    ) {
        self.store = store
        self.receipt = receipt
        self.export = export
        self.onDelete = onDelete
        _template = State(initialValue: V02ReceiptTemplate.recommended(for: receipt, resources: store.state.resources))
    }

    init(store: V02Store, receipt: V02Receipt) {
        self.init(store: store, receipt: receipt, export: nil, onDelete: nil)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                NoteTheme.background.ignoresSafeArea()
                ScrollView {
                    longTicket
                    .padding(.horizontal, 12)
                    .padding(.top, 12)
                    .padding(.bottom, 28)
                }
                .scrollIndicators(.hidden)
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle("小票详情")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "chevron.left") }
                        .accessibilityLabel("返回小票册")
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Menu("切换模板", systemImage: "rectangle.2.swap") {
                            ForEach(V02ReceiptTemplate.allCases) { item in
                                Button(item.rawValue) { template = item }
                            }
                        }
                        Button("在小票中查找", systemImage: "magnifyingglass") {
                            isSearching = true
                        }
                        Button("继续构思", systemImage: "arrow.counterclockwise") {
                            continueThinking()
                        }
                        .disabled(store.state.collections.first(where: { $0.id == receipt.collectionID })?.currentRoundID != nil)
                        Divider()
                        ForEach(V02ReceiptExportFormat.allCases, id: \.fileExtension) { format in
                            Button(format.title, systemImage: "arrow.down.doc") {
                                handleExport(format)
                            }
                        }
                        Button("分享当前小票", systemImage: "square.and.arrow.up") {
                            handleShare()
                        }
                        Button("复制", systemImage: "doc.on.doc") {
                            copyReceipt()
                        }
                        Divider()
                        Button("删除小票", role: .destructive) {
                            isConfirmingDelete = true
                        }
                    } label: { Image(systemName: "ellipsis") }
                    .accessibilityLabel("小票更多操作")
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                if isSearching {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(NoteTheme.secondaryInk)
                        TextField("在小票中查找", text: $searchQuery)
                            .focused($searchFocused)
                            .textInputAutocapitalization(.never)
                            .accessibilityIdentifier("v02.receipt.detail.find")
                        Button("关闭") {
                            isSearching = false
                            searchFocused = false
                            searchQuery = ""
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 14)
                    .frame(minHeight: 48)
                    .background(NoteTheme.background.opacity(0.96))
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .onAppear { searchFocused = true }
                }
            }
        }
        .sheet(item: $selectedPreview) { attachment in
            V02ReceiptAttachmentPreview(attachment: attachment)
        }
        .sheet(item: $selectedImage) { attachment in
            V02ReceiptImagePreview(attachment: attachment)
        }
        .sheet(isPresented: Binding(
            get: { !shareURLs.isEmpty },
            set: { if !$0 { shareURLs.removeAll() } }
        )) {
            NavigationStack {
                List(shareURLs, id: \.self) { url in
                    ShareLink(item: url) {
                        Label(url.lastPathComponent, systemImage: "square.and.arrow.up")
                    }
                }
                .navigationTitle("分享小票")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("完成") { shareURLs.removeAll() }
                    }
                }
            }
        }
        .alert("删除这张小票？", isPresented: $isConfirmingDelete) {
            Button("删除", role: .destructive) { deleteReceipt() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("小票会进入回收站，来源构思集和灵感不会改变。")
        }
        .noteErrorAlert($error)
    }

    private var longTicket: some View {
        ZStack(alignment: .top) {
            V02ReceiptPaperShape()
                .fill(Color.white.opacity(0.84))
                .overlay {
                    V02ReceiptPaperShape()
                        .stroke(Color.white.opacity(0.94), lineWidth: 1)
                }
                .shadow(color: NoteTheme.ink.opacity(0.13), radius: 18, y: 10)

            VStack(alignment: .leading, spacing: 20) {
                receiptHeader
                V02ReceiptPerforationLineForDetail()
                timeline
                ForEach(filteredMembers, id: \.member.inspirationID) { item in
                    memberSection(index: item.index, member: item.member)
                }
                if filteredMembers.isEmpty {
                    Text(searchQuery.isEmpty ? "这一轮没有可显示的灵感。" : "没有匹配的灵感或附件。")
                        .foregroundStyle(NoteTheme.secondaryInk)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                V02ReceiptPerforationLineForDetail()
                footer
            }
            .padding(.horizontal, 22)
            .padding(.top, 62)
            .padding(.bottom, 30)

            // The clip sits over the paper's top edge; content begins below it.
            V02TicketClip()
                .padding(.horizontal, 12)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(template.rawValue)，\(receipt.snapshot.collectionName)小票，\(receipt.snapshot.members.count) 条灵感")
        .accessibilityAction(named: "在小票中查找") { isSearching = true }
    }

    private var receiptHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("NOTE1 · \(receipt.id.uuidString.prefix(8))")
                .noteFont(size: 12, weight: .semibold, relativeTo: .caption)
                .foregroundStyle(NoteTheme.secondaryInk)
            HStack(alignment: .firstTextBaseline) {
                Text(receipt.snapshot.collectionName)
                    .noteFont(size: 28, weight: .semibold, design: .rounded, relativeTo: .title2)
                    .foregroundStyle(NoteTheme.ink)
                Spacer(minLength: 8)
                Text(template.rawValue)
                    .noteFont(size: 12, weight: .semibold, relativeTo: .caption)
                    .foregroundStyle(NoteTheme.ink)
            }
            Text("本轮构思已结束 · \(receipt.snapshot.members.count) 条灵感")
                .noteFont(size: 15, relativeTo: .subheadline)
                .foregroundStyle(NoteTheme.secondaryInk)
            Text("开始：\(receipt.snapshot.startedAt.formatted(date: .abbreviated, time: .shortened))\n结束：\(receipt.snapshot.endedAt.formatted(date: .abbreviated, time: .shortened))\n持续：\(receipt.snapshot.endedAt.timeIntervalSince(receipt.snapshot.startedAt).formattedDuration) · 有效编辑：\(receipt.snapshot.effectiveEditCount) 次")
                .noteFont(size: 14, relativeTo: .subheadline)
                .foregroundStyle(NoteTheme.secondaryInk)
        }
    }

    private var timeline: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("本轮时间线")
                .noteFont(size: 17, weight: .semibold, relativeTo: .headline)
            ForEach(receipt.snapshot.events) { event in
                HStack(alignment: .top, spacing: 8) {
                    Circle()
                        .fill(NoteTheme.ink.opacity(0.55))
                        .frame(width: 6, height: 6)
                        .padding(.top, 6)
                    Text("\(event.occurredAt.formatted(date: .omitted, time: .shortened)) · \(eventDescription(event))")
                        .noteFont(size: 13, relativeTo: .caption)
                        .foregroundStyle(NoteTheme.secondaryInk)
                }
            }
        }
    }

    private func memberSection(index: Int, member: V02ReceiptSnapshot.Member) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("\(index + 1)")
                .noteFont(size: 12, weight: .bold, relativeTo: .caption)
                .foregroundStyle(NoteTheme.secondaryInk)
                .accessibilityHidden(true)
            Text(member.text.isEmpty ? "未命名灵感" : member.text)
                .noteFont(size: 18, relativeTo: .body)
                .lineSpacing(4)
                .foregroundStyle(NoteTheme.ink)
            ForEach(attachments(for: member)) { attachment in
                attachmentRow(attachment)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            template == .film ? NoteTheme.ink.opacity(0.055) : Color.white.opacity(0.58),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(NoteTheme.secondaryInk.opacity(0.12), lineWidth: 1)
        }
    }

    @ViewBuilder
    private func attachmentRow(_ attachment: ReceiptAttachment) -> some View {
        if attachment.resource.mimeType.hasPrefix("image/"),
           let image = UIImage(contentsOfFile: attachment.url.path) {
            Button { selectedImage = attachment } label: {
                HStack(spacing: 10) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: template == .film ? 86 : 56, height: template == .film ? 74 : 48)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    attachmentMetadata(attachment)
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("查看图片 \(attachment.resource.filename)")
        } else if attachment.resource.mimeType.hasPrefix("audio/") || attachment.resource.source == .voiceInspiration {
            V02AudioPlaybackControl(resource: attachment.resource, url: attachment.url)
                .accessibilityLabel("播放音频 \(attachment.resource.filename)")
        } else {
            Button { selectedPreview = attachment } label: {
                HStack(spacing: 10) {
                    Image(systemName: attachment.resource.mimeType == "application/pdf" ? "doc.richtext" : "doc")
                        .font(.title3)
                    attachmentMetadata(attachment)
                    Spacer(minLength: 4)
                    Image(systemName: "eye")
                        .font(.caption.weight(.semibold))
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("预览文件 \(attachment.resource.filename)")
        }
    }

    private func attachmentMetadata(_ attachment: ReceiptAttachment) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(attachment.resource.filename)
                .lineLimit(1)
            Text("\(attachment.resource.mimeType) · \(ByteCountFormatter.string(fromByteCount: attachment.resource.size, countStyle: .file))")
                .noteFont(size: 12, relativeTo: .caption)
                .foregroundStyle(NoteTheme.secondaryInk)
                .lineLimit(1)
        }
    }

    private var footer: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("构思小票 · 本机快照")
            Spacer()
            Text("\(receipt.snapshot.members.count) 条灵感")
        }
        .noteFont(size: 12, weight: .medium, relativeTo: .caption)
        .foregroundStyle(NoteTheme.secondaryInk)
    }

    private var filteredMembers: [(index: Int, member: V02ReceiptSnapshot.Member)] {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        return receipt.snapshot.members.enumerated().compactMap { index, member in
            guard !query.isEmpty else { return (index, member) }
            let attachmentMatch = attachments(for: member).contains {
                $0.resource.filename.localizedStandardContains(query) || $0.resource.mimeType.localizedStandardContains(query)
            }
            guard member.text.localizedStandardContains(query) || attachmentMatch else { return nil }
            return (index, member)
        }
    }

    private func attachments(for member: V02ReceiptSnapshot.Member) -> [ReceiptAttachment] {
        if !member.attachments.isEmpty {
            return member.attachments.map { metadata in
                let resource = V02AttachmentResource(
                    id: metadata.id,
                    source: metadata.source,
                    filename: metadata.filename,
                    mimeType: metadata.mimeType,
                    relativePath: metadata.relativePath,
                    size: metadata.size,
                    createdAt: metadata.createdAt
                )
                return ReceiptAttachment(resource: resource, url: store.resourceURL(relativePath: metadata.relativePath))
            }
        }
        return member.resourceIDs.compactMap { id in
            guard let resource = store.state.resources.first(where: { $0.id == id }) else { return nil }
            return ReceiptAttachment(resource: resource, url: store.resourceURL(resource))
        }
    }

    private func handleExport(_ format: V02ReceiptExportFormat) {
        if let export {
            export(receipt, format)
            return
        }
        do {
            shareURLs = [try V02ReceiptExportFile.write(
                receipt,
                format: format,
                resourceURL: { store.resourceURL(relativePath: $0) }
            )]
        }
        catch let caughtError { self.error = UserFacingAlert(error: caughtError) }
    }

    private func handleShare() {
        do {
            shareURLs = [try V02ReceiptExportFile.write(
                receipt,
                format: .pdf,
                resourceURL: { store.resourceURL(relativePath: $0) }
            )]
        }
        catch let caughtError { self.error = UserFacingAlert(error: caughtError) }
    }

    private func copyReceipt() {
        let body = receipt.snapshot.members.map(\.text).joined(separator: "\n\n")
        UIPasteboard.general.string = "\(receipt.snapshot.collectionName)\n\n\(body)"
    }

    private func continueThinking() {
        do {
            _ = try store.continueThinking(in: receipt.collectionID)
            dismiss()
        } catch let caughtError { self.error = UserFacingAlert(error: caughtError) }
    }

    private func deleteReceipt() {
        do {
            let entryIDs = try store.deleteReceipt(receipt.id)
            onDelete?(entryIDs)
            dismiss()
        } catch let caughtError { self.error = UserFacingAlert(error: caughtError) }
    }

    private func eventDescription(_ event: V02RoundEvent) -> String {
        let name = event.inspirationID.flatMap { id in
            receipt.snapshot.members.first(where: { $0.inspirationID == id })?.text
        }?.trimmingCharacters(in: .whitespacesAndNewlines)
        let suffix = name?.isEmpty == false ? "：\(name!)" : ""
        switch event.kind {
        case .started: return "开始构思"
        case .memberAdded: return "加入灵感\(suffix)"
        case .memberRemoved: return "移出灵感\(suffix)"
        case .inspirationEdited: return "编辑灵感\(suffix)"
        case .ended: return "结束本轮构思"
        }
    }
}

private struct ReceiptAttachment: Identifiable {
    let resource: V02AttachmentResource
    let url: URL
    var id: UUID { resource.id }
}

private struct V02ReceiptAttachmentPreview: View {
    @Environment(\.dismiss) private var dismiss
    let attachment: ReceiptAttachment

    var body: some View {
        NavigationStack {
            QuickLookPreview(url: attachment.url)
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle(attachment.resource.filename)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("完成") { dismiss() }
                    }
                }
        }
    }
}

private struct V02ReceiptImagePreview: View {
    @Environment(\.dismiss) private var dismiss
    let attachment: ReceiptAttachment

    var body: some View {
        NavigationStack {
            Group {
                if let image = UIImage(contentsOfFile: attachment.url.path) {
                    ScrollView([.horizontal, .vertical]) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(minWidth: 320, minHeight: 320)
                            .padding(20)
                    }
                } else {
                    ContentUnavailableView("图片不可用", systemImage: "photo")
                }
            }
            .background(Color.black.opacity(0.92))
            .navigationTitle(attachment.resource.filename)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                        .foregroundStyle(.white)
                }
            }
        }
    }
}

private struct V02ReceiptPerforationLineForDetail: View {
    var body: some View {
        Rectangle()
            .fill(NoteTheme.secondaryInk.opacity(0.36))
            .frame(height: 1)
            .overlay {
                HStack(spacing: 4) {
                    ForEach(0..<26, id: \.self) { _ in
                        Circle()
                            .fill(Color.white.opacity(0.86))
                            .frame(width: 3, height: 3)
                    }
                }
            }
    }
}
