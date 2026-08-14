import SwiftUI
import UIKit
import PhotosUI
import UniformTypeIdentifiers

struct V02InspirationEditorView: View {
    @ObservedObject var store: V02Store
    let inspirationID: UUID
    let reportError: (Error) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var text = ""
    @State private var savedText = ""
    @State private var sessionOriginalText = ""
    @State private var didFinishEditSession = false
    @State private var pendingSaveTask: Task<Void, Never>?
    @State private var photos: [PhotosPickerItem] = []
    @State private var sourcePanel = false
    @State private var photoPicker = false
    @State private var fileImporter = false
    @State private var preview: V02AttachmentResource?
    @State private var removing: V02AttachmentResource?
    @FocusState private var focused: Bool

    private var inspiration: V02Inspiration? { store.state.inspirations.first { $0.id == inspirationID } }

    var body: some View {
        NavigationStack {
            ScrollView {
                Group {
                    if let inspiration {
                        VStack(alignment: .leading, spacing: 14) {
                            TextEditor(text: $text)
                                .noteFont(size: 18, relativeTo: .body).lineSpacing(5).noteScrollBackgroundHidden()
                                .focused($focused).padding(12)
                                .background(NoteTheme.paper.opacity(0.72), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                                .frame(maxWidth: .infinity, minHeight: 260, maxHeight: dynamicTypeSize.isAccessibilitySize ? 300 : 320)
                                .accessibilityLabel("灵感内容")
                                .onChange(of: text) { _, _ in scheduleSave() }
                            if !inspiration.resourceIDs.isEmpty {
                                Text("附件").noteFontCapped(size: 16, maximumScale: 1.3, weight: .semibold, relativeTo: .headline)
                                ScrollView { VStack(spacing: 8) {
                                    ForEach(inspiration.resourceIDs, id: \.self) { id in
                                        if let resource = store.state.resources.first(where: { $0.id == id }) { attachmentRow(resource) }
                                    }
                                }}.frame(maxHeight: 220)
                            }
                        }.padding(24)
                    } else { EmptyStateView(systemName: "exclamationmark.triangle", title: "这条灵感已不可用", message: "它可能已被删除或移入回收站。") }
                }
                .padding(.bottom, 112)
            }
            .background(NoteTheme.background.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .notePrimaryHeader {
                editorHeader
                    .accessibilityHidden(sourcePanel)
            }
            .safeAreaInset(edge: .bottom) { bottomBar }
        }
        .accessibilityHidden(sourcePanel || preview != nil)
        .background {
            V02PresentedContentAccessibilityIsolation(isPresented: preview != nil)
                .frame(width: 0, height: 0)
        }
        .scrollDismissesKeyboard(.interactively)
        .simultaneousGesture(
            DragGesture(minimumDistance: 18, coordinateSpace: .local)
                .onEnded { value in
                    let startsAtLeadingEdge = value.startLocation.x <= 24
                    guard startsAtLeadingEdge,
                          value.translation.width >= 72,
                          value.translation.width > abs(value.translation.height) * 1.2 else { return }
                    closeEditor()
                }
        )
        .onAppear {
            text = inspiration?.text ?? ""
            savedText = text
            sessionOriginalText = text
            didFinishEditSession = false
            // Keep the largest accessibility layout anchored at the start of
            // the long-text field so the page remains legible on entry. The
            // field is still fully editable; tapping it starts editing and
            // shows the keyboard. Normal sizes retain V0.1 auto-focus.
            guard !dynamicTypeSize.isAccessibilitySize else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { focused = true }
        }
        .onDisappear {
            pendingSaveTask?.cancel()
            _ = finishEditSession()
        }
        .overlay(alignment: .bottom) { if sourcePanel { AttachmentSourcePanel(onSelect: selectSource, onCancel: { sourcePanel = false }).padding(.horizontal, 18).padding(.bottom, 82) } }
        .fileImporter(isPresented: $fileImporter, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
            Task { @MainActor in do { try add(try await AttachmentImporter.inputs(from: result.get())) } catch { reportError(error) } }
        }
        .photosPicker(isPresented: $photoPicker, selection: $photos, maxSelectionCount: 10, matching: .images)
        .onChange(of: photos) { _, items in Task { @MainActor in let inputs = await photoAttachmentInputs(from: items); defer { photos = [] }; do { try add(inputs) } catch { reportError(error) } } }
        .sheet(item: $preview) { resource in V02AttachmentPreview(resource: resource, url: store.resourceURL(resource)) }
        .alert("移除附件？", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }), presenting: removing) { resource in
            Button("移除", role: .destructive) { do { try store.removeResource(resource.id, from: inspirationID) } catch { reportError(error) }; removing = nil }
            Button("取消", role: .cancel) { removing = nil }
        } message: { _ in Text("若构思小票或回收站仍引用该附件，它会继续保留在本机。") }
    }

