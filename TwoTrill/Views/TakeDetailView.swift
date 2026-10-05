import AVKit
import SwiftUI

/// Preview one take against the song and nudge its lip-sync.
struct TakeDetailView: View {
    @Binding var take: Take
    let videoURL: URL
    let songURL: URL
    let clipStart: Double
    let clipLength: Double
    let onDelete: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var player = AVPlayer()
    @State private var offset: Double = 0
    @State private var originalOffset: Double = 0
    @State private var errorMessage: String? = nil

    init(take: Binding<Take>, videoURL: URL, songURL: URL, clipStart: Double, clipLength: Double,
         onDelete: @escaping () -> Void) {
        _take = take
        self.videoURL = videoURL
        self.songURL = songURL
        self.clipStart = clipStart
        self.clipLength = clipLength
        self.onDelete = onDelete
        _offset = State(initialValue: take.wrappedValue.syncOffset)
        _originalOffset = State(initialValue: take.wrappedValue.syncOffset)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VideoPlayer(player: player)
                        .aspectRatio(9 / 16, contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: 420)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.black)
                    if let errorMessage {
                        Text(errorMessage).foregroundStyle(.red)
                    }
                }

                Section {
                    Toggle("Use in edit", isOn: $take.isEnabled)
                }

                Section {
                    VStack(alignment: .leading) {
                        Text("Offset: \(Int((offset * 1000).rounded())) ms")
                            .monospacedDigit()
                        Slider(value: $offset, in: (originalOffset - 1)...(originalOffset + 1), step: 0.01) { editing in
                            if !editing { apply(offset) }
                        }
                    }
                    HStack {
                        Button("−20 ms") { apply(offset - 0.02) }
                        Button("+20 ms") { apply(offset + 0.02) }
                        Spacer()
                        Button("Reset") { apply(originalOffset) }
                    }
                    .buttonStyle(.bordered)
                } header: {
                    Text("Lip-sync")
                } footer: {
                    Text("Watch the preview with the song. If your lips move after the words, slide right; if before, slide left.")
                }

                Section {
                    Button("Delete take", role: .destructive) {
                        dismiss()
                        onDelete()
                    }
                }
            }
            .navigationTitle("Take")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task(id: take.syncOffset) { await rebuild() }
        .onReceive(NotificationCenter.default.publisher(for: AVPlayerItem.didPlayToEndTimeNotification)) { note in
            guard (note.object as? AVPlayerItem) === player.currentItem else { return }
            player.seek(to: .zero)
            player.play()
        }
        .onDisappear { player.pause() }
    }

    private func apply(_ value: Double) {
        offset = value
        take.syncOffset = value
    }

    /// The take on its own, lined up with the song exactly as the edit will use it.
    private func rebuild() async {
        let coverage = take.coverage
        let start = max(0, coverage.start)
        let end = min(clipLength, coverage.end)
        guard end > start + 0.1 else {
            errorMessage = "This take doesn't overlap the song clip."
            return
        }
        errorMessage = nil
        let plan = EditPlan(segments: [EditSegment(start: start, end: end, takeID: take.id)], duration: end)
        do {
            let edit = try await VideoComposer.compose(plan: plan, songURL: songURL, clipStart: clipStart,
                                                       takes: [take]) { _ in videoURL }
            guard !Task.isCancelled else { return }
            player.replaceCurrentItem(with: edit.makePlayerItem())
            player.play()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
