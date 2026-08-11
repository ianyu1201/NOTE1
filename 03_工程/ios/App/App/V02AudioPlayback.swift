import AVFAudio
import SwiftUI

@MainActor
final class V02AudioPlayer: NSObject, ObservableObject, @preconcurrency AVAudioPlayerDelegate {
    @Published private(set) var isPlaying = false
    @Published private(set) var currentTime: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0

    private var player: AVAudioPlayer?
    private var loadedURL: URL?
    private var progressTimer: Timer?

    deinit { progressTimer?.invalidate() }

    func prepare(url: URL) {
        guard loadedURL != url else { return }
        stop()
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.delegate = self
            player.prepareToPlay()
            self.player = player
            loadedURL = url
            duration = player.duration
            currentTime = 0
        } catch {
            self.player = nil
            loadedURL = nil
            duration = 0
            currentTime = 0
        }
    }

    func toggle(url: URL) {
        prepare(url: url)
        guard let player else { return }
        if player.isPlaying {
            pause()
        } else {
            player.play()
            isPlaying = true
            startProgressUpdates()
        }
    }

    func pause() {
        player?.pause()
        isPlaying = false
        progressTimer?.invalidate()
        progressTimer = nil
        currentTime = player?.currentTime ?? currentTime
    }

    func seek(to time: TimeInterval) {
        player?.currentTime = time
        currentTime = time
    }

    func stop() {
        player?.stop()
        isPlaying = false
        currentTime = 0
        progressTimer?.invalidate()
        progressTimer = nil
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        isPlaying = false
        currentTime = 0
        progressTimer?.invalidate()
        progressTimer = nil
    }

    private func startProgressUpdates() {
        progressTimer?.invalidate()
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.currentTime = self.player?.currentTime ?? 0
            }
        }
    }
}

struct V02AudioPlaybackControl: View {
    let resource: V02AttachmentResource
    let url: URL
    @StateObject private var player = V02AudioPlayer()

    var body: some View {
        HStack(spacing: 10) {
            Button {
                player.toggle(url: url)
            } label: {
                Label(player.isPlaying ? "暂停" : "播放", systemImage: player.isPlaying ? "pause.fill" : "play.fill")
            }
            .buttonStyle(.bordered)
            .accessibilityValue(player.isPlaying ? "正在播放" : "已暂停")

            VStack(alignment: .leading, spacing: 3) {
                Text(resource.filename)
                    .lineLimit(1)
                Slider(
                    value: Binding(
                        get: { player.currentTime },
                        set: { player.seek(to: $0) }
                    ),
                    in: 0...max(player.duration, 0.1)
                )
                .accessibilityLabel("播放进度")
                .accessibilityValue("\(Self.timeText(player.currentTime))，共 \(Self.timeText(player.duration))")
                Text("\(Self.timeText(player.currentTime)) / \(Self.timeText(player.duration))")
                    .noteFont(size: 12, relativeTo: .caption)
                    .foregroundStyle(NoteTheme.secondaryInk)
            }
        }
        .onDisappear { player.stop() }
    }

    private static func timeText(_ time: TimeInterval) -> String {
        guard time.isFinite, time > 0 else { return "0:00" }
        let rounded = Int(time.rounded(.down))
        return String(format: "%d:%02d", rounded / 60, rounded % 60)
    }
}
