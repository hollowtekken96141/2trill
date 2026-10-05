import AVFoundation
import CoreGraphics

/// A ready-to-play (or export) edit: the cut-together takes plus the song clip.
struct ComposedEdit {
    let composition: AVComposition
    let videoComposition: AVVideoComposition

    func makePlayerItem() -> AVPlayerItem {
        let item = AVPlayerItem(asset: composition)
        item.videoComposition = videoComposition
        return item
    }
}

enum VideoComposer {
    static let renderSize = CGSize(width: 1080, height: 1920)
    private static let timescale: CMTimeScale = 600

    enum ComposeError: LocalizedError {
        case trackCreation, missingTake, noVideo

        var errorDescription: String? {
            switch self {
            case .trackCreation: "Couldn't create the video."
            case .missingTake: "A take used in this edit is missing."
            case .noVideo: "One of the takes has no video."
            }
        }
    }

    private struct LoadedTake {
        let track: AVAssetTrack
        let naturalSize: CGSize
        let transform: CGAffineTransform
        /// Video time of the first and (as `duration`) last frame.
        let firstFrame: Double
        let duration: Double
        let syncOffset: Double
        let songRate: Double
    }

    /// Builds the edit. Each segment shows the take's footage from the same moment in the song,
    /// so lip-sync is preserved across cuts.
    static func compose(plan: EditPlan, songURL: URL, clipStart: Double,
                        takes: [Take], urlForTake: (Take) -> URL) async throws -> ComposedEdit {
        let composition = AVMutableComposition()
        guard let videoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
              let audioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
        else { throw ComposeError.trackCreation }

        let usedIDs = Set(plan.segments.map(\.takeID))
        var loaded: [UUID: LoadedTake] = [:]
        for take in takes where usedIDs.contains(take.id) {
            let asset = AVURLAsset(url: urlForTake(take))
            guard let track = try await asset.loadTracks(withMediaType: .video).first else { throw ComposeError.noVideo }
            let (size, transform) = try await track.load(.naturalSize, .preferredTransform)
            // Use the video track's own range: a clip's audio can run longer than its picture.
            let range = try await track.load(.timeRange)
            loaded[take.id] = LoadedTake(track: track, naturalSize: size, transform: transform,
                                         firstFrame: range.start.seconds, duration: range.end.seconds,
                                         syncOffset: take.syncOffset,
                                         songRate: max(take.songRate, 0.01))
        }

        var instructions: [AVVideoCompositionInstructionProtocol] = []
        var cursor = CMTime.zero

        for segment in plan.segments {
            guard let take = loaded[segment.takeID] else { throw ComposeError.missingTake }
            let start = time(segment.start)
            let end = time(segment.end)
            guard end > start else { continue }

            if start > cursor {
                // Nothing to show here (only happens in single-take sync previews).
                let gap = CMTimeRange(start: cursor, end: start)
                videoTrack.insertEmptyTimeRange(gap)
                instructions.append(blackInstruction(gap, track: videoTrack))
            }

            // Same song moment in the take's own timeline. Half-speed takes cover the shot with
            // half as much footage, which is then stretched to fill it (slow motion, still in sync).
            // If a take doesn't quite reach, slide the window inside the footage rather than leave a hole.
            let rate = take.songRate
            let sourceLength = (segment.end - segment.start) / rate
            // (The small margin keeps rounding from asking for frames past the end of the file.)
            let sourceStart = max(take.firstFrame, min(take.syncOffset + segment.start / rate,
                                                       take.duration - sourceLength - 0.01))
            let available = min(sourceLength, take.duration - sourceStart)
            if available > 0.01 {
                let sourceDuration = time(available)
                let filled = rate == 1 ? CMTimeMinimum(sourceDuration, end - start)
                                       : CMTimeMinimum(time(available * rate), end - start)
                try videoTrack.insertTimeRange(CMTimeRange(start: time(sourceStart), duration: rate == 1 ? filled : sourceDuration),
                                               of: take.track, at: start)
                if rate != 1 {
                    videoTrack.scaleTimeRange(CMTimeRange(start: start, duration: sourceDuration), toDuration: filled)
                }
                if start + filled < end {
                    videoTrack.insertEmptyTimeRange(CMTimeRange(start: start + filled, end: end))
                }
            } else {
                videoTrack.insertEmptyTimeRange(CMTimeRange(start: start, end: end))
            }

            let instruction = AVMutableVideoCompositionInstruction()
            instruction.timeRange = CMTimeRange(start: start, end: end)
            let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: videoTrack)
            let base = fillTransform(naturalSize: take.naturalSize, preferred: take.transform, zoom: segment.zoom)
            if segment.zoom > 1 {
                // Punch-in shots slowly keep pushing in.
                let pushed = fillTransform(naturalSize: take.naturalSize, preferred: take.transform, zoom: segment.zoom * 1.05)
                layer.setTransformRamp(fromStart: base, toEnd: pushed, timeRange: instruction.timeRange)
            } else {
                layer.setTransform(base, at: start)
            }
            instruction.layerInstructions = [layer]
            instructions.append(instruction)
            cursor = end
        }

        // Song audio for the clip.
        let songAsset = AVURLAsset(url: songURL)
        if let songTrack = try await songAsset.loadTracks(withMediaType: .audio).first {
            let songDuration = try await songAsset.load(.duration)
            let audioStart = time(clipStart)
            let audioDuration = CMTimeMinimum(cursor, songDuration - audioStart)
            if audioDuration > .zero {
                try audioTrack.insertTimeRange(CMTimeRange(start: audioStart, duration: audioDuration),
                                               of: songTrack, at: .zero)
            }
        }

        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = renderSize
        videoComposition.frameDuration = CMTime(value: 1, timescale: 30)
        videoComposition.instructions = instructions
        return ComposedEdit(composition: composition, videoComposition: videoComposition)
    }

    /// Rotates footage upright, then scales it to fill the 9:16 frame (cropping the overflow), centered.
    static func fillTransform(naturalSize: CGSize, preferred: CGAffineTransform, zoom: Double) -> CGAffineTransform {
        let oriented = CGRect(origin: .zero, size: naturalSize).applying(preferred)
        guard oriented.width > 0, oriented.height > 0 else { return preferred }
        let scale = max(renderSize.width / oriented.width, renderSize.height / oriented.height) * zoom
        return preferred
            .concatenating(CGAffineTransform(translationX: -oriented.minX, y: -oriented.minY))
            .concatenating(CGAffineTransform(scaleX: scale, y: scale))
            .concatenating(CGAffineTransform(translationX: (renderSize.width - oriented.width * scale) / 2,
                                             y: (renderSize.height - oriented.height * scale) / 2))
    }

    private static func blackInstruction(_ range: CMTimeRange, track: AVCompositionTrack) -> AVMutableVideoCompositionInstruction {
        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = range
        instruction.backgroundColor = CGColor(gray: 0, alpha: 1)
        let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: track)
        layer.setOpacity(0, at: range.start)
        instruction.layerInstructions = [layer]
        return instruction
    }

    private static func time(_ seconds: Double) -> CMTime {
        CMTime(seconds: seconds, preferredTimescale: timescale)
    }
}
