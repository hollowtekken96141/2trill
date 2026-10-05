# 2trill

An offline, Triller-style music video maker for iPhone. Load a song from Files, film yourself
lip-syncing the same section a few times, and 2trill cuts the takes together on the beat.

There's no account, no network and no feed. Everything stays on the phone.

## Screens

1. **Load audio.** The app opens here. Tap **Load audio** and pick an MP3 (or M4A/WAV) from
   Files. Earlier videos are listed underneath.
2. **Pick your clip.** Choose the length (15/30/45/60 s) and drag the highlighted window across the
   song's waveform to set the start. It snaps to the start of a bar. A close-up shows the clip
   with its bar lines, and you can play it back. Tempo can be corrected with ½×, 2× or Tap.
3. **Camera.** The song plays out loud while you film one take of the whole clip per press.
   The side buttons flip the camera, toggle **½ speed** and toggle the 3-second countdown.
   Takes collect along the bottom: tap one to preview it, fix its lip-sync or leave it out, or
   tap **+** to import a clip from Photos. Tap **Edit** when you're ready.
4. **Edit.** This is the auto edit. Pick Chill, Balanced or Hype, tap Remix for a new cut, and
   Export to Photos or share.

### Half speed

With **½ speed** on, the song plays at 2× while you film, so the take is half as long. In the edit
the footage is stretched to twice its length: it plays in slow motion while your lips still match
the song at normal speed. If the camera supports it, half-speed takes are filmed at 60 fps so the
slow motion stays smooth. Half-speed takes show a tortoise badge and can be mixed freely with
normal ones.

## How it works

1. **Song analysis.** 2trill copies the song into the project and analyses it on the device:
   - **Onset detection:** the audio is decoded to mono and run through an FFT (Accelerate). The
     log-magnitude spectral flux shows where drum hits and new notes land.
   - **Tempo:** autocorrelation of that curve finds the strongest repeat between 60 and 200 BPM,
     weighted toward about 120 BPM. A beat "comb" is then slid across the song to fine-tune
     tempo and phase together.
   - **Bar starts:** the beat (out of every four) with the most kick-drum (< 150 Hz) energy
     counts as beat 1.
   - **Default clip:** the busiest 30 seconds (usually the hook) are picked, starting on a bar.
2. **Film takes.** The camera records while the song clip plays, so every take lines up with the
   song. Only video is recorded; the song is laid back on at edit time, so speakers are fine.
   Each take stores a *sync offset* (where the clip starts inside the video file). It's measured
   from the camera's start time, the audio clock and the output latency. It also stores the
   song's playback rate (1× or 2×), which the edit uses to stretch half-speed footage. You can also import
   clips from Photos, then line them up in the take's Lip-sync screen.
3. **Auto edit.** Because every take follows the same song, any take can be shown at any moment
   and the lip-sync still holds. The planner (`Core/CutPlanner.swift`) walks the clip on a
   half-beat grid:
   - Shots are mostly 1–4 beats long, picked at random with weights. Busy parts of the song
     favour short shots and calm parts favour long ones.
   - Longer shots are nudged so they end on strong beats (beat 1 or 3, ideally the bar line).
   - Sometimes a **stutter burst** of quick half-beat or one-beat cuts fires on busy parts.
   - Sometimes a **punch-in** zoom starts on a loud bar line.
   - The same take never plays twice in a row, and screen time is spread across takes.
   - **Chill / Balanced / Hype** change how busy the edit is. **Remix** makes a new random cut of
     the same takes.
4. **Export.** The edit is rendered to a 1080×1920 MP4. Save it to Photos or share it.

## Building

Requirements: **Xcode 16 or newer** and an iPhone running **iOS 17+**. The camera doesn't work
in the Simulator, but importing clips does.

1. Open `TwoTrill/2trill.xcodeproj`.
2. Select the **TwoTrill** target, go to **Signing & Capabilities**, choose your Team and, if
   needed, change the bundle identifier (`com.example.twotrill`) to something unique.
3. Plug in your iPhone, select it as the run destination and press **Run**.

