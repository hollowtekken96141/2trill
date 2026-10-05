import AppTrackingTransparency
import GoogleMobileAds
import SwiftUI

/// The banner slot shown at the top of a screen. Shows an AdMob banner when one is configured
/// and loaded, and our own house ad otherwise.
struct AdBanner: View {
    @State private var adMobLoaded = false

    var body: some View {
        ZStack {
            HouseAd()
                .opacity(adMobLoaded ? 0 : 1)
            if case .adMob(let unitID) = AdConfig.mode {
                AdMobBanner(unitID: unitID, isLoaded: $adMobLoaded)
            }
        }
        .frame(height: AdConfig.bannerHeight)
        .frame(maxWidth: .infinity)
        .background(Color.black)
        .animation(.easeInOut(duration: 0.3), value: adMobLoaded)
    }
}

/// Our own banner: a tap opens the SoundCloud page.
struct HouseAd: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        Button {
            openURL(AdConfig.houseAdURL)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "waveform.circle.fill")
                    .font(.title)
                    .foregroundStyle(.white, .orange)
                VStack(alignment: .leading, spacing: 1) {
                    Text(AdConfig.houseAdTitle)
                        .font(.subheadline.bold())
                    Text(AdConfig.houseAdSubtitle)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.8))
                }
                Spacer()
                Text("Ad")
                    .font(.caption2.bold())
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(.white.opacity(0.2), in: RoundedRectangle(cornerRadius: 3))
                Image(systemName: "chevron.right")
                    .font(.caption.bold())
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .frame(height: AdConfig.bannerHeight)
            .frame(maxWidth: .infinity)
            .background(LinearGradient(colors: [Color(red: 1, green: 0.33, blue: 0), Color(red: 1, green: 0.55, blue: 0)],
                                       startPoint: .leading, endPoint: .trailing))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Advertisement: \(AdConfig.houseAdTitle) on SoundCloud")
    }
}

/// A Google AdMob banner sized to the screen width.
struct AdMobBanner: UIViewRepresentable {
    let unitID: String
    @Binding var isLoaded: Bool

    func makeCoordinator() -> Coordinator { Coordinator(isLoaded: $isLoaded) }

    func makeUIView(context: Context) -> BannerView {
        let width = UIScreen.main.bounds.width
        let banner = BannerView(adSize: currentOrientationAnchoredAdaptiveBanner(width: width))
        banner.adUnitID = unitID
        banner.delegate = context.coordinator
        banner.rootViewController = UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow?.rootViewController }
            .first
        banner.load(Request())
        return banner
    }

    func updateUIView(_ uiView: BannerView, context: Context) {}

    final class Coordinator: NSObject, BannerViewDelegate {
        @Binding var isLoaded: Bool

        init(isLoaded: Binding<Bool>) { _isLoaded = isLoaded }

        func bannerViewDidReceiveAd(_ bannerView: BannerView) { isLoaded = true }

        func bannerView(_ bannerView: BannerView, didFailToReceiveAdWithError error: Error) {
            isLoaded = false
            print("Banner failed to load: \(error.localizedDescription)")
        }
    }
}

enum AdsSetup {
    /// Starts the ad SDK (only when AdMob is in use) and asks for tracking permission once.
    /// Call after the first screen is on screen so the prompt doesn't land on a blank app.
    static func start() async {
        guard AdConfig.usesAdMob else { return }
        try? await Task.sleep(for: .seconds(1))
        if ATTrackingManager.trackingAuthorizationStatus == .notDetermined {
            _ = await ATTrackingManager.requestTrackingAuthorization()
        }
        await MobileAds.shared.start()
    }
}
