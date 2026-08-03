import SwiftUI

struct V02ReceiptBookView: View {
    @ObservedObject var store: V02Store
    @Binding var isSelecting: Bool
    @State private var selectedIDs = Set<UUID>()
    @State private var pendingDeleteIDs = Set<UUID>()
    @State private var shareURLs: [URL] = []
    @State private var error: UserFacingAlert?
    @State private var receiptIndex = 0
    @State private var detailReceipt: V02Receipt?
    @State private var undoTrashEntryIDs = Set<UUID>()
    @State private var isPresentingSearch = false
    @State private var templateOverrides: [UUID: V02ReceiptTemplate] = [:]

    private var selectedReceipts: [V02Receipt] {
        store.state.receipts.filter { selectedIDs.contains($0.id) }
    }

    private var receipts: [V02Receipt] {
        store.state.receipts.sorted { $0.createdAt > $1.createdAt }
    }

    private var currentReceipt: V02Receipt? {
        guard receipts.indices.contains(receiptIndex) else { return nil }
        return receipts[receiptIndex]
    }

    var body: some View {
        NavigationStack {
          ScrollView {
            VStack(spacing: 14) {
                if isSelecting { selectionToolbar }
                if receipts.isEmpty {
                    emptyBook
                } else {
                    V02ReceiptDeck(
                        store: store,
                        receipts: receipts,
                        index: $receiptIndex,
                        isSelecting: isSelecting,
                        selectedIDs: $selectedIDs,
                        openReceipt: { detailReceipt = $0 },
                        minimumPaperHeight: currentReceipt.map(receiptPaperHeight) ?? 560,
                        templateFor: { receipt in
                            templateOverrides[receipt.id]
                                ?? V02ReceiptTemplate.recommended(for: receipt, resources: store.state.resources)
                        }
                    )
                    .zIndex(1)
                    Text("第 \(receiptIndex + 1) 张，共 \(receipts.count) 张")
                        .noteFont(size: 13, relativeTo: .caption)
                        .foregroundStyle(NoteTheme.secondaryInk)
                        .accessibilityLabel("第 \(receiptIndex + 1) 张，共 \(receipts.count) 张。可左右切换或向下抽取。")
                        .padding(.top, 18)
                }
            }
            .padding(.horizontal, NoteTheme.horizontalPadding)
            .padding(.top, 6)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Color.clear
                    .frame(height: V02NavigationLayoutPolicy.primaryContentBottomPadding)
                    .allowsHitTesting(false)
            }
        }
          .scrollIndicators(.hidden)
          .background(NoteTheme.background.ignoresSafeArea())
          .toolbar(.hidden, for: .navigationBar)
          .safeAreaInset(edge: .top, spacing: 0) {
              receiptHeader
          }
        }
        .onChange(of: receipts.map(\.id)) { _, ids in
            receiptIndex = min(receiptIndex, max(0, ids.count - 1))
        }
        .sheet(item: $detailReceipt) { receipt in
            V02ReceiptDetailView(
                store: store,
                receipt: receipt,
                export: export,
                onDelete: { entryIDs in undoTrashEntryIDs.formUnion(entryIDs) }
            )
        }
        .sheet(isPresented: $isPresentingSearch) {
            V02SearchView(store: store, initialScope: .receipts, locksScope: true)
        }
        .sheet(isPresented: Binding(
            get: { !shareURLs.isEmpty },
            set: { if !$0 { shareURLs.removeAll() } }
        )) {
            NavigationStack {
                List(shareURLs, id: \.self) { url in
                    ShareLink(item: url) { Label(url.lastPathComponent, systemImage: "square.and.arrow.up") }
                }
                .navigationTitle("导出文件")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("完成") { shareURLs.removeAll() } } }
            }
        }
        .alert("删除构思小票？", isPresented: Binding(
            get: { !pendingDeleteIDs.isEmpty },
            set: { if !$0 { pendingDeleteIDs.removeAll() } }
        )) {
            Button("删除", role: .destructive) { deleteSelectedReceipts() }
            Button("取消", role: .cancel) { pendingDeleteIDs.removeAll() }
        } message: {
            Text("删除后可在回收站中恢复。")
        }
        .safeAreaInset(edge: .bottom) {
            V02ReceiptUndoTrashBanner(store: store, entryIDs: $undoTrashEntryIDs) { error in
                self.error = UserFacingAlert(error: error)
            }
        }
        .noteErrorAlert($error)
    }

    private var receiptHeader: some View {
        ZStack {
            Text("小票册")
                .noteFontCapped(size: 20, maximumScale: 1.2, weight: .semibold, design: .rounded, relativeTo: .headline)
                .foregroundStyle(NoteTheme.ink)
                .accessibilityAddTraits(.isHeader)

            HStack(spacing: 10) {
                Spacer(minLength: 0)
                Button {
                    isPresentingSearch = true
                } label: {
                    V02GlassIconLabel(systemName: "magnifyingglass")
                }
                .accessibilityLabel("搜索小票")
                receiptMenu
            }
        }
        .padding(.horizontal, NoteTheme.horizontalPadding)
        .frame(height: NoteTheme.topBarHeight)
        .background(NoteTheme.background)
    }

    private var receiptMenu: some View {
        Menu {
            Button(isSelecting ? "取消选择" : "选择", systemImage: "checkmark.circle") {
                isSelecting.toggle()
                if !isSelecting { selectedIDs.removeAll() }
            }
            Menu("切换模板", systemImage: "rectangle.2.swap") {
                ForEach(V02ReceiptTemplate.allCases) { template in
                    Button(template.rawValue) { setTemplate(template) }
                }
            }
            Button("导出 PDF", systemImage: "doc.badge.arrow.up") { exportCurrent(.pdf) }
            Button("分享", systemImage: "square.and.arrow.up") { exportCurrent(.pdf) }
            Button("复制", systemImage: "doc.on.doc") { copyCurrentReceipt() }
            Button("在小票中查找", systemImage: "magnifyingglass") {
                if let currentReceipt { detailReceipt = currentReceipt }
            }
            Button("删除", systemImage: "trash", role: .destructive) {
                if let currentReceipt { pendingDeleteIDs = [currentReceipt.id] }
            }
        } label: {
            V02GlassIconLabel(systemName: "ellipsis")
        }
        .accessibilityLabel("更多小票册操作")
    }

    private var selectionToolbar: some View {
        HStack(spacing: 10) {
            Text("已选 \(selectedIDs.count) 张")
                .noteFont(size: 14, weight: .medium, relativeTo: .subheadline)
            Spacer()
            Button("全选") { selectedIDs = Set(receipts.map(\.id)) }
                .buttonStyle(.plain)
            Menu("操作") {
                Button("导出 PDF", systemImage: "arrow.down.doc") { exportSelectedPDFs() }
                    .disabled(selectedIDs.isEmpty)
                Button("分享 PDF", systemImage: "square.and.arrow.up") { exportSelectedPDFs() }
                    .disabled(selectedIDs.isEmpty)
                Button("删除", role: .destructive) { pendingDeleteIDs = selectedIDs }
                    .disabled(selectedIDs.isEmpty)
            }
            .accessibilityLabel("批量操作")
        }
        .noteFont(size: 13, relativeTo: .caption)
        .foregroundStyle(NoteTheme.ink)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: 278)
        .noteGlass(cornerRadius: 15, castsShadow: false)
        .frame(maxWidth: .infinity, alignment: .trailing)
        .accessibilityIdentifier("v02.receipt.selection")
    }

    private var emptyBook: some View {
        VStack(spacing: 18) {
            V02TicketClip().padding(.horizontal, 22)
            VStack(spacing: 10) {
                Text("每一轮构思，都留下一张存根")
                    .noteFont(size: 21, weight: .semibold, design: .rounded, relativeTo: .title3)
                Text("结束一轮构思后，小票会从这里的票据夹中出现。")
                    .noteFont(size: 15, relativeTo: .body)
                    .foregroundStyle(NoteTheme.secondaryInk)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 30)
        }
        .frame(maxWidth: .infinity, minHeight: 430)
        .accessibilityIdentifier("v02.receipt.empty")
    }

    private func export(_ receipt: V02Receipt, format: V02ReceiptExportFormat) {
        do {
            shareURLs = [try V02ReceiptExportFile.write(
                receipt,
                format: format,
                resourceURL: { store.resourceURL(relativePath: $0) }
            )]
        }
        catch { self.error = UserFacingAlert(error: error) }
    }

    private func exportSelectedPDFs() {
        do {
            shareURLs = try V02ReceiptExportFile.writePDFs(
                selectedReceipts,
                resourceURL: { store.resourceURL(relativePath: $0) }
            )
        }
        catch { self.error = UserFacingAlert(error: error) }
    }

    private func deleteSelectedReceipts() {
        do {
            undoTrashEntryIDs.formUnion(try store.batchDeleteReceipts(pendingDeleteIDs))
            selectedIDs.subtract(pendingDeleteIDs)
            pendingDeleteIDs.removeAll()
        } catch {
            self.error = UserFacingAlert(error: error)
        }
    }

    private func receiptPaperHeight(_ receipt: V02Receipt) -> CGFloat {
        let textCount = receipt.snapshot.members.reduce(0) { $0 + $1.text.count }
        let memberCount = CGFloat(max(receipt.snapshot.members.count, 1))
        let estimatedTextLines = CGFloat(max(1, Int(ceil(Double(max(textCount, 1)) / 18.0))))
        let timelineHeight = memberCount * 72
        let attachmentCount = receipt.snapshot.members.flatMap(\.attachments).count
        let attachmentHeight = attachmentCount == 0 ? 0 : CGFloat(58 + ((attachmentCount + 3) / 4) * 42)
        let photoHeight = V02ReceiptTemplate.recommended(for: receipt, resources: store.state.resources) == .film ? 148.0 : 0.0
        // The root book is an archive rail with a natural long ticket. Keep a
        // readable timeline and attachment/photo state in the paper itself;
        // detail may reveal further actions but must not be the only place
        // where the receipt's contents are legible.
        let naturalHeight = 360 + timelineHeight + estimatedTextLines * 22 + attachmentHeight + photoHeight
        return min(max(naturalHeight, 560), 1800)
    }

    private func setTemplate(_ template: V02ReceiptTemplate) {
        guard let currentReceipt else { return }
        templateOverrides[currentReceipt.id] = template
    }

    private func exportCurrent(_ format: V02ReceiptExportFormat) {
        guard let currentReceipt else { return }
        export(currentReceipt, format: format)
    }

    private func copyCurrentReceipt() {
        guard let currentReceipt else { return }
        let body = currentReceipt.snapshot.members.map(\.text).joined(separator: "\n\n")
        UIPasteboard.general.string = "\(currentReceipt.snapshot.collectionName)\n\n\(body)"
    }
}

private struct V02ReceiptUndoTrashBanner: View {
    @ObservedObject var store: V02Store
    @Binding var entryIDs: Set<UUID>
    let reportError: (Error) -> Void

    var body: some View {
        if !entryIDs.isEmpty {
            HStack {
                Text("已移入回收站")
                Spacer()
                Button("撤回") {
                    do { try store.restoreTrash(entryIDs); entryIDs.removeAll() }
                    catch { reportError(error) }
                }
                .buttonStyle(PressScaleButtonStyle())
                .noteGlass(cornerRadius: 16, castsShadow: false)
            }
            .accessibilityLabel("构思小票已移入回收站，可在两秒内撤回")
            .padding(12)
            .background(NoteTheme.background.opacity(0.92), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .padding(.horizontal, 16)
            .task(id: entryIDs) {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { return }
                entryIDs.removeAll()
            }
        }
    }
}