A free Apple ID works for running on your own phone. The app then expires after 7 days and
needs re-installing from Xcode.

The target and Swift module are named `TwoTrill`, because Swift names can't start with a digit.
The name shown under the app icon is **2trill**.

The project uses Xcode 16 folder-synced groups, so any `.swift` file you add under
`TwoTrill/TwoTrill/` is picked up without editing the project.

Run the unit tests (cut planner and tempo detection) with **⌘U**.

## Ads

A banner sits at the top of the Home and Edit screens (never over the camera). It is driven by
`TwoTrill/Ads/AdConfig.swift`:

- **Now:** `mode = .house`. The banner is a *house ad*, our own promo linking to
  [soundcloud.com/citadell](https://soundcloud.com/citadell). No ad network is contacted.
- **Later:** once AdMob has approved the app, set `mode = .adMob(unitID: "ca-app-pub-…/…")` and
  put your AdMob app ID in `Info.plist` under `GADApplicationIdentifier`. Google's
  banner then fills the slot; the house ad stays as the fallback whenever no ad is available. To
  try AdMob before approval, use Google's sample banner unit `ca-app-pub-3940256099942544/2435281174`
  (where its test ads link to is up to Google and can't be changed).

The first time AdMob mode runs, the app asks for tracking permission (Apple requires the prompt).
Ads still show if the person declines; they're just less targeted. When you fill in the App Store
privacy questionnaire, declare that the app shows third-party ads and uses the device identifier.

## Installing without a Mac

Every push to `main` runs the **iOS** workflow on GitHub's Mac runners
(`.github/workflows/ios.yml`). It does two things:

- **Build and test:** compiles the app and runs the unit tests in the iOS Simulator. A red ✗ on
  the commit means a compile error or a failing test; open the run to see which.
- **Unsigned .ipa:** builds a release copy of the app for iPhone and attaches it to the run as
  the `2trill-unsigned-ipa` artifact (kept for 30 days).

To put that build on your iPhone from a Windows PC:

1. Open the repo's **Actions** tab, click the latest green run, and download
   `2trill-unsigned-ipa`. Unzip it to get `2trill-unsigned.ipa`.
2. Install [iTunes from Apple's site](https://support.apple.com/en-us/HT210384) (not the
   Microsoft Store version) and [Sideloadly](https://sideloadly.io).
3. Plug in the iPhone, open Sideloadly, drag the `.ipa` in, enter your Apple ID and press
   **Start**. Sideloadly signs the app with your Apple ID and installs it.
4. On the iPhone, go to **Settings → General → VPN & Device Management**, tap your Apple ID and
   **Trust** it. Then open 2trill.

With a free Apple ID the app stops opening after 7 days; repeat step 3 to renew it. A paid Apple
Developer account ($99/year) extends that to a year and lets up to 100 devices install it.

You can also start a build by hand from the Actions tab with **Run workflow**.

## Project layout

```
TwoTrill/
├── App/          App entry point, audio session setup, screen routing
├── Core/         Pure logic: beat grid, tempo estimation, cut planner, seeded RNG
├── Audio/        Decoding, onset detection (Accelerate), song analysis, clip preview player
├── Models/       Project/Take/Song models and on-disk store (Documents/Projects/<id>/)
├── Video/        AVComposition builder, MP4 export, thumbnails
├── Camera/       Capture session, recording + song sync
└── Views/        SwiftUI screens: Home → Clip → Record → Editor
```

## Tips

- Film 3–6 takes and vary them: change the angle, the location, the outfit or the distance.
  That variety is what makes the cuts pop.
- Perform the whole clip in every take. Any take can be cut to at any moment.
- If one take looks early or late against the music, open it and use the Lip-sync slider.

## Ideas for later

- Pick the best take for each shot using face detection and motion (Vision framework).
- Transitions and filters (Core Image in a custom video compositor).
- Beat-synced flashes or shakes on the strongest hits.
- Support songs whose tempo drifts by tracking beats one by one instead of using a fixed grid.
