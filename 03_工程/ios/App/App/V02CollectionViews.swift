import SwiftUI

/// Keeps the workbench and its end-round confirmation as two mutually
/// exclusive accessibility surfaces. The confirmation is a SwiftUI overlay
/// in the same visual host, so the policy is deliberately state-only and can
/// be asserted without constructing a view hierarchy.
enum V04EndRoundAccessibilityPolicy {
    static func hidesWorkbench(isPresented: Bool) -> Bool {
        isPresented
    }

    static func showsConfirmation(isPresented: Bool) -> Bool {
        isPresented
    }
}

struct V02CollectionListView: View {
    @ObservedObject var store: V02Store
    @Binding var isWorkbenchPresented: Bool
    let isGenerationPresented: Bool
    let showSettings: () -> Void
    let showTrash: () -> Void
    let showSearch: () -> Void
    let showHistory: () -> Void
    let showGeneration: (V02Receipt) -> Void
    let reportError: (Error) -> Void
    @State private var deletingCollection: V02ThinkingCollection?
    @State private var renamingCollection: V02ThinkingCollection?
    @State private var renamingText = ""
    @State private var editingInspiration: V02Inspiration?
    @State private var addingToCollection: V02ThinkingCollection?
    @State private var workingCollection: V02ThinkingCollection?

    private var endedCollections: [V02ThinkingCollection] {
        store.state.collections.filter { $0.currentRoundID == nil }
    }

