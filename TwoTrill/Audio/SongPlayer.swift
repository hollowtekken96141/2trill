import AVFoundation
import Observation

/// Plays a section of the song for previewing the clip.
@Observable
final class SongPlayer {
    private(set) var isPlaying = false
    private(set) var position: Double = 0

    @ObservationIgnored private var player: AVAudioPlayer?
    @ObservationIgnored private var loadedURL: URL?
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var stopAt: Double = 0

    func play(url: URL, from start: Double, until end: Double) {
        do {
            if loadedURL != url || player == nil {
                player = try AVAudioPlayer(contentsOf: url)
                loadedURL = url
            }
            guard let player else { return }
            player.currentTime = start
            stopAt = end
            player.play()
            isPlaying = true
            timer?.invalidate()
            timer = Timer.scheduledTimer(withTimeInterval: 1 / 20, repeats: true) { [weak self] _ in
                guard let self, let player = self.player else { return }
                self.position = player.currentTime
                if !player.isPlaying || player.currentTime >= self.stopAt { self.stop() }
            }
        } catch {
            stop()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        player?.stop()
        isPlaying = false
    }
}
