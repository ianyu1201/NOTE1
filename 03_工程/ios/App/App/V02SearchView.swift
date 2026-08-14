import SwiftUI

struct V02SearchView: View {
    @ObservedObject var store: V02Store
    private let lockedScope: V02SearchScope?
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var scope: V02SearchScope
    @State private var isSelecting = false
    @State private var selectedIDs = Set<UUID>()
    @State private var isConfirmingDelete = false
    @State private var error: UserFacingAlert?
    @State private var shareURLs: [URL] = []
    @State private var selectedInspiration: V02Inspiration?
    @State private var selectedCollection: V02ThinkingCollection?
    @State private var selectedReceipt: V02Receipt?

    init(store: V02Store, initialScope: V02SearchScope = .all, locksScope: Bool = false) {
        self.store = store
        lockedScope = locksScope ? initialScope : nil
        _scope = State(initialValue: initialScope)
    }

    private var results: [V02SearchResult] { store.search(query, scope: scope) }
    private var selectedInspirations: [V02Inspiration] {
        store.state.inspirations.filter { selectedIDs.contains($0.id) }
    }
    private var selectedReceipts: [V02Receipt] {
        store.state.receipts.filter { selectedIDs.contains($0.id) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(NoteTheme.secondaryInk)
                        TextField("搜索灵感、构思集、小票或附件", text: $query)
                            .textFieldStyle(.plain)
                            .submitLabel(.search)
                            .accessibilityIdentifier("v02.search.field")
                        if !query.isEmpty {
                            Button("清除", systemImage: "xmark.circle.fill") { query = "" }
                                .labelStyle(.iconOnly)
                                .foregroundStyle(NoteTheme.secondaryInk)
                                .accessibilityLabel("清除搜索")
                        }
                    }
                    .padding(.horizontal, 16)
                    .frame(minHeight: 48)
                    .noteGlass(cornerRadius: 18, castsShadow: false)

                    scopePicker

                    if isSelecting { selectionToolbar }

                    if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        EmptyStateView(systemName: "magnifyingglass", title: "搜索你的本机内容", message: "灵感、构思集、小票和附件都可以查找。")
                            .frame(maxWidth: .infinity, minHeight: 300)
                    } else if results.isEmpty {
                        EmptyStateView(systemName: "magnifyingglass", title: "没有找到内容", message: "可尝试更短的关键词或更换搜索范围。")
                            .frame(maxWidth: .infinity, minHeight: 300)
                    } else {
                        Text("结果（\(results.count)）")
                            .noteFont(size: 14, weight: .semibold, relativeTo: .subheadline)
                            .foregroundStyle(NoteTheme.secondaryInk)
                            .padding(.top, 4)
                        LazyVStack(spacing: 0) {
                            ForEach(results) { result in
                                HStack(alignment: .top, spacing: 12) {
                                    if isSelecting, let id = selectableID(for: result) {
                                        Button {
                                            if selectedIDs.contains(id) { selectedIDs.remove(id) }
                                            else { selectedIDs.insert(id) }
                                        } label: {
                                            Image(systemName: selectedIDs.contains(id) ? "checkmark.circle.fill" : "circle")
                                                .font(.system(size: 20, weight: .medium))
                                        }
                                        .buttonStyle(.plain)
                                        .foregroundStyle(selectedIDs.contains(id) ? NoteTheme.ink : NoteTheme.secondaryInk)
                                        .accessibilityLabel(selectedIDs.contains(id) ? "取消选择" : "选择")
                                    }
                                    Button { open(result) } label: {
                                        VStack(alignment: .leading, spacing: 5) {
                                            Text(title(for: result))
                                                .noteFont(size: 16, relativeTo: .body)
                                                .foregroundStyle(NoteTheme.ink)
                                                .lineLimit(3)
                                            Text(subtitle(for: result))
                                                .noteFont(size: 13, relativeTo: .caption)
                                                .foregroundStyle(NoteTheme.secondaryInk)
                                        }
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(.vertical, 14)
                                .overlay(alignment: .bottom) { Rectangle().fill(NoteTheme.divider).frame(height: 1) }
                                .accessibilityElement(children: .contain)
                            }
                        }
                    }
                }
                .padding(.horizontal, NoteTheme.horizontalPadding)
                .padding(.top, 10)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            .background(NoteTheme.background.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .notePrimaryHeader { searchHeader }
        }
        .accessibilityHidden(isPresentingObject)
        .background {
            V02PresentedContentAccessibilityIsolation(isPresented: isPresentingObject)
                .frame(width: 0, height: 0)
        }
        .onChange(of: scope) { _, _ in
            isSelecting = false
            selectedIDs.removeAll()
        }
        .onChange(of: query) { _, _ in
            // A new query can remove previously selected rows from the
            // result set. Never keep hidden IDs actionable in the selection
            // toolbar after the visible result set changes.
            isSelecting = false
            selectedIDs.removeAll()
        }
        .sheet(isPresented: Binding(get: { !shareURLs.isEmpty }, set: { if !$0 { shareURLs.removeAll() } })) {
            NavigationStack {
                List(shareURLs, id: \.self) { url in ShareLink(item: url) { Label(url.lastPathComponent, systemImage: "square.and.arrow.up") } }
                    .navigationTitle("导出文件")
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("完成") { shareURLs.removeAll() } } }
            }
        }
        .alert(scope == .receipts ? "删除选中的构思小票？" : "删除选中的灵感？", isPresented: $isConfirmingDelete) {
            Button("删除", role: .destructive) {
                do {
                    if scope == .receipts {
                        _ = try store.batchDeleteReceipts(selectedIDs)
                    } else {
                        _ = try store.batchDeleteInspirations(selectedIDs)
                    }
                    selectedIDs.removeAll(); isSelecting = false
                }
                catch let caughtError { error = UserFacingAlert(error: caughtError) }
            }
            Button("取消", role: .cancel) { }
        } message: {
            Text("删除后可在回收站中恢复，30 天后会自动永久清理。")
        }
        .noteErrorAlert($error)
        .fullScreenCover(item: $selectedInspiration) { inspiration in
            // Search must open the same full-focus editor as the timeline and
            // card preview so attachments, auto-save, Quick Look and the
            // single visible back action remain available on the real object.
            V02InspirationEditorView(
                store: store,
                inspirationID: inspiration.id,
                reportError: { caughtError in
                    error = UserFacingAlert(error: caughtError)
                }
            )
        }
        .sheet(item: $selectedCollection) { collection in
            V02SearchCollectionDetail(store: store, collection: collection)
        }
        .sheet(item: $selectedReceipt) { receipt in
            V02ReceiptDetailView(store: store, receipt: receipt)
        }
    }

    private var searchHeader: some View {
        V02SecondaryPageHeader("搜索") {
            V02GlassTextButton(title: "取消") { dismiss() }
        } trailing: {
            if scope == .inspirations || scope == .receipts {
                V02GlassTextButton(title: isSelecting ? "取消选择" : "选择") {
                    isSelecting.toggle()
                    if !isSelecting { selectedIDs.removeAll() }
                }
            } else {
                V02SecondaryHeaderPlaceholder()
            }
        }
    }

    private var isPresentingObject: Bool {
        selectedInspiration != nil || selectedCollection != nil || selectedReceipt != nil
    }

    private func title(for result: V02SearchResult) -> String {
        switch result {
        case .inspiration(let inspiration): inspiration.text.isEmpty ? "未命名灵感" : inspiration.text
        case .collection(let collection): collection.name
        case .receipt(let receipt): receipt.snapshot.collectionName
        }
    }

    private var scopePicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            V02ScopeSectionLabel()
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(lockedScope.map { [$0] } ?? V02SearchScope.allCases, id: \.self) { item in
                        Button(item.title) { scope = item }
                            .buttonStyle(.plain)
                            .noteFont(size: 13, weight: .medium, relativeTo: .caption)
                            .foregroundStyle(scope == item ? .white : NoteTheme.ink)
                            .padding(.horizontal, 13)
                            .frame(minHeight: 34)
                            .background(scope == item ? NoteTheme.ink : Color.white.opacity(0.42), in: Capsule())
                            .accessibilityIdentifier("v02.search.scope.\(item.title)")
                            .accessibilityAddTraits(scope == item ? .isSelected : [])
                    }
                }
            }
            .scrollClipDisabled()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .contain)
    }

    private var selectionToolbar: some View {
        ViewThatFits(in: .horizontal) {
            selectionActions(axis: .horizontal)
                .fixedSize(horizontal: true, vertical: false)
            selectionActions(axis: .vertical)
        }
        .noteFontCapped(
            size: V02PrimaryTypographyPolicy.contextLabelSize,
            maximumScale: V02PrimaryTypographyPolicy.contextLabelMaximumScale,
            weight: .medium,
            relativeTo: .subheadline
        )
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .noteGlass(cornerRadius: 18, castsShadow: false)
    }

    private enum SelectionActionAxis { case horizontal, vertical }

    @ViewBuilder
    private func selectionActions(axis: SelectionActionAxis) -> some View {
        if axis == .horizontal {
            HStack(spacing: 14) {
                Text("已选 \(selectedIDs.count)")
                    .noteFontCapped(
                        size: V02PrimaryTypographyPolicy.contextLabelSize,
                        maximumScale: V02PrimaryTypographyPolicy.contextLabelMaximumScale,
                        weight: .semibold,
                        relativeTo: .subheadline
                    )
                selectionActionButtons
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text("已选 \(selectedIDs.count)")
                    .noteFontCapped(
                        size: V02PrimaryTypographyPolicy.contextLabelSize,
                        maximumScale: V02PrimaryTypographyPolicy.contextLabelMaximumScale,
                        weight: .semibold,
                        relativeTo: .subheadline
                    )
                selectionActionButtons
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var selectionActionButtons: some View {
        if scope == .inspirations {
            Button("全选") {
                selectedIDs = Set(results.compactMap { if case .inspiration(let item) = $0 { item.id } else { nil } })
            }
            .frame(minHeight: 44)
            Button(V02InspirationSelectionCopy.returnToCardFlow) {
                do { try store.batchReturnToCardFlow(selectedIDs); selectedIDs.removeAll() }
                catch let caughtError { error = UserFacingAlert(error: caughtError) }
            }
            .frame(minHeight: 44)
            .disabled(selectedInspirations.isEmpty || !selectedInspirations.allSatisfy { $0.cardFlowState == .tuckedAway })
            Menu(V02InspirationSelectionCopy.assignToCollection) {
                ForEach(store.activeCollections) { collection in
                    Button(collection.name) {
                        do { try store.batchAssign(selectedIDs, to: collection.id); selectedIDs.removeAll() }
                        catch let caughtError { error = UserFacingAlert(error: caughtError) }
                    }
                    .disabled(!canAssignSelected(to: collection))
                }
            }
            .frame(minHeight: 44)
            .disabled(selectedIDs.isEmpty || store.activeCollections.isEmpty)
        } else if scope == .receipts {
            Button("全选") {
                selectedIDs = Set(results.compactMap { if case .receipt(let item) = $0 { item.id } else { nil } })
            }
            .frame(minHeight: 44)
            Button("导出") { exportSelectedReceipts() }
                .frame(minHeight: 44)
                .disabled(selectedIDs.isEmpty)
        }
        Button("删除", role: .destructive) { isConfirmingDelete = true }
            .frame(minHeight: 44)
            .disabled(selectedIDs.isEmpty)
    }

    private func subtitle(for result: V02SearchResult) -> String {
        switch result {
        case .inspiration: "灵感"
        case .collection: "构思集"
        case .receipt: "构思小票"
        }
    }

    private func canAssignSelected(to collection: V02ThinkingCollection) -> Bool {
        guard !selectedInspirations.isEmpty,
              selectedInspirations.allSatisfy({ $0.collectionID == nil || $0.collectionID == collection.id }),
              collection.currentRoundID != nil else { return false }
        return true
    }

    private func selectableID(for result: V02SearchResult) -> UUID? {
        switch result {
        case .inspiration(let inspiration) where scope == .inspirations: inspiration.id
        case .receipt(let receipt) where scope == .receipts: receipt.id
        default: nil
        }
    }

    private func exportSelectedReceipts() {
        do {
            shareURLs = try V02ReceiptExportFile.writePDFs(
                selectedReceipts,
                resourceURL: { store.resourceURL(relativePath: $0) }
            )
        }
        catch let caughtError { error = UserFacingAlert(error: caughtError) }
    }

    private func open(_ result: V02SearchResult) {
        guard !isSelecting else { return }
        switch result {
        case .inspiration(let item): selectedInspiration = item
        case .collection(let item): selectedCollection = item
        case .receipt(let item): selectedReceipt = item
        }
    }
}

private struct V02SearchCollectionDetail: View {
    @ObservedObject var store: V02Store
    let collection: V02ThinkingCollection
    @Environment(\.dismiss) private var dismiss
    private var members: [V02Inspiration] {
        let ids = store.state.rounds.first(where: { $0.id == collection.currentRoundID })?.memberIDs ?? []
        return ids.compactMap { id in store.state.inspirations.first(where: { $0.id == id }) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(collection.name)
                        .noteFont(size: 24, weight: .semibold, relativeTo: .title2)
                        .foregroundStyle(NoteTheme.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("构思中")
                        .noteFont(size: 14, weight: .semibold, relativeTo: .subheadline)
                        .foregroundStyle(NoteTheme.secondaryInk)
                    ForEach(members) { member in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(member.text.isEmpty ? "未命名灵感" : member.text)
                                .noteFont(size: 16, relativeTo: .body)
                                .foregroundStyle(NoteTheme.ink)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            V02MemberAttachmentSummary(store: store, resourceIDs: member.resourceIDs)
                        }
                        .padding(16)
                        .noteGlass(cornerRadius: 18, castsShadow: false)
                    }
                }
                .padding(.horizontal, NoteTheme.horizontalPadding)
                .padding(.vertical, 18)
            }
            .background(NoteTheme.background.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .notePrimaryHeader { collectionDetailHeader }
        }
    }

    private var collectionDetailHeader: some View {
        V02SecondaryPageHeader("构思集详情") {
            V02GlassIconButton(
                systemName: "xmark",
                label: "关闭构思集详情",
                action: { dismiss() }
            )
        } trailing: {
            V02SecondaryHeaderPlaceholder()
        }
    }
}
