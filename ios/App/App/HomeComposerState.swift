import Foundation

struct HomeComposerDraft: Equatable {
    var text = ""
    var attachments: [AttachmentInput] = []

    private(set) var textBeforeTranscription: String?
    private(set) var liveTranscript = ""

    var hasUnsavedContent: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !attachments.isEmpty
    }

    var isTranscribing: Bool {
        textBeforeTranscription != nil
    }

    mutating func beginTranscription() {
        guard textBeforeTranscription == nil else { return }
        textBeforeTranscription = text
        liveTranscript = ""
    }

    mutating func updateLiveTranscript(_ transcript: String) {
        guard let baseText = textBeforeTranscription else { return }
        liveTranscript = transcript
        text = Self.appending(transcript, to: baseText)
    }

    mutating func commitTranscription(_ transcript: String? = nil) {
        guard let baseText = textBeforeTranscription else { return }
        let finalTranscript = transcript ?? liveTranscript
        text = Self.appending(finalTranscript, to: baseText)
        textBeforeTranscription = nil
        liveTranscript = ""
    }

    mutating func cancelTranscription() {
        guard let baseText = textBeforeTranscription else { return }
        text = baseText
        textBeforeTranscription = nil
        liveTranscript = ""
    }

    mutating func discard() {
        text = ""
        attachments = []
        textBeforeTranscription = nil
        liveTranscript = ""
    }

    static func appending(_ transcript: String, to baseText: String) -> String {
        let cleanedTranscript = transcript.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !cleanedTranscript.isEmpty else { return baseText }
        guard !baseText.isEmpty else { return cleanedTranscript }
        guard let last = baseText.last,
              !last.isWhitespace else {
            return baseText + cleanedTranscript
        }
        return baseText + "\n" + cleanedTranscript
    }
}

enum HomeComposerDismissalPolicy {
    case dismissImmediately
    case confirmDiscard

    static func action(for draft: HomeComposerDraft) -> Self {
        draft.hasUnsavedContent ? .confirmDiscard : .dismissImmediately
    }
}
