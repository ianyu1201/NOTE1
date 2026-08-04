import SwiftUI
import UIKit

struct V02CollectionListView: View {
    @ObservedObject var store: V02Store
    @Binding var isWorkbenchPresented: Bool
    @Binding var isRequestingNewCollection: Bool
    let showGeneration: (V02Receipt) -> Void
    let reportError: (Error) -> Void
    @State private var endingRound: V02ThinkingRound?
    @State private var deletingCollection: V02ThinkingCollection?
    @State private var undoReceipt: V02Receipt?
    @State private var renamingCollection: V02ThinkingCollection?
    @State private var renamingText = ""
    @State private var editingInspiration: V02Inspiration?
    @State private var addingToCollection: V02ThinkingCollection?
    @State private var workingCollection: V02ThinkingCollection?
    @State private var isShowingHistory = false
    @State private var isPresentingSearch = false
    @State private var isCreatingCollection = false
    @State private var newCollectionName = ""
    @State private var capacityNotice = false

    private var endedCollections: [V02ThinkingCollection] {
        store.state.collections.filter { $0.currentRoundID == nil }
    }

    var body: some View {
        NavigationStack {
          ZStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                Text("你的灵感容器 · 持续积累，随时启发")
                    .noteFont(size: 13, relativeTo: .caption)
                    .foregroundStyle(NoteTheme.secondaryInk)
                    .frame(maxWidth: .infinity)
                    .padding(.top, -10)
                if V02CollectionOperationPolicy.showsEmptyState(activeCollectionCount: store.activeCollections.count) {
                    V02CollectionEmptyState()
                        .frame(maxWidth: .infinity, minHeight: 300)
                } else {
                    ForEach(store.activeCollections) { collection in
                        let round = store.state.rounds.first { $0.id == collection.currentRoundID }
                        let previewImage = previewImage(for: round)
                        Button {
                            workingCollection = collection
                            isWorkbenchPresented = true
                        } label: {
                            V02CollectionPaperCard(
                                collection: collection,
                                memberCount: round?.memberIDs.count ?? 0,
                                previewImage: previewImage,
                                updatedAt: updatedAt(for: round)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                }
                .padding(.horizontal, NoteTheme.horizontalPadding)
                .padding(.top, 10)
            }
            .scrollIndicators(.hidden)
            // The workbench is presented as a focused page-level layer. Do
            // not leave the covered collection rows in the VoiceOver order;
            // they remain underneath for the visual transition only.
            .accessibilityHidden(workingCollection != nil)
            .background(NoteTheme.background.ignoresSafeArea())
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Color.clear
                    .frame(height: V02NavigationLayoutPolicy.primaryContentBottomPadding)
                    .allowsHitTesting(false)
            }

            if let collection = workingCollection {
                V02CollectionWorkbenchView(
                    store: store,
                    collectionID: collection.id,
                    showGeneration: showGeneration,
                    reportError: reportError,
                    onClose: {
                        workingCollection = nil
                        isWorkbenchPresented = false
                    }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(.move(edge: .trailing).combined(with: .opacity))
                .zIndex(2)
            }
          }
          .toolbar(workingCollection == nil ? .hidden : .visible, for: .navigationBar)
          .notePrimaryHeader {
              if workingCollection == nil {
                  collectionHeader
              }
          }
        }
        .onChange(of: isRequestingNewCollection) { _, requested in
            guard requested else { return }
            isRequestingNewCollection = false
            requestNewCollection()
        }
        .alert("结束本轮构思？", isPresented: Binding(
            get: { endingRound != nil },
            set: { if !$0 { endingRound = nil } }
        ), presenting: endingRound) { round in
            Button("结束并生成小票") {
                finishRound(round)
            }
            Button("取消", role: .cancel) { endingRound = nil }
        } message: { _ in
            Text("确认后将结束本轮构思，并生成一张构思小票。")
        }
        .alert("新建构思集", isPresented: $isCreatingCollection) {
            TextField("构思集名称（可不填）", text: $newCollectionName)
            Button("新建") { createCollection() }
            Button("取消", role: .cancel) { newCollectionName = "" }
        } message: {
            Text("不填写名称时，将按顺序使用“构思集（1）”等默认名称。")
        }
        .overlay(alignment: .bottom) {
            if capacityNotice {
                Text("当前版本只支持 5 个构思集")
                    .noteFont(size: 14, weight: .semibold, relativeTo: .subheadline)
                    .foregroundStyle(NoteTheme.ink)
                    .padding(.horizontal, 18)
                    .frame(minHeight: 48)
                    .background(NoteTheme.paper.opacity(0.94), in: Capsule())
                    .overlay { Capsule().stroke(Color.white.opacity(0.82), lineWidth: 1) }
                    .shadow(color: NoteTheme.ink.opacity(0.10), radius: 18, y: 8)
                    .padding(.bottom, NoteTheme.navigationHeight + 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .task {
                        try? await Task.sleep(for: .seconds(2))
                        guard !Task.isCancelled else { return }
                        capacityNotice = false
                    }
            }
        }
        .overlay(alignment: .bottom) {
            if let undoReceipt {
                HStack {
                    Text("本轮构思已结束，\(undoReceipt.snapshot.members.count) 条灵感已收录。")
                        .lineLimit(2)
                    Spacer()
                    Button("撤回") {
                        do { try store.undoEndRound(undoReceipt.id) }
                        catch { reportError(error) }
                        self.undoReceipt = nil
                    }
                    .buttonStyle(PressScaleButtonStyle())
                    .padding(.horizontal, 15)
                    .frame(minHeight: 38)
                    .foregroundStyle(NoteTheme.ink)
                    .noteGlass(cornerRadius: 20, castsShadow: false)
                }
                .padding(12)
                .background(NoteTheme.paper.opacity(0.82), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay { RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.white.opacity(0.74), lineWidth: 1) }
                .padding(.horizontal, 16)
                .task(id: undoReceipt.id) {
                    try? await Task.sleep(for: .seconds(2))
                    guard !Task.isCancelled else { return }
                    self.undoReceipt = nil
                }
                .padding(.bottom, V02NavigationLayoutPolicy.transientBannerBottomPadding)
            }
        }
        .alert("删除构思集？", isPresented: Binding(
            get: { deletingCollection != nil },
            set: { if !$0 { deletingCollection = nil } }
        ), presenting: deletingCollection) { collection in
            Button("删除构思集", role: .destructive) {
                do { try store.deleteCollection(collection.id) }
                catch { reportError(error) }
                deletingCollection = nil
            }
            Button("取消", role: .cancel) { deletingCollection = nil }
        } message: { _ in
            Text("组内灵感会分别进入回收站，构思集和未结束轮次不会恢复；已有构思小票保持不变。")
        }
        .alert("构思集名称", isPresented: Binding(
            get: { renamingCollection != nil },
            set: { if !$0 { renamingCollection = nil } }
        ), presenting: renamingCollection) { collection in
            TextField("构思集名称", text: $renamingText)
            Button("保存") {
                do { try store.renameCollection(collection.id, name: renamingText) }
                catch { reportError(error) }
                renamingCollection = nil
            }
            Button("取消", role: .cancel) { renamingCollection = nil }
        } message: { _ in
            Text("名称只影响当前构思集，不改变既有构思小票快照。")
        }
        .fullScreenCover(item: $editingInspiration) { inspiration in
            V02InspirationEditorView(store: store, inspirationID: inspiration.id, reportError: reportError)
        }
        .sheet(item: $addingToCollection) { collection in
            V02ComposerView(store: store, initialCollectionID: collection.id, reportError: reportError)
        }
        .sheet(isPresented: $isShowingHistory) {
            V02CollectionHistoryView(store: store, reportError: reportError)
        }
        .sheet(isPresented: $isPresentingSearch) {
            V02SearchView(store: store, initialScope: .collections, locksScope: true)
        }
        .onChange(of: isWorkbenchPresented) { _, presented in
            if !presented { workingCollection = nil }
        }
    }

    private var collectionHeader: some View {
        ZStack {
            Text("构思集")
                .noteFontCapped(size: 20, maximumScale: 1.2, weight: .semibold, design: .rounded, relativeTo: .headline)
                .foregroundStyle(NoteTheme.ink)
                .accessibilityAddTraits(.isHeader)

            HStack(spacing: 10) {
                Menu {
                    Button("新建构思集", systemImage: "plus", action: requestNewCollection)
                } label: {
                    V02GlassIconLabel(systemName: "line.3.horizontal")
                }
                .accessibilityLabel("构思集菜单")

                Spacer(minLength: 0)

                Button {
                    isPresentingSearch = true
                } label: {
                    V02GlassIconLabel(systemName: "magnifyingglass")
                }
                .accessibilityLabel("搜索构思集")
                Button {
                    isShowingHistory = true
                } label: {
                    V02GlassIconLabel(systemName: "clock.arrow.circlepath")
                }
                .accessibilityLabel("构思历程")
            }
        }
        .padding(.horizontal, NoteTheme.horizontalPadding)
        .frame(height: V02NavigationLayoutPolicy.primaryHeaderHeight)
        .background(NoteTheme.background)
    }

    private func finishRound(_ round: V02ThinkingRound) {
        do {
            showGeneration(try store.endRound(round.id))
            endingRound = nil
        } catch { reportError(error) }
    }

    private func requestNewCollection() {
        guard V02CollectionOperationPolicy.canCreate(activeCollectionCount: store.activeCollections.count) else {
            withAnimation(.easeOut(duration: 0.2)) { capacityNotice = true }
            return
        }
        newCollectionName = ""
        isCreatingCollection = true
    }

    private func createCollection() {
        do {
            let trimmed = newCollectionName.trimmingCharacters(in: .whitespacesAndNewlines)
            let collection = try store.createCollectionAndRound(name: trimmed.isEmpty ? nil : trimmed)
            newCollectionName = ""
            workingCollection = collection
            isWorkbenchPresented = true
        } catch {
            reportError(error)
        }
    }

    private func previewImage(for round: V02ThinkingRound?) -> UIImage? {
        guard let round else { return nil }
        for memberID in round.memberIDs {
            guard let member = store.state.inspirations.first(where: { $0.id == memberID }) else { continue }
            for resourceID in member.resourceIDs {
                guard let resource = store.state.resources.first(where: { $0.id == resourceID }),
                      resource.mimeType.hasPrefix("image/") else { continue }
                if let image = UIImage(contentsOfFile: store.resourceURL(resource).path) { return image }
            }
        }
        return nil
    }

    private func updatedAt(for round: V02ThinkingRound?) -> Date? {
        guard let round else { return nil }
        let memberDates = round.memberIDs.compactMap { memberID in
            store.state.inspirations.first(where: { $0.id == memberID })?.updatedAt
        }
        return memberDates.max() ?? round.startedAt
    }
}
private struct V02CollectionPaperCard: View {
    let collection: V02ThinkingCollection
    let memberCount: Int
    let previewImage: UIImage?
    let updatedAt: Date?

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(NoteTheme.paper.opacity(0.24))
                .overlay { RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.white.opacity(0.48), lineWidth: 1) }
                .offset(x: 9, y: 9)
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(NoteTheme.paper.opacity(0.48))
                .overlay { RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.white.opacity(0.62), lineWidth: 1) }
                .offset(x: 5, y: 5)
            HStack(spacing: 15) {
                V02CollectionThumbnail(image: previewImage)
                VStack(alignment: .leading, spacing: 7) {
                    Text(collection.name)
                        .noteFont(size: 17, weight: .semibold, relativeTo: .headline)
                        .foregroundStyle(NoteTheme.ink)
                        .lineLimit(1)
                    Text("\(memberCount) / 10 条灵感")
                        .noteFont(size: 13, relativeTo: .subheadline)
                        .foregroundStyle(NoteTheme.secondaryInk)
                    if let updateLabel {
                        Text("更新 \(updateLabel)")
                            .noteFont(size: 11, relativeTo: .caption2)
                            .foregroundStyle(NoteTheme.secondaryInk.opacity(0.82))
                    }
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(NoteTheme.secondaryInk)
                    // Leave a visual exclusion zone for the shell-owned
                    // floating plus when the last visible card sits above
                    // the TabView; the whole card remains one hit target.
                    .padding(.trailing, 24)
            }
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity, minHeight: 148, alignment: .leading)
            .background(NoteTheme.paper.opacity(0.76), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.white.opacity(0.82), lineWidth: 1) }
        }
        .padding(.trailing, 9)
        .padding(.bottom, 9)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(collection.name)，\(memberCount) / 10 条灵感")
    }

    private var updateLabel: String? {
        updatedAt?.formatted(date: .numeric, time: .shortened)
    }
}

