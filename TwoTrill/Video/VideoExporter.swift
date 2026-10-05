import AVFoundation
import Photos

enum VideoExporter {
    enum ExportError: LocalizedError {
        case cannotExport, failed(Error?), photosDenied

        var errorDescription: String? {
            switch self {
            case .cannotExport: "This edit can't be exported."
            case .failed(let error): error?.localizedDescription ?? "Export failed."
            case .photosDenied: "Allow 2trill to add to Photos in Settings to save videos."
            }
        }
    }

    /// Renders the edit to an .mp4 in the temporary folder and returns its URL.
    static func export(_ edit: ComposedEdit, name: String) async throws -> URL {
        let safeName = name.components(separatedBy: CharacterSet(charactersIn: "/\\:?%*|\"<>")).joined()
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(safeName.isEmpty ? "2trill" : safeName)
            .appendingPathExtension("mp4")
        try? FileManager.default.removeItem(at: url)

        guard let session = AVAssetExportSession(asset: edit.composition, presetName: AVAssetExportPresetHighestQuality) else {
            throw ExportError.cannotExport
        }
        session.outputURL = url
        session.outputFileType = .mp4
        session.videoComposition = edit.videoComposition
        session.shouldOptimizeForNetworkUse = true
        await session.export()
        guard session.status == .completed else { throw ExportError.failed(session.error) }
        return url
    }

    static func saveToPhotos(_ url: URL) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { throw ExportError.photosDenied }
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
        }
    }
}
