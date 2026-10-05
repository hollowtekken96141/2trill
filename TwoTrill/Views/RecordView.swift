import PhotosUI
import SwiftUI

/// Third screen: the camera. Each press of the record button films one take of the whole clip
/// while the song plays out loud. Takes collect along the bottom; hit Edit when you have enough.
struct RecordView: View {
    @Binding var project: Project
    let songURL: URL
    /// Receives each recorded file with its sync offset and song rate.
    let onTake: (_ url: URL, _ syncOffset: Double, _ songRate: Double) -> Void

    // Created once on appear: SwiftUI re-runs this view's initializer whenever the project
    // changes, and a recording session owns the whole camera pipeline.
    @State private var session: RecordSession? = nil

    init(project: Binding<Project>, songURL: URL,
         onTake: @escaping (_ url: URL, _ syncOffset: Double, _ songRate: Double) -> Void) {
        _project = project
        self.songURL = songURL
        self.onTake = onTake
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let session {
                CameraScreen(project: $project, songURL: songURL, session: session)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            if session == nil {
                session = RecordSession(songURL: songURL, clipStart: project.clipStart,
                                        clipLength: project.effectiveClipLength, onTake: onTake)
            }
        }
    }
}

private struct CameraScreen: View {
    @Environment(ProjectStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(\.dismiss) private var dismiss
    @Binding var project: Project
    let songURL: URL
    let session: RecordSession

    @State private var useCountdown = true
    @State private var showSaved = false
    @State private var selectedTake: TakeSelection? = nil
    @State private var importItems: [PhotosPickerItem] = []

    private var isBusy: Bool { session.phase != .idle }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            CameraPreview(session: session.camera.session)
                .ignoresSafeArea()

            if session.camera.permissionDenied {
                ContentUnavailableView("Camera access needed",
                                       systemImage: "video.slash",
                                       description: Text("Allow camera access for 2trill in Settings to film takes."))
            }

            VStack(spacing: 10) {
                topBar
                ProgressView(value: session.progress)
                    .tint(session.halfSpeed ? .orange : .pink)
                    .padding(.horizontal)
                HStack {
                    Spacer()
                    sideTools
                }
                .padding(.horizontal)
                Spacer()
                if case .countdown(let n) = session.phase {
                    Text("\(n)")
                        .font(.system(size: 140, weight: .heavy, design: .rounded))
                        .shadow(radius: 10)
                        .contentTransition(.numericText(countsDown: true))
                }
                Spacer()
                status
                takesStrip
                bottomBar
            }
            .padding(.bottom, 12)
        }
        .statusBarHidden()
        .animation(.spring, value: session.phase)
        .animation(.spring, value: showSaved)
        .animation(.spring, value: session.halfSpeed)
        .task { await session.camera.start() }
        .onDisappear {
            session.cancel()
            session.camera.stop()
        }
        .onChange(of: session.savedCount) { _, _ in
            showSaved = true
            Task {
                try? await Task.sleep(for: .seconds(2))
                showSaved = false
            }
        }
        .onChange(of: importItems) { _, items in importClips(items) }
        .sheet(item: $selectedTake) { selection in
            if let take = project.takes.first(where: { $0.id == selection.id }) {
                TakeDetailView(
                    take: takeBinding(id: take.id, fallback: take),
                    videoURL: store.url(for: take, in: project),
                    songURL: songURL,
                    clipStart: project.clipStart,
                    clipLength: project.effectiveClipLength,
                    onDelete: { store.deleteTake(id: take.id, from: project.id) }
                )
            }
        }
        .alert("Recording problem", isPresented: Binding(
            get: { session.errorMessage != nil },
            set: { if !$0 { session.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(session.errorMessage ?? "")
        }
    }

    // MARK: - Pieces

    private var topBar: some View {
        HStack {
            circleButton("chevron.left") { dismiss() }
                .disabled(isBusy)
            Spacer()
            Text("Take \(project.takes.count + 1)")
                .font(.headline)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial, in: Capsule())
            Spacer()
            Color.clear.frame(width: 44, height: 44)
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }

    private var sideTools: some View {
        VStack(spacing: 18) {
            toolButton(icon: "arrow.triangle.2.circlepath.camera", label: "Flip") {
                session.camera.flip()
            }
            toolButton(icon: "tortoise.fill", label: "½ speed", isOn: session.halfSpeed) {
                session.setHalfSpeed(!session.halfSpeed)
            }
            toolButton(icon: "timer", label: useCountdown ? "3s" : "Off", isOn: useCountdown) {
                useCountdown.toggle()
            }
        }
        .disabled(isBusy)
        .opacity(isBusy ? 0.4 : 1)
    }

    @ViewBuilder
    private var status: some View {
        if showSaved {
            Label("Take saved", systemImage: "checkmark.circle.fill")
                .font(.headline)
                .pill()
                .transition(.move(edge: .bottom).combined(with: .opacity))
        } else if session.halfSpeed && session.phase == .idle {
            Label("Half speed: the song plays 2× fast. Your take becomes slow-mo in the edit.",
                  systemImage: "tortoise.fill")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .pill()
        } else if session.phase == .idle && project.takes.isEmpty {
            Text("Lip-sync along. The song plays while you film.")
                .font(.subheadline)
                .pill()
        }
    }

    private var takesStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(project.takes.enumerated()), id: \.element.id) { index, take in
                    Button {
                        selectedTake = TakeSelection(id: take.id)
                    } label: {
                        TakeTile(url: store.url(for: take, in: project), number: index + 1,
                                 isEnabled: take.isEnabled, isHalfSpeed: take.songRate > 1)
                            .frame(width: 48)
                    }
                }
                PhotosPicker(selection: $importItems, matching: .videos) {
                    Image(systemName: "plus")
                        .font(.headline)
                        .frame(width: 48, height: 85)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
                }
                .foregroundStyle(.white)
            }
            .padding(.horizontal)
        }
        .frame(height: 85)
        .disabled(isBusy)
        .opacity(isBusy ? 0.4 : 1)
    }

    private var bottomBar: some View {
        HStack {
            Color.clear.frame(width: 90, height: 44)
            Spacer()
            Button {
                session.toggle(countdown: useCountdown)
            } label: {
                ZStack {
                    Circle().stroke(.white, lineWidth: 5).frame(width: 80, height: 80)
                    if session.phase == .recording || session.phase == .saving {
                        RoundedRectangle(cornerRadius: 6).fill(.red).frame(width: 30, height: 30)
                    } else {
                        Circle().fill(session.halfSpeed ? .orange : .red).frame(width: 66, height: 66)
                    }
                }
            }
            .disabled(session.phase == .saving || session.camera.permissionDenied)
            Spacer()
            Button {
                router.path.append(.edit(project.id))
            } label: {
                Label("Edit", systemImage: "wand.and.stars")
                    .font(.headline)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color.pink, in: Capsule())
            }
            .foregroundStyle(.white)
            .frame(width: 90)
            .disabled(isBusy || project.enabledTakes.isEmpty)
            .opacity(isBusy || project.enabledTakes.isEmpty ? 0.4 : 1)
        }
        .padding(.horizontal, 20)
    }

    private func circleButton(_ systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.title3.weight(.semibold))
                .frame(width: 44, height: 44)
                .background(.ultraThinMaterial, in: Circle())
        }
        .foregroundStyle(.white)
    }

    private func toolButton(icon: String, label: String, isOn: Bool = false,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.title3.weight(.semibold))
                    .frame(width: 46, height: 46)
                    .background(isOn ? AnyShapeStyle(Color.orange) : AnyShapeStyle(Material.ultraThinMaterial), in: Circle())
                Text(label).font(.caption2.bold()).shadow(radius: 2)
            }
        }
        .foregroundStyle(.white)
    }

    // MARK: - Takes

    private func takeBinding(id: UUID, fallback: Take) -> Binding<Take> {
        Binding(
            get: { project.takes.first { $0.id == id } ?? fallback },
            set: { newValue in
                if let index = project.takes.firstIndex(where: { $0.id == id }) { project.takes[index] = newValue }
            }
        )
    }

    private func importClips(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        importItems = []
        let id = project.id
        Task {
            for item in items {
                do {
                    if let movie = try await item.loadTransferable(type: PickedMovie.self) {
                        // Imported clips are assumed to start right at the clip start; fix per take if not.
                        await store.addTake(to: id, from: movie.url, syncOffset: 0, songRate: 1, source: .imported)
                    }
                } catch {
                    store.errorMessage = "Couldn't import a video: \(error.localizedDescription)"
                }
            }
        }
    }
}

private extension View {
    func pill() -> some View {
        padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial, in: Capsule())
            .padding(.horizontal)
    }
}
