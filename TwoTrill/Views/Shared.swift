import CoreTransferable
import SwiftUI
import UIKit
import UniformTypeIdentifiers

func formatTime(_ seconds: Double) -> String {
    let total = max(0, Int(seconds.rounded(.down)))
    return String(format: "%d:%02d", total / 60, total % 60)
}

/// One color per take, shared by the take grid and the edit timeline.
enum TakePalette {
    static let colors: [Color] = [.pink, .orange, .yellow, .green, .mint, .cyan, .blue, .purple]

    static func color(_ index: Int) -> Color {
        colors[positiveModulo(index, colors.count)]
    }
}

/// A video picked from Photos, copied somewhere we can keep it.
struct PickedMovie: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            let ext = received.file.pathExtension.isEmpty ? "mov" : received.file.pathExtension
            let copy = FileManager.default.temporaryDirectory.appendingPathComponent("import-\(UUID().uuidString).\(ext)")
            try FileManager.default.copyItem(at: received.file, to: copy)
            return PickedMovie(url: copy)
        }
    }
}

/// Shows which take is on screen when, one colored block per shot.
struct TimelineStrip: View {
    let plan: EditPlan
    let takes: [Take]

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 1) {
                ForEach(Array(plan.segments.enumerated()), id: \.offset) { _, segment in
                    let index = takes.firstIndex { $0.id == segment.takeID } ?? 0
                    RoundedRectangle(cornerRadius: 2)
                        .fill(TakePalette.color(index))
                        .overlay {
                            if segment.zoom > 1 {
                                Image(systemName: "plus.magnifyingglass")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundStyle(.black)
                            }
                        }
                        .frame(width: max(1, geometry.size.width * segment.duration / max(plan.duration, 0.01) - 1))
                }
            }
        }
    }
}

struct TakeSelection: Identifiable {
    let id: UUID
}

/// Thumbnail of a take with its number in the take's color.
struct TakeTile: View {
    let url: URL
    let number: Int
    let isEnabled: Bool
    var isHalfSpeed = false
    @State private var image: UIImage? = nil

    var body: some View {
        Color.gray.opacity(0.3)
            .aspectRatio(9 / 16, contentMode: .fit)
            .overlay {
                if let image {
                    Image(uiImage: image).resizable().scaledToFill()
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(alignment: .topLeading) {
                Text("\(number)")
                    .font(.caption2.bold())
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(TakePalette.color(number - 1), in: Capsule())
                    .padding(3)
            }
            .overlay(alignment: .bottomTrailing) {
                if isHalfSpeed {
                    Image(systemName: "tortoise.fill")
                        .font(.caption2)
                        .padding(3)
                        .background(.orange, in: Circle())
                        .padding(3)
                }
            }
            .overlay {
                if !isEnabled {
                    Image(systemName: "eye.slash.fill")
                }
            }
            .opacity(isEnabled ? 1 : 0.4)
            .foregroundStyle(.white)
            .task(id: url) { image = await Thumbnailer.image(for: url) }
    }
}
