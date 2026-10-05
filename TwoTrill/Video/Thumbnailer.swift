import AVFoundation
import UIKit

enum Thumbnailer {
    private static let cache = NSCache<NSURL, UIImage>()

    static func image(for url: URL, at seconds: Double = 1) async -> UIImage? {
        if let cached = cache.object(forKey: url as NSURL) { return cached }
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 360, height: 360)
        guard let cgImage = try? await generator.image(at: CMTime(seconds: seconds, preferredTimescale: 600)).image else {
            return nil
        }
        let image = UIImage(cgImage: cgImage)
        cache.setObject(image, forKey: url as NSURL)
        return image
    }
}