    private var editorHeader: some View {
        V02SecondaryPageHeader("编辑灵感") {
            V02GlassIconButton(
                systemName: "chevron.left",
                label: "返回",
                action: closeEditor
            )
            .accessibilityHint("保存后返回上一页")
        } trailing: {
            V02SecondaryHeaderPlaceholder()
        }
    }

    private var bottomBar: some View { HStack(spacing: 12) {
        Button { focused = false; sourcePanel = true } label: {
            Label("添加附件", systemImage: "paperclip")
                .noteFontCapped(size: 15, maximumScale: 1.25, relativeTo: .subheadline)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(minHeight: 48)
        }.buttonStyle(.plain).accessibilityIdentifier("v02.editor.addAttachment")
        Spacer()
        Button {
            closeEditor()
        } label: {
            Text("完成")
                .noteFontCapped(size: 15, maximumScale: 1.25, weight: .semibold, relativeTo: .subheadline)
                .frame(minWidth: 76, minHeight: 48)
        }.buttonStyle(PressScaleButtonStyle()).noteGlass(cornerRadius: 24, castsShadow: false).accessibilityIdentifier("v02.editor.done")
    }.padding(.horizontal, NoteTheme.horizontalPadding).padding(.vertical, 10).background(NoteTheme.background.opacity(0.94)).overlay(alignment: .top) { Rectangle().fill(NoteTheme.divider).frame(height: 1) } }

    private func attachmentRow(_ resource: V02AttachmentResource) -> some View { HStack(spacing: 10) {
        if resource.mimeType.hasPrefix("audio/") || resource.source == .voiceInspiration { V02AudioPlaybackControl(resource: resource, url: store.resourceURL(resource)) }
        else { Button { preview = resource } label: { HStack(spacing: 10) {
            if resource.mimeType.hasPrefix("image/"), let image = UIImage(contentsOfFile: store.resourceURL(resource).path) {
                Image(uiImage: image).resizable().scaledToFill().frame(width: 42, height: 42).clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            } else { Image(systemName: "doc") }
            VStack(alignment: .leading, spacing: 2) {
                Text(resource.filename)
                    .noteFontCapped(size: 15, maximumScale: 1.3, relativeTo: .body)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text("\(resource.mimeType) · \(ByteCountFormatter.string(fromByteCount: resource.size, countStyle: .file))")
                    .noteFontCapped(size: 12, maximumScale: 1.25, relativeTo: .caption)
                    .foregroundStyle(NoteTheme.secondaryInk)
                    .lineLimit(2)
                    .minimumScaleFactor(0.78)
            }
            .layoutPriority(1)
            Spacer(minLength: 4)
            Image(systemName: "chevron.right").font(.caption.weight(.semibold))
        }.contentShape(Rectangle()) }.buttonStyle(.plain).accessibilityLabel("预览附件 \(resource.filename)") }
        Button("移除", role: .destructive) {
            removing = resource
        }
        .noteFontCapped(size: 15, maximumScale: 1.25, weight: .semibold, relativeTo: .subheadline)
        .buttonStyle(.borderless)
    }.padding(.horizontal, 12).frame(minHeight: 52).noteGlass(cornerRadius: 18, strokeOpacity: 0.45) }

