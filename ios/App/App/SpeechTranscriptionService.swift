import AVFAudio
import Combine
import Foundation
import Speech

enum SpeechTranscriptionError: LocalizedError, Equatable {
    case microphonePermissionDenied
    case speechPermissionDenied
    case speechPermissionRestricted
    case onDeviceRecognitionUnavailable
    case recognizerUnavailable
    case audioInputUnavailable
    case interrupted
    case emptyResult
    case recognitionFailed

    var errorDescription: String? {
        switch self {
        case .microphonePermissionDenied:
            "未获得麦克风权限。你仍可继续键入文字；如需语音录入，请在系统设置中允许 NOTE1 使用麦克风。"
        case .speechPermissionDenied:
            "未获得语音识别权限。你仍可继续键入文字；如需语音录入，请在系统设置中允许 NOTE1 使用语音识别。"
        case .speechPermissionRestricted:
            "当前设备限制了语音识别。你仍可继续键入文字。"
        case .onDeviceRecognitionUnavailable:
            "这台设备当前不支持简体中文本机语音识别。NOTE1 不会改用联网识别，你仍可继续键入文字。"
        case .recognizerUnavailable:
            "本机语音识别暂时不可用，请稍后重试；你仍可继续键入文字。"
        case .audioInputUnavailable:
            "当前没有可用的麦克风输入，请检查设备后重试。"
        case .interrupted:
            "语音录入已被系统中断，已保留识别出的文字。"
        case .emptyResult:
            "没有识别到可用文字，请重试或继续键入。"
        case .recognitionFailed:
            "本机语音识别没有完成，请重试或继续键入文字。"
        }
    }
}

enum SpeechTranscriptionEvent: Equatable {
    case partial(String)
    case final(String)
    case failed(SpeechTranscriptionError)
}

@MainActor
protocol SpeechTranscribing: AnyObject {
    var eventHandler: ((SpeechTranscriptionEvent) -> Void)? { get set }

    func requestAuthorization() async throws
    func start() throws
    func stop()
    func cancel()
}

struct SpeechSessionCompletion: Identifiable, Equatable {
    enum Outcome: Equatable {
        case commit(String)
        case discard
    }

    let id = UUID()
    let outcome: Outcome
}

@MainActor
final class SpeechTranscriptionController: ObservableObject {
    enum State: Equatable {
        case idle
        case requestingPermission
        case listening
        case finishing
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var transcript = ""
    @Published private(set) var completion: SpeechSessionCompletion?
    @Published private(set) var feedbackMessage: String?

    private let service: any SpeechTranscribing
    private var finishingTimeoutTask: Task<Void, Never>?

    init(service: any SpeechTranscribing) {
        self.service = service
        service.eventHandler = { [weak self] event in
            self?.handle(event)
        }
    }

    var isActive: Bool {
        state != .idle
    }

    var isListening: Bool {
        state == .listening
    }

    @discardableResult
    func begin() async -> Bool {
        guard state == .idle else { return false }
        feedbackMessage = nil
        completion = nil
        transcript = ""
        state = .requestingPermission

        do {
            try await service.requestAuthorization()
            try service.start()
            state = .listening
            return true
        } catch {
            state = .idle
            feedbackMessage = userMessage(for: error)
            completion = SpeechSessionCompletion(outcome: .discard)
            return false
        }
    }

    func stop() {
        guard state == .listening else { return }
        state = .finishing
        service.stop()
        scheduleFinishingTimeout()
    }

    func cancel() {
        guard state != .idle else { return }
        finishingTimeoutTask?.cancel()
        service.cancel()
        transcript = ""
        state = .idle
        completion = SpeechSessionCompletion(outcome: .discard)
    }

    func clearFeedback() {
        feedbackMessage = nil
    }

    private func handle(_ event: SpeechTranscriptionEvent) {
        guard state != .idle else { return }

        switch event {
        case .partial(let text):
            transcript = text

        case .final(let text):
            finishingTimeoutTask?.cancel()
            let finalText = text.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            state = .idle
            if finalText.isEmpty {
                feedbackMessage = SpeechTranscriptionError.emptyResult
                    .localizedDescription
                completion = SpeechSessionCompletion(outcome: .discard)
            } else {
                transcript = finalText
                completion = SpeechSessionCompletion(
                    outcome: .commit(finalText)
                )
            }

        case .failed(let error):
            finishingTimeoutTask?.cancel()
            state = .idle
            feedbackMessage = error.localizedDescription
            if transcript.trimmingCharacters(
                in: .whitespacesAndNewlines
            ).isEmpty {
                completion = SpeechSessionCompletion(outcome: .discard)
            } else {
                completion = SpeechSessionCompletion(
                    outcome: .commit(transcript)
                )
            }
        }
    }

    private func scheduleFinishingTimeout() {
        finishingTimeoutTask?.cancel()
        finishingTimeoutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard let self,
                  !Task.isCancelled,
                  self.state == .finishing else {
                return
            }
            self.service.cancel()
            self.state = .idle
            if self.transcript.trimmingCharacters(
                in: .whitespacesAndNewlines
            ).isEmpty {
                self.feedbackMessage = SpeechTranscriptionError.emptyResult
                    .localizedDescription
                self.completion = SpeechSessionCompletion(outcome: .discard)
            } else {
                self.completion = SpeechSessionCompletion(
                    outcome: .commit(self.transcript)
                )
            }
        }
    }

    private func userMessage(for error: Error) -> String {
        if let speechError = error as? SpeechTranscriptionError {
            return speechError.localizedDescription
        }
        return SpeechTranscriptionError.recognitionFailed.localizedDescription
    }
}

