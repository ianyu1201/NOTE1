import AVFAudio
import Foundation
import Speech

enum V02VoiceRecordingError: LocalizedError {
    case microphonePermissionDenied
    case failedToStart

    var errorDescription: String? {
        switch self {
        case .microphonePermissionDenied:
            "未获得麦克风权限。请在系统设置中允许 NOTE1 使用麦克风后再录音。"
        case .failedToStart:
            "录音未能启动。请检查麦克风是否正在被其他 App 使用后重试。"
        }
    }
}

@MainActor
final class V02VoiceRecorder: NSObject, ObservableObject {
    static let maximumDuration: TimeInterval = 10 * 60

    @Published private(set) var isRecording = false
    @Published private(set) var temporaryURL: URL?
    @Published private(set) var interruptionMessage: String?
    @Published private(set) var transcript = ""
    @Published private(set) var transcriptionMessage: String?

    private let audioEngine = AVAudioEngine()
    private var audioFile: AVAudioFile?
    private var hasAudioTap = false
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var observer: NSObjectProtocol?

    override init() {
        super.init()
        observer = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.handleInterruption() }
        }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    func requestPermissionAndBegin(in directory: URL) async throws {
        let permission = AVAudioApplication.shared.recordPermission
        let granted: Bool
        switch permission {
        case .granted:
            granted = true
        case .undetermined:
            granted = await withCheckedContinuation { continuation in
                AVAudioApplication.requestRecordPermission { continuation.resume(returning: $0) }
            }
        case .denied:
            granted = false
        @unknown default:
            granted = false
        }
        guard granted else { throw V02VoiceRecordingError.microphonePermissionDenied }
        let transcription = await prepareOnDeviceTranscription()
        try begin(in: directory, transcription: transcription)
    }

    private func begin(
        in directory: URL,
        transcription: SFSpeechRecognizer?
    ) throws {
        guard !isRecording else { return }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: [.duckOthers])
        try session.setActive(true, options: .notifyOthersOnDeactivation)
        let url = directory.appendingPathComponent("voice-\(UUID().uuidString).m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 64_000
        ]
        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            try? FileManager.default.removeItem(at: url)
            try? session.setActive(false, options: .notifyOthersOnDeactivation)
            throw V02VoiceRecordingError.failedToStart
        }
        audioFile = try AVAudioFile(forWriting: url, settings: settings)
        if let transcription {
            let request = SFSpeechAudioBufferRecognitionRequest()
            request.requiresOnDeviceRecognition = true
            request.shouldReportPartialResults = true
            request.taskHint = .dictation
            recognitionRequest = request
            recognitionTask = transcription.recognitionTask(with: request) { [weak self] result, error in
                Task { @MainActor in
                    if let text = result?.bestTranscription.formattedString {
                        self?.transcript = text
                    }
                    if error != nil, result?.isFinal != true {
                        self?.transcriptionMessage = "本机转写已停止，录音仍会保留。"
                    }
                }
            }
        }
        inputNode.installTap(onBus: 0, bufferSize: 1_024, format: format) { [weak self] buffer, _ in
            do { try self?.audioFile?.write(from: buffer) }
            catch { Task { @MainActor in self?.interruptionMessage = "录音写入出现问题，已保留可用片段供你决定是否保存。" } }
            self?.recognitionRequest?.append(buffer)
        }
        hasAudioTap = true
        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            stopCapture()
            try? FileManager.default.removeItem(at: url)
            try? session.setActive(false, options: .notifyOthersOnDeactivation)
            throw V02VoiceRecordingError.failedToStart
        }
        temporaryURL = url
        interruptionMessage = nil
        transcript = ""
        isRecording = true
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(Self.maximumDuration))
            guard let self, self.isRecording else { return }
            _ = self.stop()
            self.interruptionMessage = "已达到本次录音时长上限，已保留可用片段供你决定是否保存。"
        }
    }

    func stop() -> URL? {
        stopCapture()
        isRecording = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        return temporaryURL
    }

    func discard() {
        recognitionTask?.cancel()
        recognitionTask = nil
        _ = stop()
        if let temporaryURL { try? FileManager.default.removeItem(at: temporaryURL) }
        temporaryURL = nil
    }

    func consumeTemporaryRecording() {
        temporaryURL = nil
        interruptionMessage = nil
    }

    private func handleInterruption() {
        guard isRecording else { return }
        _ = stop()
        interruptionMessage = "录音已被系统中断，已保留可用片段供你决定是否保存。"
    }

    private func stopCapture() {
        if audioEngine.isRunning { audioEngine.stop() }
        if hasAudioTap {
            audioEngine.inputNode.removeTap(onBus: 0)
            hasAudioTap = false
        }
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        audioFile = nil
    }

    private func prepareOnDeviceTranscription() async -> SFSpeechRecognizer? {
        transcriptionMessage = nil
        let authorization = SFSpeechRecognizer.authorizationStatus()
        let status: SFSpeechRecognizerAuthorizationStatus
        if authorization == .notDetermined {
            status = await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
            }
        } else {
            status = authorization
        }
        guard status == .authorized,
              let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN")),
              recognizer.supportsOnDeviceRecognition,
              recognizer.isAvailable else {
            transcriptionMessage = "本机简体中文转写当前不可用；录音仍会仅保存在本机。"
            return nil
        }
        recognizer.defaultTaskHint = .dictation
        return recognizer
    }
}
