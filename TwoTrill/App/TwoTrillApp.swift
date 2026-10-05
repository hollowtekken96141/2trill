import AVFoundation
import SwiftUI

@main
struct TwoTrillApp: App {
    @State private var store = ProjectStore()
    @State private var router = Router()

    init() {
        // Play out loud through the silent switch, alongside the camera.
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environment(store)
                .environment(router)
                .preferredColorScheme(.dark)
                .tint(.pink)
        }
    }
}
