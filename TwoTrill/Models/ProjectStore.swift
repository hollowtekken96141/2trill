import AVFoundation
import Observation
import SwiftUI

/// Keeps every project in its own folder under Documents/Projects:
/// `project.json`, the song file, take videos and the cached song analysis.
@Observable
final class ProjectStore {
    private(set) var projects: [Project] = []
    /// Projects whose song is still being analysed.
    private(set) var analyzing: Set<UUID> = []
    var errorMessage: String?
    let rootURL: URL

    @ObservationIgnored private var envelopes: [UUID: OnsetEnvelope] = [:]
    @ObservationIgnored private var waveforms: [UUID: Waveform] = [:]

    init(rootURL: URL? = nil) {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        self.rootURL = rootURL ?? documents.appendingPathComponent("Projects", isDirectory: true)
        try? FileManager.default.createDirectory(at: self.rootURL, withIntermediateDirectories: true)
        load()
    }

    // MARK: Paths

    func folder(for id: UUID) -> URL {
        rootURL.appendingPathComponent(id.uuidString, isDirectory: true)
    }

    func fileURL(_ name: String, in project: Project) -> URL {
        folder(for: project.id).appendingPathComponent(name)
    }

    func songURL(for project: Project) -> URL? {
        project.song.map { fileURL($0.fileName, in: project) }
    }

    func url(for take: Take, in project: Project) -> URL {
        fileURL(take.fileName, in: project)
    }

    // MARK: Projects

    func project(id: UUID) -> Project? {
        projects.first { $0.id == id }
    }

    /// A binding that reads and writes the stored project, saving every change.
    func binding(for id: UUID) -> Binding<Project> {
        let fallback = project(id: id) ?? Project(id: id, name: "")
        return Binding(
            get: { self.project(id: id) ?? fallback },
            set: { self.update($0) }
        )
    }

    func update(_ project: Project) {
        guard let index = projects.firstIndex(where: { $0.id == project.id }), projects[index] != project else { return }
        projects[index] = project
        save(project)
    }

    func delete(_ project: Project) {
        projects.removeAll { $0.id == project.id }
        envelopes[project.id] = nil
        waveforms[project.id] = nil
        try? FileManager.default.removeItem(at: folder(for: project.id))
    }

    // MARK: Song

    /// Starts a new project from an audio file picked in Files. Analysis continues in the background.
    func createProject(withSongAt url: URL) -> UUID? {
        var project = Project(name: url.deletingPathExtension().lastPathComponent,
                              seed: UInt64.random(in: 1...UInt64(UInt32.max)))
        try? FileManager.default.createDirectory(at: folder(for: project.id), withIntermediateDirectories: true)

        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        let ext = url.pathExtension.isEmpty ? "mp3" : url.pathExtension.lowercased()
        let fileName = "song.\(ext)"
        do {
            try FileManager.default.copyItem(at: url, to: fileURL(fileName, in: project))
        } catch {
            try? FileManager.default.removeItem(at: folder(for: project.id))
            errorMessage = "Couldn't open that audio file: \(error.localizedDescription)"
            return nil
        }
        project.song = Song(fileName: fileName, title: project.name, duration: 0)
        projects.insert(project, at: 0)
        save(project)

        let id = project.id
        analyzing.insert(id)
        Task { @MainActor [self] in
            await analyzeSong(projectID: id)
            analyzing.remove(id)
        }
        return id
    }

    @MainActor
    private func analyzeSong(projectID: UUID) async {
        guard let project = project(id: projectID), let url = songURL(for: project) else { return }
        let metadata = await SongAnalyzer.metadata(url: url)
        do {
            let analysis = try await SongAnalyzer.analyze(url: url)
            envelopes[projectID] = analysis.envelope
            waveforms[projectID] = analysis.waveform
            write(analysis.envelope, to: "analysis.json", in: project)
            write(analysis.waveform, to: "waveform.json", in: project)

            guard var updated = self.project(id: projectID) else { return }
            let grid = analysis.grid ?? BeatGrid(bpm: 120, firstBeat: 0, downbeatIndex: 0)
            let duration = metadata.duration > 0 ? metadata.duration : analysis.waveform.duration
            if let title = metadata.title { updated.name = title }
            updated.song?.title = metadata.title ?? updated.name
            updated.song?.artist = metadata.artist
            updated.song?.duration = duration
            updated.song?.grid = grid
            updated.clipLength = min(30, duration)
            updated.clipStart = SongAnalyzer.suggestedClipStart(envelope: analysis.envelope, grid: grid,
                                                                length: updated.clipLength, songDuration: duration)
            update(updated)
            if analysis.grid == nil {
                errorMessage = "Couldn't find the beat, so it's set to 120 BPM. Tap along to fix it."
            }
        } catch {
            errorMessage = "Couldn't read this song: \(error.localizedDescription)"
        }
    }

    func envelope(for project: Project) -> OnsetEnvelope? {
        if let cached = envelopes[project.id] { return cached }
        let loaded: OnsetEnvelope? = read("analysis.json", in: project)
        envelopes[project.id] = loaded
        return loaded
    }

    func waveform(for project: Project) -> Waveform? {
        if let cached = waveforms[project.id] { return cached }
        let loaded: Waveform? = read("waveform.json", in: project)
        waveforms[project.id] = loaded
        return loaded
    }

    // MARK: Takes

    /// Moves a recorded or imported video into the project as a new take.
    @MainActor
    func addTake(to projectID: UUID, from tempURL: URL, syncOffset: Double, songRate: Double,
                 source: Take.Source) async {
        guard let project = project(id: projectID) else { return }
        let ext = tempURL.pathExtension.isEmpty ? "mov" : tempURL.pathExtension
        let fileName = "take-\(UUID().uuidString).\(ext)"
        let destination = fileURL(fileName, in: project)
        do {
            try FileManager.default.moveItem(at: tempURL, to: destination)
            let duration = try await AVURLAsset(url: destination).load(.duration).seconds
            guard var updated = self.project(id: projectID) else { return }
            updated.takes.append(Take(fileName: fileName, syncOffset: syncOffset, duration: duration,
                                      source: source, songRate: songRate))
            update(updated)
        } catch {
            errorMessage = "Couldn't save the take: \(error.localizedDescription)"
        }
    }

    func deleteTake(id takeID: UUID, from projectID: UUID) {
        guard var project = project(id: projectID),
              let index = project.takes.firstIndex(where: { $0.id == takeID }) else { return }
        let take = project.takes.remove(at: index)
        try? FileManager.default.removeItem(at: url(for: take, in: project))
        update(project)
    }

    // MARK: Persistence

    private func save(_ project: Project) {
        write(project, to: "project.json", in: project)
    }

    private func write<T: Encodable>(_ value: T, to name: String, in project: Project) {
        do {
            try JSONEncoder().encode(value).write(to: fileURL(name, in: project), options: .atomic)
        } catch {
            print("Failed to write \(name) for \(project.id): \(error)")
        }
    }

    private func read<T: Decodable>(_ name: String, in project: Project) -> T? {
        guard let data = try? Data(contentsOf: fileURL(name, in: project)) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private func load() {
        let folders = (try? FileManager.default.contentsOfDirectory(at: rootURL, includingPropertiesForKeys: nil)) ?? []
        projects = folders
            .compactMap { try? Data(contentsOf: $0.appendingPathComponent("project.json")) }
            .compactMap { try? JSONDecoder().decode(Project.self, from: $0) }
            .sorted { $0.createdAt > $1.createdAt }
    }
}
