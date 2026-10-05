import AVFoundation
import Observation
import QuartzCore

/// Runs one recording: countdown, film while the song clip plays, stop at the end of the clip.
///
/// Sync: recording starts first; the moment the camera reports frame 0 we schedule the song a
/// hair later on the audio clock. The gap between the two (plus the output latency of speakers
/// or headphones) is the take's `syncOffset`: where the clip start lands in the video file.
///
/// Half speed: the song plays at 2x, so filming takes half as long. The edit stretches the
/// footage back out to normal length, which turns it into slow motion that's still in sync.
@Observable
final class RecordSession {
    enum Phase: Equatable {
        case idle
        case countdown(Int)
        case recording
        case saving
    }

    private(set) var phase: Phase = .idle
    private(set) var progress: Double = 0
    private(set) var savedCount = 0
    /// Film with the song at 2x for slow-motion footage.
    private(set) var halfSpeed = false
    var errorMessage: String?

    let camera = CameraController()

    private let songURL: URL
    private let clipStart: Double
    private let clipLength: Double
    private let onTake: (_ url: URL, _ syncOffset: Double, _ songRate: Double) -> Void
    @ObservationIgnored private var player: AVAudioPlayer?
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var countdownTask: Task<Void, Never>?
    @ObservationIgnored private var syncOffset: Double = 0
    @ObservationIgnored private var songRate: Double = 1

    init(songURL: URL, clipStart: Double, clipLength: Double,
         onTake: @escaping (_ url: URL, _ syncOffset: Double, _ songRate: Double) -> Void) {
        self.songURL = songURL
        self.clipStart = clipStart
        self.clipLength = clipLength
        self.onTake = onTake
    }

    func setHalfSpeed(_ on: Bool) {
        guard phase == .idle else { return }
        halfSpeed = on
        // Film at 60 fps when we can, so the stretched footage stays smooth.
        camera.setFrameRate(on ? 60 : 30)
    }

    func toggle(countdown: Bool) {
        switch phase {
        case .idle: begin(countdown: countdown)
        case .countdown: cancel()
        case .recording: finish()
        case .saving: break
        }
    }

    func cancel() {
        countdownTask?.cancel()
        if phase == .recording { finish() } else if case .countdown = phase { phase = .idle }
    }

    private func begin(countdown: Bool) {
        guard clipLength > 0 else {
            errorMessage = "The clip has no length. Go back and pick a part of the song."
            return
        }
        do {
            let player = try AVAudioPlayer(contentsOf: songURL)
            songRate = halfSpeed ? 2 : 1
            player.enableRate = true
            player.rate = Float(songRate)
            player.prepareToPlay()
            player.currentTime = clipStart
            self.player = player
        } catch {
            errorMessage = "Couldn't play the song: \(error.localizedDescription)"
            return
        }
        countdownTask = Task { @MainActor in
            if countdown {
                for n in stride(from: 3, through: 1, by: -1) {
                    phase = .countdown(n)
                    try? await Task.sleep(for: .seconds(1))
                    if Task.isCancelled { return }
                }
            }
            startRecording()
        }
    }

    private func startRecording() {
        phase = .recording
        progress = 0
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("take-\(UUID().uuidString).mov")
        camera.startRecording(to: url, onStart: { [weak self] startedAt in
            self?.startSong(recordingStartedAt: startedAt)
        }, onFinish: { [weak self] result in
            self?.saved(result)
        })
    }

    private func startSong(recordingStartedAt: CFTimeInterval) {
        guard let player, phase == .recording else { return }
        let lead = 0.05
        let now = CACurrentMediaTime()
        player.currentTime = clipStart
        player.play(atTime: player.deviceCurrentTime + lead)
        let latency = AVAudioSession.sharedInstance().outputLatency
        syncOffset = (now + lead - recordingStartedAt) + latency

        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1 / 30, repeats: true) { [weak self] _ in
            guard let self, let player = self.player else { return }
            let elapsed = player.currentTime - self.clipStart // song time, whatever the rate
            self.progress = min(1, max(0, elapsed / self.clipLength))
            let songEnded = !player.isPlaying && CACurrentMediaTime() > now + lead + 0.5
            if elapsed >= self.clipLength || songEnded { self.finish() }
        }
    }

    private func finish() {
        timer?.invalidate()
        timer = nil
        player?.stop()
        guard phase == .recording else { return }
        phase = .saving
        camera.stopRecording()
    }

    private func saved(_ result: Result<URL, Error>) {
        timer?.invalidate()
        player?.stop()
        phase = .idle
        progress = 0
        switch result {
        case .success(let url):
            onTake(url, syncOffset, songRate)
            savedCount += 1
        case .failure(let error): errorMessage = "Recording failed: \(error.localizedDescription)"
        }
    }
}
