import SwiftUI
import PhotosUI
import QuickLook
import UniformTypeIdentifiers

struct HistoryView: View {
    @ObservedObject var store: NoteStore
    let onOpenIdea: (UUID) -> Void
    let onOpenGroup: (UUID) -> Void

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
            .frame(height: 54)
            .noteGlass(cornerRadius: 27)
            .padding(.horizontal, NoteTheme.horizontalPadding)
            .padding(.top, 10)

            HStack(spacing: 10) {
                HStack(spacing: 2) {
                    filterButton(.all)

                    filterButton(.active)
                    filterButton(.completed)
                }
                .padding(3)
                .background(Color.white.opacity(0.24), in: Capsule())
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("history.status.filter")

                Button(selecting ? "完成" : "选择") {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selecting.toggle()
                        if !selecting { selection.removeAll() }
                    }
                }
                .font(.system(size: 13, weight: .semibold))
                .buttonStyle(.plain)
                .frame(width: 52, height: 44)
                .contentShape(Rectangle())
                .accessibilityIdentifier("history.selection.toggle")
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
                                }
                                HistoryRow(item: item)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(Color.clear)
                        .listRowSeparatorTint(Color.white.opacity(0.65))
                        .accessibilityIdentifier("history.item.\(item.id.uuidString)")
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
                    .font(.system(size: 15, weight: .semibold))
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
                        .font(.system(size: 15, weight: .semibold))
                    }
                    .disabled(selectedItems.isEmpty)
                    .accessibilityIdentifier("history.selection.delete")
                }
                .padding(.horizontal, NoteTheme.horizontalPadding)
                .frame(height: 58)
                .noteGlass(cornerRadius: 24)
                .padding(.horizontal, NoteTheme.horizontalPadding)
                .padding(.bottom, 8)
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
        .font(.system(size: 13, weight: filter == item ? .semibold : .regular))
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

    private func open(_ item: ReviewItem) {
        switch item {
        case .idea(let idea): onOpenIdea(idea.id)
        case .group(let group): onOpenGroup(group.id)
        }
    }
}

struct EditorView: View {
    @ObservedObject var store: NoteStore
    let ideaID: UUID

    @State private var content = ""
    @State private var savedContent = ""
    @State private var saving = false
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var showAttachmentSource = false
    @State private var showPhotoPicker = false
    @State private var showFileImporter = false
    @State private var previewAttachment: Attachment?
    @State private var errorAlert: UserFacingAlert?
    @FocusState private var editorFocused: Bool

