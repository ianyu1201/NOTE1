import SwiftUI

struct V02TrashView: View {
    @ObservedObject var store: V02Store
    @Environment(\.dismiss) private var dismiss
    @State private var pendingPermanentDelete: V02TrashEntry?
    @State private var error: UserFacingAlert?
    @State private var isSelecting = false
    @State private var selectedIDs = Set<UUID>()
    @State private var isConfirmingEmpty = false

    private var inspirations: [V02TrashEntry] {
        store.state.trash.filter { if case .inspiration = $0.object { return true }; return false }
    }

    private var receipts: [V02TrashEntry] {
        store.state.trash.filter { if case .receipt = $0.object { return true }; return false }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                NoteTheme.background.ignoresSafeArea()
                Group {
                    if store.state.trash.isEmpty {
                        ScrollView {
                            EmptyStateView(
                                systemName: "trash",
                                title: "回收站为空",
                                message: "删除的灵感和构思小票会保留 30 天。"
                            )
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, 20)
                            .padding(.top, 72)
                        }
                    } else {
                        trashList
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("回收站")
                        .noteFontCapped(size: 20, maximumScale: 1.2, weight: .semibold, design: .rounded, relativeTo: .headline)
                        .foregroundStyle(NoteTheme.ink)
                        .accessibilityAddTraits(.isHeader)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { V02GlassIconLabel(systemName: "xmark") }
                    .accessibilityLabel("关闭回收站")
                }
                .noteSharedBackgroundHidden()
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button(isSelecting ? "取消选择" : "选择") {
                            isSelecting.toggle()
                            if !isSelecting { selectedIDs.removeAll() }
                        }
                        Button("清空回收站", role: .destructive) {
                            isConfirmingEmpty = true
                        }
                        .disabled(store.state.trash.isEmpty)
                    } label: { V02GlassIconLabel(systemName: "ellipsis") }
                    .accessibilityLabel("回收站更多操作")
                }
                .noteSharedBackgroundHidden()
            }
            .task {
                do { try store.purgeExpiredTrash() }
                catch { self.error = UserFacingAlert(error: error) }
            }
        }
        .alert("永久删除？", isPresented: Binding(
            get: { pendingPermanentDelete != nil },
            set: { if !$0 { pendingPermanentDelete = nil } }
        ), presenting: pendingPermanentDelete) { entry in
            Button("永久删除", role: .destructive) {
                do { try store.permanentlyDeleteTrash([entry.id]) }
                catch { self.error = UserFacingAlert(error: error) }
                pendingPermanentDelete = nil
            }
            Button("取消", role: .cancel) { pendingPermanentDelete = nil }
        } message: { _ in
            Text("此操作不能撤销，相关附件在没有其他引用时也会被永久清理。")
        }
        .confirmationDialog(
            selectedIDs.isEmpty ? "清空回收站？" : "永久删除选中项目？",
            isPresented: $isConfirmingEmpty,
            titleVisibility: .visible
        ) {
            Button(selectedIDs.isEmpty ? "清空回收站" : "永久删除", role: .destructive) {
                do {
                    if selectedIDs.isEmpty {
                        try store.emptyTrash()
                    } else {
                        try store.permanentlyDeleteTrash(selectedIDs)
                        selectedIDs.removeAll()
                        isSelecting = false
                    }
                } catch { self.error = UserFacingAlert(error: error) }
            }
            Button("取消", role: .cancel) { }
        } message: {
            Text("此操作不能撤销，相关附件在没有其他引用时也会被永久清理。")
        }
        .noteErrorAlert($error)
    }

    private var trashList: some View {
        List {
            if isSelecting {
                Section {
                    HStack {
                        Text("已选 \(selectedIDs.count) 项")
                        Spacer()
                        Button("全选") { selectedIDs = Set(store.state.trash.map(\.id)) }
                        Button("恢复") { restoreSelected() }
                            .disabled(selectedIDs.isEmpty)
                        Button("永久删除", role: .destructive) {
                            pendingPermanentDelete = nil
                            isConfirmingEmpty = true
                        }
                        .disabled(selectedIDs.isEmpty)
                    }
                    .buttonStyle(.bordered)
                }
            }
            Section {
                ForEach(inspirations) { entry in row(for: entry) }
            } header: {
                Text("灵感")
            } footer: {
                Text("在回收站中超过 30 天的灵感将会自动删除。")
            }

            Section {
                ForEach(receipts) { entry in row(for: entry) }
            } header: {
                Text("构思小票")
            } footer: {
                Text("在回收站中超过 30 天的构思小票将会自动删除。")
            }
        }
        .scrollContentBackground(.hidden)
        .listSectionSpacing(18)
        .listRowBackground(NoteTheme.paper.opacity(0.72))
    }

    @ViewBuilder
    private func row(for entry: V02TrashEntry) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if isSelecting {
                Button {
                    if selectedIDs.contains(entry.id) { selectedIDs.remove(entry.id) }
                    else { selectedIDs.insert(entry.id) }
                } label: {
                    Label(selectedIDs.contains(entry.id) ? "已选择" : "选择", systemImage: selectedIDs.contains(entry.id) ? "checkmark.square.fill" : "square")
                }
                .buttonStyle(.borderless)
            }
            Text(title(for: entry))
                .lineLimit(2)
            Text("将在 \(entry.deletedAt.addingTimeInterval(V02DomainEngine.trashRetention), style: .date) 后自动删除")
                .noteFont(size: 13, relativeTo: .caption)
                .foregroundStyle(NoteTheme.secondaryInk)
            HStack {
                Button("恢复") {
                    do { try store.restoreTrash(entry.id) }
                    catch { self.error = UserFacingAlert(error: error) }
                }
                .buttonStyle(.bordered)
                Button("永久删除", role: .destructive) {
                    pendingPermanentDelete = entry
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.vertical, 4)
        .foregroundStyle(NoteTheme.ink)
        .accessibilityElement(children: .contain)
    }

    private func title(for entry: V02TrashEntry) -> String {
        switch entry.object {
        case .inspiration(let inspiration):
            inspiration.text.isEmpty ? "未命名灵感" : inspiration.text
        case .receipt(let receipt):
            "构思小票 · \(receipt.snapshot.collectionName)"
        }
    }

    private func restoreSelected() {
        do {
            try store.restoreTrash(selectedIDs)
            selectedIDs.removeAll()
            isSelecting = false
        } catch {
            self.error = UserFacingAlert(error: error)
        }
    }
}