    var body: some View {
        NavigationStack {
          ZStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                if V02CollectionOperationPolicy.showsEmptyState(activeCollectionCount: store.activeCollections.count) {
                    V02CollectionEmptyState()
                        .frame(maxWidth: .infinity, minHeight: 300)
                } else {
                    ForEach(store.activeCollections) { collection in
                        let round = store.state.rounds.first { $0.id == collection.currentRoundID }
                        Button {
                            workingCollection = collection
                            isWorkbenchPresented = true
                        } label: {
                            V02CollectionRow(
                                collection: collection,
                                memberCount: round?.memberIDs.count ?? 0,
                                updatedAt: updatedAt(for: round)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                }
                .padding(.horizontal, V02PrimaryContentLayoutPolicy.horizontalInset)
                .padding(.top, V02PrimaryContentLayoutPolicy.topSpacing)
            }
            .scrollIndicators(.hidden)
            // The workbench is presented as a focused page-level layer. Do
            // not leave the covered collection rows in the VoiceOver order;
            // they remain underneath for the visual transition only.
            .accessibilityHidden(workingCollection != nil || isGenerationPresented)
            .background(NoteTheme.canvas.ignoresSafeArea())
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
          .background(NoteTheme.canvas.ignoresSafeArea())
          .toolbar(.hidden, for: .navigationBar)
          .notePrimaryHeader {
              if workingCollection == nil && !isGenerationPresented {
                  collectionHeader
              }
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
        .onChange(of: isWorkbenchPresented) { _, presented in
            if !presented { workingCollection = nil }
        }
    }

    private var collectionHeader: some View {
        V02PrimaryPageHeader(
            showTrash: showTrash,
            showSettings: showSettings,
            showHistory: showHistory,
            showSearch: showSearch
        ) {
            V02PrimaryHeaderTitle()
        }
    }

    private func updatedAt(for round: V02ThinkingRound?) -> Date? {
        guard let round else { return nil }
        let memberDates = round.memberIDs.compactMap { memberID in
            store.state.inspirations.first(where: { $0.id == memberID })?.updatedAt
        }
        return memberDates.max() ?? round.startedAt
    }
}
private struct V02CollectionRow: View {
    let collection: V02ThinkingCollection
    let memberCount: Int
    let updatedAt: Date?

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "folder")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(NoteTheme.ink)
                .frame(width: 44, height: 44)
                .background(NoteTheme.selectedGlass.opacity(0.55), in: RoundedRectangle(cornerRadius: 14))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text(collection.name)
                    .noteFont(size: 17, weight: .semibold, relativeTo: .headline)
                    .foregroundStyle(NoteTheme.ink)
                    .lineLimit(1)
                Text(metadata)
                    .noteFont(size: 13, relativeTo: .subheadline)
                    .foregroundStyle(NoteTheme.secondaryInk)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(NoteTheme.secondaryInk)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, minHeight: 82, alignment: .leading)
        .overlay(alignment: .bottom) {
            Rectangle().fill(NoteTheme.divider).frame(height: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(collection.name)，\(metadata)")
    }

    private var metadata: String {
        let update = updatedAt?.formatted(date: .abbreviated, time: .shortened) ?? "刚刚"
        return "\(memberCount) 条灵感 · 更新 \(update)"
    }
}

private struct V02CollectionEmptyState: View {
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "folder")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(NoteTheme.ink)
            Text("还没有构思集")
                .noteFont(size: 20, weight: .semibold, relativeTo: .title3)
                .foregroundStyle(NoteTheme.ink)
            Text("在卡片预览中点按“归入构思集”，\n可将当前灵感归入现有或新构思集。")
                .noteFont(size: 14, relativeTo: .body)
                .multilineTextAlignment(.center)
                .foregroundStyle(NoteTheme.secondaryInk)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct V04EndRoundConfirmationView: View {
    let round: V02ThinkingRound
    let members: [V02Inspiration]
    let onGenerate: () -> Void
    let onCancel: () -> Void

    private var durationText: String {
        let minutes = max(1, Int(Date.now.timeIntervalSince(round.startedAt) / 60))
        return "\(minutes) 分钟"
    }

    private var attachmentCount: Int {
        members.reduce(0) { $0 + $1.resourceIDs.count }
    }

    var body: some View {
        VStack(spacing: 0) {
            Text("已结束本轮构思")
                .noteFont(size: 24, weight: .semibold, design: .rounded, relativeTo: .title2)
                .foregroundStyle(NoteTheme.ink)
                .accessibilityAddTraits(.isHeader)
                .padding(.top, 34)

            VStack(spacing: 0) {
                summaryRow("构思时间", value: durationText)
                summaryRow("灵感数量", value: "\(members.count)")
                summaryRow("附件数量", value: "\(attachmentCount)")
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 8)
            .frame(maxWidth: 330)
            .noteGlass(cornerRadius: 24, castsShadow: false)
            .padding(.top, 32)

            Spacer(minLength: 28)

            VStack(spacing: 12) {
                Button("生成小票", action: onGenerate)
                    .noteFont(size: 16, weight: .semibold, relativeTo: .body)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(NoteTheme.ink, in: Capsule())
                    .buttonStyle(PressScaleButtonStyle())
                Button("取消", action: onCancel)
                    .noteFont(size: 16, weight: .medium, relativeTo: .body)
                    .foregroundStyle(NoteTheme.ink)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .noteGlass(cornerRadius: 24, castsShadow: false)
                    .buttonStyle(RoundGlassPressButtonStyle())
            }
            .frame(maxWidth: 330)
            .padding(.bottom, V02NavigationLayoutPolicy.primaryContentBottomPadding)
        }
        .padding(.horizontal, NoteTheme.horizontalPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(NoteTheme.canvas.ignoresSafeArea())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("v04.end-round-confirmation")
    }

    private func summaryRow(_ title: String, value: String) -> some View {
        LabeledContent(title, value: value)
            .noteFont(size: 15, relativeTo: .body)
            .foregroundStyle(NoteTheme.ink)
            .frame(minHeight: 52)
            .overlay(alignment: .bottom) {
                Rectangle().fill(NoteTheme.divider).frame(height: 1)
            }
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
    @State private var memberSessionOriginalText = ""
    @State private var editingMemberID: UUID?
    @State private var pendingMemberSave: Task<Void, Never>?
    @State private var isShowingOutline = false
    @State private var outlineEditMode: EditMode = .inactive
    @State private var isAdding = false
    @State private var renamingText = ""
    @State private var isRenaming = false
    @State private var isEnding = false
    @State private var managingAttachments: V02Inspiration?
    @State private var deletingMember: V02Inspiration?
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
    private var isPresentingWorkbenchSheet: Bool {
        isAdding || isShowingOutline || managingAttachments != nil
    }

    var body: some View {
        ZStack {
            if !V04EndRoundAccessibilityPolicy.hidesWorkbench(isPresented: isEnding) {
                NavigationStack {
                    workbenchContent
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .padding(.top, 8)
                        .background(NoteTheme.canvas.ignoresSafeArea())
                        .toolbar(.hidden, for: .navigationBar)
                        .notePrimaryHeader { workbenchHeader }
                        .toolbar {
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
                    .accessibilityHidden(isPresentingWorkbenchSheet)
            } else if V04EndRoundAccessibilityPolicy.showsConfirmation(isPresented: isEnding), let round {
                V04EndRoundConfirmationView(
                    round: round,
                    members: members,
                    onGenerate: finishRound,
                    onCancel: { isEnding = false }
                )
                .transition(.opacity)
                .zIndex(5)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if !editorFocused && !isEnding {
                V02FloatingComposerButton(
                    action: {
                        isAdding = true
                    },
                    label: "新增组内灵感"
                )
                .padding(.trailing, NoteTheme.horizontalPadding)
                .padding(.bottom, V02NavigationLayoutPolicy.workbenchFloatingComposerBottomPadding)
            }
        }
        .background {
            V02PresentedContentAccessibilityIsolation(isPresented: isPresentingWorkbenchSheet)
                .frame(width: 0, height: 0)
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
                .environment(\.editMode, $outlineEditMode)
                .scrollContentBackground(.hidden)
                .background(NoteTheme.canvas.ignoresSafeArea())
                .toolbar(.hidden, for: .navigationBar)
                .notePrimaryHeader { outlineHeader }
            }
        }
        .onChange(of: isShowingOutline) { _, isPresented in
            if !isPresented { outlineEditMode = .inactive }
        }
        .alert("构思集名称", isPresented: $isRenaming) {
            TextField("构思集名称", text: $renamingText)
            Button("保存") { do { try store.renameCollection(collectionID, name: renamingText) } catch { reportError(error) } }
            Button("取消", role: .cancel) {}
        }
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

    private var workbenchHeader: some View {
        GeometryReader { proxy in
            let trailingWidth = NoteTheme.controlSize * 2 + 8
            let centeredTitleWidth = max(
                56,
                min(
                    104,
                    proxy.size.width - 2 * (NoteTheme.horizontalPadding + trailingWidth + 6)
                )
            )

            ZStack {
                VStack(spacing: 2) {
                    Text(collection?.name ?? "构思集")
                        .noteFontCapped(
                            size: 17,
                            maximumScale: 1.2,
                            weight: .semibold,
                            design: .rounded,
                            relativeTo: .headline
                        )
                        .foregroundStyle(NoteTheme.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                    Text("\(members.count) 条灵感")
                        .noteFontCapped(size: 11, maximumScale: 1.2, relativeTo: .caption)
                        .foregroundStyle(NoteTheme.secondaryInk)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }
                .frame(width: centeredTitleWidth)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(collection?.name ?? "构思集")，\(members.count) 条灵感")

                HStack(spacing: 0) {
                    V02GlassIconButton(
                        systemName: "chevron.left",
                        label: "返回构思集"
                    ) {
                        persistEditingMember()
                        onClose()
                    }

                    Spacer(minLength: 0)

                    HStack(spacing: 8) {
                        V02GlassIconButton(
                            systemName: "flag",
                            label: "结束本轮构思",
                            action: { isEnding = true }
                        )
                        Menu {
                            Button("概览与排序", systemImage: "list.bullet") { isShowingOutline = true }
                            Button("改名", systemImage: "pencil") {
                                renamingText = collection?.name ?? ""
                                isRenaming = true
                            }
                            Button("删除构思集", systemImage: "trash", role: .destructive) {
                                do { try store.deleteCollection(collectionID); onClose() }
                                catch { reportError(error) }
                            }
                        } label: {
                            V02GlassIconLabel(systemName: "ellipsis")
                        }
                        .accessibilityLabel("更多构思集操作")
                    }
                }
            }
            .padding(.horizontal, NoteTheme.horizontalPadding)
        }
        .frame(height: V02NavigationLayoutPolicy.pageHeaderHeight)
        .background(NoteTheme.canvas)
    }

    private var outlineHeader: some View {
        V02SecondaryPageHeader("概览与排序") {
            V02GlassIconButton(
                systemName: "xmark",
                label: "关闭概览与排序"
            ) {
                outlineEditMode = .inactive
                isShowingOutline = false
            }
        } trailing: {
            V02GlassTextButton(title: outlineEditMode.isEditing ? "完成" : "编辑") {
                outlineEditMode = outlineEditMode.isEditing ? .inactive : .active
            }
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
                            .noteFontCapped(
                                size: 12,
                                maximumScale: 1.25,
                                weight: .medium,
                                relativeTo: .caption
                            )
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
                    .noteFontCapped(
                        size: 12,
                        maximumScale: 1.25,
                        weight: .medium,
                        relativeTo: .caption
                    )
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
            memberSessionOriginalText = ""
            return
        }
        editingMemberID = members[index].id
        memberText = members[index].text
        memberSessionOriginalText = memberText
    }

    private func scheduleMemberSave(for id: UUID) {
        pendingMemberSave?.cancel()
        let textToSave = memberText
        pendingMemberSave = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled else { return }
            do {
                try store.updateInspiration(
                    id,
                    text: textToSave,
                    recordsEffectiveEdit: false
                )
            }
            catch { reportError(error) }
        }
    }

    @discardableResult
    private func persistEditingMember() -> Bool {
        pendingMemberSave?.cancel()
        guard let id = editingMemberID else { return true }
        do {
            try store.finishInspirationEditSession(
                id,
                originalText: memberSessionOriginalText,
                finalText: memberText
            )
            memberSessionOriginalText = memberText
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

/// The four root pages route to one shared history center. Keep the scope and
/// entry policy free of view state so the ordering and exclusions can be
/// asserted without constructing SwiftUI views.
enum V02HistoryScope: String, CaseIterable, Identifiable {
    case all
    case tuckedAway
    case thinkingHistory
    case receipts

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "全部"
        case .tuckedAway: "已收起"
        case .thinkingHistory: "构思历程"
        case .receipts: "小票"
        }
    }
}

enum V02HistoryEntry: Identifiable {
    case tuckedAwayInspiration(V02Inspiration)
    case endedRound(V02ThinkingRound, collection: V02ThinkingCollection?)
    case receipt(V02Receipt)

    var id: String {
        switch self {
        case .tuckedAwayInspiration(let inspiration): "inspiration.\(inspiration.id.uuidString)"
        case .endedRound(let round, _): "round.\(round.id.uuidString)"
        case .receipt(let receipt): "receipt.\(receipt.id.uuidString)"
        }
    }

    var date: Date {
        switch self {
        case .tuckedAwayInspiration(let inspiration): inspiration.updatedAt
        case .endedRound(let round, _): round.endedAt ?? round.startedAt
        case .receipt(let receipt): receipt.createdAt
        }
    }

    var scope: V02HistoryScope {
        switch self {
        case .tuckedAwayInspiration: .tuckedAway
        case .endedRound: .thinkingHistory
        case .receipt: .receipts
        }
    }
}

enum V02HistoryCenterPolicy {
    static func entries(
        state: V02DomainState,
        scope: V02HistoryScope = .all
    ) -> [V02HistoryEntry] {
        var values: [V02HistoryEntry] = []

        if scope == .all || scope == .tuckedAway {
            // A tucked-away entry is historical only while it remains an
            // independent inspiration. Collection members belong to their
            // round/history, not to this bucket.
            values += state.inspirations
                .filter { $0.collectionID == nil && $0.cardFlowState == .tuckedAway }
                .map(V02HistoryEntry.tuckedAwayInspiration)
        }

        if scope == .all || scope == .thinkingHistory {
            let collectionsByID = Dictionary(uniqueKeysWithValues: state.collections.map { ($0.id, $0) })
            values += state.rounds
                .filter { $0.state == .ended }
                .map { V02HistoryEntry.endedRound($0, collection: collectionsByID[$0.collectionID]) }
        }

        if scope == .all || scope == .receipts {
            values += state.receipts.map(V02HistoryEntry.receipt)
        }

        return values.sorted {
            if $0.date != $1.date { return $0.date > $1.date }
            // Stable tie-breaking keeps deterministic test fixtures and
            // avoids rows jumping when two objects share a timestamp.
            return $0.id < $1.id
        }
    }
}

struct V02CollectionHistoryView: View {
    @ObservedObject var store: V02Store
    let reportError: (Error) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var scope: V02HistoryScope = .all
    @State private var selectedEntry: V02HistoryEntry?

    private var entries: [V02HistoryEntry] {
        V02HistoryCenterPolicy.entries(state: store.state, scope: scope)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    scopePicker
                    if entries.isEmpty {
                        V02HistoryEmptyState(scope: scope)
                            .frame(maxWidth: .infinity, minHeight: 360)
                            .padding(.top, 26)
                    } else if scope == .all {
                        V02HistoryTimeline(entries: entries) { selectedEntry = $0 }
                    } else {
                        V02HistoryEntryList(entries: entries) { selectedEntry = $0 }
                    }
                }
                .padding(.horizontal, NoteTheme.horizontalPadding)
                .padding(.bottom, V02NavigationLayoutPolicy.primaryContentBottomPadding)
            }
            .scrollIndicators(.hidden)
            .background(NoteTheme.background.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .notePrimaryHeader { historyHeader }
        }
        .accessibilityHidden(selectedEntry != nil)
        .background {
            V02PresentedContentAccessibilityIsolation(isPresented: selectedEntry != nil)
                .frame(width: 0, height: 0)
        }
        .sheet(item: $selectedEntry) { entry in
            switch entry {
            case .tuckedAwayInspiration(let inspiration):
                V02HistoryInspirationDetailView(
                    store: store,
                    inspirationID: inspiration.id,
                    reportError: reportError
                )
            case .endedRound(let round, let collection):
                V02HistoryCollectionDetailView(
                    store: store,
                    round: round,
                    collection: collection,
                    reportError: reportError
                )
            case .receipt(let receipt):
                V02ReceiptDetailView(store: store, receipt: receipt)
            }
        }
    }

    private var historyHeader: some View {
        V02SecondaryPageHeader("历史") {
            V02GlassIconButton(
                systemName: "chevron.left",
                label: "返回",
                action: { dismiss() }
            )
        } trailing: {
            V02SecondaryHeaderPlaceholder()
        }
    }

    private var scopePicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            V02ScopeSectionLabel()

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(V02HistoryScope.allCases) { item in
                        Button {
                            withAnimation(.easeOut(duration: 0.18)) { scope = item }
                        } label: {
                            Text(item.title)
                                .noteFont(size: 16, weight: .semibold, relativeTo: .body)
                                .foregroundStyle(scope == item ? Color.white : NoteTheme.ink)
                                .frame(minWidth: 60, minHeight: 46)
                                .padding(.horizontal, 4)
                                .background(scope == item ? NoteTheme.ink : Color.clear, in: Capsule())
                        }
                        .buttonStyle(PressScaleButtonStyle())
                        .accessibilityAddTraits(scope == item ? .isSelected : [])
                        .accessibilityLabel("当前范围，\(item.title)")
                    }
                }
                .padding(4)
            }
            .noteGlass(cornerRadius: 26, castsShadow: false)
        }
        .padding(.top, 14)
        .padding(.bottom, 20)
    }
}

private struct V02HistoryTimeline: View {
    let entries: [V02HistoryEntry]
    let onSelect: (V02HistoryEntry) -> Void

    private var groups: [(date: Date, entries: [V02HistoryEntry])] {
        let grouped = Dictionary(grouping: entries) { Calendar.current.startOfDay(for: $0.date) }
        return grouped.keys.sorted(by: >).map { date in
            (date: date, entries: grouped[date, default: []].sorted { $0.date > $1.date })
        }
    }

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 22) {
            ForEach(groups, id: \.date) { group in
                HStack(alignment: .top, spacing: 10) {
                    V02HistoryDateRail(date: group.date, rowCount: group.entries.count)
                        .frame(width: 58)
                    VStack(spacing: 12) {
                        ForEach(group.entries) { entry in
                            V02HistoryEntryRow(entry: entry, onSelect: onSelect)
                        }
                    }
                }
            }
        }
    }
}

private struct V02HistoryEntryList: View {
    let entries: [V02HistoryEntry]
    let onSelect: (V02HistoryEntry) -> Void

