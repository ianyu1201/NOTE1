import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

struct HomeView: View {
    @ObservedObject var store: NoteStore
    let onReview: () -> Void
    let onOpenIdea: (UUID) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var draft = ""
    @State private var draftAttachments: [AttachmentInput] = []
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var showAttachmentSource = false
    @State private var showPhotoPicker = false
    @State private var showFileImporter = false
    @State private var errorAlert: UserFacingAlert?
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 24)

            if !store.recentActiveIdeas.isEmpty {
                recentIdeas
                    .frame(maxHeight: 238)
                    .transition(
                        .move(edge: .bottom)
                            .combined(with: .opacity)
                    )
            }

            Spacer(minLength: 20)

            (
                dynamicTypeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(alignment: .trailing, spacing: 14))
                    : AnyLayout(HStackLayout(alignment: .bottom, spacing: 14))
            ) {
                HStack(alignment: .bottom, spacing: 12) {
                    Button {
                        showAttachmentSource = true
                    } label: {
                        Image(systemName: draftAttachments.isEmpty ? "plus" : "paperclip")
                            .font(.system(size: 20, weight: .semibold))
                            .frame(width: 44, height: 44)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("添加附件")

                    TextField(
                        dynamicTypeSize.isAccessibilitySize
                            ? "记录……"
                            : "记录此刻的想法……",
                        text: $draft,
                        axis: .vertical
                    )
                        .accessibilityLabel("记录此刻的想法")
                        .focused($inputFocused)
                        .lineLimit(1...5)
                        .frame(minHeight: 48, alignment: .center)
                        .submitLabel(.send)
                        .onSubmit(saveDraft)

                    Button(action: saveDraft) {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(hasSaveableDraft ? .white : NoteTheme.secondaryInk)
                            .frame(width: 48, height: 48)
                            .background(
                                hasSaveableDraft ? NoteTheme.ink : Color.white.opacity(0.3),
                                in: Circle()
                            )
                    }
                    .buttonStyle(PressScaleButtonStyle())
                    .disabled(!hasSaveableDraft)
                    .accessibilityLabel("保存想法")
                }
                .padding(.leading, 20)
                .padding(.trailing, 8)
                .padding(.vertical, 8)
                .frame(minHeight: 64)
                .noteGlass(cornerRadius: 32, castsShadow: false)

                RoundGlassButton(
                    systemName: "square.on.square",
                    label: "进入卡片回看",
                    size: 64,
                    iconSize: 20,
                    action: onReview
                )
            }
            .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, NoteTheme.horizontalPadding)
        .contentShape(Rectangle())
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
                    .padding(.bottom, 96)
                    .transition(
                        .move(edge: .bottom)
                            .combined(with: .opacity)
                            .combined(with: .scale(scale: 0.96, anchor: .bottom))
                    )
                }
            }
        }
        .animation(
            reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.82),
            value: showAttachmentSource
        )
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.item],
            allowsMultipleSelection: true
        ) { result in
            do {
                let urls = try result.get()
                draftAttachments.append(
                    contentsOf: try urls.map(AttachmentImporter.input)
                )
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
        .noteErrorAlert($errorAlert)
    }

    @ViewBuilder
    private var recentIdeas: some View {
        VStack(spacing: 0) {
            ForEach(recentIdeasForDisplay) { idea in
                Button {
                    onOpenIdea(idea.id)
                } label: {
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(idea.content.isEmpty ? "未命名想法" : idea.content)
                                .noteFont(
                                    size: 14,
                                    weight: .semibold,
                                    relativeTo: .subheadline
                                )
                                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                                .multilineTextAlignment(.leading)
                            Text(NoteDateFormatter.display(idea.activityAt))
                                .noteFont(size: 11, relativeTo: .caption)
                                .foregroundStyle(NoteTheme.secondaryInk)
                        }
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(NoteTheme.secondaryInk)
                    }
                    .padding(.vertical, 7)
                    .padding(.horizontal, 16)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .transition(
                    .move(edge: .bottom)
                        .combined(with: .opacity)
                        .combined(with: .scale(scale: 0.97))
                )

                if idea.id != recentIdeasForDisplay.last?.id {
                    Divider()
                        .overlay(NoteTheme.divider)
                        .padding(.horizontal, 16)
                }
            }
        }
        .noteGlass(cornerRadius: 22, strokeOpacity: 0.55)
        .animation(
            reduceMotion ? nil : .spring(response: 0.44, dampingFraction: 0.82),
            value: recentIdeasForDisplay.map(\.id)
        )
    }

    private var recentIdeasForDisplay: [Idea] {
        Array(
            store.recentActiveIdeas.prefix(
                dynamicTypeSize.isAccessibilitySize ? 1 : 5
            )
        )
    }

    private func saveDraft() {
        let content = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty || !draftAttachments.isEmpty else { return }
        do {
            _ = try withAnimation(
                reduceMotion ? nil : .spring(response: 0.44, dampingFraction: 0.82)
            ) {
                try store.createIdea(
                    content: content,
                    attachmentInputs: draftAttachments
                )
            }
            draft = ""
            draftAttachments = []
            inputFocused = false
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } catch {
            present(error)
        }
    }

    private var hasSaveableDraft: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        || !draftAttachments.isEmpty
    }

    private func importPhotos(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        Task { @MainActor in
            let inputs = await photoAttachmentInputs(from: items)
            draftAttachments.append(contentsOf: inputs)
            selectedPhotoItems = []
            if inputs.isEmpty {
                UINotificationFeedbackGenerator().notificationOccurred(.error)
                errorAlert = UserFacingAlert(message: "没有读到可添加的照片，请重新选择。")
            }
        }
    }

    private func present(_ error: Error) {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
        errorAlert = UserFacingAlert.local(error: error)
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
}
