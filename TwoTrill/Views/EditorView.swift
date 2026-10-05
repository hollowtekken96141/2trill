import AVKit
import SwiftUI

/// Shows the auto edit. Change the style or hit Remix for a different cut; export when happy.
struct EditorView: View {
    @Environment(ProjectStore.self) private var store
    @Binding var project: Project
    let envelope: OnsetEnvelope?

    @State private var player = AVPlayer()
    @State private var edit: ComposedEdit? = nil
    @State private var plan: EditPlan? = nil
    @State private var isBuilding = false
    @State private var isExporting = false
    @State private var exported: ExportedVideo? = nil
    @State private var errorMessage: String? = nil

    /// Everything that changes the edit; a change rebuilds it.
    private struct Inputs: Hashable {
        var takes: [Take]
        var style: CutStyle
        var seed: UInt64
        var clipStart: Double
        var clipLength: Double
        var grid: BeatGrid?
    }

    private var inputs: Inputs {
        Inputs(takes: project.enabledTakes, style: project.style, seed: project.seed,
               clipStart: project.clipStart, clipLength: project.effectiveClipLength, grid: project.song?.grid)
    }

    var body: some View {
        VStack(spacing: 16) {
            AdBanner()
                .padding(.horizontal, -16)
            ZStack {
                Color.black
                VideoPlayer(player: player)
                if isBuilding { ProgressView().controlSize(.large) }
            }
            .aspectRatio(9 / 16, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .frame(maxHeight: .infinity)

            if let plan {
                VStack(alignment: .leading, spacing: 4) {
                    TimelineStrip(plan: plan, takes: project.takes)
                        .frame(height: 24)
                    Text("\(plan.segments.count) shots")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Picker("Style", selection: $project.style) {
                ForEach(CutStyle.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)

            HStack(spacing: 12) {
                Button {
                    project.seed = UInt64.random(in: 1...UInt64(UInt32.max))
                } label: {
                    Label("Remix", systemImage: "shuffle").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button {
                    Task { await export() }
                } label: {
                    Label(isExporting ? "Exporting…" : "Export", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(edit == nil || isExporting || isBuilding)
            }
            .controlSize(.large)
        }
        .padding()
        .navigationTitle("Auto Edit")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: inputs) { await rebuild() }
        .onReceive(NotificationCenter.default.publisher(for: AVPlayerItem.didPlayToEndTimeNotification)) { note in
            guard (note.object as? AVPlayerItem) === player.currentItem else { return }
            player.seek(to: .zero)
            player.play()
        }
        .onDisappear { player.pause() }
        .sheet(item: $exported) { video in
            ExportedSheet(url: video.url)
        }
        .alert("Something went wrong", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func rebuild() async {
        guard let grid = project.song?.grid, let songURL = store.songURL(for: project) else { return }
        let takes = project.enabledTakes
        guard !takes.isEmpty else { return }

        isBuilding = true
        defer { isBuilding = false }

        let planner = CutPlanner(grid: grid, clipStart: project.clipStart, clipLength: project.effectiveClipLength,
                                 envelope: envelope, style: project.style)
        let newPlan = planner.plan(takes: takes.map(\.coverage), seed: project.seed)
        let snapshot = project
        do {
            let newEdit = try await VideoComposer.compose(plan: newPlan, songURL: songURL, clipStart: snapshot.clipStart,
                                                          takes: takes) { store.url(for: $0, in: snapshot) }
            guard !Task.isCancelled else { return }
            plan = newPlan
            edit = newEdit
            player.replaceCurrentItem(with: newEdit.makePlayerItem())
            player.play()
        } catch {
            if !Task.isCancelled { errorMessage = error.localizedDescription }
        }
    }

    private func export() async {
        guard let edit else { return }
        player.pause()
        isExporting = true
        defer { isExporting = false }
        do {
            let url = try await VideoExporter.export(edit, name: project.name)
            exported = ExportedVideo(url: url)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct ExportedVideo: Identifiable {
    let url: URL
    var id: URL { url }
}

private struct ExportedSheet: View {
    let url: URL
    @State private var player = AVPlayer()
    @State private var saveState: SaveState = .idle

    private enum SaveState: Equatable {
        case idle, saving, saved, failed(String)
    }

    var body: some View {
        VStack(spacing: 16) {
            Text("Your video is ready").font(.title2.bold())
            VideoPlayer(player: player)
                .aspectRatio(9 / 16, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .frame(maxHeight: .infinity)

            Button {
                Task { await save() }
            } label: {
                Group {
                    switch saveState {
                    case .idle, .failed: Label("Save to Photos", systemImage: "photo.badge.arrow.down")
                    case .saving: Label("Saving…", systemImage: "hourglass")
                    case .saved: Label("Saved to Photos", systemImage: "checkmark.circle.fill")
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(saveState == .saving || saveState == .saved)

            ShareLink(item: url) {
                Label("Share", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            if case .failed(let message) = saveState {
                Text(message).font(.footnote).foregroundStyle(.red)
            }
        }
        .controlSize(.large)
        .padding()
        .presentationDragIndicator(.visible)
        .onAppear {
            if player.currentItem == nil { player.replaceCurrentItem(with: AVPlayerItem(url: url)) }
            player.play()
        }
        .onDisappear { player.pause() }
    }

    private func save() async {
        saveState = .saving
        do {
            try await VideoExporter.saveToPhotos(url)
            saveState = .saved
        } catch {
            saveState = .failed(error.localizedDescription)
        }
    }
}
