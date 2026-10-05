import AVFoundation
import Observation
import QuartzCore

/// Owns the capture session and records video-only movies (the song is added back at edit time).
@Observable
final class CameraController: NSObject {
    private(set) var position: AVCaptureDevice.Position = .front
    private(set) var isRecording = false
    private(set) var permissionDenied = false

    let session = AVCaptureSession()
    private let output = AVCaptureMovieFileOutput()
    private let queue = DispatchQueue(label: "2trill.camera")
    @ObservationIgnored private var input: AVCaptureDeviceInput?
    @ObservationIgnored private var isConfigured = false
    @ObservationIgnored private var frameRate: Double = 30
    @ObservationIgnored private var onStart: ((CFTimeInterval) -> Void)?
    @ObservationIgnored private var onFinish: ((Result<URL, Error>) -> Void)?

    @MainActor
    func start() async {
        var granted = AVCaptureDevice.authorizationStatus(for: .video) == .authorized
        if AVCaptureDevice.authorizationStatus(for: .video) == .notDetermined {
            granted = await AVCaptureDevice.requestAccess(for: .video)
        }
        guard granted else {
            permissionDenied = true
            return
        }
        let position = self.position
        queue.async { [self] in
            if !isConfigured { configure(position: position) }
            if !session.isRunning { session.startRunning() }
        }
    }

    func stop() {
        queue.async { [self] in
            if session.isRunning { session.stopRunning() }
        }
    }

    func flip() {
        guard !isRecording else { return }
        let newPosition: AVCaptureDevice.Position = position == .front ? .back : .front
        position = newPosition
        queue.async { [self] in
            guard let device = Self.camera(newPosition),
                  let newInput = try? AVCaptureDeviceInput(device: device) else { return }
            session.beginConfiguration()
            if let input { session.removeInput(input) }
            if session.canAddInput(newInput) {
                session.addInput(newInput)
                input = newInput
            } else if let input {
                session.addInput(input)
            }
            configureConnection(mirrored: newPosition == .front)
            session.commitConfiguration()
            applyFrameRate()
        }
    }

    /// Asks for a 1080p format that can run at `fps`; quietly keeps the current one if there isn't one.
    func setFrameRate(_ fps: Double) {
        queue.async { [self] in
            frameRate = fps
            applyFrameRate()
        }
    }

    private func applyFrameRate() {
        guard let device = input?.device else { return }
        let fps = frameRate
        let supports = { (format: AVCaptureDevice.Format) in
            format.videoSupportedFrameRateRanges.contains { $0.minFrameRate <= fps && fps <= $0.maxFrameRate }
        }
        let format: AVCaptureDevice.Format?
        if supports(device.activeFormat) {
            format = device.activeFormat
        } else {
            format = device.formats.first { format in
                let size = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
                return size.width == 1920 && size.height == 1080 && supports(format)
            }
        }
        guard let format else { return }
        do {
            try device.lockForConfiguration()
            device.activeFormat = format
            let duration = CMTime(value: 1, timescale: CMTimeScale(fps))
            device.activeVideoMinFrameDuration = duration
            device.activeVideoMaxFrameDuration = duration
            device.unlockForConfiguration()
        } catch {
            print("Couldn't set \(fps) fps: \(error)")
        }
    }

    /// `onStart` receives the host time recording began, so the caller can line the song up with frame 0.
    func startRecording(to url: URL,
                        onStart: @escaping (CFTimeInterval) -> Void,
                        onFinish: @escaping (Result<URL, Error>) -> Void) {
        self.onStart = onStart
        self.onFinish = onFinish
        isRecording = true
        queue.async { [self] in
            output.startRecording(to: url, recordingDelegate: self)
        }
    }

    func stopRecording() {
        queue.async { [self] in
            if output.isRecording { output.stopRecording() }
        }
    }

    private func configure(position: AVCaptureDevice.Position) {
        session.beginConfiguration()
        // We play music while filming; don't let the camera take over the audio session.
        session.automaticallyConfiguresApplicationAudioSession = false
        if session.canSetSessionPreset(.hd1920x1080) { session.sessionPreset = .hd1920x1080 }
        if let device = Self.camera(position), let newInput = try? AVCaptureDeviceInput(device: device),
           session.canAddInput(newInput) {
            session.addInput(newInput)
            input = newInput
        }
        if session.canAddOutput(output) { session.addOutput(output) }
        configureConnection(mirrored: position == .front)
        session.commitConfiguration()
        isConfigured = true
    }

    private func configureConnection(mirrored: Bool) {
        guard let connection = output.connection(with: .video) else { return }
        if connection.isVideoRotationAngleSupported(90) { connection.videoRotationAngle = 90 }
        if connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = mirrored
        }
        if connection.isVideoStabilizationSupported { connection.preferredVideoStabilizationMode = .auto }
    }

    private static func camera(_ position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position)
    }
}

extension CameraController: AVCaptureFileOutputRecordingDelegate {
    func fileOutput(_ output: AVCaptureFileOutput, didStartRecordingTo fileURL: URL, from connections: [AVCaptureConnection]) {
        let startedAt = CACurrentMediaTime()
        DispatchQueue.main.async { self.onStart?(startedAt) }
    }

    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL,
                    from connections: [AVCaptureConnection], error: Error?) {
        // Some "errors" still leave a usable file (e.g. max length reached).
        var succeeded = error == nil
        if let error = error as NSError? {
            succeeded = (error.userInfo[AVErrorRecordingSuccessfullyFinishedKey] as? Bool) ?? false
        }
        DispatchQueue.main.async {
            self.isRecording = false
            if succeeded {
                self.onFinish?(.success(outputFileURL))
            } else {
                self.onFinish?(.failure(error ?? CocoaError(.fileWriteUnknown)))
            }
            self.onStart = nil
            self.onFinish = nil
        }
    }
}
