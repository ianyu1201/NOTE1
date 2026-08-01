import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

struct EditorView: View {
    @ObservedObject var store: NoteStore
    let ideaID: UUID

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var content = ""
    @State private var savedContent = ""
    @State private var pendingSaveTask: Task<Void, Never>?
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var showAttachmentSource = false
    @State private var showPhotoPicker = false
    @State private var showFileImporter = false
    @State private var isImportingAttachments = false
    @State private var previewAttachment: Attachment?
    @State private var errorAlert: UserFacingAlert?
    @FocusState private var editorFocused: Bool

    private var idea: Idea? { store.idea(id: ideaID) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let idea {
                Text(NoteDateFormatter.display(idea.createdAt))
                    .noteFont(
                        size: 14,
                        weight: .medium,
                        relativeTo: .subheadline
                    )
                    .foregroundStyle(NoteTheme.secondaryInk)
            }

            TextEditor(text: $content)
                .noteFont(
                    size: 22,
                    design: .rounded,
                    relativeTo: .title3
                )
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
                                    Text(attachment.name)
                                        .lineLimit(
                                            dynamicTypeSize.isAccessibilitySize ? nil : 1
                                        )
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
                            .accessibilityLabel("移除附件 \(attachment.name)")
                        }
                        .padding(.horizontal, 16)
                        .frame(minHeight: 46)
                        .noteGlass(cornerRadius: 18, strokeOpacity: 0.45)
                    }
                }
            }

            HStack(spacing: 16) {
                Button {
                    showAttachmentSource = true
                } label: {
                    Label("添加附件", systemImage: "plus")
                        .noteFont(
                            size: 15,
                            weight: .semibold,
                            relativeTo: .subheadline
                        )
                        .frame(minHeight: 48)
                }
                .buttonStyle(.plain)
                .disabled(isImportingAttachments)

                Spacer()

                Button {
                    saveNow()
                    editorFocused = false
                } label: {
                    Text("完成")
                        .noteFont(
                            size: 15,
                            weight: .semibold,
                            relativeTo: .subheadline
                        )
                        .frame(minWidth: 76, minHeight: 48)
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
        .onDisappear {
            pendingSaveTask?.cancel()
            saveNow()
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.item],
            allowsMultipleSelection: true
        ) { result in
            Task { @MainActor in
                isImportingAttachments = true
                defer { isImportingAttachments = false }
                do {
                    let urls = try result.get()
                    addAttachments(
                        try await AttachmentImporter.inputs(from: urls)
                    )
                } catch {
                    present(error)
                }
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
        pendingSaveTask?.cancel()
        guard content != savedContent else { return }
        pendingSaveTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled else { return }
            saveNow()
        }
    }

    private func saveNow() {
        guard idea != nil, content != savedContent else { return }
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
