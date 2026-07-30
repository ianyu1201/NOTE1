import SwiftUI
import PhotosUI
import QuickLook
import UniformTypeIdentifiers

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
                    .noteFont(
                        size: 17,
                        weight: .semibold,
                        design: .rounded,
                        relativeTo: .headline
                    )
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
                    .noteFont(
                        size: 15,
                        weight: .semibold,
                        relativeTo: .subheadline
                    )
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 72)
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

struct AttachmentPreviewSheet: View {
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

struct QuickLookPreview: UIViewControllerRepresentable {
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