private struct V02CollectionThumbnail: View {
    let image: UIImage?

    @ViewBuilder
    var body: some View {
        if let image {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 76, height: 94)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(NoteTheme.canvas.opacity(0.82))
            VStack(spacing: 7) {
                Image(systemName: "sparkles")
                    .font(.system(size: 19, weight: .medium))
                Capsule()
                    .fill(NoteTheme.secondaryInk.opacity(0.28))
                    .frame(width: 34, height: 2)
                Capsule()
                    .fill(NoteTheme.secondaryInk.opacity(0.18))
                    .frame(width: 25, height: 2)
            }
            .foregroundStyle(NoteTheme.secondaryInk.opacity(0.72))
        }
        .frame(width: 76, height: 94)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct V02CollectionEmptyState: View {
    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(NoteTheme.paper.opacity(0.45))
                    .frame(width: 94, height: 52)
                    .rotationEffect(.degrees(10))
                    .offset(x: 18, y: -13)
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(NoteTheme.paper.opacity(0.58))
                    .frame(width: 94, height: 52)
                    .rotationEffect(.degrees(-8))
                    .offset(x: -15, y: -5)
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(NoteTheme.paper.opacity(0.88))
                    .frame(width: 112, height: 62)
                    .overlay {
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .stroke(NoteTheme.secondaryInk.opacity(0.22), lineWidth: 1)
                    }
            }
            .frame(height: 90)
            Text("还没有构思集")
                .noteFont(size: 20, weight: .semibold, relativeTo: .title3)
                .foregroundStyle(NoteTheme.ink)
            Text("将相关的灵感汇集成构思集，\n让思考的脉络自然生长。")
                .noteFont(size: 14, relativeTo: .body)
                .multilineTextAlignment(.center)
                .foregroundStyle(NoteTheme.secondaryInk)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct V02CollectionWorkbenchView: View {
    @ObservedObject var store: V02Store
    let collectionID: UUID
    let showGeneration: (V02Receipt) -> Void
    let reportError: (Error) -> Void
    let onClose: () -> Void
    @State private var index = 0
    @State private var memberText = ""
    @State private var editingMemberID: UUID?
    @State private var pendingMemberSave: Task<Void, Never>?
    @State private var isShowingOutline = false
    @State private var isAdding = false
    @State private var renamingText = ""
    @State private var isRenaming = false
    @State private var isEnding = false
    @State private var managingAttachments: V02Inspiration?
    @State private var deletingMember: V02Inspiration?
    @State private var memberCapacityNotice = false
    @FocusState private var editorFocused: Bool

    private var collection: V02ThinkingCollection? {
        store.state.collections.first { $0.id == collectionID }
    }
    private var round: V02ThinkingRound? {
        guard let id = collection?.currentRoundID else { return nil }
        return store.state.rounds.first { $0.id == id }
    }
    private var members: [V02Inspiration] {
        guard let round else { return [] }
        return round.memberIDs.compactMap { id in store.state.inspirations.first { $0.id == id } }
    }

    var body: some View {
        NavigationStack {
            workbenchContent
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.top, 8)
            .background(NoteTheme.background.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        persistEditingMember()
                        onClose()
                    } label: {
                        V02GlassIconLabel(systemName: "chevron.left")
                    }
                    .accessibilityLabel("返回构思集")
                }
                .noteSharedBackgroundHidden()
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 2) {
                        Text(collection?.name ?? "构思集")
                            .noteFontCapped(size: 17, maximumScale: 1.2, weight: .semibold, design: .rounded, relativeTo: .headline)
                            .foregroundStyle(NoteTheme.ink)
                            .lineLimit(1)
                        Text("\(members.count)/\(V02DomainEngine.maximumMembersPerCollection) 条灵感")
                            .noteFontCapped(size: 11, maximumScale: 1.2, relativeTo: .caption)
                            .foregroundStyle(NoteTheme.secondaryInk)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(collection?.name ?? "构思集")，\(members.count) 条灵感")
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        isEnding = true
                    } label: {
                        Label("结束本轮构思", systemImage: "flag")
                            .fontWeight(.semibold)
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel("结束本轮构思")
                    Menu {
                        Button("概览与排序", systemImage: "list.bullet") { isShowingOutline = true }
                        Button("改名", systemImage: "pencil") { renamingText = collection?.name ?? ""; isRenaming = true }
                        Button("删除构思集", systemImage: "trash", role: .destructive) {
                            do { try store.deleteCollection(collectionID); onClose() }
                            catch { reportError(error) }
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .fontWeight(.semibold)
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel("更多构思集操作")
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Button("上一张卡片") { moveCard(by: -1) }
                        .disabled(index <= 0)
                    Button("下一张卡片") { moveCard(by: 1) }
                        .disabled(index + 1 >= members.count)
                    Spacer()
                    Button("收起键盘") { editorFocused = false }
                }
            }
            .onAppear { syncMemberText() }
            .onChange(of: index) { _, _ in
                persistEditingMember()
                syncMemberText()
            }
            .onChange(of: members.map(\.id)) { _, ids in
                index = min(index, max(ids.count - 1, 0))
                syncMemberText()
            }
            .onDisappear { persistEditingMember() }
        }
        .overlay(alignment: .bottomTrailing) {
            if !editorFocused {
                V02FloatingComposerButton(
                    action: {
                        if !V02CollectionOperationPolicy.canAddMember(memberCount: members.count) {
                            withAnimation(.easeOut(duration: 0.2)) { memberCapacityNotice = true }
                        } else {
                            isAdding = true
                        }
                    },
                    label: "新增组内灵感"
                )
                .padding(.trailing, NoteTheme.horizontalPadding)
                .padding(.bottom, V02NavigationLayoutPolicy.workbenchFloatingComposerBottomPadding)
            }
        }
        .overlay(alignment: .bottom) {
            if memberCapacityNotice {
                Text("当前版本每个构思集只支持 10 条灵感")
                    .noteFont(size: 14, weight: .semibold, relativeTo: .subheadline)
                    .foregroundStyle(NoteTheme.ink)
                    .padding(.horizontal, 18)
                    .frame(minHeight: 48)
                    .background(NoteTheme.paper.opacity(0.94), in: Capsule())
                    .overlay { Capsule().stroke(Color.white.opacity(0.82), lineWidth: 1) }
                    .shadow(color: NoteTheme.ink.opacity(0.10), radius: 18, y: 8)
                    .padding(.bottom, NoteTheme.navigationHeight + 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .task {
                        try? await Task.sleep(for: .seconds(2))
                        guard !Task.isCancelled else { return }
                        memberCapacityNotice = false
                    }
            }
        }
        .sheet(isPresented: $isAdding) {
            V02ComposerView(store: store, initialCollectionID: collectionID, reportError: reportError)
        }
        .sheet(isPresented: $isShowingOutline) {
            NavigationStack {
                List {
                    ForEach(members) { member in
                        Text(member.text.isEmpty ? "未命名灵感" : member.text).lineLimit(1)
                    }
                    .onMove { source, destination in
                        guard var order = round?.memberIDs else { return }
                        order.move(fromOffsets: source, toOffset: destination)
                        do { try store.reorderMembers(order, in: round?.id ?? UUID()) }
                        catch { reportError(error) }
                    }
                }
                .navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(.hidden, for: .navigationBar)
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        Text("概览与排序")
                            .noteFontCapped(size: 20, maximumScale: 1.2, weight: .semibold, design: .rounded, relativeTo: .headline)
                            .foregroundStyle(NoteTheme.ink)
                            .accessibilityAddTraits(.isHeader)
                    }
                    ToolbarItem(placement: .primaryAction) { EditButton() }
                }
            }
        }
        .alert("构思集名称", isPresented: $isRenaming) {
            TextField("构思集名称", text: $renamingText)
            Button("保存") { do { try store.renameCollection(collectionID, name: renamingText) } catch { reportError(error) } }
            Button("取消", role: .cancel) {}
        }
        .alert("结束本轮构思？", isPresented: $isEnding) {
            Button("结束并生成小票") {
                finishRound()
            }
            Button("取消", role: .cancel) {}
        } message: { Text("确认后会生成一张固定构思小票。") }
        .sheet(item: $managingAttachments) { member in
            V02WorkbenchAttachmentSheet(
                store: store,
                inspirationID: member.id,
                reportError: reportError
            )
        }
        .alert("删除这条灵感？", isPresented: Binding(
            get: { deletingMember != nil },
            set: { if !$0 { deletingMember = nil } }
        ), presenting: deletingMember) { member in
            Button("移入回收站", role: .destructive) {
                do { _ = try store.deleteInspiration(member.id) }
                catch { reportError(error) }
                deletingMember = nil
            }
            Button("取消", role: .cancel) { deletingMember = nil }
        } message: { _ in
            Text("灵感会进入回收站，既有构思小票快照保持不变。")
        }
    }

    @ViewBuilder
    private var workbenchContent: some View {
        if collection == nil || round == nil {
            ContentUnavailableView("构思集已结束", systemImage: "folder")
        } else if members.isEmpty {
            ContentUnavailableView("先放入一条灵感", systemImage: "rectangle.stack")
        } else {
            // Keep workbench papers on the same first-screen geometry as
            // standalone card preview: the paper owns all space above the
            // shared TabView instead of stopping at a separate fixed height.
            GeometryReader { proxy in
                V02CardDeck(
                    cards: members,
                    index: $index,
                    height: V02CardPreviewLayoutPolicy.pageHeight(for: proxy.size.height),
                    cornerRadius: 18,
                    horizontalPadding: 26,
                    showsLayeredPaper: true,
                    isGestureEnabled: !editorFocused
                ) { member in
                    workbenchCard(member)
                }
            }
        }
    }

    private func workbenchCard(_ member: V02Inspiration) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(member.createdAt, format: .dateTime.month().day().hour().minute())
                .noteFont(size: 13, relativeTo: .caption)
                .foregroundStyle(NoteTheme.secondaryInk)
            TextEditor(text: Binding(
                get: { members.indices.contains(index) && member.id == members[index].id ? memberText : member.text },
                set: { newText in
                    memberText = newText
                    scheduleMemberSave(for: member.id)
                }
            ))
            .noteFont(size: 16, relativeTo: .body)
            .lineSpacing(5)
            .noteScrollBackgroundHidden()
            .focused($editorFocused)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            V02MemberAttachmentSummary(store: store, resourceIDs: member.resourceIDs)

            HStack(spacing: 0) {
                workbenchAction("附件", systemName: "paperclip") {
                    editorFocused = false
                    managingAttachments = member
                }
                workbenchAction("移出", systemName: "rectangle.portrait.and.arrow.right") {
                    editorFocused = false
                    do { try store.removeFromCollection(member.id) }
                    catch { reportError(error) }
                }
                Menu {
                    Button("概览与排序", systemImage: "list.bullet") { isShowingOutline = true }
                    Button("删除灵感", systemImage: "trash", role: .destructive) { deletingMember = member }
                } label: {
                    VStack(spacing: 5) {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 17, weight: .semibold))
                        Text("更多")
                            .noteFont(size: 12, weight: .medium, relativeTo: .caption)
                    }
                    .foregroundStyle(NoteTheme.secondaryInk)
                    .frame(maxWidth: .infinity, minHeight: 58)
                    .contentShape(Rectangle())
                }
                .accessibilityLabel("更多灵感操作")
            }
            .background(NoteTheme.paper.opacity(0.60), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.white.opacity(0.78), lineWidth: 1) }
            .shadow(color: NoteTheme.ink.opacity(0.05), radius: 12, y: 5)
        }
    }

    private func workbenchAction(_ title: String, systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: systemName)
                    .font(.system(size: 17, weight: .semibold))
                Text(title)
                    .noteFont(size: 12, weight: .medium, relativeTo: .caption)
            }
            .foregroundStyle(NoteTheme.secondaryInk)
            .frame(maxWidth: .infinity, minHeight: 58)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleButtonStyle())
    }

    private func moveCard(by direction: Int) {
        guard !members.isEmpty else { return }
        persistEditingMember()
        index = min(max(index + direction, 0), members.count - 1)
        syncMemberText()
    }

    private func finishRound() {
        guard let round else { return }
        // End-round snapshots must include the latest text even when the
        // debounce window has not elapsed yet.
        guard persistEditingMember() else { return }
        do {
            let receipt = try store.endRound(round.id)
            isEnding = false
            // Publish the generation overlay before leaving the workbench so
            // the root-page composer cannot flash during the transition.
            showGeneration(receipt)
            onClose()
        } catch { reportError(error) }
    }

    private func syncMemberText() {
        guard members.indices.contains(index) else {
            editingMemberID = nil
            memberText = ""
            return
        }
        editingMemberID = members[index].id
        memberText = members[index].text
    }

    private func scheduleMemberSave(for id: UUID) {
        pendingMemberSave?.cancel()
        let textToSave = memberText
        pendingMemberSave = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled else { return }
            do { try store.updateInspiration(id, text: textToSave) }
            catch { reportError(error) }
        }
    }

    @discardableResult
    private func persistEditingMember() -> Bool {
        pendingMemberSave?.cancel()
        guard let id = editingMemberID,
              let member = members.first(where: { $0.id == id }),
              member.text != memberText else { return true }
        do {
            try store.updateInspiration(id, text: memberText)
            return true
        } catch {
            reportError(error)
            return false
        }
    }
}

