import SwiftUI
import UniformTypeIdentifiers

/// First screen: load a song. Earlier videos are listed underneath.
struct HomeView: View {
    @Environment(ProjectStore.self) private var store
    @Environment(Router.self) private var router
    @State private var isPicking = false

    var body: some View {
        @Bindable var router = router
        NavigationStack(path: $router.path) {
            List {
                Section {
                    VStack(spacing: 20) {
                        Text("2trill")
                            .font(.system(size: 64, weight: .black, design: .rounded))
                            .foregroundStyle(LinearGradient(colors: [.pink, .orange], startPoint: .leading, endPoint: .trailing))
                        Text("Load a song, film a few takes, and get a music video cut on the beat.")
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                        Button {
                            isPicking = true
                        } label: {
                            Label("Load audio", systemImage: "waveform.badge.plus")
                                .font(.title3.bold())
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        Text("MP3, M4A or WAV from the Files app")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 24)
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                }

                if !store.projects.isEmpty {
                    Section("Recent") {
                        ForEach(store.projects) { project in
                            Button {
                                open(project)
                            } label: {
                                ProjectRow(project: project, isAnalyzing: store.analyzing.contains(project.id))
                            }
                            .foregroundStyle(.primary)
                        }
                        .onDelete { offsets in
                            offsets.map { store.projects[$0] }.forEach(store.delete)
                        }
                    }
                }
            }
            .navigationDestination(for: Route.self) { route in
                destination(route)
            }
            .fileImporter(isPresented: $isPicking, allowedContentTypes: [.mp3, .audio]) { result in
                switch result {
                case .success(let url):
                    if let id = store.createProject(withSongAt: url) { router.path = [.clip(id)] }
                case .failure(let error):
                    store.errorMessage = error.localizedDescription
                }
            }
        }
        .alert("Something went wrong", isPresented: Binding(
            get: { store.errorMessage != nil },
            set: { if !$0 { store.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(store.errorMessage ?? "")
        }
    }

    private func open(_ project: Project) {
        router.path = project.takes.isEmpty ? [.clip(project.id)] : [.clip(project.id), .record(project.id)]
    }

    @ViewBuilder
    private func destination(_ route: Route) -> some View {
        switch route {
        case .clip(let id):
            ClipView(projectID: id)
        case .record(let id):
            if let project = store.project(id: id), let songURL = store.songURL(for: project) {
                RecordView(project: store.binding(for: id), songURL: songURL) { url, offset, rate in
                    Task { await store.addTake(to: id, from: url, syncOffset: offset, songRate: rate, source: .camera) }
                }
            }
        case .edit(let id):
            if let project = store.project(id: id) {
                EditorView(project: store.binding(for: id), envelope: store.envelope(for: project))
            }
        }
    }
}

private struct ProjectRow: View {
    let project: Project
    let isAnalyzing: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "music.note")
                .font(.title3)
                .frame(width: 40, height: 40)
                .background(Color.pink.gradient, in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 3) {
                Text(project.name).font(.headline).lineLimit(1)
                Group {
                    if isAnalyzing {
                        Text("Analyzing…")
                    } else {
                        Text("\(project.takes.count) take\(project.takes.count == 1 ? "" : "s") · \(project.createdAt.formatted(date: .abbreviated, time: .omitted))")
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}
