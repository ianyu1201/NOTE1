import SwiftUI
import UIKit

struct V02SettingsView: View {
    @ObservedObject var store: V02Store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var backupDocument = V02BackupDocument()
    @State private var isExportingBackup = false
    @State private var isImportingBackup = false
    @State private var pendingRestoreData: Data?
    @State private var isConfirmingRestore = false
    @State private var error: UserFacingAlert?
    @State private var copiedEmail = false

    var body: some View {
        NavigationStack {
            ZStack {
                NoteTheme.background.ignoresSafeArea()
                List {
                Section {
                    settingsButton("导出本机备份", systemImage: "square.and.arrow.up", action: exportBackup)
                    settingsButton("从备份恢复", systemImage: "arrow.down.doc") { isImportingBackup = true }
                } header: {
                    Text("本机数据")
                } footer: {
                    Text("备份包含灵感、构思集、构思轮次、小票、回收站和仍被引用的附件。恢复会替换当前本机数据。")
                }

                Section("隐私") {
                    NavigationLink("本机隐私说明") {
                        V02PrivacyView()
                    }
                    .frame(minHeight: 44)
                }

                Section("联系我") {
                    settingsButton("发送邮件", systemImage: "envelope", action: contactByEmail)
                    settingsButton(copiedEmail ? "邮箱地址已复制" : "复制邮箱地址", systemImage: "doc.on.doc") {
                        UIPasteboard.general.string = "y2694390075@gmail.com"
                        copiedEmail = true
                    }
                    Text("y2694390075@gmail.com")
                        .textSelection(.enabled)
                }

                Section("关于 NOTE1") {
                    LabeledContent("版本", value: versionDescription)
                    Text("简单记，快速看。NOTE1 只在本机保存你的灵感与构思成果。")
                }
                }
                .scrollContentBackground(.hidden)
                .listSectionSpacing(18)
                .listRowBackground(NoteTheme.paper.opacity(0.72))
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("设置")
                        .noteFontCapped(size: 20, maximumScale: 1.2, weight: .semibold, design: .rounded, relativeTo: .headline)
                        .foregroundStyle(NoteTheme.ink)
                        .accessibilityAddTraits(.isHeader)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { V02GlassIconLabel(systemName: "xmark") }
                    .accessibilityLabel("关闭设置")
                }
                .noteSharedBackgroundHidden()
            }
        }
        .fileExporter(
            isPresented: $isExportingBackup,
            document: backupDocument,
            contentType: .note1V02Backup,
            defaultFilename: "NOTE1-V0.2-本机备份"
        ) { result in
            if case .failure(let error) = result { self.error = UserFacingAlert(error: error) }
        }
        .fileImporter(
            isPresented: $isImportingBackup,
            allowedContentTypes: [.note1V02Backup, .json]
        ) { result in
            importBackup(result)
        }
        .alert("恢复本机备份？", isPresented: $isConfirmingRestore) {
            Button("恢复并替换当前数据", role: .destructive) { restorePendingBackup() }
            Button("取消", role: .cancel) { pendingRestoreData = nil }
        } message: {
            Text("当前 V0.2 本机数据会被备份内容替换，此操作不能撤销。")
        }
        .noteErrorAlert($error)
    }

    private func settingsButton(
        _ title: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(NoteTheme.ink)
    }

    private var versionDescription: String {
        let dictionary = Bundle.main.infoDictionary
        let version = dictionary?["CFBundleShortVersionString"] as? String ?? "开发版本"
        let build = dictionary?["CFBundleVersion"] as? String ?? "—"
        return "\(version)（\(build)）"
    }

    private func exportBackup() {
        do {
            backupDocument = V02BackupDocument(data: try store.exportBackupData())
            isExportingBackup = true
        } catch {
            self.error = UserFacingAlert(error: error)
        }
    }

    private func importBackup(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            let data = try Data(contentsOf: url, options: [.mappedIfSafe])
            try store.validateBackupData(data)
            pendingRestoreData = data
            isConfirmingRestore = true
        } catch {
            self.error = UserFacingAlert(error: error)
        }
    }

    private func restorePendingBackup() {
        guard let pendingRestoreData else { return }
        do {
            try store.restoreBackupData(pendingRestoreData)
            self.pendingRestoreData = nil
        } catch {
            self.error = UserFacingAlert(error: error)
        }
    }

    private func contactByEmail() {
        guard let address = URL(string: "mailto:y2694390075@gmail.com") else { return }
        openURL(address) { accepted in
            if !accepted {
                UIPasteboard.general.string = "y2694390075@gmail.com"
                copiedEmail = true
            }
        }
    }
}

private struct V02PrivacyView: View {
    var body: some View {
        ZStack {
            NoteTheme.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("本机隐私说明")
                        .noteFont(size: 24, weight: .semibold, relativeTo: .title2)
                        .accessibilityAddTraits(.isHeader)
                    Text("NOTE1 的灵感、构思集、构思轮次、构思小票、回收站内容、录音和附件默认只保存在这台设备的 App 沙盒中。")
                    Text("V0.2 不提供登录、后端、云同步、AI 分析或静默上传。只有在你主动发起系统分享、导出 PDF、导出本机备份，或从外部选择文件时，系统才会处理你明确选择的对象。")
                }
                .noteFont(size: 17, relativeTo: .body)
                .foregroundStyle(NoteTheme.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(24)
                .noteGlass(cornerRadius: 26, castsShadow: false)
                .padding(20)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("本机隐私说明")
                    .noteFontCapped(size: 20, maximumScale: 1.2, weight: .semibold, design: .rounded, relativeTo: .headline)
                    .foregroundStyle(NoteTheme.ink)
                    .accessibilityAddTraits(.isHeader)
            }
        }
    }
}