    var body: some View {
        LazyVStack(spacing: 12) {
            ForEach(entries) { entry in
                V02HistoryEntryRow(entry: entry, onSelect: onSelect)
            }
        }
    }
}

private struct V02HistoryDateRail: View {
    let date: Date
    let rowCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(date, format: .dateTime.month().day())
                .noteFont(size: 16, weight: .semibold, relativeTo: .headline)
                .foregroundStyle(NoteTheme.secondaryInk)
            Text(date, format: .dateTime.weekday(.wide))
                .noteFont(size: 13, relativeTo: .caption)
                .foregroundStyle(NoteTheme.secondaryInk)
            VStack(spacing: 0) {
                Circle()
                    .fill(NoteTheme.ink)
                    .frame(width: 10, height: 10)
                    .padding(.top, 10)
                Rectangle()
                    .fill(NoteTheme.secondaryInk.opacity(0.35))
                    .frame(width: 1)
                    .frame(maxHeight: .infinity)
            }
            .frame(maxHeight: .infinity, alignment: .top)
            .accessibilityHidden(true)
        }
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(date.formatted(date: .abbreviated, time: .omitted))，\(rowCount) 条历史内容")
    }
}

private struct V02HistoryEntryRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let entry: V02HistoryEntry
    let onSelect: (V02HistoryEntry) -> Void

    var body: some View {
        Button { onSelect(entry) } label: {
            HStack(alignment: .top, spacing: 14) {
                icon
                VStack(alignment: .leading, spacing: 7) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(kindLabel)
                            .noteFont(size: 13, weight: .semibold, relativeTo: .subheadline)
                            .foregroundStyle(NoteTheme.secondaryInk)
                        Spacer(minLength: 4)
                        Text(NoteDateFormatter.time.string(from: entry.date))
                            .noteFont(size: 13, weight: .medium, relativeTo: .caption)
                            .foregroundStyle(NoteTheme.ink)
                    }
                    Text(title)
                        .noteFont(size: 19, weight: .semibold, relativeTo: .title3)
                        .foregroundStyle(NoteTheme.ink)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 3)
                        .multilineTextAlignment(.leading)
                    Text(summary)
                        .noteFont(size: 14, relativeTo: .subheadline)
                        .foregroundStyle(NoteTheme.secondaryInk)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                        .multilineTextAlignment(.leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .background(paperBackground)
            .overlay { paperBorder }
        }
        .buttonStyle(PressScaleButtonStyle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(kindLabel)，\(title)，\(summary)，\(NoteDateFormatter.time.string(from: entry.date))")
        .accessibilityHint("点按查看详情")
    }

    @ViewBuilder
    private var icon: some View {
        switch entry {
        case .tuckedAwayInspiration:
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(NoteTheme.paper.opacity(0.92))
                Image(systemName: "star")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(NoteTheme.secondaryInk)
            }
            .frame(width: 66, height: 72)
            .shadow(color: NoteTheme.ink.opacity(0.08), radius: 7, y: 3)
        case .endedRound:
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(NoteTheme.canvas.opacity(0.92))
                Image(systemName: "folder")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(NoteTheme.ink)
            }
            .frame(width: 66, height: 72)
        case .receipt:
            ZStack {
                V02ReceiptPaperShape()
                    .fill(NoteTheme.paper.opacity(0.95))
                    .overlay { V02ReceiptPaperShape().stroke(NoteTheme.secondaryInk.opacity(0.2), lineWidth: 1) }
                Image(systemName: "ticket")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(NoteTheme.secondaryInk)
            }
            .frame(width: 66, height: 72)
        }
    }

    private var kindLabel: String {
        switch entry {
        case .tuckedAwayInspiration: "灵感 · 已收起"
        case .endedRound: "构思历程 · 已结束"
        case .receipt: "构思小票"
        }
    }

    private var title: String {
        switch entry {
        case .tuckedAwayInspiration(let inspiration):
            let text = inspiration.text.trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? "未命名灵感" : text
        case .endedRound(_, let collection):
            return collection?.name ?? "未命名构思集"
        case .receipt(let receipt):
            return receipt.snapshot.collectionName
        }
    }

    private var summary: String {
        switch entry {
        case .tuckedAwayInspiration(let inspiration):
            if inspiration.resourceIDs.isEmpty { return "已退出卡片流，可在详情中放回卡片流。" }
            return "已退出卡片流 · 附件 \(inspiration.resourceIDs.count) 个"
        case .endedRound(let round, _):
            return "第 \(round.roundNumber) 轮构思 · \(round.memberIDs.count) 条灵感"
        case .receipt(let receipt):
            let attachments = receipt.statistics.attachmentCount
            return "第 \(receipt.snapshot.roundNumber) 轮构思 · \(receipt.snapshot.members.count) 条灵感 · 附件 \(attachments) 个"
        }
    }

    @ViewBuilder
    private var paperBackground: some View {
        switch entry {
        case .tuckedAwayInspiration:
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(NoteTheme.paper.opacity(0.83))
        case .endedRound:
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(NoteTheme.canvas.opacity(0.86))
        case .receipt:
            V02ReceiptPaperShape()
                .fill(NoteTheme.paper.opacity(0.9))
        }
    }

    private var paperBorder: some View {
        Group {
            switch entry {
            case .tuckedAwayInspiration:
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .stroke(Color.white.opacity(0.82), lineWidth: 1)
            case .endedRound:
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .stroke(NoteTheme.secondaryInk.opacity(0.14), lineWidth: 1)
            case .receipt:
                V02ReceiptPaperShape()
                    .stroke(Color.white.opacity(0.84), lineWidth: 1)
            }
        }
    }

}