struct V02MemberAttachmentSummary: View {
    @ObservedObject var store: V02Store
    let resourceIDs: [UUID]
    var body: some View {
        if !resourceIDs.isEmpty {
            HStack(spacing: 8) {
                ForEach(resourceIDs, id: \.self) { id in
                    if let resource = store.state.resources.first(where: { $0.id == id }) {
                        if resource.mimeType.hasPrefix("audio/") || resource.source == .voiceInspiration {
                            V02AudioPlaybackControl(resource: resource, url: store.resourceURL(resource))
                        } else {
                            Image(systemName: resource.mimeType.hasPrefix("image/") ? "photo" : "doc")
                        }
                    }
                }
            }.foregroundStyle(NoteTheme.secondaryInk)
        }
    }
}

struct V02CollectionHistoryView: View {
    @ObservedObject var store: V02Store
    let reportError: (Error) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var isPresentingSearch = false

    private var collections: [V02ThinkingCollection] { store.state.collections.filter { $0.currentRoundID == nil } }
    var body: some View {
        NavigationStack {
            List(collections) { collection in
                HStack {
                    VStack(alignment: .leading) {
                        Text(collection.name)
                        Text("已结束构思，可从小票册查看成果")
                            .noteFont(size: 13, relativeTo: .caption)
                            .foregroundStyle(NoteTheme.secondaryInk)
                    }
                    Spacer()
                    Button("继续") { do { _ = try store.continueThinking(in: collection.id); dismiss() } catch { reportError(error) } }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .notePrimaryHeader {
                historyHeader
            }
            .sheet(isPresented: $isPresentingSearch) {
                V02SearchView(store: store, initialScope: .collections, locksScope: true)
            }
        }
    }

    private var historyHeader: some View {
        ZStack {
            Text("构思历程")
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
                .accessibilityLabel("搜索构思历程")
                Button("完成") { dismiss() }
                    .frame(minHeight: 48)
            }
        }
        .padding(.horizontal, NoteTheme.horizontalPadding)
        .frame(height: V02NavigationLayoutPolicy.primaryHeaderHeight)
        .background(NoteTheme.background)
    }
}

extension TimeInterval {
    var formattedDuration: String {
        let totalMinutes = max(0, Int(self) / 60)
        return totalMinutes >= 60 ? "\(totalMinutes / 60) 小时 \(totalMinutes % 60) 分" : "\(totalMinutes) 分"
    }
}

struct V02UndoTrashBanner: View {
    @ObservedObject var store: V02Store
    @Binding var entryIDs: Set<UUID>
    let noun: String
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
            .accessibilityLabel("\(noun)已移入回收站，可在两秒内撤回")
            .padding(12)
            .background(NoteTheme.background.opacity(0.92), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .padding(.horizontal, 16)
            .task(id: entryIDs) {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { return }
                entryIDs.removeAll()
            }
        }
    }
}
