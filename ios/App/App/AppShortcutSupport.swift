import AppIntents
import Foundation

enum AppShortcutDraftStore {
    private static let key = "note1.shortcut.pending-draft"
    static let didSaveNotification = Notification.Name(
        "note1.shortcut.pending-draft.did-save"
    )

    static func save(
        _ text: String,
        defaults: UserDefaults = .standard
    ) {
        defaults.set(text, forKey: key)
        NotificationCenter.default.post(name: didSaveNotification, object: nil)
    }

    static func consume(defaults: UserDefaults = .standard) -> String? {
        guard let text = defaults.string(forKey: key) else { return nil }
        defaults.removeObject(forKey: key)
        return text
    }
}

enum CaptureIdeaIntentError: LocalizedError {
    case emptyContent

    var errorDescription: String? {
        "灵感内容不能为空。"
    }
}

struct CaptureIdeaIntent: AppIntent {
    static let title: LocalizedStringResource = "记录灵感"
    static let description = IntentDescription(
        "打开 NOTE1，并把文字预填到首页输入框。"
    )

    @Parameter(title: "灵感内容")
    var content: String

    static var parameterSummary: some ParameterSummary {
        Summary("在 NOTE1 中记录 \(\.$content)")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw CaptureIdeaIntentError.emptyContent
        }
        AppShortcutDraftStore.save(trimmed)
        return .result(dialog: "已打开 NOTE1，请确认后保存。")
    }
}

@available(*, deprecated)
extension CaptureIdeaIntent {
    static var openAppWhenRun: Bool { true }
}

struct NOTE1ShortcutsProvider: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CaptureIdeaIntent(),
            phrases: [
                "用 \(.applicationName) 记录灵感",
                "在 \(.applicationName) 记一下"
            ],
            shortTitle: "记录灵感",
            systemImageName: "square.and.pencil"
        )
    }

    static var shortcutTileColor: ShortcutTileColor {
        .navy
    }
}