    private func selectSource(_ source: AttachmentSource) { sourcePanel = false; DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { if source == .photos { photoPicker = true } else { fileImporter = true } } }
    private func scheduleSave() { pendingSaveTask?.cancel(); guard text != savedText else { return }; pendingSaveTask = Task { @MainActor in try? await Task.sleep(for: .milliseconds(450)); guard !Task.isCancelled else { return }; saveNow() } }
    private func saveNow() {
        guard text != savedText else { return }
        do {
            try store.updateInspiration(
                inspirationID,
                text: text,
                recordsEffectiveEdit: false
            )
            savedText = text
        } catch {
            reportError(error)
        }
    }
    private func finishEditSession() -> Bool {
        guard !didFinishEditSession else { return true }
        do {
            try store.finishInspirationEditSession(
                inspirationID,
                originalText: sessionOriginalText,
                finalText: text
            )
            savedText = text
            didFinishEditSession = true
            return true
        } catch {
            reportError(error)
            return false
        }
    }
    private func closeEditor() {
        pendingSaveTask?.cancel()
        guard finishEditSession() else { return }
        focused = false
        dismiss()
    }
    private func add(_ inputs: [AttachmentInput]) throws { guard !inputs.isEmpty else { return }; try store.addImportedResources(inputs, to: inspirationID) }
}

private struct V02AttachmentPreview: View {
    @Environment(\.dismiss) private var dismiss
    let resource: V02AttachmentResource
    let url: URL
    var body: some View { NavigationStack { QuickLookPreview(url: url).ignoresSafeArea(edges: .bottom).navigationTitle(resource.filename).navigationBarTitleDisplayMode(.inline).toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } } } }
}

