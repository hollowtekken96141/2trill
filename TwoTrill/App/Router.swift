import Foundation
import Observation

/// The app's screens, in the order you move through them.
enum Route: Hashable {
    case clip(UUID)
    case record(UUID)
    case edit(UUID)
}

@Observable
final class Router {
    var path: [Route] = []
}
