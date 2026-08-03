import SwiftUI
import UIKit
import PhotosUI
import UniformTypeIdentifiers

struct V02WorkbenchAttachmentSheet: View {
    @ObservedObject var store: V02Store
    let inspirationID: UUID
    let reportError: (Error) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var sourcePanel = false
    @State private var photoPicker = false
    @State private var fileImporter = false
    @State private var photos: [PhotosPickerItem] = []
    @State private var preview: V02AttachmentResource?
    @State private var removing: V02AttachmentResource?

    private var inspiration: V02Inspiration? {
        store.state.inspirations.first { $0.id == inspirationID }
    }

    private var resources: [V02AttachmentResource] {
        guard let inspiration else { return [] }
        return inspiration.resourceIDs.compactMap { id in
            store.state.resources.first { $0.id == id }
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if resources.isEmpty {
                    ContentUnavailableView(
                        "还没有附件",
                        systemImage: "paperclip",
                        description: Text("可添加照片、音频、PDF 或其他本机文件。")
                    )
                } else {
                    List(resources) { resource in
                        attachmentRow(resource)
                    }
                    .scrollContentBackground(.hidden)
                }
            }
            .background(NoteTheme.background.ignoresSafeArea())
            .navigationTitle("附件")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("完成") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        sourcePanel = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("添加附件")
                }
            }
        }
        .overlay(alignment: .bottom) {
            if sourcePanel {
                AttachmentSourcePanel(
                    onSelect: selectSource,
                    onCancel: { sourcePanel = false }
                )
                .padding(.horizontal, 18)
                .padding(.bottom, 24)
            }
        }
        .photosPicker(isPresented: $photoPicker, selection: $photos, maxSelectionCount: 10, matching: .images)
        .onChange(of: photos) { _, items in
            Task { @MainActor in
                let inputs = await photoAttachmentInputs(from: items)
                defer { photos = [] }
                do { try store.addImportedResources(inputs, to: inspirationID) }
                catch { reportError(error) }
            }
        }
        .fileImporter(isPresented: $fileImporter, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
            Task { @MainActor in
                do {
                    try store.addImportedResources(
                        try await AttachmentImporter.inputs(from: result.get()),
                        to: inspirationID
                    )
                } catch {
                    reportError(error)
                }
            }
        }
        .sheet(item: $preview) { resource in
            NavigationStack {
                QuickLookPreview(url: store.resourceURL(resource))
                    .ignoresSafeArea(edges: .bottom)
                    .navigationTitle(resource.filename)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("完成") { preview = nil }
                        }
                    }
            }
        }
        .alert("移除附件？", isPresented: Binding(
            get: { removing != nil },
            set: { if !$0 { removing = nil } }
        ), presenting: removing) { resource in
            Button("移除", role: .destructive) {
                do { try store.removeResource(resource.id, from: inspirationID) }
                catch { reportError(error) }
                removing = nil
            }
            Button("取消", role: .cancel) { removing = nil }
        } message: { _ in
            Text("既有构思小票中的附件快照不会被改写。")
        }
    }

    private func attachmentRow(_ resource: V02AttachmentResource) -> some View {
        HStack(spacing: 12) {
            if resource.mimeType.hasPrefix("audio/") || resource.source == .voiceInspiration {
                V02AudioPlaybackControl(resource: resource, url: store.resourceURL(resource))
            } else {
                Button {
                    preview = resource
                } label: {
                    HStack(spacing: 12) {
                        if resource.mimeType.hasPrefix("image/"),
                           let image = UIImage(contentsOfFile: store.resourceURL(resource).path) {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 46, height: 46)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        } else {
                            Image(systemName: "doc")
                                .frame(width: 46, height: 46)
                        }
                        VStack(alignment: .leading, spacing: 3) {
                            Text(resource.filename).lineLimit(1)
                            Text(ByteCountFormatter.string(fromByteCount: resource.size, countStyle: .file))
                                .noteFont(size: 12, relativeTo: .caption)
                                .foregroundStyle(NoteTheme.secondaryInk)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
            Button("移除", role: .destructive) { removing = resource }
                .buttonStyle(.borderless)
        }
        .listRowBackground(NoteTheme.paper.opacity(0.72))
    }

    private func selectSource(_ source: AttachmentSource) {
        sourcePanel = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            if source == .photos { photoPicker = true }
            else { fileImporter = true }
        }
    }
}
