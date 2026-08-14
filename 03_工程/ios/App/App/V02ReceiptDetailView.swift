import SwiftUI
import UIKit

/// The detail screen deliberately keeps the receipt as the primary object. It
/// is a long, scrollable paper rather than a generic white information list.
struct V02ReceiptDetailView: View {
    @ObservedObject var store: V02Store
    let receipt: V02Receipt
    let onDelete: ((Set<UUID>) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var template: V02ReceiptTemplate
    @State private var error: UserFacingAlert?
    @State private var shareURLs: [URL] = []
    @State private var selectedPreview: ReceiptAttachment?
    @State private var selectedImage: ReceiptAttachment?
    @State private var searchQuery = ""
    @State private var isSearching = false
    @State private var isConfirmingDelete = false
    @FocusState private var searchFocused: Bool
    @AccessibilityFocusState private var isReceiptHeaderFocused: Bool

    init(
        store: V02Store,
        receipt: V02Receipt,
        onDelete: ((Set<UUID>) -> Void)? = nil
    ) {
        self.store = store
        self.receipt = receipt
        self.onDelete = onDelete
        _template = State(initialValue: V02ReceiptTemplate.recommended(for: receipt, resources: store.state.resources))
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
            .toolbar(.hidden, for: .navigationBar)
            .notePrimaryHeader { receiptPageHeader }
        }
        .accessibilityHidden(isPresentingChildSheet)
        .background {
            V02PresentedContentAccessibilityIsolation(isPresented: isPresentingChildSheet)
                .frame(width: 0, height: 0)
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
        .onAppear { isReceiptHeaderFocused = true }
    }

    private var receiptPageHeader: some View {
        VStack(spacing: 0) {
            V02SecondaryPageHeader("小票详情") {
                V02GlassIconButton(
                    systemName: "chevron.left",
                    label: "返回小票册",
                    action: { dismiss() }
                )
            } trailing: {
                receiptActionsMenu
            }

            if isSearching {
                receiptSearchBar
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .background(NoteTheme.background)
    }

    private var isPresentingChildSheet: Bool {
        selectedPreview != nil || selectedImage != nil || !shareURLs.isEmpty
    }

    private var receiptActionsMenu: some View {
        Menu {
            Menu("切换模板", systemImage: "rectangle.2.swap") {
                ForEach(V02ReceiptTemplate.allCases) { item in
                    Button(item.rawValue) { template = item }
                }
            }
            Button("在小票中查找", systemImage: "magnifyingglass") {
                withAnimation(NoteMotion.reveal(reduceMotion: reduceMotion)) { isSearching = true }
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
        } label: {
            V02GlassIconLabel(systemName: "ellipsis")
        }
        .accessibilityLabel("小票更多操作")
    }

    private var receiptSearchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(NoteTheme.secondaryInk)
            TextField("在小票中查找", text: $searchQuery)
                .noteFontCapped(
                    size: 16,
                    maximumScale: 1.25,
                    relativeTo: .body
                )
                .focused($searchFocused)
                .textInputAutocapitalization(.never)
                .accessibilityIdentifier("v02.receipt.detail.find")
            Button {
                withAnimation(NoteMotion.reveal(reduceMotion: reduceMotion)) { isSearching = false }
                searchFocused = false
                searchQuery = ""
            } label: {
                Text("关闭")
                    .noteFontCapped(
                        size: 16,
                        maximumScale: 1.25,
                        weight: .medium,
                        relativeTo: .body
                    )
                    .frame(minHeight: 44)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, NoteTheme.horizontalPadding)
        .frame(minHeight: 48)
        .background(NoteTheme.background.opacity(0.96))
        .onAppear { searchFocused = true }
    }

    private var longTicket: some View {
        VStack(alignment: .leading, spacing: 20) {
            receiptHeader
            V02ThermalReceiptRule(style: .double)
            timeline
            ForEach(filteredMembers, id: \.member.inspirationID) { item in
                memberSection(index: item.index, member: item.member)
            }
            if filteredMembers.isEmpty {
                Text(searchQuery.isEmpty ? "这一轮没有可显示的灵感。" : "没有匹配的灵感或附件。")
                    .foregroundStyle(NoteTheme.receiptSecondaryInk)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            V02ThermalReceiptRule(style: .double)
            footer
        }
        .padding(.horizontal, 22)
        .padding(.top, 26)
        .padding(.bottom, 30)
        .foregroundStyle(NoteTheme.receiptInk)
        .background { V02ReceiptPaperSurface() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(template.rawValue)，\(receipt.snapshot.collectionName)小票，\(receipt.statistics.detailText)")
        .accessibilityAction(named: "在小票中查找") { isSearching = true }
    }

    private var receiptHeader: some View {
        VStack(spacing: 6) {
            Text("NOTE1")
                .noteFont(size: 30, weight: .black, design: .monospaced, relativeTo: .title2)
                .tracking(3.2)
            Text("构 思 小 票")
                .noteFont(size: 12, weight: .bold, design: .monospaced, relativeTo: .caption)
            Text(receipt.snapshot.collectionName)
                .noteFont(size: 22, weight: .bold, design: .monospaced, relativeTo: .title3)
                .foregroundStyle(NoteTheme.receiptInk)
                .multilineTextAlignment(.center)
            Text("\(receipt.statistics.roundTitle) · \(template.rawValue)")
                .noteFont(size: 12, weight: .medium, design: .monospaced, relativeTo: .caption)
                .foregroundStyle(NoteTheme.receiptSecondaryInk)
            Text("\(receipt.snapshot.startedAt.formatted(date: .numeric, time: .shortened)) – \(receipt.snapshot.endedAt.formatted(date: .numeric, time: .shortened))")
                .noteFont(size: 12, design: .monospaced, relativeTo: .caption)
                .foregroundStyle(NoteTheme.receiptSecondaryInk)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .accessibilityFocused($isReceiptHeaderFocused)
    }

    private var timeline: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("本轮时间线")
                .noteFont(size: 17, weight: .bold, design: .monospaced, relativeTo: .headline)
            ForEach(receipt.snapshot.events) { event in
                HStack(alignment: .top, spacing: 8) {
                    Circle()
                        .fill(NoteTheme.receiptInk.opacity(0.58))
                        .frame(width: 6, height: 6)
                        .padding(.top, 6)
                    Text("\(event.occurredAt.formatted(date: .omitted, time: .shortened)) · \(eventDescription(event))")
                        .noteFont(size: 13, design: .monospaced, relativeTo: .caption)
                        .foregroundStyle(NoteTheme.receiptSecondaryInk)
                }
            }
        }
    }

    private func memberSection(index: Int, member: V02ReceiptSnapshot.Member) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("\(index + 1)")
                .noteFont(size: 12, weight: .bold, design: .monospaced, relativeTo: .caption)
                .foregroundStyle(NoteTheme.receiptSecondaryInk)
                .accessibilityHidden(true)
            Text(member.text.isEmpty ? "未命名灵感" : member.text)
                .noteFont(size: 18, design: .monospaced, relativeTo: .body)
                .lineSpacing(4)
                .foregroundStyle(NoteTheme.receiptInk)
            ForEach(attachments(for: member)) { attachment in
                attachmentRow(attachment)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            template == .film ? NoteTheme.receiptInk.opacity(0.055) : Color.black.opacity(0.025),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(NoteTheme.receiptDivider.opacity(0.72), lineWidth: 1)
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
                .noteFont(size: 12, design: .monospaced, relativeTo: .caption)
                .foregroundStyle(NoteTheme.receiptSecondaryInk)
                .lineLimit(1)
        }
    }

    private var footer: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("构思小票 · 本机快照")
            Spacer()
            Text("\(receipt.snapshot.members.count) 条灵感")
        }
        .noteFont(size: 12, weight: .medium, design: .monospaced, relativeTo: .caption)
        .foregroundStyle(NoteTheme.receiptSecondaryInk)
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
        let suffix = name.map { $0.isEmpty ? "" : "：\($0)" } ?? ""
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