private struct V02HistoryEmptyState: View {
    let scope: V02HistoryScope

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: iconName)
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(NoteTheme.secondaryInk)
            Text(emptyTitle)
                .noteFont(size: 21, weight: .semibold, relativeTo: .title3)
                .foregroundStyle(NoteTheme.ink)
            Text(message)
                .noteFont(size: 15, relativeTo: .subheadline)
                .foregroundStyle(NoteTheme.secondaryInk)
                .multilineTextAlignment(.center)
        }
        .padding(28)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private var iconName: String {
        switch scope {
        case .all: "clock.arrow.circlepath"
        case .tuckedAway: "archivebox"
        case .thinkingHistory: "folder"
        case .receipts: "ticket"
        }
    }

    private var emptyTitle: String {
        switch scope {
        case .all: "还没有历史内容"
        case .tuckedAway: "还没有已收起灵感"
        case .thinkingHistory: "还没有构思历程"
        case .receipts: "还没有构思小票"
        }
    }

    private var message: String {
        switch scope {
        case .all: "收起灵感、结束构思或生成小票后，它们会在这里按时间出现。"
        case .tuckedAway: "左滑收起的独立灵感会保留在这里，点开后可以放回卡片流。"
        case .thinkingHistory: "结束一轮构思后，构思历程会保留本轮成员与时间。"
        case .receipts: "结束本轮构思并生成构思小票后，它会出现在这里。"
        }
    }
}

