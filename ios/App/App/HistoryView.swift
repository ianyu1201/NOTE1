import SwiftUI

struct HistoryView: View {
    @ObservedObject var store: NoteStore
    let onOpenIdea: (UUID) -> Void
    let onOpenGroup: (UUID) -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private enum RecordFilter: String, CaseIterable, Identifiable {
        case all = "全部"
        case active = "未完成"
        case completed = "已完成"

        var id: Self { self }
        var status: ItemStatus? {
            switch self {
            case .all: nil
            case .active: .active
            case .completed: .completed
            }
        }
    }

    @State private var filter: RecordFilter = .all
    @State private var query = ""
    @State private var selecting = false
    @State private var selection: Set<UUID> = []
    @State private var showingDeleteConfirmation = false
    @State private var errorAlert: UserFacingAlert?
    @State private var backupDocument = NoteBackupDocument()
    @State private var isExportingBackup = false
    @State private var isImportingBackup = false
    @State private var isBackupOperationInProgress = false
    @State private var pendingRestoreData: Data?
    @State private var showingRestoreConfirmation = false

    private var visibleItems: [ReviewItem] {
        store.recordItems(status: filter.status, matching: query)
    }

    private var selectedItems: [ReviewItem] {
        visibleItems.filter { selection.contains($0.id) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(NoteTheme.secondaryInk)
                TextField("搜索全部记录", text: $query)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                if !query.isEmpty {
                    Button {
                        query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .accessibilityLabel("清除历史搜索")
                }
            }
            .padding(.horizontal, 18)
            .frame(minHeight: 54)
            .noteGlass(cornerRadius: 27)
            .padding(.horizontal, NoteTheme.horizontalPadding)
            .padding(.top, 10)

            (
                dynamicTypeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
                    : AnyLayout(HStackLayout(spacing: 10))
            ) {
                HStack(spacing: 2) {
                    filterButton(.all)

                    filterButton(.active)
                    filterButton(.completed)
                }
                .padding(3)
                .background(Color.white.opacity(0.24), in: Capsule())
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("history.status.filter")

                HStack(spacing: 2) {
                    Button(selecting ? "完成" : "选择") {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selecting.toggle()
                            if !selecting { selection.removeAll() }
                        }
                    }
                    .noteFont(
                        size: 13,
                        weight: .semibold,
                        relativeTo: .footnote
                    )
                    .buttonStyle(.plain)
                    .frame(
                        minWidth: 52,
                        maxWidth: dynamicTypeSize.isAccessibilitySize ? .infinity : 52,
                        minHeight: 44,
                        alignment: .trailing
                    )
                    .contentShape(Rectangle())
                    .accessibilityIdentifier("history.selection.toggle")

                    Menu {
                        Button {
                            exportBackup()
                        } label: {
                            Label("导出本机备份", systemImage: "square.and.arrow.up")
                        }

                        Button {
                            isImportingBackup = true
                        } label: {
                            Label("从备份恢复", systemImage: "arrow.down.doc")
                        }
                    } label: {
                        Image(systemName: "externaldrive")
                            .font(.system(size: 16, weight: .semibold))
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(PressScaleButtonStyle())
                    .disabled(isBackupOperationInProgress)
                    .accessibilityLabel("本机数据")
                    .accessibilityHint("导出备份或从备份恢复")
                }
            }
            .padding(.horizontal, NoteTheme.horizontalPadding)

            if visibleItems.isEmpty {
                EmptyStateView(
                    systemName: "clock.arrow.circlepath",
                    title: query.isEmpty ? emptyTitle : "没有找到记录",
                    message: ""
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(visibleItems) { item in
                        Button {
                            selecting ? toggleSelection(item) : open(item)
                        } label: {
                            HStack(spacing: 10) {
                                if selecting {
                                    Image(
                                        systemName: selection.contains(item.id)
                                            ? "checkmark.circle.fill"
                                            : "circle"
                                    )
                                    .font(.system(size: 21, weight: .semibold))
                                    .foregroundStyle(
                                        selection.contains(item.id)
                                            ? NoteTheme.accent
                                            : NoteTheme.secondaryInk
                                    )
                                    .accessibilityHidden(true)
                                }
                                HistoryRow(item: item)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(Color.clear)
                        .listRowSeparatorTint(Color.white.opacity(0.65))
                        .accessibilityIdentifier("history.item.\(item.id.uuidString)")
                        .accessibilityLabel(item.title)
                        .accessibilityValue(accessibilityValue(for: item))
                        .accessibilityHint(
                            selecting ? "点按切换选择状态" : "点按打开记录"
                        )
                        .if(item.status == .completed && !selecting) { row in
                            row
                            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                Button {
                                    restore(item)
                                } label: {
                                    Label("恢复", systemImage: "arrow.uturn.backward")
                                }
                                .tint(NoteTheme.accent)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    selection = [item.id]
                                    showingDeleteConfirmation = true
                                } label: {
                                    Label("删除", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .noteScrollBackgroundHidden()
            }

            if selecting {
                HStack {
                    Button(allVisibleSelected ? "取消全选" : "全选") {
                        toggleSelectAll()
                    }
                    .noteFont(
                        size: 15,
                        weight: .semibold,
                        relativeTo: .subheadline
                    )
                    .foregroundStyle(NoteTheme.accent)
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("history.selection.selectAll")

                    Spacer()

                    Button(role: .destructive) {
                        showingDeleteConfirmation = true
                    } label: {
                        Label(
                            "删除（\(selectedItems.count)）",
                            systemImage: "trash"
                        )
                        .noteFont(
                            size: 15,
                            weight: .semibold,
                            relativeTo: .subheadline
                        )
                    }
                    .disabled(selectedItems.isEmpty)
                    .accessibilityIdentifier("history.selection.delete")
                }
                .padding(.horizontal, NoteTheme.horizontalPadding)
                .frame(minHeight: 58)
                .noteGlass(cornerRadius: 24)
                .padding(.horizontal, NoteTheme.horizontalPadding)
                .padding(.bottom, 8)
            }
        }
        .overlay {
            if isBackupOperationInProgress {
                ZStack {
                    Color.black.opacity(0.04)
                        .ignoresSafeArea()
                    HStack(spacing: 12) {
                        ProgressView()
                        Text("正在处理本机数据…")
                            .noteFont(
                                size: 14,
                                weight: .semibold,
                                relativeTo: .subheadline
                            )
                    }
                    .padding(.horizontal, 22)
                    .frame(minHeight: 58)
                    .noteGlass(cornerRadius: 24)
                }
                .transition(.opacity)
            }
        }
        .alert(
            "永久删除 \(selectedItems.count) 项记录？",
            isPresented: $showingDeleteConfirmation
        ) {
            Button("删除记录", role: .destructive) {
                deleteSelected()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("此操作会同时删除记录中的附件，且无法撤销。")
        }
        .alert(
            "使用备份替换当前本机数据？",
            isPresented: $showingRestoreConfirmation
        ) {
            Button("恢复并替换", role: .destructive) {
                restorePendingBackup()
            }
            Button("取消", role: .cancel) {
                pendingRestoreData = nil
            }
        } message: {
            Text("当前全部文字、灵感组、状态和附件会被备份中的内容替换。恢复前请确认已导出当前数据。")
        }
        .fileExporter(
            isPresented: $isExportingBackup,
            document: backupDocument,
            contentType: .note1Backup,
            defaultFilename: backupFilename
        ) { result in
            if case .failure(let error) = result {
                present(error)
            } else {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }
            backupDocument = NoteBackupDocument()
        }
        .fileImporter(
            isPresented: $isImportingBackup,
            allowedContentTypes: [.note1Backup, .json],
            allowsMultipleSelection: false
        ) { result in
            importBackup(result)
        }
        .onChange(of: visibleItems.map(\.id)) { _, visibleItemIDs in
            selection = HistorySelectionPolicy.visibleSelection(
                selection,
                visibleItemIDs: visibleItemIDs
            )
        }
        .noteErrorAlert($errorAlert)
    }

    private var emptyTitle: String {
        switch filter {
        case .all: "还没有记录"
        case .active: "没有未完成记录"
        case .completed: "还没有已完成记录"
        }
    }

    private var allVisibleSelected: Bool {
        !visibleItems.isEmpty && visibleItems.allSatisfy { selection.contains($0.id) }
    }

    private func toggleSelectAll() {
        let visibleIDs = Set(visibleItems.map(\.id))
        if allVisibleSelected {
            selection.subtract(visibleIDs)
        } else {
            selection.formUnion(visibleIDs)
        }
    }

    private func setFilter(_ nextFilter: RecordFilter) {
        filter = nextFilter
        selection = HistorySelectionPolicy.visibleSelection(
            selection,
            visibleItemIDs: store.recordItems(
                status: nextFilter.status,
                matching: query
            ).map(\.id)
        )
    }

    private func filterButton(_ item: RecordFilter) -> some View {
        Button(item.rawValue) {
            setFilter(item)
        }
        .noteFont(
            size: 13,
            weight: filter == item ? .semibold : .regular,
            relativeTo: .footnote
        )
        .foregroundStyle(NoteTheme.ink)
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, minHeight: 44)
        .background(
            filter == item ? Color.white.opacity(0.82) : Color.clear,
            in: Capsule()
        )
        .contentShape(Capsule())
        .accessibilityAddTraits(filter == item ? .isSelected : [])
        .accessibilityIdentifier("history.status.\(item.id)")
    }

    private func toggleSelection(_ item: ReviewItem) {
        if selection.contains(item.id) {
            selection.remove(item.id)
        } else {
            selection.insert(item.id)
        }
    }

    private func accessibilityValue(for item: ReviewItem) -> String {
        let status = item.status == .completed ? "已完成" : "未完成"
        guard selecting else { return status }
        return selection.contains(item.id)
            ? "\(status)，已选择"
            : "\(status)，未选择"
    }

    private func restore(_ item: ReviewItem) {
        do {
            try store.restore(item)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } catch {
            present(error)
        }
    }

    private func deleteSelected() {
        let items = selectedItems
        guard !items.isEmpty else { return }
        do {
            try store.deleteRecords(items)
            selection.subtract(items.map(\.id))
            if selection.isEmpty { selecting = false }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } catch {
            present(error)
        }
    }

    private func present(_ error: Error) {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
        errorAlert = UserFacingAlert.local(error: error)
    }

    private var backupFilename: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        formatter.dateFormat = "yyyy-MM-dd-HHmm"
        return "NOTE1-本机备份-\(formatter.string(from: Date()))"
    }

    private func exportBackup() {
        guard !isBackupOperationInProgress else { return }
        isBackupOperationInProgress = true
        Task { @MainActor in
            defer { isBackupOperationInProgress = false }
            do {
                backupDocument = NoteBackupDocument(
                    data: try await store.exportBackupData()
                )
                isExportingBackup = true
            } catch {
                present(error)
            }
        }
    }

    private func importBackup(_ result: Result<[URL], Error>) {
        guard !isBackupOperationInProgress else { return }
        isBackupOperationInProgress = true
        Task { @MainActor in
            defer { isBackupOperationInProgress = false }
            do {
                guard let url = try result.get().first else { return }
                let data = try await Task.detached(priority: .userInitiated) {
                    let accessed = url.startAccessingSecurityScopedResource()
                    defer {
                        if accessed {
                            url.stopAccessingSecurityScopedResource()
                        }
                    }
                    return try Data(
                        contentsOf: url,
                        options: [.mappedIfSafe]
                    )
                }.value
                try await store.validateBackupData(data)
                pendingRestoreData = data
                showingRestoreConfirmation = true
            } catch {
                present(error)
            }
        }
    }

    private func restorePendingBackup() {
        guard let data = pendingRestoreData,
              !isBackupOperationInProgress else {
            return
        }
        isBackupOperationInProgress = true
        Task { @MainActor in
            defer { isBackupOperationInProgress = false }
            do {
                try await store.restoreBackupData(data)
                pendingRestoreData = nil
                selection.removeAll()
                selecting = false
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            } catch {
                present(error)
                if store.isReadOnlyBecausePersistenceFailed {
                    pendingRestoreData = nil
                }
            }
        }
    }

    private func open(_ item: ReviewItem) {
        switch item {
        case .idea(let idea): onOpenIdea(idea.id)
        case .group(let group): onOpenGroup(group.id)
        }
    }
}
