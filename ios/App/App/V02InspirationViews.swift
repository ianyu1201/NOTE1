import SwiftUI
import UIKit

struct V02InspirationListView: View {
    @ObservedObject var store: V02Store
    @Binding var isSelecting: Bool
    let showSettings: () -> Void
    let showTrash: () -> Void
    let showSearch: () -> Void
    let showHistory: () -> Void
    let onEditingChange: (Bool) -> Void
    let reportError: (Error) -> Void
    @State private var selectedIDs = Set<UUID>()
    @State private var isConfirmingDelete = false
    @State private var editingInspiration: V02Inspiration?
    @State private var undoTrashEntryIDs = Set<UUID>()
    @AppStorage("v02.inspirationSortAscending") private var isAscending = false

    private var selectedInspirations: [V02Inspiration] {
        store.state.inspirations.filter { selectedIDs.contains($0.id) }
    }

    private var canReturnSelected: Bool {
        !selectedInspirations.isEmpty && selectedInspirations.allSatisfy { $0.cardFlowState == .tuckedAway }
    }

    private var sortedInspirations: [V02Inspiration] {
        store.state.inspirations.sorted {
            isAscending ? $0.createdAt < $1.createdAt : $0.createdAt > $1.createdAt
        }
    }

    private var dateGroups: [V02InspirationDateGroup] {
        let grouped = Dictionary(grouping: sortedInspirations) {
            Calendar.current.startOfDay(for: $0.createdAt)
        }
        return grouped.keys.sorted(by: isAscending ? (<) : (>)).map {
            V02InspirationDateGroup(date: $0, items: grouped[$0] ?? [])
        }
    }