private struct V02HistoryInspirationDetailView: View {
    @ObservedObject var store: V02Store
    let inspirationID: UUID
    let reportError: (Error) -> Void
    @Environment(\.dismiss) private var dismiss

    private var inspiration: V02Inspiration? {
        store.state.inspirations.first { $0.id == inspirationID }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(inspiration?.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? inspiration?.text ?? "未命名灵感" : "未命名灵感")
                        .noteFont(size: 22, weight: .semibold, relativeTo: .title2)
                        .foregroundStyle(NoteTheme.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if let inspiration, !inspiration.resourceIDs.isEmpty {
                        Text("附件 · \(inspiration.resourceIDs.count) 个")
                            .noteFont(size: 15, weight: .semibold, relativeTo: .subheadline)
                            .foregroundStyle(NoteTheme.secondaryInk)
                        V02MemberAttachmentSummary(store: store, resourceIDs: inspiration.resourceIDs)
                    }
                    Text("已收起灵感")
                        .noteFont(size: 14, relativeTo: .subheadline)
                        .foregroundStyle(NoteTheme.secondaryInk)
                    Text("\(inspiration?.createdAt.formatted(date: .abbreviated, time: .shortened) ?? "")")
                        .noteFont(size: 13, relativeTo: .caption)
                        .foregroundStyle(NoteTheme.secondaryInk)
                }
                .padding(.horizontal, NoteTheme.horizontalPadding)
                .padding(.top, 24)
                .padding(.bottom, 110)
            }
            .background(NoteTheme.background.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .notePrimaryHeader { inspirationDetailHeader }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Button {
                    do {
                        try store.returnToCardFlow(inspirationID)
                        dismiss()
                    } catch { reportError(error) }
                } label: {
                    Text("放回卡片流")
                        .noteFontCapped(size: 16, maximumScale: 1.25, weight: .semibold, relativeTo: .body)
                        .frame(maxWidth: .infinity, minHeight: 50)
                }
                .buttonStyle(PressScaleButtonStyle())
                .noteGlass(cornerRadius: 24, castsShadow: false)
                .padding(.horizontal, NoteTheme.horizontalPadding)
                .padding(.vertical, 10)
                .background(NoteTheme.background.opacity(0.94))
            }
        }
    }

    private var inspirationDetailHeader: some View {
        V02SecondaryPageHeader("灵感详情") {
            V02GlassIconButton(
                systemName: "chevron.left",
                label: "返回历史",
                action: { dismiss() }
            )
        } trailing: {
            V02SecondaryHeaderPlaceholder()
        }
    }
}

