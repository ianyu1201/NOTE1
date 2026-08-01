import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

@MainActor
struct HomeComposerView: View {
    @ObservedObject var store: NoteStore
    @Binding var draft: HomeComposerDraft

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @StateObject private var speech: SpeechTranscriptionController
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var showAttachmentSource = false
    @State private var showPhotoPicker = false
    @State private var showFileImporter = false
    @State private var isImportingAttachments = false
    @State private var showDiscardConfirmation = false
    @State private var errorAlert: UserFacingAlert?
    @FocusState private var inputFocused: Bool

    init(
        store: NoteStore,
        draft: Binding<HomeComposerDraft>,
        speechService: (any SpeechTranscribing)? = nil
    ) {
        self.store = store
        _draft = draft
        _speech = StateObject(
            wrappedValue: SpeechTranscriptionController(
                service: speechService
                    ?? OnDeviceSpeechTranscriptionService()
            )
        )
    }

    var body: some View {
        VStack(spacing: 14) {
            header
            editor

            if !draft.attachments.isEmpty {
                attachmentSummary
            }

            if speech.isActive || speech.feedbackMessage != nil {
                speechStatus
            }

            controls
        }
        .foregroundStyle(NoteTheme.ink)
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(NoteTheme.canvas.opacity(0.98))
        .interactiveDismissDisabled(draft.hasUnsavedContent || speech.isActive)
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(32)
        .presentationBackground(NoteTheme.canvas)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                inputFocused = true
            }
        }
        .onDisappear {
            if speech.isActive {
                speech.cancel()
                draft.cancelTranscription()
            }
        }
        .onChange(of: speech.transcript) { _, transcript in
            draft.updateLiveTranscript(transcript)
        }
        .onChange(of: speech.completion) { _, completion in
            guard let completion else { return }
            switch completion.outcome {
            case .commit(let transcript):
                draft.commitTranscription(transcript)
            case .discard:
                draft.cancelTranscription()
            }
        }
        .overlay {
            if showAttachmentSource {
                attachmentSourceOverlay
            }
        }
        .animation(
            reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.84),
            value: showAttachmentSource
        )
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.item],
            allowsMultipleSelection: true
        ) { result in
            importFiles(result)
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
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button {
                    inputFocused = false
                } label: {
                    Label(
                        "收起",
                        systemImage: "keyboard.chevron.compact.down"
                    )
                }
                .accessibilityLabel("收起键盘")
            }
        }
        .confirmationDialog(
            "放弃本次记录？",
            isPresented: $showDiscardConfirmation,
            titleVisibility: .visible
        ) {
            Button("放弃本次内容", role: .destructive) {
                speech.cancel()
                draft.discard()
                dismiss()
            }
            Button("继续编辑", role: .cancel) {}
        } message: {
            Text("尚未保存的文字和附件将被移除。")
        }
        .noteErrorAlert($errorAlert)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text("记录灵感")
                .noteFont(
                    size: 18,
                    weight: .semibold,
                    design: .rounded,
                    relativeTo: .headline
                )

            Spacer()

            Button(action: requestDismissal) {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .frame(width: 38, height: 38)
                    .background(
                        NoteTheme.ink.opacity(0.045),
                        in: Circle()
                    )
                    .contentShape(Circle())
            }
            .buttonStyle(PressScaleButtonStyle())
            .accessibilityLabel("关闭录入")
        }
    }

    private var editor: some View {
        TextField(
            "现在的想法是……",
            text: $draft.text,
            axis: .vertical
        )
        .noteFont(
            size: 17,
            design: .rounded,
            relativeTo: .body
        )
        .lineSpacing(4)
        .lineLimit(1...5)
        .focused($inputFocused)
        .disabled(speech.isActive)
        .accessibilityLabel("灵感内容")
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .frame(
            minHeight: 54,
            maxHeight: dynamicTypeSize.isAccessibilitySize ? 170 : 132,
            alignment: .topLeading
        )
        .background(
            Color.white.opacity(0.36),
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.7), lineWidth: 1)
        }
    }

    private var attachmentSummary: some View {
        HStack(spacing: 8) {
            Image(systemName: "paperclip")
            Text("已添加 \(draft.attachments.count) 个附件")
                .lineLimit(1)
            Spacer()
        }
        .noteFont(
            size: 13,
            weight: .medium,
            relativeTo: .footnote
        )
        .foregroundStyle(NoteTheme.secondaryInk)
        .accessibilityElement(children: .combine)
    }

    private var speechStatus: some View {
        HStack(spacing: 10) {
            if speech.isActive {
                Circle()
                    .fill(NoteTheme.accent)
                    .frame(width: 7, height: 7)
                    .opacity(speech.isListening ? 1 : 0.55)

                Text(
                    speech.state == .requestingPermission
                        ? "正在请求本机语音权限"
                        : speech.state == .finishing
                            ? "正在完成转写"
                            : "正在聆听，仅在本机转成文字"
                )

                Spacer()

                Button("取消语音") {
                    speech.cancel()
                }
                .buttonStyle(.plain)
                .foregroundStyle(NoteTheme.accent)
            } else if let message = speech.feedbackMessage {
                Image(systemName: "info.circle")
                Text(message)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
        }
        .noteFont(
            size: 12,
            weight: .medium,
            relativeTo: .caption
        )
        .foregroundStyle(NoteTheme.secondaryInk)
        .accessibilityElement(children: .combine)
    }

    private var controls: some View {
        HStack(spacing: 12) {
            controlButton(
                systemName: "plus",
                label: "添加附件",
                action: {
                    inputFocused = false
                    showAttachmentSource = true
                }
            )
            .disabled(isImportingAttachments || speech.isActive)

            controlButton(
                systemName: speech.isActive ? "stop.fill" : "mic",
                label: speech.isActive ? "停止语音录入" : "开始本机语音录入",
                selected: speech.isActive,
                action: toggleSpeech
            )
            .disabled(isImportingAttachments)

            controlButton(
                systemName: "keyboard.chevron.compact.down",
                label: "收起键盘",
                action: {
                    inputFocused = false
                }
            )

            Spacer(minLength: 0)

            Button(action: saveDraft) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(hasSaveableDraft ? .white : NoteTheme.secondaryInk)
                    .frame(width: 48, height: 48)
                    .background(
                        hasSaveableDraft
                            ? NoteTheme.ink
                            : NoteTheme.ink.opacity(0.045),
                        in: Circle()
                    )
            }
            .buttonStyle(PressScaleButtonStyle())
            .disabled(!hasSaveableDraft || speech.isActive)
            .accessibilityLabel("保存灵感")
        }
        .frame(minHeight: 48)
    }

    private func controlButton(
        systemName: String,
        label: String,
        selected: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(selected ? NoteTheme.accent : NoteTheme.ink)
                .frame(width: 46, height: 46)
                .background(
                    selected
                        ? NoteTheme.accent.opacity(0.1)
                        : NoteTheme.ink.opacity(0.035),
                    in: Circle()
                )
                .contentShape(Circle())
        }
        .buttonStyle(PressScaleButtonStyle())
        .accessibilityLabel(label)
    }

    private var attachmentSourceOverlay: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.04)
                .contentShape(Rectangle())
                .onTapGesture {
                    showAttachmentSource = false
                }

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
            .padding(.bottom, 12)
            .transition(
                .move(edge: .bottom)
                    .combined(with: .opacity)
            )
        }
    }

    private func requestDismissal() {
        inputFocused = false
        switch HomeComposerDismissalPolicy.action(for: draft) {
        case .dismissImmediately:
            speech.cancel()
            dismiss()
        case .confirmDiscard:
            showDiscardConfirmation = true
        }
    }

    private func toggleSpeech() {
        inputFocused = false
        if speech.isActive {
            speech.stop()
            return
        }

        draft.beginTranscription()
        Task {
            let started = await speech.begin()
            if !started {
                draft.cancelTranscription()
                UINotificationFeedbackGenerator()
                    .notificationOccurred(.warning)
            } else {
                UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            }
        }
    }

    private func saveDraft() {
        let content = draft.text.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !content.isEmpty || !draft.attachments.isEmpty else { return }

        do {
            _ = try withAnimation(
                reduceMotion
                    ? nil
                    : .spring(response: 0.4, dampingFraction: 0.84)
            ) {
                try store.createIdea(
                    content: content,
                    attachmentInputs: draft.attachments
                )
            }
            inputFocused = false
            draft.discard()
            UINotificationFeedbackGenerator()
                .notificationOccurred(.success)
            dismiss()
        } catch {
            present(error)
        }
    }

    private var hasSaveableDraft: Bool {
        draft.hasUnsavedContent && !isImportingAttachments
    }

    private func importFiles(_ result: Result<[URL], Error>) {
        Task { @MainActor in
            isImportingAttachments = true
            defer { isImportingAttachments = false }
            do {
                let urls = try result.get()
                draft.attachments.append(
                    contentsOf: try await AttachmentImporter.inputs(from: urls)
                )
            } catch {
                present(error)
            }
        }
    }

    private func importPhotos(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        Task { @MainActor in
            isImportingAttachments = true
            let inputs = await photoAttachmentInputs(from: items)
            draft.attachments.append(contentsOf: inputs)
            selectedPhotoItems = []
            isImportingAttachments = false
            if inputs.isEmpty {
                UINotificationFeedbackGenerator()
                    .notificationOccurred(.error)
                errorAlert = UserFacingAlert(
                    message: "没有读到可添加的照片，请重新选择。"
                )
            }
        }
    }

    private func presentAttachmentPicker(_ source: AttachmentSource) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
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