    private func canAssignSelected(to collection: V02ThinkingCollection) -> Bool {
        guard !selectedInspirations.isEmpty,
              selectedInspirations.allSatisfy({ $0.collectionID == nil || $0.collectionID == collection.id }),
              let roundID = collection.currentRoundID,
              let round = store.state.rounds.first(where: { $0.id == roundID }) else { return false }
        let newIDs = selectedIDs.subtracting(round.memberIDs)
        return round.memberIDs.count + newIDs.count <= V02DomainEngine.maximumMembersPerCollection
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                if isSelecting { selectionToolbar }
                if store.state.inspirations.isEmpty {
                    EmptyStateView(systemName: "sparkles", title: "留住此刻", message: "点按右下角记录一条灵感。")
                        .frame(maxWidth: .infinity, minHeight: 360)
                } else {
                    ForEach(dateGroups) { group in
                        HStack(alignment: .firstTextBaseline) {
                            Text(NoteDateFormatter.group.string(from: group.date))
                                .noteFontCapped(size: 18, maximumScale: 1.2, weight: .semibold, relativeTo: .headline)
                                .foregroundStyle(NoteTheme.ink)
                            Spacer()
                            Text("\(group.items.count) 条灵感⌄")
                                .noteFontCapped(size: 13, maximumScale: 1.2, weight: .medium, relativeTo: .subheadline)
                                .foregroundStyle(NoteTheme.secondaryInk)
                        }
                        .padding(.top, 12)
                        .padding(.bottom, 4)
                        ForEach(group.items) { item in
                            V02InspirationTimelineRow(
                                inspiration: item,
                                collectionName: collectionName(for: item),
                                attachmentSymbols: attachmentSymbols(for: item),
                                thumbnailURL: thumbnailURL(for: item),
                                isSelecting: isSelecting,
                                isSelected: selectedIDs.contains(item.id),
                                onSelect: { toggleSelection(item.id) },
                                onLongPress: {
                                    // Long press is the batch-selection entry
                                    // point. Preserve an existing selection and
                                    // add the pressed item so repeated presses
                                    // can build a batch without losing context.
                                    isSelecting = true
                                    selectedIDs.insert(item.id)
                                },
                                onOpen: { editingInspiration = item; onEditingChange(true) }
                            )
                        }
                    }
                }
                }
                .padding(.horizontal, NoteTheme.horizontalPadding)
                .padding(.top, 6)
            }
            .scrollIndicators(.hidden)
            // `fullScreenCover` is hosted by this page's NavigationStack.
            // Explicitly remove the covered list from the accessibility tree
            // while the editor is active so VoiceOver cannot reach stale rows.
            .accessibilityHidden(editingInspiration != nil)
            .background(NoteTheme.background.ignoresSafeArea())
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Color.clear
                    .frame(height: V02NavigationLayoutPolicy.primaryContentBottomPadding)
                    .allowsHitTesting(false)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(editingInspiration == nil ? .visible : .hidden, for: .navigationBar)
            // Keep the native toolbar semantics while giving the title band an
            // opaque page surface. A transparent toolbar lets scrolled rows
            // bleed through the title and top controls on compact viewports.
            .toolbarBackground(NoteTheme.background, for: .navigationBar)
            .toolbar { inspirationToolbar }
        }
        .alert("删除选中的灵感？", isPresented: $isConfirmingDelete) {
            Button("删除", role: .destructive) {
                do {
                    undoTrashEntryIDs = try store.batchDeleteInspirations(selectedIDs)
                    selectedIDs.removeAll()
                    isSelecting = false
                } catch { reportError(error) }
            }
            Button("取消", role: .cancel) { }
        } message: {
            Text("删除后可在回收站中恢复，30 天后会自动永久清理。")
        }
        .fullScreenCover(item: $editingInspiration, onDismiss: { onEditingChange(false) }) { inspiration in
            V02InspirationEditorView(store: store, inspirationID: inspiration.id, reportError: reportError)
        }
        .overlay(alignment: .bottom) {
            V02UndoTrashBanner(store: store, entryIDs: $undoTrashEntryIDs, noun: "灵感", reportError: reportError)
                .padding(.bottom, V02NavigationLayoutPolicy.transientBannerBottomPadding)
        }
    }

    @ToolbarContentBuilder
    private var inspirationToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            V02GlobalMenuButton(showTrash: showTrash, showSettings: showSettings)
        }
        .noteSharedBackgroundHidden()
        ToolbarItem(placement: .principal) {
            Menu {
                Button("创建时间从新到旧") { isAscending = false }
                Button("创建时间从旧到新") { isAscending = true }
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("NOTE1")
                        .noteFontCapped(size: 20, maximumScale: 1.2, weight: .semibold, design: .rounded, relativeTo: .headline)
                        .tracking(4)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundStyle(NoteTheme.ink)
            }
            .accessibilityLabel("NOTE1，排序")
        }
        ToolbarItem(placement: .topBarTrailing) {
            HStack(spacing: 4) {
                V02GlassIconButton(
                    systemName: "clock.arrow.circlepath",
                    label: "历史记录",
                    action: showHistory
                )
                V02GlassIconButton(
                    systemName: "magnifyingglass",
                    label: "搜索",
                    action: showSearch
                )
            }
        }
        .noteSharedBackgroundHidden()
    }

    private var selectionToolbar: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("已选 \(selectedIDs.count) 条")
                    .noteFont(size: 15, weight: .semibold, relativeTo: .subheadline)
                Spacer()
                Button("全选") { selectedIDs = Set(store.state.inspirations.map(\.id)) }
                Button("取消") {
                    isSelecting = false
                    selectedIDs.removeAll()
                }
            }
            ViewThatFits(in: .horizontal) {
                selectionActions(axis: .horizontal)
                    .fixedSize(horizontal: true, vertical: false)
                selectionActions(axis: .vertical)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .noteGlass(cornerRadius: 20, castsShadow: false)
        .padding(.bottom, 10)
    }

    private enum SelectionActionAxis { case horizontal, vertical }

    @ViewBuilder
    private func selectionActions(axis: SelectionActionAxis) -> some View {
        if axis == .horizontal {
            HStack(spacing: 16) {
                selectionActionButtons
            }
            .noteFont(size: 14, weight: .medium, relativeTo: .subheadline)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                selectionActionButtons
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .noteFont(size: 14, weight: .medium, relativeTo: .subheadline)
        }
    }

    @ViewBuilder
    private var selectionActionButtons: some View {
        Button("删除", role: .destructive) { isConfirmingDelete = true }
            .frame(minHeight: 44)
            .disabled(selectedIDs.isEmpty)
        Button("放回卡片流") {
            do { try store.batchReturnToCardFlow(selectedIDs); selectedIDs.removeAll() }
            catch { reportError(error) }
        }
        .frame(minHeight: 44)
        .disabled(!canReturnSelected)
        Menu {
            ForEach(store.activeCollections) { collection in
                Button(collection.name) {
                    do { try store.batchAssign(selectedIDs, to: collection.id); selectedIDs.removeAll() }
                    catch { reportError(error) }
                }
                .disabled(!canAssignSelected(to: collection))
            }
        } label: {
            Label("归入构思集", systemImage: "folder.badge.plus")
                .frame(minHeight: 44)
        }
        .disabled(selectedIDs.isEmpty || store.activeCollections.isEmpty)
    }

    private func toggleSelection(_ id: UUID) {
        if selectedIDs.contains(id) { selectedIDs.remove(id) }
        else { selectedIDs.insert(id) }
    }

    private func collectionName(for item: V02Inspiration) -> String? {
        guard let collectionID = item.collectionID else { return nil }
        return store.state.collections.first(where: { $0.id == collectionID })?.name
    }

    private func attachmentSymbols(for item: V02Inspiration) -> [String] {
        item.resourceIDs.compactMap { resourceID in
            guard let resource = store.state.resources.first(where: { $0.id == resourceID }) else { return nil }
            if resource.mimeType.hasPrefix("audio/") || resource.source == .voiceInspiration { return "waveform" }
            if resource.mimeType.hasPrefix("image/") { return "photo" }
            if resource.mimeType == "application/pdf" { return "doc.richtext" }
            return "doc"
        }
    }

    private func thumbnailURL(for item: V02Inspiration) -> URL? {
        item.resourceIDs.compactMap { resourceID in
            guard let resource = store.state.resources.first(where: { $0.id == resourceID }),
                  resource.mimeType.hasPrefix("image/") else { return nil }
            return store.resourceURL(resource)
        }.first
    }

}
private struct V02InspirationDateGroup: Identifiable {
    let date: Date
    let items: [V02Inspiration]
    var id: Date { date }
}