    private var idea: Idea? { store.idea(id: ideaID) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let idea {
                Text(NoteDateFormatter.display(idea.createdAt))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(NoteTheme.secondaryInk)
            }

            TextEditor(text: $content)
                .font(.system(size: 22, weight: .regular, design: .rounded))
                .lineSpacing(7)
                .noteScrollBackgroundHidden()
                .focused($editorFocused)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityLabel("想法内容")
                .onChange(of: content) { _, _ in scheduleSave() }

            if let idea, !store.attachments(for: idea.id).isEmpty {
                VStack(spacing: 8) {
                    ForEach(store.attachments(for: idea.id)) { attachment in
                        HStack {
                            Button {
                                previewAttachment = attachment
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: attachmentIcon(for: attachment))
                                    Text(attachment.name).lineLimit(1)
                                    Spacer()
                                    Text(
                                        ByteCountFormatter.string(
                                            fromByteCount: attachment.size,
                                            countStyle: .file
                                        )
                                    )
                                    .font(.caption)
                                    .foregroundStyle(NoteTheme.secondaryInk)
                                    Image(systemName: "chevron.right")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(NoteTheme.secondaryInk)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("预览附件 \(attachment.name)")

                            Button {
                                removeAttachment(attachment)
                            } label: {
                                Image(systemName: "xmark")
                            }
                            .buttonStyle(.plain)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                            .accessibilityLabel("移除附件")
                        }
                        .padding(.horizontal, 16)
                        .frame(height: 46)
                        .noteGlass(cornerRadius: 18, strokeOpacity: 0.45)
                    }
                }
            }

            HStack(spacing: 16) {
                Button {
                    showAttachmentSource = true
                } label: {
                    Label("添加附件", systemImage: "plus")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(height: 48)
                }
                .buttonStyle(.plain)

                Spacer()

                Button {
                    saveNow()
                    editorFocused = false
                } label: {
                    Text("完成")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(width: 76, height: 48)
                }
                .buttonStyle(PressScaleButtonStyle())
                .noteGlass(cornerRadius: 24, castsShadow: false)
            }
        }
        .padding(.horizontal, NoteTheme.horizontalPadding)
        .padding(.top, 26)
        .padding(.bottom, 12)
        .overlay {
            if showAttachmentSource {
                ZStack(alignment: .bottom) {
                    Color.clear

                    AttachmentSourcePanel(
                        onSelect: { source in
                            showAttachmentSource = false
                            presentAttachmentPicker(source)
                        },
                        onCancel: {
                            showAttachmentSource = false
                        }
                    )
                    .padding(.horizontal, 18)
                    .padding(.bottom, 76)
                    .transition(
                        .move(edge: .bottom)
                            .combined(with: .opacity)
                            .combined(with: .scale(scale: 0.96, anchor: .bottom))
                    )
                }
            }
        }
        .animation(
            .spring(response: 0.3, dampingFraction: 0.82),
            value: showAttachmentSource
        )
        .onAppear {
            content = idea?.content ?? ""
            savedContent = content
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                editorFocused = true
            }
        }
        .onDisappear(perform: saveNow)
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.item],
            allowsMultipleSelection: true
        ) { result in
            do {
                let urls = try result.get()
                addAttachments(try urls.map(AttachmentImporter.input))
            } catch {
                present(error)
            }
        }
        .photosPicker(
            isPresented: $showPhotoPicker,
            selection: $selectedPhotoItems,
            maxSelectionCount: 10,
            matching: .images
        )
        .onChange(of: selectedPhotoItems) { _, items in
            importPhotos(items)
        }
        .sheet(item: $previewAttachment) { attachment in
            AttachmentPreviewSheet(
                attachment: attachment,
                url: store.attachmentURL(attachment)
            )
        }
        .noteErrorAlert($errorAlert)
    }

    private func scheduleSave() {
        guard content != savedContent else { return }
        let expected = content
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            guard content == expected else { return }
            saveNow()
        }
    }

    private func saveNow() {
        guard idea != nil, content != savedContent else { return }
        saving = true
        do {
            try store.updateIdea(
                id: ideaID,
                content: content,
                newAttachments: [],
                removingAttachmentIDs: []
            )
            savedContent = content
        } catch {
            present(error)
        }
        saving = false
    }

    private func removeAttachment(_ attachment: Attachment) {
        do {
            try store.updateIdea(
                id: ideaID,
                content: content,
                newAttachments: [],
                removingAttachmentIDs: [attachment.id]
            )
            savedContent = content
        } catch {
            present(error)
        }
    }

    private func addAttachments(_ inputs: [AttachmentInput]) {
        guard !inputs.isEmpty else { return }
        do {
            try store.updateIdea(
                id: ideaID,
                content: content,
                newAttachments: inputs,
                removingAttachmentIDs: []
            )
            savedContent = content
        } catch {
            present(error)
        }
    }

    private func importPhotos(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        Task { @MainActor in
            let inputs = await photoAttachmentInputs(from: items)
            addAttachments(inputs)
            selectedPhotoItems = []
            if inputs.isEmpty {
                UINotificationFeedbackGenerator().notificationOccurred(.error)
                errorAlert = UserFacingAlert(message: "没有读到可添加的照片，请重新选择。")
            }
        }
    }

    private func attachmentIcon(for attachment: Attachment) -> String {
        if attachment.mimeType.hasPrefix("image/") {
            return "photo"
        }
        if attachment.mimeType == "application/pdf"
            || attachment.name.lowercased().hasSuffix(".pdf") {
            return "doc.richtext"
        }
        return "paperclip"
    }

    private func presentAttachmentPicker(_ source: AttachmentSource) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            switch source {
            case .photos:
                showPhotoPicker = true
            case .files:
                showFileImporter = true
            }
        }
    }

    private func present(_ error: Error) {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
        errorAlert = UserFacingAlert.local(error: error)
    }
}

