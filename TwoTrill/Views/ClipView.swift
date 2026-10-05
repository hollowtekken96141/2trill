import SwiftUI

/// Second screen: choose how long the video is and where in the song it starts.
struct ClipView: View {
    @Environment(ProjectStore.self) private var store
    @Environment(Router.self) private var router
    let projectID: UUID

    @State private var player = SongPlayer()
    @State private var tapTimes: [Date] = []

    private var binding: Binding<Project> { store.binding(for: projectID) }
    private var project: Project { binding.wrappedValue }
    private var isAnalyzing: Bool { store.analyzing.contains(projectID) }

    var body: some View {
        VStack(spacing: 20) {
            header
            if isAnalyzing {
                Spacer()
                ProgressView {
                    Text("Finding the beat…")
                }
                .controlSize(.large)
                Spacer()
            } else if let song = project.song {
                editor(song)
            }
        }
        .padding()
        .navigationTitle("Pick your clip")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: project.clipLength) { _, _ in binding.wrappedValue.snapClipStart() }
        .onDisappear { player.stop() }
    }

    private var header: some View {
        VStack(spacing: 4) {
            Text(project.song?.title ?? project.name)
                .font(.title2.bold())
                .lineLimit(1)
            if let artist = project.song?.artist {
                Text(artist).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func editor(_ song: Song) -> some View {
        let waveform = store.waveform(for: project)
        let playhead = player.isPlaying ? player.position : nil

        VStack(alignment: .leading, spacing: 8) {
            Text("Length").font(.headline)
            Picker("Length", selection: binding.clipLength) {
                ForEach([15.0, 30, 45, 60].filter { $0 <= max(15, song.duration) }, id: \.self) {
                    Text("\(Int($0)) sec").tag($0)
                }
            }
            .pickerStyle(.segmented)
        }

        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Start").font(.headline)
                Spacer()
                Text("\(formatTime(project.clipStart)) – \(formatTime(project.clipStart + project.effectiveClipLength))")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            WaveformScrubber(waveform: waveform, duration: song.duration, clipLength: project.clipLength,
                             clipStart: binding.clipStart, playhead: playhead) {
                binding.wrappedValue.snapClipStart()
                if player.isPlaying { play() }
            }
            .frame(height: 64)
            Text("Drag the highlighted part to choose where your video starts. It snaps to the start of a bar.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        ClipWaveform(waveform: waveform, grid: song.grid, start: project.clipStart,
                     length: project.effectiveClipLength, playhead: playhead)
            .frame(height: 90)
            .padding(10)
            .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))

        HStack(spacing: 16) {
            Button {
                if player.isPlaying { player.stop() } else { play() }
            } label: {
                Image(systemName: player.isPlaying ? "stop.fill" : "play.fill")
                    .font(.title2)
                    .frame(width: 56, height: 56)
                    .background(Color.white.opacity(0.12), in: Circle())
            }
            .foregroundStyle(.white)

            if let grid = song.grid {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(grid.bpm, specifier: "%.1f") BPM").font(.headline.monospacedDigit())
                    Text("Tempo").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                HStack(spacing: 6) {
                    Button("½×") { setBPM(grid.bpm / 2) }
                    Button("2×") { setBPM(grid.bpm * 2) }
                    Button("Tap") { tap() }
                }
                .buttonStyle(.bordered)
            }
        }

        Spacer(minLength: 0)

        Button {
            player.stop()
            router.path.append(.record(projectID))
        } label: {
            Label("Next: film takes", systemImage: "video.fill")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(song.grid == nil)
    }

    private func play() {
        guard let url = store.songURL(for: project) else { return }
        player.play(url: url, from: project.clipStart, until: project.clipStart + project.effectiveClipLength)
    }

    private func setBPM(_ bpm: Double) {
        guard project.song?.grid != nil else { return }
        let clamped = min(240, max(40, bpm))
        var updated = project
        if let envelope = store.envelope(for: project) {
            updated.song?.grid = TempoEstimator.fitGrid(envelope, bpm: clamped)
        } else {
            updated.song?.grid?.bpm = clamped
        }
        updated.snapClipStart()
        binding.wrappedValue = updated
    }

    /// Tap tempo: the median gap of the last few taps.
    private func tap() {
        let now = Date()
        if let last = tapTimes.last, now.timeIntervalSince(last) > 2 { tapTimes.removeAll() }
        tapTimes.append(now)
        tapTimes = Array(tapTimes.suffix(8))
        guard tapTimes.count >= 4 else { return }
        let gaps = zip(tapTimes.dropFirst(), tapTimes).map { $0.timeIntervalSince($1) }.sorted()
        setBPM((60 / gaps[gaps.count / 2] * 2).rounded() / 2)
    }
}