struct V02ComposerView: View {
    @ObservedObject var store: V02Store
    var initialCollectionID: UUID? = nil
    let reportError: (Error) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @StateObject private var recorder = V02VoiceRecorder()
    @State private var voiceResourceID: UUID?
    @State private var attachmentResourceIDs: [UUID] = []
    @State private var isPresentingAttachmentImporter = false
    @State private var isPresentingAttachmentSource = false
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var isPresentingPhotoPicker = false
    @State private var isConfirmingDiscard = false
    @State private var textBeforeVoiceRecording = ""
    @State private var appliedTranscript = ""
    @State private var didCommitDraft = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    TextEditor(text: $text)
                        .noteFont(size: 18, relativeTo: .body)
                        .padding(12)
                        .background(NoteTheme.paper.opacity(0.86), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .frame(minHeight: 260)
                        .accessibilityLabel("灵感内容")
                    if recorder.isRecording {
                        Text("正在录制本机语音灵感")
                            .noteFont(size: 15, weight: .semibold, relativeTo: .subheadline)
                            .foregroundStyle(NoteTheme.ink)
                    } else if voiceResourceID == nil, let url = recorder.temporaryURL {
                        HStack(spacing: 12) {
                            Button("保留这段录音") {
                                do {
                                    voiceResourceID = try store.persistVoiceRecording(at: url).id
                                    recorder.consumeTemporaryRecording()
                                } catch { reportError(error) }
                            }
                            .buttonStyle(.plain)
                            .noteGlass(cornerRadius: 18, castsShadow: false)
                            Button("舍弃", role: .destructive) {
                                recorder.discard()
                                removeAppliedTranscript()
                            }
                            .buttonStyle(.plain)
                        }
                        if let message = recorder.interruptionMessage ?? recorder.transcriptionMessage {
                            Text(message)
                                .noteFont(size: 14, relativeTo: .subheadline)
                                .foregroundStyle(NoteTheme.secondaryInk)
                        }
                    } else if voiceResourceID != nil {
                        Label("已附加本机录音（M4A）", systemImage: "waveform")
                            .foregroundStyle(NoteTheme.secondaryInk)
                    }
                    if !attachmentResourceIDs.isEmpty {
                        Label("已添加 \(attachmentResourceIDs.count) 个附件", systemImage: "paperclip")
                            .noteFont(size: 14, relativeTo: .subheadline)
                            .foregroundStyle(NoteTheme.secondaryInk)
                            .accessibilityLabel("已添加 \(attachmentResourceIDs.count) 个附件")
                    }
                }
                .padding(.horizontal, NoteTheme.horizontalPadding)
                .padding(.top, 18)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(NoteTheme.background.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .notePrimaryHeader { composerHeader }
            .safeAreaInset(edge: .bottom) {
                HStack(spacing: 8) {
                    Button {
                        isPresentingAttachmentSource = true
                    } label: {
                        Image(systemName: "paperclip")
                            .font(.system(size: 19, weight: .semibold))
                            .frame(width: 48, height: 48)
                    }
                    .buttonStyle(.plain)
                    .noteGlass(cornerRadius: 24, castsShadow: false)
                    .accessibilityLabel("添加附件")
                    Button {
                        if recorder.isRecording { _ = recorder.stop() }
                        else {
                            textBeforeVoiceRecording = text
                            appliedTranscript = ""
                            Task { do { try await recorder.requestPermissionAndBegin(in: store.temporaryVoiceDirectory) } catch { reportError(error) } }
                        }
                    } label: {
                        Image(systemName: recorder.isRecording ? "stop.fill" : "mic")
                            .font(.system(size: 19, weight: .semibold))
                            .frame(width: 48, height: 48)
                    }
                    .buttonStyle(.plain)
                    .noteGlass(cornerRadius: 24, castsShadow: false)
                    .accessibilityLabel(recorder.isRecording ? "停止录音" : "录制语音灵感")
                    .accessibilityHint("原录音会以 M4A 保存在本机，可随时播放或删除")
                    Spacer(minLength: 0)
                    Button(action: saveDraft) {
                        Text("保存")
                            .noteFontCapped(
                                size: 16,
                                maximumScale: 1.25,
                                weight: .medium,
                                relativeTo: .body
                            )
                            .frame(minWidth: 96, minHeight: 48)
                    }
                    .buttonStyle(PressScaleButtonStyle())
                    .noteGlass(cornerRadius: 24, castsShadow: false)
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && voiceResourceID == nil && attachmentResourceIDs.isEmpty)
                    .accessibilityIdentifier("v02.composer.save")
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background(NoteTheme.background.opacity(0.94))
            }
        }
        .fileImporter(
            isPresented: $isPresentingAttachmentImporter,
            allowedContentTypes: [.image, .audio, .pdf, .data],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                for url in urls {
                    importAttachment(from: url)
                }
            case .failure(let error):
                reportError(error)
            }
        }
        .photosPicker(isPresented: $isPresentingPhotoPicker, selection: $selectedPhotoItems, maxSelectionCount: 10, matching: .images)
        .onChange(of: selectedPhotoItems) { _, items in
            Task { @MainActor in
                let inputs = await photoAttachmentInputs(from: items)
                defer { selectedPhotoItems = [] }
                for input in inputs {
                    do { attachmentResourceIDs.append(try store.createResource(input: input, source: .importedAttachment).id) }
                    catch { reportError(error) }
                }
            }
        }
        .overlay(alignment: .bottom) {
            if isPresentingAttachmentSource {
                AttachmentSourcePanel(onSelect: { source in
                    isPresentingAttachmentSource = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        if source == .photos { isPresentingPhotoPicker = true }
                        else { isPresentingAttachmentImporter = true }
                    }
                }, onCancel: { isPresentingAttachmentSource = false })
                .padding(.horizontal, 18).padding(.bottom, 24)
            }
        }
        .onChange(of: recorder.transcript) { _, transcript in
            guard !transcript.isEmpty else { return }
            if !appliedTranscript.isEmpty, text.hasSuffix(appliedTranscript) {
                text.removeLast(appliedTranscript.count)
            }
            text += transcript
            appliedTranscript = transcript
        }
        .confirmationDialog("放弃本次记录？", isPresented: $isConfirmingDiscard, titleVisibility: .visible) {
            Button("放弃本次内容", role: .destructive) {
                discardDraft()
                dismiss()
            }
            Button("继续编辑", role: .cancel) { }
        } message: {
            Text("尚未保存的文字、录音和附件将被移除。")
        }
        .onDisappear {
            // A sheet can also be dismissed by a swipe or system-driven
            // dismissal, bypassing the explicit cancel confirmation. Any
            // resources created while composing are still unreferenced until
            // save succeeds, so reclaim them at the lifecycle boundary.
            guard !didCommitDraft else { return }
            discardDraft()
        }
        .presentationDetents([.medium])
    }

    private var composerHeader: some View {
        V02SecondaryPageHeader("记录灵感") {
            V02GlassTextButton(title: "取消", action: requestCancellation)
        } trailing: {
            V02SecondaryHeaderPlaceholder()
        }
    }

    private var hasUnsavedContent: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        recorder.isRecording ||
        recorder.temporaryURL != nil ||
        voiceResourceID != nil ||
        !attachmentResourceIDs.isEmpty
    }

    private func requestCancellation() {
        if hasUnsavedContent {
            isConfirmingDiscard = true
        } else {
            discardDraft()
            dismiss()
        }
    }

    private func importAttachment(from url: URL) {
        let accessingSecurityScopedResource = url.startAccessingSecurityScopedResource()
        defer {
            if accessingSecurityScopedResource { url.stopAccessingSecurityScopedResource() }
        }
        do {
            let values = try url.resourceValues(forKeys: [.contentTypeKey])
            let resource = try store.createResource(
                input: AttachmentInput(
                    name: url.lastPathComponent,
                    mimeType: values.contentType?.preferredMIMEType ?? "application/octet-stream",
                    data: try Data(contentsOf: url, options: [.mappedIfSafe])
                ),
                source: .importedAttachment
            )
            attachmentResourceIDs.append(resource.id)
        } catch {
            reportError(error)
        }
    }

    private func saveDraft() {
        do {
            var resourceIDs = (voiceResourceID.map { [$0] } ?? []) + attachmentResourceIDs
            var autoPersistedVoiceID: UUID?
            if voiceResourceID == nil, let temporaryURL = recorder.temporaryURL {
                let resource = try store.persistVoiceRecording(at: temporaryURL)
                autoPersistedVoiceID = resource.id
                resourceIDs.insert(resource.id, at: 0)
            }
            do {
                if let initialCollectionID {
                    _ = try store.createInspiration(text: text, resourceIDs: resourceIDs, in: initialCollectionID)
                } else {
                    _ = try store.createInspiration(text: text, resourceIDs: resourceIDs)
                }
            } catch {
                // The composer still owns all pending resources after a
                // failed inspiration transaction. Keep an auto-persisted
                // recording attached so the user can retry (for example
                // after resolving a full collection) instead of losing the
                // temporary recording and leaving a dead URL behind.
                if let autoPersistedVoiceID {
                    voiceResourceID = autoPersistedVoiceID
                    recorder.consumeTemporaryRecording()
                }
                throw error
            }
            recorder.consumeTemporaryRecording()
            didCommitDraft = true
            dismiss()
        } catch { reportError(error) }
    }

    private func discardPendingResources() {
        let resourceIDs = (voiceResourceID.map { [$0] } ?? []) + attachmentResourceIDs
        for resourceID in resourceIDs {
            try? store.discardUnreferencedResource(resourceID)
        }
    }

    private func discardDraft() {
        recorder.discard()
        discardPendingResources()
    }

    private func removeAppliedTranscript() {
        if !appliedTranscript.isEmpty, text.hasSuffix(appliedTranscript) {
            text.removeLast(appliedTranscript.count)
        }
        appliedTranscript = ""
    }
}
