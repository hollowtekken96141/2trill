import Foundation

/// Everything about the banner ad slot in one place.
enum AdConfig {
    enum Mode {
        /// Our own banner, linking to `houseAdURL`. No ad network involved.
        case house
        /// Google AdMob banners, falling back to the house ad when none is available.
        case adMob(unitID: String)
    }

    /// Switch to `.adMob(unitID: "ca-app-pub-…/…")` once AdMob has approved the app.
    /// Google's sample banner unit for testing is `ca-app-pub-3940256099942544/2435281174`;
    /// also change `GADApplicationIdentifier` in Info.plist when going live.
    static let mode: Mode = .house

    static let houseAdURL = URL(string: "https://soundcloud.com/citadell")!
    static let houseAdTitle = "citadell"
    static let houseAdSubtitle = "Hear more on SoundCloud"

    /// Standard banner height.
    static let bannerHeight: CGFloat = 50

    static var usesAdMob: Bool {
        if case .adMob = mode { return true }
        return false
    }
}