@MainActor
final class OnDeviceSpeechTranscriptionService: SpeechTranscribing {
    var eventHandler: ((SpeechTranscriptionEvent) -> Void)?

    private var speechRecognizer: SFSpeechRecognizer?
    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var hasAudioTap = false
    private var interruptionObserver: NSObjectProtocol?
    private var isCancelling = false
    private let notificationCenter: NotificationCenter

    init(notificationCenter: NotificationCenter = .default) {
        self.notificationCenter = notificationCenter
        interruptionObserver = notificationCenter.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                self?.handleInterruption(notification)
            }
        }
    }

    deinit {
        if let interruptionObserver {
            notificationCenter.removeObserver(interruptionObserver)
        }
    }

    func requestAuthorization() async throws {
        let speechStatus = await speechAuthorizationStatus()
        switch speechStatus {
        case .authorized:
            break
        case .denied:
            throw SpeechTranscriptionError.speechPermissionDenied
        case .restricted:
            throw SpeechTranscriptionError.speechPermissionRestricted
        case .notDetermined:
            throw SpeechTranscriptionError.speechPermissionDenied
        @unknown default:
            throw SpeechTranscriptionError.speechPermissionDenied
        }

        guard await microphonePermissionGranted() else {
            throw SpeechTranscriptionError.microphonePermissionDenied
        }

        guard let recognizer = SFSpeechRecognizer(
            locale: Locale(identifier: "zh-CN")
        ) else {
            throw SpeechTranscriptionError.onDeviceRecognitionUnavailable
        }
        guard recognizer.supportsOnDeviceRecognition else {
            throw SpeechTranscriptionError.onDeviceRecognitionUnavailable
        }
        guard recognizer.isAvailable else {
            throw SpeechTranscriptionError.recognizerUnavailable
        }
        recognizer.defaultTaskHint = .dictation
        recognizer.queue = .main
        speechRecognizer = recognizer
    }

    func start() throws {
        guard let speechRecognizer,
              speechRecognizer.supportsOnDeviceRecognition else {
            throw SpeechTranscriptionError.onDeviceRecognitionUnavailable
        }

        cancelCurrentRecognition(deactivateAudioSession: false)
        isCancelling = false

        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(
            .record,
            mode: .measurement,
            options: [.duckOthers]
        )
        try audioSession.setActive(
            true,
            options: .notifyOthersOnDeactivation
        )

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        guard recordingFormat.sampleRate > 0,
              recordingFormat.channelCount > 0 else {
            deactivateAudioSession()
            throw SpeechTranscriptionError.audioInputUnavailable
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true
        request.taskHint = .dictation
        recognitionRequest = request

        inputNode.installTap(
            onBus: 0,
            bufferSize: 1_024,
            format: recordingFormat
        ) { buffer, _ in
            request.append(buffer)
        }
        hasAudioTap = true

        recognitionTask = speechRecognizer.recognitionTask(
            with: request
        ) { [weak self] result, error in
            Task { @MainActor in
                self?.handleRecognition(result: result, error: error)
            }
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            cancelCurrentRecognition()
            throw SpeechTranscriptionError.audioInputUnavailable
        }
    }

    func stop() {
        guard recognitionRequest != nil else { return }
        stopAudioCapture()
        recognitionRequest?.endAudio()
    }

    func cancel() {
        isCancelling = true
        cancelCurrentRecognition()
    }

    private func speechAuthorizationStatus() async
        -> SFSpeechRecognizerAuthorizationStatus {
        let current = SFSpeechRecognizer.authorizationStatus()
        guard current == .notDetermined else { return current }
        return await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }

    private func microphonePermissionGranted() async -> Bool {
        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            return true
        case .denied:
            return false
        case .undetermined:
            return await withCheckedContinuation { continuation in
                AVAudioApplication.requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
        @unknown default:
            return false
        }
    }

    private func handleRecognition(
        result: SFSpeechRecognitionResult?,
        error: Error?
    ) {
        if let result {
            let text = result.bestTranscription.formattedString
            if result.isFinal {
                finishCurrentRecognition()
                eventHandler?(.final(text))
                return
            }
            eventHandler?(.partial(text))
        }

        guard error != nil else { return }
        let wasCancelling = isCancelling
        cancelCurrentRecognition()
        guard !wasCancelling else { return }
        eventHandler?(.failed(.recognitionFailed))
    }

    private func handleInterruption(_ notification: Notification) {
        guard recognitionRequest != nil,
              let rawValue = notification.userInfo?[
                AVAudioSessionInterruptionTypeKey
              ] as? UInt,
              AVAudioSession.InterruptionType(rawValue: rawValue) == .began
        else {
            return
        }
        cancelCurrentRecognition()
        eventHandler?(.failed(.interrupted))
    }

    private func stopAudioCapture() {
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        if hasAudioTap {
            audioEngine.inputNode.removeTap(onBus: 0)
            hasAudioTap = false
        }
    }

    private func finishCurrentRecognition() {
        stopAudioCapture()
        recognitionRequest = nil
        recognitionTask = nil
        deactivateAudioSession()
    }

    private func cancelCurrentRecognition(
        deactivateAudioSession shouldDeactivate: Bool = true
    ) {
        stopAudioCapture()
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil
        if shouldDeactivate {
            deactivateAudioSession()
        }
    }

    private func deactivateAudioSession() {
        try? AVAudioSession.sharedInstance().setActive(
            false,
            options: .notifyOthersOnDeactivation
        )
    }
}
