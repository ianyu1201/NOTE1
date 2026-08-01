import XCTest
@testable import App

final class HomeComposerStateTests: XCTestCase {
    func testVoiceTranscriptAppendsWithoutOverwritingTypedText() {
        var draft = HomeComposerDraft(text: "手动写下的内容")

        draft.beginTranscription()
        draft.updateLiveTranscript("第一段语音")
        draft.commitTranscription("最终语音")

        XCTAssertEqual(draft.text, "手动写下的内容\n最终语音")
        XCTAssertFalse(draft.isTranscribing)
    }

    func testCancellingVoiceRestoresManualTextAndKeepsAttachments() {
        let attachment = AttachmentInput(
            name: "照片.jpg",
            mimeType: "image/jpeg",
            data: Data([1, 2, 3])
        )
        var draft = HomeComposerDraft(
            text: "原来的文字",
            attachments: [attachment]
        )

        draft.beginTranscription()
        draft.updateLiveTranscript("不应保留")
        draft.cancelTranscription()

        XCTAssertEqual(draft.text, "原来的文字")
        XCTAssertEqual(draft.attachments, [attachment])
    }

    func testDiscardClearsTextAttachmentsAndLiveTranscript() {
        var draft = HomeComposerDraft(
            text: "尚未保存",
            attachments: [
                AttachmentInput(
                    name: "文件.pdf",
                    mimeType: "application/pdf",
                    data: Data([4])
                )
            ]
        )
        draft.beginTranscription()
        draft.updateLiveTranscript("语音")

        draft.discard()

        XCTAssertFalse(draft.hasUnsavedContent)
        XCTAssertFalse(draft.isTranscribing)
        XCTAssertEqual(draft.text, "")
        XCTAssertTrue(draft.attachments.isEmpty)
    }

    func testDismissalRequiresConfirmationOnlyForUnsavedContent() {
        switch HomeComposerDismissalPolicy.action(
            for: HomeComposerDraft()
        ) {
        case .dismissImmediately:
            break
        case .confirmDiscard:
            XCTFail("空白草稿应直接关闭")
        }

        switch HomeComposerDismissalPolicy.action(
            for: HomeComposerDraft(text: "未保存")
        ) {
        case .dismissImmediately:
            XCTFail("有内容时应确认丢弃")
        case .confirmDiscard:
            break
        }
    }
}