enum AttachmentSource {
    case photos
    case files
}

struct AttachmentSourcePanel: View {
    let onSelect: (AttachmentSource) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("添加附件")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                Spacer()
                Button(action: onCancel) {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .frame(width: 32, height: 32)
                        .background(
                            NoteTheme.ink.opacity(0.05),
                            in: Circle()
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("关闭")
            }

            HStack(spacing: 12) {
                sourceButton(
                    title: "照片",
                    systemName: "photo.on.rectangle",
                    source: .photos
                )
                sourceButton(
                    title: "文件",
                    systemName: "doc",
                    source: .files
                )
            }
        }
        .foregroundStyle(NoteTheme.ink)
        .padding(16)
        .background(
            NoteTheme.canvas.opacity(0.44),
            in: RoundedRectangle(cornerRadius: 28, style: .continuous)
        )
        .noteGlass(cornerRadius: 28)
    }

    private func sourceButton(
        title: String,
        systemName: String,
        source: AttachmentSource
    ) -> some View {
        Button {
            onSelect(source)
        } label: {
            VStack(spacing: 8) {
                Image(systemName: systemName)
                    .font(.system(size: 23, weight: .semibold))
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 72)
            .background(
                NoteTheme.ink.opacity(0.045),
                in: RoundedRectangle(cornerRadius: 22, style: .continuous)
            )
            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(PressScaleButtonStyle())
        .accessibilityLabel("添加\(title)")
    }
}

func photoAttachmentInputs(
    from items: [PhotosPickerItem]
) async -> [AttachmentInput] {
    var inputs: [AttachmentInput] = []

    for item in items {
        guard let data = try? await item.loadTransferable(type: Data.self) else {
            continue
        }
        let contentType = item.supportedContentTypes.first ?? .jpeg
        let fileExtension = contentType.preferredFilenameExtension ?? "jpg"
        let mimeType = contentType.preferredMIMEType ?? "image/jpeg"
        let shortID = UUID().uuidString.prefix(8)
        inputs.append(
            AttachmentInput(
                name: "照片-\(shortID).\(fileExtension)",
                mimeType: mimeType,
                data: data
            )
        )
    }

    return inputs
}

private struct AttachmentPreviewSheet: View {
    @Environment(\.dismiss) private var dismiss

    let attachment: Attachment
    let url: URL

    var body: some View {
        NavigationStack {
            QuickLookPreview(url: url)
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle(attachment.name)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("完成") {
                            dismiss()
                        }
                    }
                }
        }
    }
}

private struct QuickLookPreview: UIViewControllerRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator {
        Coordinator(url: url)
    }

    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }

    func updateUIViewController(
        _ controller: QLPreviewController,
        context: Context
    ) {
        context.coordinator.url = url
        controller.reloadData()
    }

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        var url: URL

        init(url: URL) {
            self.url = url
        }

        func numberOfPreviewItems(
            in controller: QLPreviewController
        ) -> Int {
            FileManager.default.fileExists(atPath: url.path) ? 1 : 0
        }

        func previewController(
            _ controller: QLPreviewController,
            previewItemAt index: Int
        ) -> QLPreviewItem {
            url as NSURL
        }
    }
}

struct IdeaGroupView: View {
    @ObservedObject var store: NoteStore
    let groupID: UUID
    let onOpenIdea: (UUID) -> Void

    @State private var editingName = false
    @State private var name = ""
    @State private var showComposer = false
    @State private var errorAlert: UserFacingAlert?
    @FocusState private var nameFocused: Bool

    private var group: IdeaGroup? { store.group(id: groupID) }
    private var ideas: [Idea] { store.ideas(in: groupID) }
    private var isGroupActive: Bool { group?.status == .active }