private struct V02InspirationTimelineRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let inspiration: V02Inspiration
    let collectionName: String?
    let attachmentSymbols: [String]
    let thumbnailURL: URL?
    let isSelecting: Bool
    let isSelected: Bool
    let onSelect: () -> Void
    let onLongPress: () -> Void
    let onOpen: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if isSelecting {
                Button(action: onSelect) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 21, weight: .medium))
                        .foregroundStyle(isSelected ? NoteTheme.ink : NoteTheme.secondaryInk)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isSelected ? "取消选择" : "选择灵感")
            }
            Button(action: onOpen) {
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 7) {
                        Text(inspiration.text.isEmpty ? "未命名灵感" : inspiration.text)
                            .noteFont(size: 16, relativeTo: .body)
                            .foregroundStyle(NoteTheme.ink)
                            .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 3)
                            .multilineTextAlignment(.leading)
                        HStack(spacing: 8) {
                            Text(NoteDateFormatter.display(inspiration.createdAt))
                            if let collectionName { Text("构思集 · \(collectionName)") }
                            if inspiration.cardFlowState == .tuckedAway { Text("已收起") }
                        }
                        .noteFontCapped(size: 12, maximumScale: 1.35, relativeTo: .caption)
                        .foregroundStyle(NoteTheme.secondaryInk)
                        if !attachmentSymbols.isEmpty {
                            HStack(spacing: 7) {
                                ForEach(Array(attachmentSymbols.prefix(3).enumerated()), id: \.offset) { _, symbol in
                                    Image(systemName: symbol)
                                }
                                Text("附件 \(inspiration.resourceIDs.count) 个")
                            }
                            .noteFontCapped(size: 12, maximumScale: 1.35, relativeTo: .caption)
                            .foregroundStyle(NoteTheme.secondaryInk)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    if let thumbnailURL,
                       let image = UIImage(contentsOfFile: thumbnailURL.path) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 54, height: 54)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .accessibilityHidden(true)
                    } else if let symbol = attachmentSymbols.first {
                        Image(systemName: symbol)
                            .font(.system(size: 19, weight: .medium))
                            .foregroundStyle(NoteTheme.secondaryInk)
                            .frame(width: 48, height: 48)
                            .background(NoteTheme.ink.opacity(0.045), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .accessibilityHidden(true)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        // Let a completed long press win over the nested tap button. Using a
        // simultaneous recognizer would also fire the button on release and
        // incorrectly open the editor after entering batch selection.
        .highPriorityGesture(
            LongPressGesture(minimumDuration: 0.5)
                .onEnded { _ in onLongPress() }
        )
        .padding(.vertical, 14)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(NoteTheme.divider)
                .frame(height: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: "选择灵感") { onLongPress() }
    }
}
