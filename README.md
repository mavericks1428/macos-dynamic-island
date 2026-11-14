# AirIsland — a native Dynamic Island for macOS 12

[![Build](https://github.com/mavericks1428/macos-dynamic-island/actions/workflows/build.yml/badge.svg)](https://github.com/mavericks1428/macos-dynamic-island/actions/workflows/build.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
![Platform: macOS 12+](https://img.shields.io/badge/Platform-macOS%2012%2B-blue)
![Swift 5.7](https://img.shields.io/badge/Swift-5.7-orange)
![No dependencies](https://img.shields.io/badge/dependencies-none-brightgreen)

A Dynamic Island-style notch replacement for Macs that don't have a notch — built in pure **Swift + AppKit + SwiftUI** for **macOS 12 Monterey**, and tuned specifically for the **MacBook Air 2017** (`MacBookAir7,2`, 1440×900 non-Retina, Intel).

No Electron, no webviews, no third-party dependencies. Sits in the menu bar, morphs open on hover, and stays out of the way in full-screen apps.

> Built and tested against macOS 12.7.6 / Swift 5.7. It compiles and runs on later macOS too, but macOS 12 is the supported floor.

---

## Features

- **Native vibrancy that follows your menu bar.** Behind-window `NSVisualEffectView` glass (`.menu` / `.popover`) paired with live `NSStatusBarButton.effectiveAppearance` detection, so *Sync* stays accurate even with wallpaper-driven dark menu bars. Explicit **Dark** / **Light** overrides in **Prefs**.
- **Menu bar or floating.** Tucks into the 22 pt Monterey menu bar or floats just below it — switchable from **Prefs**, the menu bar icon, or the right-click menu.
- **Hides politely.** Slides away in full-screen apps, other Spaces, and when Notification Center, Control Center, Spotlight, Launchpad or Mission Control is open; slides back down when you pull the menu bar into view.
- **Now Playing + Music Theme Sync.** Works with Apple Music, Spotify and browser players (`MediaRemote.framework` with AppleScript fallback). Album art, dual-tone palette extraction, and a **theme sync** toggle that washes the island in the current track's colours.
- **Synced lyrics that stay in sync.** Spotify-style scrolling capsule with per-line CoreText rendering, edge fades, spring-eased active-line growth, ±0.25 s nudge controls, and a playback clock that interpolates between polled positions so lines change on the beat — not on the poll.
- **Pomodoro timer.** Wall-clock-accurate presets (`Focus 25m`, `Break 5m`, `15m`, `1m`), ±1 m adjustments, a live countdown right in the collapsed pill, and a completion alert.
- **File shelf & clipboard history.** Drag files onto the pill to stash them; drag back out, reveal in Finder or AirDrop. Clipboard history is in-memory only and skips password-manager entries.
- **System telemetry.** CPU, RAM (Activity Monitor's `(internal − purgeable) + wired + compressed` formula via Mach `host_statistics64`) and battery %, with MagSafe/AC toast alerts via IOKit.
- **No permissions required.** Global hotkey is Carbon `⌥ Space`; it never asks for Accessibility, Input Monitoring or Screen Recording.
- **Apple-native motion.** One table of spring-physics tokens drives every transition — weighted `0.97` press states, hover depth, a cursor-tracking sheen, and fluid layout remapping. Automatically becomes instant when **Reduce Motion** is enabled.

---

## Install

### Option A — build it yourself (recommended)

You need **Apple Command Line Tools** (~500 MB), not the full 12 GB Xcode:

```bash
xcode-select --install
```

Then:

```bash
git clone https://github.com/mavericks1428/macos-dynamic-island.git
cd macos-dynamic-island
./build.sh app        # produces AirIsland.app with its icon
open AirIsland.app
```

Or double-click **`Install AirIsland.command`**, which compiles, installs to `/Applications/AirIsland.app` and launches it.

> **If macOS says “unidentified developer”** — expected. The app is ad-hoc signed, not notarized, so Gatekeeper can't verify a publisher. Right-click the `.command` → **Open** → **Open**, or run `xattr -dr com.apple.quarantine .` in the project folder first. Details and fixes in [SECURITY.md](SECURITY.md).

### Option B — download a build

Every push is compiled on a real `macos-12` runner by GitHub Actions. Open the **Actions** tab → latest green run → download the **AirIsland-app** artifact.

### Option C — Xcode

```bash
open Package.swift   # then press ⌘R
```

---

## Controls

| Action | How |
| :--- | :--- |
| Expand / collapse | Click the pill, hover ~0.24 s, or press **`⌥ Space`** |
| Close | Click outside the island, or press **`Esc`** |
| Switch placement | Right-click the pill → *Move Below Menu Bar* / *Move Into Menu Bar*, or **Prefs** |
| Stash a file | Drag any file onto the top-centre pill |
| Launch at login | **Prefs** → *Launch at login* (writes `~/Library/LaunchAgents/com.airisland.app.plist`) |
| Quit | Menu bar icon → *Quit AirIsland*, or **Prefs** → *Quit* |

---

## How it's built

| File | Responsibility |
| :--- | :--- |
| `Sources/AirIsland/Motion.swift` | All spring-physics tokens, `FluidTextSwap`, cursor sheen, micro-press |
| `Sources/AirIsland/IslandPanel.swift` | Borderless non-activating `NSPanel`, hover/hit-testing, Space & overlay visibility |
| `Sources/AirIsland/IslandContainerView.swift` | Root SwiftUI view, 9-slice glass mask, collapsed pill, expanded hub |
| `Sources/AirIsland/TabViews.swift` | Music, lyrics (CoreText engine), timer, shelf, system and settings tabs |
| `Sources/AirIsland/MediaController.swift` | MediaRemote + AppleScript playback, interpolated clock, LRCLIB lyrics |
| `Sources/AirIsland/IslandState.swift` | Observable UI state, geometry, preferences, Launch at Login |
| `AppResources/generate_icon.swift` | Draws the app icon squircle, then `iconutil` packs the `.icns` |

Design notes worth knowing if you're reading the code:

- The panel is a **fixed 492×336 canvas** that never resizes. The island only animates *inside* it, so the window server never lags behind a morph.
- Collapse defers resigning key focus by ~0.68 s; ordering the window out mid-spring is what makes shrink animations snap instead of glide.
- Lyrics use a custom `NSView` renderer rather than SwiftUI text so the active line can grow and scroll without offscreen rasterisation blur on a 1× display.

---

## Privacy

No accounts, no analytics, no telemetry, no ads. The only network calls are a lyric lookup to `lrclib.net` (track title/artist/album/duration only, and only when you open Lyrics) and artwork fetches for Spotify. Full inventory of network calls, Apple Events, input monitoring and file writes — plus commands to verify each one yourself — in **[SECURITY.md](SECURITY.md)**.

---

## Contributing

Issues and pull requests are welcome. Please keep the pull requests focused, match the existing style, and confirm `swift build` passes before opening one. Bug reports: please include your macOS version, Mac model and install method.

---

## License

[MIT](LICENSE) — use it, fork it, ship it, just keep the copyright notice.

---

*Not affiliated with, endorsed by, or sponsored by Apple Inc. “Dynamic Island” and macOS are trademarks of Apple Inc. AirIsland is an independent hobby project.*