    var body: some View {
        VStack(spacing: 18) {
            if let group {
                HStack(spacing: 12) {
                    if editingName {
                        TextField("灵感组名称", text: $name)
                            .font(.largeTitle.bold())
                            .focused($nameFocused)
                            .onSubmit(saveName)
                    } else {
                        Text(group.name)
                            .font(.largeTitle.bold())
                    }
                    Spacer()
                    if isGroupActive {
                        RoundGlassButton(
                            systemName: editingName ? "checkmark" : "square.and.pencil",
                            label: editingName ? "保存灵感组名称" : "编辑灵感组名称",
                            action: editingName ? saveName : beginEditingName
                        )
                    }
                }

                if ideas.isEmpty {
                    EmptyStateView(
                        systemName: isGroupActive
                            ? "rectangle.stack.badge.plus"
                            : "checkmark.circle",
                        title: "这个灵感组还是空的",
                        message: isGroupActive
                            ? "可以从卡片页把灵感加入这里。"
                            : "恢复整个灵感组后，才能继续添加内容。"
                    )
                    .frame(maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(ideas) { idea in
                                HStack(spacing: 12) {
                                    Button {
                                        onOpenIdea(idea.id)
                                    } label: {
                                        VStack(alignment: .leading, spacing: 8) {
                                            Text(NoteDateFormatter.display(idea.createdAt))
                                                .font(.caption)
                                                .foregroundStyle(NoteTheme.secondaryInk)
                                            Text(idea.content.isEmpty ? "未命名想法" : idea.content)
                                                .font(.body)
                                                .multilineTextAlignment(.leading)
                                                .lineLimit(4)
                                        }
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    .buttonStyle(.plain)

                                    if isGroupActive {
                                        Button {
                                            removeFromGroup(idea.id)
                                        } label: {
                                            Image(systemName: "rectangle.portrait.and.arrow.right")
                                                .font(.system(size: 16, weight: .semibold))
                                        }
                                        .buttonStyle(.plain)
                                        .frame(width: 44, height: 44)
                                        .contentShape(Rectangle())
                                        .accessibilityLabel("移出灵感组")
                                    }
                                }
                                .padding(20)
                                .background(
                                    Color.white.opacity(0.34),
                                    in: RoundedRectangle(
                                        cornerRadius: 24,
                                        style: .continuous
                                    )
                                )
                                .overlay {
                                    RoundedRectangle(
                                        cornerRadius: 24,
                                        style: .continuous
                                    )
                                    .stroke(Color.white.opacity(0.62), lineWidth: 1)
                                }
                            }
                        }
                        .padding(.bottom, 4)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .scrollIndicators(.visible)
                    .scrollBounceBehavior(.basedOnSize)
                }

                if isGroupActive {
                    Button {
                        showComposer = true
                    } label: {
                        Label("新增", systemImage: "plus")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                    }
                    .buttonStyle(PressScaleButtonStyle())
                    .noteGlass(cornerRadius: 28)
                }
            } else {
                EmptyStateView(
                    systemName: "exclamationmark.circle",
                    title: "找不到灵感组",
                    message: "它可能已被删除。"
                )
                .frame(maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, NoteTheme.horizontalPadding)
        .padding(.top, 24)
        .padding(.bottom, 12)
        .onAppear { name = group?.name ?? "" }
        .onChange(of: group?.name) { _, nextName in
            guard !editingName else { return }
            name = nextName ?? ""
        }
        .sheet(isPresented: $showComposer) {
            GroupIdeaComposer(store: store, groupID: groupID)
        }
        .noteErrorAlert($errorAlert)
    }

    private func beginEditingName() {
        guard isGroupActive else { return }
        name = group?.name ?? ""
        editingName = true
        DispatchQueue.main.async {
            nameFocused = true
        }
    }

    private func saveName() {
        let nextName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !nextName.isEmpty else { return }
        do {
            try store.renameGroup(id: groupID, name: nextName)
            nameFocused = false
            editingName = false
        } catch {
            present(error)
        }
    }

    private func removeFromGroup(_ ideaID: UUID) {
        do {
            try store.removeIdeaFromGroup(ideaID)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } catch {
            present(error)
        }
    }

    private func present(_ error: Error) {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
        errorAlert = UserFacingAlert.local(error: error)
    }
}

struct GroupPickerView: View {
    @ObservedObject var store: NoteStore
    let ideaID: UUID

    @Environment(\.dismiss) private var dismiss
    @State private var newGroupName = ""
    @State private var errorAlert: UserFacingAlert?

    var body: some View {
        NavigationStack {
            List {
                Section("选择灵感组") {
                    ForEach(store.activeGroups) { group in
                        Button {
                            assign(to: group.id)
                        } label: {
                            Label(group.name, systemImage: "rectangle.stack.fill")
                        }
                    }
                }

                Section("新建灵感组") {
                    HStack {
                        TextField("输入名称", text: $newGroupName)
                        Button("创建") { createGroup() }
                            .disabled(newGroupName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
            .navigationTitle("灵感组")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
        .noteErrorAlert($errorAlert)
    }

    private func assign(to groupID: UUID) {
        do {
            try store.assignIdea(ideaID, to: groupID)
            dismiss()
        } catch {
            present(error)
        }
    }

    private func createGroup() {
        let groupName = newGroupName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !groupName.isEmpty else { return }
        do {
            _ = try store.createGroup(name: groupName, initialIdeaID: ideaID)
            dismiss()
        } catch {
            present(error)
        }
    }

    private func present(_ error: Error) {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
        errorAlert = UserFacingAlert.local(error: error)
    }
}

struct IdeaGroupsListView: View {
    @ObservedObject var store: NoteStore
    let onOpenGroup: (UUID) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(store.activeGroups) { group in
                Button {
                    dismiss()
                    DispatchQueue.main.async { onOpenGroup(group.id) }
                } label: {
                    HStack {
                        Label(group.name, systemImage: "rectangle.stack.fill")
                        Spacer()
                        Text("\(store.ideas(in: group.id).count)")
                            .foregroundStyle(NoteTheme.secondaryInk)
                    }
                }
            }
            .navigationTitle("灵感组")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }
}

private struct GroupIdeaComposer: View {
    @ObservedObject var store: NoteStore
    let groupID: UUID

    @Environment(\.dismiss) private var dismiss
    @State private var content = ""
    @State private var errorAlert: UserFacingAlert?

    var body: some View {
        NavigationStack {
            TextEditor(text: $content)
                .font(.body)
                .padding()
                .navigationTitle("新增")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("取消") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("加入") { add() }
                            .disabled(content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
        }
        .noteErrorAlert($errorAlert)
    }

    private func add() {
        let value = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        do {
            _ = try store.createIdea(
                content: value,
                attachmentInputs: [],
                groupID: groupID
            )
            dismiss()
        } catch {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            errorAlert = UserFacingAlert.local(error: error)
        }
    }
}

private struct HistoryRow: View {
    let item: ReviewItem

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: item.symbolName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(NoteTheme.ink)
                .frame(width: 32, height: 32)
                .background(Color.white.opacity(0.34), in: RoundedRectangle(cornerRadius: 10))
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.white.opacity(0.68), lineWidth: 1)
                }
            VStack(alignment: .leading, spacing: 5) {
                Text(item.title)
                    .font(.system(size: 16, weight: .semibold))
                    .lineLimit(2)
                if let completedAt = item.completedAt {
                    Text("完成于 \(NoteDateFormatter.display(completedAt))")
                        .font(.caption)
                        .foregroundStyle(NoteTheme.secondaryInk)
                } else {
                    Text("更新于 \(NoteDateFormatter.display(item.activityAt))")
                        .font(.caption)
                        .foregroundStyle(NoteTheme.secondaryInk)
                }
            }
            Spacer()
            Text(item.status == .completed ? "已完成" : "未完成")
                .font(.caption.weight(.semibold))
                .foregroundStyle(
                    item.status == .completed
                        ? NoteTheme.secondaryInk
                        : NoteTheme.accent
                )
        }
        .padding(.vertical, 8)
    }
}

private extension View {
    @ViewBuilder
    func `if`<Content: View>(
        _ condition: Bool,
        transform: (Self) -> Content
    ) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}

extension ReviewItem {
    var title: String {
        switch self {
        case .idea(let idea): return idea.content.isEmpty ? "未命名想法" : idea.content
        case .group(let group): return group.name
        }
    }

    var symbolName: String {
        switch self {
        case .idea: return "note.text"
        case .group: return "rectangle.stack.fill"
        }
    }
}