private struct V02HistoryCollectionDetailView: View {
    @ObservedObject var store: V02Store
    let round: V02ThinkingRound
    let collection: V02ThinkingCollection?
    let reportError: (Error) -> Void
    @Environment(\.dismiss) private var dismiss

    private var isActive: Bool {
        collection?.currentRoundID != nil
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(collection?.name ?? "未命名构思集")
                        .noteFont(size: 24, weight: .semibold, relativeTo: .title2)
                        .foregroundStyle(NoteTheme.ink)
                    Text("构思历程 · 已结束")
                        .noteFont(size: 15, weight: .semibold, relativeTo: .subheadline)
                        .foregroundStyle(NoteTheme.secondaryInk)
                    Text("开始：\(round.startedAt.formatted(date: .abbreviated, time: .shortened))\n结束：\(round.endedAt?.formatted(date: .abbreviated, time: .shortened) ?? "")")
                        .noteFont(size: 14, relativeTo: .subheadline)
                        .foregroundStyle(NoteTheme.secondaryInk)
                    Text("本轮保留 \(round.memberIDs.count) 条灵感")
                        .noteFont(size: 17, weight: .semibold, relativeTo: .headline)
                        .foregroundStyle(NoteTheme.ink)
                    if round.memberIDs.isEmpty {
                        Text("本轮没有可显示的灵感。")
                            .foregroundStyle(NoteTheme.secondaryInk)
                    } else {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(Array(round.memberIDs.enumerated()), id: \.element) { index, id in
                                let text = store.state.inspirations.first(where: { $0.id == id })?.text.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                                HStack(alignment: .top, spacing: 10) {
                                    Text(String(format: "%02d", index + 1))
                                        .noteFont(size: 12, weight: .semibold, relativeTo: .caption)
                                        .foregroundStyle(NoteTheme.secondaryInk)
                                    Text(text.isEmpty ? "未命名灵感" : text)
                                        .noteFont(size: 16, relativeTo: .body)
                                        .foregroundStyle(NoteTheme.ink)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, NoteTheme.horizontalPadding)
                .padding(.top, 24)
                .padding(.bottom, 110)
            }
            .background(NoteTheme.background.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .notePrimaryHeader { collectionHistoryHeader }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Button {
                    do {
                        _ = try store.continueThinking(in: round.collectionID)
                        dismiss()
                    } catch { reportError(error) }
                } label: {
                    Text(isActive ? "当前构思中" : "继续构思")
                        .noteFontCapped(size: 16, maximumScale: 1.25, weight: .semibold, relativeTo: .body)
                        .frame(maxWidth: .infinity, minHeight: 50)
                }
                .buttonStyle(PressScaleButtonStyle())
                .disabled(isActive || collection == nil)
                .noteGlass(cornerRadius: 24, castsShadow: false)
                .padding(.horizontal, NoteTheme.horizontalPadding)
                .padding(.vertical, 10)
                .background(NoteTheme.background.opacity(0.94))
            }
        }
    }

    private var collectionHistoryHeader: some View {
        V02SecondaryPageHeader("构思历程详情") {
            V02GlassIconButton(
                systemName: "chevron.left",
                label: "返回历史",
                action: { dismiss() }
            )
        } trailing: {
            V02SecondaryHeaderPlaceholder()
        }
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
