import XCTest
@testable import App

@MainActor
final class SpeechTranscriptionTests: XCTestCase {
    func testPermissionFailureReturnsChineseFeedbackAndDiscardsSession()
        async {
        let service = MockSpeechTranscriptionService()
        service.authorizationError =
            SpeechTranscriptionError.speechPermissionDenied
        let controller = SpeechTranscriptionController(service: service)

        let started = await controller.begin()

        XCTAssertFalse(started)
        XCTAssertFalse(controller.isActive)
        XCTAssertEqual(service.startCallCount, 0)
        XCTAssertTrue(
            controller.feedbackMessage?.contains("语音识别权限") == true
        )
        XCTAssertEqual(controller.completion?.outcome, .discard)
    }

    func testOnDeviceUnavailableDoesNotStartRecognition() async {
        let service = MockSpeechTranscriptionService()
        service.authorizationError =
            SpeechTranscriptionError.onDeviceRecognitionUnavailable
        let controller = SpeechTranscriptionController(service: service)

        let started = await controller.begin()

        XCTAssertFalse(started)
        XCTAssertEqual(service.startCallCount, 0)
        XCTAssertTrue(
            controller.feedbackMessage?.contains("不会改用联网识别") == true
        )
    }

    func testPartialAndFinalTranscriptsArePublished() async {
        let service = MockSpeechTranscriptionService()
        let controller = SpeechTranscriptionController(service: service)

        let started = await controller.begin()
        XCTAssertTrue(started)
        service.emit(.partial("正在识别"))
        XCTAssertEqual(controller.transcript, "正在识别")

        service.emit(.final("最终文字"))

        XCTAssertFalse(controller.isActive)
        XCTAssertEqual(
            controller.completion?.outcome,
            .commit("最终文字")
        )
    }

    func testCancelDiscardsOnlyCurrentSpeechSession() async {
        let service = MockSpeechTranscriptionService()
        let controller = SpeechTranscriptionController(service: service)

        let started = await controller.begin()
        XCTAssertTrue(started)
        service.emit(.partial("临时语音"))
        controller.cancel()

        XCTAssertEqual(service.cancelCallCount, 1)
        XCTAssertEqual(controller.transcript, "")
        XCTAssertEqual(controller.completion?.outcome, .discard)
    }
}

@MainActor
private final class MockSpeechTranscriptionService: SpeechTranscribing {
    var eventHandler: ((SpeechTranscriptionEvent) -> Void)?
    var authorizationError: Error?
    var startError: Error?
    var startCallCount = 0
    var cancelCallCount = 0

    func requestAuthorization() async throws {
        if let authorizationError {
            throw authorizationError
        }
    }

    func start() throws {
        startCallCount += 1
        if let startError {
            throw startError
        }
    }

    func stop() {}

    func cancel() {
        cancelCallCount += 1
    }

    func emit(_ event: SpeechTranscriptionEvent) {
        eventHandler?(event)
    }
}
