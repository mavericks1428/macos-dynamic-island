import QuartzCore
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Adaptive Surface Helpers

private extension ColorScheme {
    var moduleFill: Color {
        self == .dark ? Color.white.opacity(0.085) : Color.black.opacity(0.055)
    }

    var moduleStroke: Color {
        self == .dark ? Color.white.opacity(0.11) : Color.black.opacity(0.08)
    }

    var subtleTrack: Color {
        self == .dark ? Color.white.opacity(0.16) : Color.black.opacity(0.12)
    }

    var solidActionFill: Color {
        self == .dark ? Color.white : Color.primary
    }

    var solidActionText: Color {
        self == .dark ? Color.black : Color.white
    }
}

// MARK: - Now Playing Tab

struct NowPlayingTabView: View {
    @ObservedObject var state: IslandState
    @ObservedObject var media: MediaController
    @Environment(\.colorScheme) private var colorScheme
    @State private var isArtworkHovered: Bool = false
    @State private var isPlayHovered: Bool = false

    private var activeThemeAccent: Color {
        state.syncMusicTheme ? media.accentColor : Color.primary
    }

    var body: some View {
        if media.hasTrack {
            VStack(spacing: 12) {
                HStack(spacing: 14) {
                    Button {
                        media.openNowPlayingApp()
                    } label: {
                        ZStack(alignment: .bottomTrailing) {
                            artworkView
                            if isArtworkHovered {
                                Image(systemName: "arrow.up.forward.circle.fill")
                                    .font(.system(size: 16))
                                    .foregroundColor(.white)
                                    .background(Circle().fill(Color.black.opacity(0.55)))
                                    .padding(4)
                                    .transition(.opacity.combined(with: .scale(scale: 0.85)))
                            }
                        }
                        .scaleEffect(isArtworkHovered ? 1.035 : 1.0)
                        .animation(IslandMotion.hover(isArtworkHovered), value: isArtworkHovered)
                    }
                    .buttonStyle(SpringPressButtonStyle())
                    .onHover { hovering in
                        isArtworkHovered = hovering
                    }
                    .help("Switch to Player App")

                    VStack(alignment: .leading, spacing: 3.5) {
                        FluidTextSwap(
                            text: media.title,
                            font: .system(size: 14.5, weight: .semibold)
                        )
                        FluidTextSwap(
                            text: media.artist.isEmpty ? "Unknown Artist" : media.artist,
                            font: .system(size: 12, weight: .medium),
                            color: .secondary
                        )
                        if !media.album.isEmpty {
                            FluidTextSwap(
                                text: media.album,
                                font: .system(size: 10.5),
                                color: Color(NSColor.tertiaryLabelColor)
                            )
                            .transition(.opacity.combined(with: .offset(y: 3)))
                        }
                    }
                    // Fluid layout remap: the info stack (and the row beside it) interpolate, never snap.
                    // Title/artist text swaps self-animate inside FluidTextSwap; the album row
                    // appearing or disappearing re-flows the stack on the layout spring.
                    .animation(IslandMotion.resolved(IslandMotion.layout), value: media.album)

                    Spacer()

                    AudioWaveformView(
                        isPlaying: media.isPlaying,
                        color: media.accentColor,
                        secondaryColor: media.secondaryColor,
                        seed: media.title.hashValue
                    )
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(colorScheme.moduleFill)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(
                                    state.syncMusicTheme
                                        ? media.accentColor.opacity(0.28)
                                        : Color.white.opacity(colorScheme == .dark ? 0.14 : 0.45),
                                    lineWidth: 0.6
                                )
                        )
                )

                if media.duration > 0 {
                    NowPlayingProgressBar(
                        clock: media.clock,
                        accentColor: media.accentColor,
                        secondaryColor: media.secondaryColor,
                        syncMusicTheme: state.syncMusicTheme,
                        onSeek: { sec in media.seek(to: sec) }
                    )
                }

                HStack(spacing: 10) {
                    // Music Theme Sync toggle
                    Button {
                        withAnimation(IslandMotion.resolved(IslandMotion.theme)) {
                            state.syncMusicTheme.toggle()
                        }
                    } label: {
                        Image(systemName: "paintpalette.fill")
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundColor(state.syncMusicTheme ? media.accentColor : .secondary)
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(
                        AppleHoverCircleButtonStyle(
                            tint: state.syncMusicTheme ? media.accentColor : .primary,
                            baseFillOpacity: state.syncMusicTheme ? 0.20 : nil
                        )
                    )
                    .help(state.syncMusicTheme ? "Music Theme Sync: On" : "Music Theme Sync: Off")

                    // Spotify-style Synced Lyrics pill
                    Button {
                        state.setLyricsMode(true)
                    } label: {
                        HStack(spacing: 4.5) {
                            Image(systemName: "quote.bubble.fill")
                                .font(.system(size: 10.5, weight: .semibold))
                            Text("Lyrics")
                                .font(.system(size: 10.5, weight: .semibold))
                        }
                        .foregroundColor(media.hasSyncedLyrics ? media.accentColor : .primary)
                        .padding(.horizontal, 10)
                        .frame(height: 30)
                    }
                    .buttonStyle(
                        AppleControlPillButtonStyle(
                            fillColor: media.hasSyncedLyrics ? media.accentColor.opacity(0.18) : nil
                        )
                    )
                    .help("Synced Lyrics")

                    Spacer(minLength: 2)

                    Button {
                        media.previousTrack()
                    } label: {
                        Image(systemName: "backward.fill")
                            .font(.system(size: 13.5))
                            .foregroundColor(.primary)
                            .frame(width: 34, height: 32)
                    }
                    .buttonStyle(AppleHoverCircleButtonStyle())

                    Button {
                        media.togglePlayPause()
                    } label: {
                        Image(systemName: media.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 16.5))
                            .foregroundColor(colorScheme.solidActionText)
                            .frame(width: 48, height: 36)
                            .background(Capsule().fill(colorScheme.solidActionFill))
                            .contentShape(Capsule())
                            .shadow(color: activeThemeAccent.opacity(isPlayHovered ? 0.34 : 0.18), radius: isPlayHovered ? 5 : 3, x: 0, y: 1.5)
                            .scaleEffect(isPlayHovered ? 1.045 : 1.0)
                            .animation(IslandMotion.hover(isPlayHovered), value: isPlayHovered)
                    }
                    .buttonStyle(SpringPressButtonStyle())
                    .onHover { over in
                        isPlayHovered = over
                    }
                    .help(media.isPlaying ? "Pause" : "Play")

                    Button {
                        media.nextTrack()
                    } label: {
                        Image(systemName: "forward.fill")
                            .font(.system(size: 13.5))
                            .foregroundColor(.primary)
                            .frame(width: 34, height: 32)
                    }
                    .buttonStyle(AppleHoverCircleButtonStyle())

                    Spacer(minLength: 2)

                    Button {
                        media.openNowPlayingApp()
                    } label: {
                        Image(systemName: "arrow.up.forward.app")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.secondary)
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(AppleHoverCircleButtonStyle())
                    .help("Open Player App")
                }
            }
        } else {
            VStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(colorScheme.moduleFill)
                        .frame(width: 48, height: 48)
                    Image(systemName: "music.note")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(.secondary)
                }
                Text("Nothing Playing")
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundColor(.primary)
                Text("Start playback in Apple Music, Spotify, or your browser.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                Button {
                    media.togglePlayPause()
                } label: {
                    Label("Play / Resume", systemImage: "play.fill")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundColor(colorScheme.solidActionText)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 7)
                        .background(Capsule().fill(colorScheme.solidActionFill))
                }
                .buttonStyle(SpringPressButtonStyle())
            }
        }
    }

    @ViewBuilder
    private var artworkView: some View {
        if let art = media.artwork {
            Image(nsImage: art)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                .id(ObjectIdentifier(art))
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
                .animation(IslandMotion.fade, value: ObjectIdentifier(art))
                .overlay(
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .strokeBorder(Color.white.opacity(colorScheme == .dark ? 0.22 : 0.52), lineWidth: 0.7)
                )
                .shadow(color: media.accentColor.opacity(0.32), radius: 5, x: 0, y: 1.5)
        } else {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(
                    LinearGradient(
                        gradient: Gradient(colors: [media.accentColor.opacity(0.90), media.secondaryColor.opacity(0.65)]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 64, height: 64)
                .overlay(
                    Image(systemName: "music.note")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(.white)
                )
                .shadow(color: media.accentColor.opacity(0.30), radius: 5, x: 0, y: 1.5)
        }
    }
}

private struct NowPlayingProgressBar: View {
    @ObservedObject var clock: MediaController.PlaybackClock
    let accentColor: Color
    let secondaryColor: Color
    let syncMusicTheme: Bool
    let onSeek: (Double) -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var isScrubberHovered: Bool = false
    @State private var dragRatio: Double? = nil

    var body: some View {
        let safeDuration = clock.duration.isFinite && clock.duration > 0 ? clock.duration : 0
        let safeElapsed = clock.elapsedTime.isFinite ? max(0, clock.elapsedTime) : 0
        let duration = max(1, safeDuration)
        let rawRatio = dragRatio ?? max(0, min(1, safeElapsed / duration))
        let liveRatio = rawRatio.isFinite ? rawRatio : 0
        let displayedTime = dragRatio.map { $0 * safeDuration } ?? safeElapsed

        VStack(spacing: 4) {
            GeometryReader { geo in
                let isActive = isScrubberHovered || dragRatio != nil
                let barHeight: CGFloat = isActive ? 6 : 4
                let knobX = max(5, min(geo.size.width - 5, geo.size.width * CGFloat(liveRatio)))

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(colorScheme.subtleTrack)
                        .frame(height: barHeight)
                    Capsule()
                        .fill(
                            LinearGradient(
                                gradient: Gradient(colors: [accentColor, syncMusicTheme ? secondaryColor : accentColor.opacity(0.88)]),
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(barHeight, geo.size.width * CGFloat(liveRatio)), height: barHeight)
                        .shadow(color: accentColor.opacity(isActive ? 0.55 : 0.25), radius: isActive ? 4 : 2, x: 0, y: 0)

                    if isActive {
                        Circle()
                            .fill(Color.white)
                            .frame(width: 10, height: 10)
                            .shadow(color: Color.black.opacity(0.28), radius: 2, x: 0, y: 1)
                            .offset(x: knobX - 5)
                    }
                }
                .frame(maxHeight: .infinity, alignment: .center)
                .contentShape(Rectangle())
                .onHover { hovering in
                    withAnimation(IslandMotion.resolved(IslandMotion.quick)) {
                        isScrubberHovered = hovering
                    }
                }
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            dragRatio = Double(max(0, min(1, value.location.x / max(1, geo.size.width))))
                        }
                        .onEnded { value in
                            let pct = Double(max(0, min(1, value.location.x / max(1, geo.size.width))))
                            dragRatio = nil
                            onSeek(pct * safeDuration)
                        }
                )
            }
            .frame(height: 12)

            HStack {
                Text(formatTime(displayedTime))
                Spacer()
                Text(formatTime(safeDuration))
            }
            .font(.system(size: 10, design: .rounded).monospacedDigit())
            .foregroundColor(.secondary)
        }
    }

    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite else { return "0:00" }
        let total = max(0, Int(seconds))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

// MARK: - Apple-Grade Crisp Synced Lyrics Capsule

struct LyricsCapsuleView: View {
    @ObservedObject var state: IslandState
    @ObservedObject var media: MediaController
    @Environment(\.colorScheme) private var colorScheme
    @State private var isLyricsHovered: Bool = false

    private var visibleLines: [LyricLine] {
        media.lyricLines.filter { !$0.text.isEmpty }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Heading: Artwork + Song Title + Artist + Theme Sync + Back & Collapse
            HStack(spacing: 8) {
                Button {
                    media.openNowPlayingApp()
                } label: {
                    headerArtwork
                }
                .buttonStyle(SpringPressButtonStyle())
                .help("Open Player App")

                VStack(alignment: .leading, spacing: 1) {
                    Text(media.hasTrack ? media.title : "Lyrics")
                        .font(.system(size: 12.5, weight: .bold))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    if !media.artist.isEmpty {
                        Text(media.artist)
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 4)

                Button {
                    withAnimation(IslandMotion.resolved(IslandMotion.theme)) {
                        state.syncMusicTheme.toggle()
                    }
                } label: {
                    Image(systemName: "paintpalette.fill")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundColor(state.syncMusicTheme ? media.accentColor : .secondary)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(
                    AppleHoverCircleButtonStyle(
                        tint: state.syncMusicTheme ? media.accentColor : .primary,
                        baseFillOpacity: state.syncMusicTheme ? 0.20 : nil
                    )
                )
                .help(state.syncMusicTheme ? "Music Theme Sync: On" : "Music Theme Sync: Off")

                AudioWaveformView(
                    isPlaying: media.isPlaying,
                    color: media.accentColor,
                    secondaryColor: media.secondaryColor,
                    seed: media.title.hashValue
                )

                Button {
                    state.setLyricsMode(false)
                } label: {
                    HStack(spacing: 3.5) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 9.5, weight: .bold))
                        Text("Controls")
                            .font(.system(size: 10.5, weight: .semibold))
                    }
                    .foregroundColor(.primary)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4.5)
                }
                .buttonStyle(AppleControlPillButtonStyle())
                .help("Back to Music Controls")

                Button {
                    state.collapse()
                } label: {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.secondary)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(AppleHoverCircleButtonStyle())
                .help("Collapse (⌥ Space)")
            }
            .padding(.horizontal, 14)
            .padding(.top, 11)
            .padding(.bottom, 8)

            Rectangle()
                .fill(Color.primary.opacity(colorScheme == .dark ? 0.10 : 0.09))
                .frame(height: 0.5)

            // Synced Lyrics Body (isolated from clock ticks; zero offscreen masks for razor-sharp text)
            ZStack(alignment: .topTrailing) {
                lyricsBody
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal, 14)
                    // Fluid remap when we swap between placeholder / synced / plain lyrics
                    .animation(IslandMotion.resolved(IslandMotion.layout), value: media.hasTrack)
                    .animation(IslandMotion.resolved(IslandMotion.layout), value: media.isLyricsLoading)
                    .animation(IslandMotion.resolved(IslandMotion.layout), value: visibleLines.count)
                    .animation(IslandMotion.resolved(IslandMotion.layout), value: media.plainLyricsLines.count)

                if media.hasTrack && !visibleLines.isEmpty && (isLyricsHovered || abs(media.lyricSyncOffset) > 0.01) {
                    lyricSyncNudgePill
                        .padding(.top, 7)
                        .padding(.trailing, 14)
                        .transition(.opacity.combined(with: .scale(scale: 0.94, anchor: .topTrailing)))
                }
            }
            .onHover { over in
                withAnimation(IslandMotion.hover(over)) {
                    isLyricsHovered = over
                }
            }

            // Compact Bottom Controls + Live Scrubber
            if media.hasTrack {
                LyricsBottomControlsView(
                    clock: media.clock,
                    media: media,
                    accentColor: media.accentColor,
                    secondaryColor: media.secondaryColor,
                    syncMusicTheme: state.syncMusicTheme
                )
            }
        }
    }

    private var lyricSyncNudgePill: some View {
        HStack(spacing: 4) {
            Button {
                media.nudgeLyricSync(-0.25)
            } label: {
                Image(systemName: "minus")
                    .font(.system(size: 8.5, weight: .bold))
                    .foregroundColor(.primary)
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(AppleHoverCircleButtonStyle(baseFillOpacity: 0.08))
            .help("Delay Lyrics (-0.25s)")

            Button {
                media.resetLyricSync()
            } label: {
                Text(formattedSyncOffset)
                    .font(.system(size: 9.5, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundColor(abs(media.lyricSyncOffset) > 0.01 ? media.accentColor : .secondary)
                    .padding(.horizontal, 4)
                    .frame(height: 18)
            }
            .buttonStyle(AppleHoverPillButtonStyle(cornerRadius: 6))
            .help("Reset Lyrics Sync Offset")

            Button {
                media.nudgeLyricSync(0.25)
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 8.5, weight: .bold))
                    .foregroundColor(.primary)
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(AppleHoverCircleButtonStyle(baseFillOpacity: 0.08))
            .help("Advance Lyrics (+0.25s)")
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 3)
        .background(
            Capsule()
                .fill(colorScheme == .dark ? Color.black.opacity(0.45) : Color.white.opacity(0.75))
                .overlay(
                    Capsule()
                        .strokeBorder(Color.white.opacity(colorScheme == .dark ? 0.14 : 0.45), lineWidth: 0.5)
                )
        )
    }

    private var formattedSyncOffset: String {
        if abs(media.lyricSyncOffset) < 0.01 {
            return "Sync"
        }
        return String(format: "%+.2fs", media.lyricSyncOffset)
    }

    @ViewBuilder
    private var headerArtwork: some View {
        if let art = media.artwork {
            Image(nsImage: art)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 30, height: 30)
                .clipShape(RoundedRectangle(cornerRadius: 7.5, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 7.5, style: .continuous)
                        .strokeBorder(Color.white.opacity(colorScheme == .dark ? 0.20 : 0.50), lineWidth: 0.6)
                )
                .shadow(color: media.accentColor.opacity(0.24), radius: 3, x: 0, y: 1)
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 7.5, style: .continuous)
                    .fill(media.accentColor.opacity(0.24))
                Image(systemName: "music.note")
                    .font(.system(size: 12.5, weight: .bold))
                    .foregroundColor(media.accentColor)
            }
            .frame(width: 30, height: 30)
        }
    }

    @ViewBuilder
    private var lyricsBody: some View {
        if !media.hasTrack {
            VStack(spacing: 8) {
                Image(systemName: "music.mic")
                    .font(.system(size: 22))
                    .foregroundColor(.secondary)
                Text("Play a song to view synced lyrics")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .transition(.opacity.combined(with: .scale(scale: 0.97)))
        } else if media.isLyricsLoading && visibleLines.isEmpty && media.plainLyricsLines.isEmpty {
            VStack(spacing: 8) {
                ProgressView()
                    .scaleEffect(0.75)
                Text("Syncing lyrics…")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .transition(.opacity.combined(with: .scale(scale: 0.97)))
        } else if !visibleLines.isEmpty {
            AppleSyncedLyricsView(
                lines: visibleLines,
                activeIndex: media.activeLyricIndex,
                accentColor: media.accentColor,
                secondaryColor: media.secondaryColor,
                isDark: colorScheme == .dark,
                onSeek: { time in media.seek(to: time) }
            )
            .transition(.opacity.combined(with: .scale(scale: 0.985)))
        } else if !media.plainLyricsLines.isEmpty {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Unsynced Lyrics")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(media.accentColor)
                        .padding(.top, 8)
                    ForEach(Array(media.plainLyricsLines.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Color.clear.frame(height: 14)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            VStack(spacing: 8) {
                Image(systemName: "quote.bubble")
                    .font(.system(size: 20))
                    .foregroundColor(.secondary)
                Text(media.lyricsStatusMessage ?? "No synced lyrics available for this track.")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                Button {
                    media.ensureLyricsLoaded(forceRetry: true)
                } label: {
                    Text("Retry")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.primary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 5.5)
                }
                .buttonStyle(AppleControlPillButtonStyle())
            }
        }
    }
}

private struct LyricsBottomControlsView: View {
    @ObservedObject var clock: MediaController.PlaybackClock
    @ObservedObject var media: MediaController
    let accentColor: Color
    let secondaryColor: Color
    let syncMusicTheme: Bool
    @Environment(\.colorScheme) private var colorScheme
    @State private var isScrubberHovered: Bool = false
    @State private var dragRatio: Double? = nil
    @State private var isPlayHovered: Bool = false

    var body: some View {
        let safeDuration = clock.duration.isFinite && clock.duration > 0 ? clock.duration : 0
        let safeElapsed = clock.elapsedTime.isFinite ? max(0, clock.elapsedTime) : 0
        let duration = max(1, safeDuration)
        let rawRatio = dragRatio ?? max(0, min(1, safeElapsed / duration))
        let ratio = rawRatio.isFinite ? rawRatio : 0
        let displayedTime = dragRatio.map { $0 * safeDuration } ?? safeElapsed
        let scrubberActive = isScrubberHovered || dragRatio != nil

        VStack(spacing: 4) {
            if safeDuration > 0 {
                GeometryReader { geo in
                    let barH: CGFloat = scrubberActive ? 5 : 3
                    let knobX = max(4.5, min(geo.size.width - 4.5, geo.size.width * CGFloat(ratio)))
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(colorScheme.subtleTrack)
                            .frame(height: barH)
                        Capsule()
                            .fill(
                                LinearGradient(
                                    gradient: Gradient(colors: [accentColor, syncMusicTheme ? secondaryColor : accentColor.opacity(0.9)]),
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: max(barH, geo.size.width * CGFloat(ratio)), height: barH)
                            .shadow(color: accentColor.opacity(scrubberActive ? 0.55 : 0.30), radius: scrubberActive ? 3.5 : 2, x: 0, y: 0)

                        if scrubberActive {
                            Circle()
                                .fill(Color.white)
                                .frame(width: 9, height: 9)
                                .shadow(color: Color.black.opacity(0.28), radius: 2, x: 0, y: 1)
                                .offset(x: knobX - 4.5)
                        }
                    }
                    .frame(maxHeight: .infinity, alignment: .center)
                    .contentShape(Rectangle())
                    .onHover { over in
                        withAnimation(IslandMotion.resolved(IslandMotion.quick)) {
                            isScrubberHovered = over
                        }
                    }
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                dragRatio = Double(max(0, min(1, value.location.x / max(1, geo.size.width))))
                            }
                            .onEnded { value in
                                let pct = Double(max(0, min(1, value.location.x / max(1, geo.size.width))))
                                dragRatio = nil
                                media.seek(to: pct * safeDuration)
                            }
                    )
                }
                .frame(height: 10)
            }

            HStack(spacing: 16) {
                Text(formatTime(displayedTime))
                    .font(.system(size: 9.5, design: .rounded).monospacedDigit())
                    .foregroundColor(.secondary)
                    .frame(width: 34, alignment: .leading)

                Spacer()

                Button {
                    media.previousTrack()
                } label: {
                    Image(systemName: "backward.fill")
                        .font(.system(size: 11.5))
                        .foregroundColor(.primary)
                        .frame(width: 28, height: 26)
                }
                .buttonStyle(AppleHoverCircleButtonStyle(baseFillOpacity: 0.04))

                Button {
                    media.togglePlayPause()
                } label: {
                    Image(systemName: media.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 12.5))
                        .foregroundColor(colorScheme.solidActionText)
                        .frame(width: 40, height: 26)
                        .background(Capsule().fill(colorScheme.solidActionFill))
                        .contentShape(Capsule())
                        .scaleEffect(isPlayHovered ? 1.05 : 1.0)
                        .animation(IslandMotion.hover(isPlayHovered), value: isPlayHovered)
                }
                .buttonStyle(SpringPressButtonStyle())
                .onHover { over in
                    isPlayHovered = over
                }
                .help(media.isPlaying ? "Pause" : "Play")

                Button {
                    media.nextTrack()
                } label: {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 11.5))
                        .foregroundColor(.primary)
                        .frame(width: 28, height: 26)
                }
                .buttonStyle(AppleHoverCircleButtonStyle(baseFillOpacity: 0.04))

                Spacer()

                Text(safeDuration > 0 ? formatTime(safeDuration) : "--:--")
                    .font(.system(size: 9.5, design: .rounded).monospacedDigit())
                    .foregroundColor(.secondary)
                    .frame(width: 34, alignment: .trailing)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 4)
        .padding(.bottom, 10)
    }

    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite else { return "0:00" }
        let total = max(0, Int(seconds))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

private struct AppleSyncedLyricsView: NSViewRepresentable {
    let lines: [LyricLine]
    let activeIndex: Int?
    let accentColor: Color
    let secondaryColor: Color
    let isDark: Bool
    let onSeek: (Double) -> Void

    func makeNSView(context: Context) -> AppleLyricsScrollContainer {
        let view = AppleLyricsScrollContainer()
        view.onSeek = onSeek
        view.apply(
            lines: lines,
            activeIndex: activeIndex,
            accent: NSColor(accentColor),
            secondary: NSColor(secondaryColor),
            isDark: isDark
        )
        return view
    }

    func updateNSView(_ nsView: AppleLyricsScrollContainer, context: Context) {
        nsView.onSeek = onSeek
        nsView.apply(
            lines: lines,
            activeIndex: activeIndex,
            accent: NSColor(accentColor),
            secondary: NSColor(secondaryColor),
            isDark: isDark
        )
    }
}

private final class FlippedLyricsDocumentView: NSView {
    override var isFlipped: Bool { true }
    override var allowsVibrancy: Bool { false }
}

private final class LyricsTrackingScrollView: NSScrollView {
    var onUserScroll: (() -> Void)?

    override func scrollWheel(with event: NSEvent) {
        if abs(event.scrollingDeltaY) >= abs(event.scrollingDeltaX), abs(event.scrollingDeltaY) > 0.05 {
            onUserScroll?()
        }
        super.scrollWheel(with: event)
    }
}

/// Layer-backed vector text renderer locked to `window.backingScaleFactor` with forced
/// crisp antialiasing (`-webkit-font-smoothing: antialiased` equivalent) and zero bitmap scaling.
private final class CrispVectorLyricTextView: NSView {
    var text: String = "" {
        didSet {
            if oldValue != text { needsDisplay = true }
        }
    }
    var font: NSFont = NSFont.systemFont(ofSize: 14.0, weight: .semibold) {
        didSet {
            if oldValue != font { needsDisplay = true }
        }
    }
    var textColor: NSColor = NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 1) {
        didSet {
            if oldValue != textColor { needsDisplay = true }
        }
    }

    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }
    override var allowsVibrancy: Bool { false }
    // Ensure AppKit always executes draw(_:) rather than internal private layer updates
    override var wantsUpdateLayer: Bool { false }

    override func hitTest(_ point: NSPoint) -> NSView? {
        return nil
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        syncBackingScale()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        syncBackingScale()
    }

    override func setFrameSize(_ newSize: NSSize) {
        let changed = abs(bounds.width - newSize.width) > 0.25 || abs(bounds.height - newSize.height) > 0.25
        super.setFrameSize(newSize)
        if changed {
            needsDisplay = true
        }
    }

    func syncBackingScale() {
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 1.0
        if layer?.contentsScale != scale {
            layer?.contentsScale = scale
            needsDisplay = true
        }
    }

    func measureSize(maxWidth: CGFloat, font targetFont: NSFont) -> CGSize {
        let attr = makeAttributedString(font: targetFont, color: textColor)
        let rect = attr.boundingRect(
            with: NSSize(width: maxWidth, height: 2000),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
        return CGSize(
            width: ceil(min(maxWidth, max(24, rect.width + 6))),
            height: ceil(max(20, rect.height + 4))
        )
    }

    private func makeAttributedString(font targetFont: NSFont, color targetColor: NSColor) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .left
        paragraph.lineBreakMode = .byWordWrapping
        return NSAttributedString(
            string: text,
            attributes: [
                .font: targetFont,
                .foregroundColor: targetColor,
                .paragraphStyle: paragraph
            ]
        )
    }

    override func draw(_ dirtyRect: NSRect) {
        guard !text.isEmpty else { return }
        let attr = makeAttributedString(font: font, color: textColor)
        let drawRect = NSRect(x: 0, y: 2, width: bounds.width, height: max(1, bounds.height - 2))
        if let ctx = NSGraphicsContext.current?.cgContext {
            ctx.saveGState()
            ctx.setAllowsAntialiasing(true)
            ctx.setShouldAntialias(true)
            ctx.setAllowsFontSubpixelPositioning(true)
            ctx.setShouldSubpixelPositionFonts(true)
            ctx.setAllowsFontSubpixelQuantization(true)
            ctx.setShouldSubpixelQuantizeFonts(true)
            // Native equivalent of `-webkit-font-smoothing: antialiased`: sharp un-dilated glyphs on dark glass
            ctx.setAllowsFontSmoothing(true)
            ctx.setShouldSmoothFonts(false)
            attr.draw(with: drawRect, options: [.usesLineFragmentOrigin, .usesFontLeading])
            ctx.restoreGState()
        } else {
            attr.draw(with: drawRect, options: [.usesLineFragmentOrigin, .usesFontLeading])
        }
    }
}

private final class AppleLyricRowView: NSView {
    let line: LyricLine
    var onClick: (() -> Void)?

    private let highlightLayer = CALayer()
    private let accentBarLayer = CAGradientLayer()
    private let textView = CrispVectorLyricTextView(frame: .zero)

    private var trackingArea: NSTrackingArea?
    private var mouseDownScreenPoint: NSPoint? = nil

    private let activeFontSize: CGFloat = 18.5
    private let inactiveFontSize: CGFloat = 14.0

    private var cachedWidth: CGFloat = 0
    private(set) var currentRowHeight: CGFloat = 32
    private var cachedIsDark: Bool = true

    private(set) var isActive: Bool = false
    private(set) var isPast: Bool = false
    private var isHovered: Bool = false

    private(set) var visualProgress: CGFloat = 0.0
    private var startProgress: CGFloat = 0.0
    private var targetProgress: CGFloat = 0.0

    var isTransitioning: Bool {
        abs(visualProgress - targetProgress) > 0.001
    }

    override var isFlipped: Bool { true }
    override var allowsVibrancy: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    init(line: LyricLine, isDark: Bool, accent: NSColor, secondary: NSColor) {
        self.line = line
        self.cachedIsDark = isDark
        super.init(frame: .zero)

        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
        layer?.masksToBounds = false

        let accentCG = (accent.usingColorSpace(.sRGB) ?? accent).cgColor
        let secondaryCG = (secondary.usingColorSpace(.sRGB) ?? secondary).cgColor

        highlightLayer.anchorPoint = CGPoint(x: 0, y: 0)
        highlightLayer.cornerRadius = 10
        if #available(macOS 10.15, *) {
            highlightLayer.cornerCurve = .continuous
        }
        highlightLayer.backgroundColor = (isDark ? NSColor.white : NSColor.black)
            .withAlphaComponent(isDark ? 0.09 : 0.06)
            .cgColor
        highlightLayer.opacity = 0
        layer?.addSublayer(highlightLayer)

        accentBarLayer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        accentBarLayer.cornerRadius = 1.5
        accentBarLayer.startPoint = CGPoint(x: 0.5, y: 0.0)
        accentBarLayer.endPoint = CGPoint(x: 0.5, y: 1.0)
        accentBarLayer.colors = [accentCG, secondaryCG]
        accentBarLayer.shadowOpacity = 0
        accentBarLayer.opacity = 0
        layer?.addSublayer(accentBarLayer)

        textView.text = line.text
        textView.alphaValue = 1.0
        textView.syncBackingScale()
        addSubview(textView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        refreshBackingScale()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        refreshBackingScale()
    }

    func refreshBackingScale() {
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 1.0
        layer?.contentsScale = scale
        highlightLayer.contentsScale = scale
        accentBarLayer.contentsScale = scale
        textView.syncBackingScale()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        refreshHoverVisual()
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        refreshHoverVisual()
    }

    override func mouseDown(with event: NSEvent) {
        mouseDownScreenPoint = NSEvent.mouseLocation
    }

    override func mouseUp(with event: NSEvent) {
        let upPoint = NSEvent.mouseLocation
        defer { mouseDownScreenPoint = nil }
        if let down = mouseDownScreenPoint {
            let dist = hypot(upPoint.x - down.x, upPoint.y - down.y)
            if dist <= 5.0 {
                let local = convert(event.locationInWindow, from: nil)
                if bounds.contains(local) {
                    onClick?()
                }
            }
        }
    }

    func updateAppearance(isDark: Bool, accent: NSColor, secondary: NSColor) {
        cachedIsDark = isDark
        refreshBackingScale()

        let accentCG = (accent.usingColorSpace(.sRGB) ?? accent).cgColor
        let secondaryCG = (secondary.usingColorSpace(.sRGB) ?? secondary).cgColor

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        accentBarLayer.colors = [accentCG, secondaryCG]
        highlightLayer.backgroundColor = (isDark ? NSColor.white : NSColor.black)
            .withAlphaComponent(isDark ? 0.09 : 0.06)
            .cgColor
        CATransaction.commit()

        textView.textColor = resolvedInkColor(progress: visualProgress)
    }

    func configureWidth(_ width: CGFloat, isDark: Bool) -> CGFloat {
        cachedWidth = width
        cachedIsDark = isDark
        refreshBackingScale()
        return layoutAtProgress(visualProgress)
    }

    func beginTransition(isActive: Bool, isPast: Bool, animated: Bool) {
        let pastChanged = (self.isPast != isPast)
        self.isActive = isActive
        self.isPast = isPast
        let newTarget: CGFloat = isActive ? 1.0 : 0.0
        startProgress = visualProgress
        targetProgress = newTarget
        if !animated {
            visualProgress = newTarget
            _ = layoutAtProgress(visualProgress)
        } else if pastChanged && !isTransitioning {
            textView.textColor = resolvedInkColor(progress: visualProgress)
        }
    }

    /// Returns true if row height changed during this animation step
    func stepTransition(easedT: CGFloat) -> Bool {
        let prevHeight = currentRowHeight
        let next = easedT >= 1.0 ? targetProgress : (startProgress + (targetProgress - startProgress) * easedT)
        visualProgress = max(0.0, min(1.0, next))
        let newHeight = layoutAtProgress(visualProgress)
        return abs(newHeight - prevHeight) > 0.25
    }

    private func refreshHoverVisual() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let baseH: Float = Float(visualProgress)
        highlightLayer.opacity = isHovered ? max(0.72, baseH) : baseH
        CATransaction.commit()
        textView.textColor = resolvedInkColor(progress: visualProgress)
    }

    @discardableResult
    private func layoutAtProgress(_ p: CGFloat) -> CGFloat {
        guard cachedWidth > 20 else { return currentRowHeight }
        let clamped = max(0.0, min(1.0, p))
        let rawSize = inactiveFontSize + (activeFontSize - inactiveFontSize) * clamped
        let snappedSize = round(rawSize * 2.0) / 2.0
        let weight: NSFont.Weight = clamped >= 0.42 ? .bold : .semibold
        let font = NSFont.systemFont(ofSize: snappedSize, weight: weight)

        let leftX = round(14.0 + 5.0 * clamped)
        let maxTextW = max(120, cachedWidth - leftX - 14.0)
        let measured = textView.measureSize(maxWidth: maxTextW, font: font)
        let rowH = ceil(measured.height + 8.0 + 4.0 * clamped)
        currentRowHeight = rowH

        let textY = round((rowH - measured.height) * 0.5)

        textView.font = font
        textView.textColor = resolvedInkColor(progress: clamped)
        textView.frame = NSRect(x: leftX, y: textY, width: measured.width, height: measured.height)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        highlightLayer.bounds = CGRect(x: 0, y: 0, width: cachedWidth, height: rowH)
        highlightLayer.position = CGPoint(x: 0, y: 0)
        highlightLayer.opacity = isHovered ? max(0.72, Float(clamped)) : Float(clamped)

        let barH = max(14, round(measured.height - 2))
        accentBarLayer.bounds = CGRect(x: 0, y: 0, width: 3.0, height: barH)
        accentBarLayer.position = CGPoint(x: 7.0, y: round(rowH * 0.5))
        accentBarLayer.opacity = Float(clamped)
        accentBarLayer.transform = CATransform3DMakeScale(1.0, 0.35 + 0.65 * clamped, 1.0)
        CATransaction.commit()

        return rowH
    }

    private func resolvedInkColor(progress p: CGFloat) -> NSColor {
        let clamped = max(0.0, min(1.0, p))
        let effectiveP = isHovered ? max(0.92, clamped) : clamped

        let inactiveRGB: (CGFloat, CGFloat, CGFloat)
        let activeRGB: (CGFloat, CGFloat, CGFloat)

        if cachedIsDark {
            inactiveRGB = isPast ? (0.56, 0.59, 0.66) : (0.84, 0.87, 0.92)
            activeRGB = (1.0, 1.0, 1.0)
        } else {
            inactiveRGB = isPast ? (0.44, 0.46, 0.52) : (0.20, 0.22, 0.26)
            activeRGB = (0.04, 0.04, 0.06)
        }

        let r = inactiveRGB.0 + (activeRGB.0 - inactiveRGB.0) * effectiveP
        let g = inactiveRGB.1 + (activeRGB.1 - inactiveRGB.1) * effectiveP
        let b = inactiveRGB.2 + (activeRGB.2 - inactiveRGB.2) * effectiveP
        return NSColor(srgbRed: r, green: g, blue: b, alpha: 1.0)
    }
}

private final class AppleLyricsScrollContainer: NSView {
    var onSeek: ((Double) -> Void)?

    private let scrollView = LyricsTrackingScrollView()
    private let documentView = FlippedLyricsDocumentView()

    private var currentLines: [LyricLine] = []
    private var currentActiveIndex: Int? = nil
    private var lastFocusedID: Int? = nil
    private var currentIsDark: Bool = true
    private var currentAccent: NSColor = .systemBlue
    private var currentSecondary: NSColor = .systemPurple

    private var rowViews: [AppleLyricRowView] = []
    private var rowViewsByID: [Int: AppleLyricRowView] = [:]
    private var lastLayoutWidth: CGFloat = 0
    private var lastLayoutHeight: CGFloat = 0
    private var hasInitialScrollPositioned: Bool = false
    private var isUserPeeking: Bool = false
    private var peekResetWorkItem: DispatchWorkItem?

    // Unified 60fps driver for crisp vector font-size growth/shrink + centered scroll (0% CPU when idle)
    private var transitionTimer: Timer?
    private var transitionStartTime: CFTimeInterval = 0
    private let transitionDuration: CFTimeInterval = 0.34
    private var scrollStartY: CGFloat = 0
    private var scrollAnimating: Bool = false

    private let topPadding: CGFloat = 88
    private let bottomPadding: CGFloat = 128
    private let rowSpacing: CGFloat = 6

    override var isFlipped: Bool { true }
    override var allowsVibrancy: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
        layer?.masksToBounds = true

        // Zero layer.mask offscreen FBO — preserves full native vector clarity on 1x & Retina
        scrollView.frame = bounds
        scrollView.autoresizingMask = [.width, .height]
        scrollView.drawsBackground = false
        scrollView.backgroundColor = .clear
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.contentInsets = NSEdgeInsetsZero
        scrollView.verticalScrollElasticity = .allowed
        scrollView.wantsLayer = true
        scrollView.contentView.wantsLayer = true
        scrollView.contentView.drawsBackground = false
        documentView.wantsLayer = true
        scrollView.documentView = documentView

        scrollView.onUserScroll = { [weak self] in
            self?.handleUserScrollPeek()
        }

        addSubview(scrollView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        transitionTimer?.invalidate()
        peekResetWorkItem?.cancel()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        applyWindowBackingScale()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        applyWindowBackingScale()
    }

    private func applyWindowBackingScale() {
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 1.0
        layer?.contentsScale = scale
        scrollView.layer?.contentsScale = scale
        scrollView.contentView.layer?.contentsScale = scale
        documentView.layer?.contentsScale = scale
        for row in rowViews {
            row.refreshBackingScale()
        }
    }

    override func layout() {
        super.layout()
        guard bounds.width > 20, bounds.height > 20 else { return }
        if abs(bounds.width - lastLayoutWidth) > 0.5 {
            lastLayoutHeight = bounds.height
            relayoutAllRows(width: bounds.width)
            if !hasInitialScrollPositioned {
                snapScrollToActiveRow()
                hasInitialScrollPositioned = true
            } else if !isUserPeeking {
                snapScrollToActiveRow()
            }
        } else if !hasInitialScrollPositioned, !rowViews.isEmpty {
            lastLayoutHeight = bounds.height
            snapScrollToActiveRow()
            hasInitialScrollPositioned = true
        } else if abs(bounds.height - lastLayoutHeight) > 0.5, !rowViews.isEmpty {
            lastLayoutHeight = bounds.height
            if !isUserPeeking && !scrollAnimating {
                snapScrollToActiveRow()
            }
        }
    }

    func apply(lines: [LyricLine], activeIndex: Int?, accent: NSColor, secondary: NSColor, isDark: Bool) {
        let linesChanged = lines != currentLines
        let activeChanged = activeIndex != currentActiveIndex
        let colorsChanged = (isDark != currentIsDark) || (accent != currentAccent) || (secondary != currentSecondary)

        currentIsDark = isDark
        currentAccent = accent
        currentSecondary = secondary

        if linesChanged {
            transitionTimer?.invalidate()
            transitionTimer = nil
            scrollAnimating = false
            currentLines = lines
            currentActiveIndex = activeIndex
            lastFocusedID = activeIndex ?? lines.first?.id
            isUserPeeking = false
            hasInitialScrollPositioned = false
            peekResetWorkItem?.cancel()
            rebuildRows()

            if bounds.width > 20, bounds.height > 20 {
                relayoutAllRows(width: bounds.width)
                snapScrollToActiveRow()
                hasInitialScrollPositioned = true
            }
            return
        }

        if colorsChanged {
            for row in rowViews {
                row.updateAppearance(isDark: isDark, accent: accent, secondary: secondary)
            }
        }

        if activeChanged {
            currentActiveIndex = activeIndex
            if let id = activeIndex {
                lastFocusedID = id
            }
            isUserPeeking = false
            peekResetWorkItem?.cancel()
            startActiveTransition()
        }
    }

    private func rebuildRows() {
        for row in rowViews {
            row.removeFromSuperview()
        }
        rowViews.removeAll(keepingCapacity: true)
        rowViewsByID.removeAll(keepingCapacity: true)

        for line in currentLines {
            let row = AppleLyricRowView(
                line: line,
                isDark: currentIsDark,
                accent: currentAccent,
                secondary: currentSecondary
            )
            row.onClick = { [weak self] in
                guard let self = self else { return }
                self.isUserPeeking = false
                self.peekResetWorkItem?.cancel()
                self.onSeek?(line.time)
            }
            documentView.addSubview(row)
            rowViews.append(row)
            rowViewsByID[line.id] = row
        }
        applyWindowBackingScale()
    }

    private func relayoutAllRows(width: CGFloat) {
        lastLayoutWidth = width
        applyWindowBackingScale()

        let effectiveID = currentActiveIndex ?? lastFocusedID
        for row in rowViews {
            let active = (row.line.id == currentActiveIndex)
            let past = effectiveID.map { row.line.id < $0 } ?? false
            _ = row.configureWidth(width, isDark: currentIsDark)
            row.beginTransition(isActive: active, isPast: past, animated: false)
        }
        recomputeRowYPositions(width: width)
    }

    private func recomputeRowYPositions(width: CGFloat) {
        var y = topPadding
        for row in rowViews {
            let h = row.currentRowHeight
            row.frame = NSRect(x: 0, y: y, width: width, height: h)
            y += h + rowSpacing
        }
        documentView.frame = NSRect(x: 0, y: 0, width: width, height: max(bounds.height, y + bottomPadding))
    }

    private func startActiveTransition() {
        let effectiveID = currentActiveIndex ?? lastFocusedID
        for row in rowViews {
            let active = (row.line.id == currentActiveIndex)
            let past = effectiveID.map { row.line.id < $0 } ?? false
            row.beginTransition(isActive: active, isPast: past, animated: true)
        }

        scrollStartY = scrollView.contentView.bounds.origin.y
        scrollAnimating = true
        transitionStartTime = CACurrentMediaTime()

        if transitionTimer == nil {
            let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
                self?.tickTransition()
            }
            RunLoop.main.add(timer, forMode: .common)
            transitionTimer = timer
        }
        tickTransition()
    }

    /// Critically damped spring easing curve: 0 -> 1 with a soft, organic settle.
    private static func springEase(_ t: Double) -> Double {
        let clamped = max(0.0, min(1.0, t))
        if clamped >= 1.0 { return 1.0 }
        let omega: Double = 9.2    // angular frequency (≈0.34s visual response)
        let zeta: Double = 0.92    // damping ratio (a whisper of overshoot)
        let wd = omega * sqrt(max(0.0, 1.0 - zeta * zeta))
        let value = 1.0 - exp(-zeta * omega * clamped) * (cos(wd * clamped) + (zeta * omega / wd) * sin(wd * clamped))
        return max(0.0, min(1.12, value))
    }

    private func tickTransition() {
        let elapsed = CACurrentMediaTime() - transitionStartTime
        let rawT = max(0.0, min(1.0, elapsed / transitionDuration))
        // Critically damped spring easing (matches the SwiftUI spring vocabulary above)
        let eased = CGFloat(Self.springEase(rawT))

        var anyHeightChanged = false
        for row in rowViews where row.isTransitioning {
            if row.stepTransition(easedT: eased) {
                anyHeightChanged = true
            }
        }

        if anyHeightChanged, lastLayoutWidth > 20 {
            recomputeRowYPositions(width: lastLayoutWidth)
        }

        if scrollAnimating, !isUserPeeking, let targetY = targetCenterScrollY() {
            let currentY = round(scrollStartY + (targetY - scrollStartY) * eased)
            let clipView = scrollView.contentView
            clipView.setBoundsOrigin(NSPoint(x: 0, y: currentY))
            scrollView.reflectScrolledClipView(clipView)
        }

        if rawT >= 1.0 {
            transitionTimer?.invalidate()
            transitionTimer = nil
            scrollAnimating = false
        }
    }

    private func targetCenterScrollY() -> CGFloat? {
        guard let targetID = currentActiveIndex ?? lastFocusedID ?? currentLines.first?.id,
              let targetRow = rowViewsByID[targetID] else {
            return nil
        }
        let viewHeight = scrollView.contentView.bounds.height
        guard viewHeight > 10 else { return nil }
        let maxOriginY = max(0, documentView.frame.height - viewHeight)
        let rawOriginY = round(targetRow.frame.midY - viewHeight * 0.45)
        return max(0, min(maxOriginY, rawOriginY))
    }

    private func snapScrollToActiveRow() {
        guard let targetY = targetCenterScrollY() else { return }
        let clipView = scrollView.contentView
        clipView.setBoundsOrigin(NSPoint(x: 0, y: targetY))
        scrollView.reflectScrolledClipView(clipView)
    }

    private func handleUserScrollPeek() {
        isUserPeeking = true
        scrollAnimating = false
        peekResetWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            self.isUserPeeking = false
            self.scrollStartY = self.scrollView.contentView.bounds.origin.y
            self.scrollAnimating = true
            self.transitionStartTime = CACurrentMediaTime()
            if self.transitionTimer == nil {
                let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
                    self?.tickTransition()
                }
                RunLoop.main.add(timer, forMode: .common)
                self.transitionTimer = timer
            }
            self.tickTransition()
        }
        peekResetWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2, execute: work)
    }
}

// MARK: - Timer & Pomodoro Tab

struct TimerTabView: View {
    @ObservedObject var timer: TimerController
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .stroke(colorScheme.subtleTrack, lineWidth: 7.5)
                Circle()
                    .trim(from: 0, to: CGFloat(timer.progress))
                    .stroke(Color.orange, style: StrokeStyle(lineWidth: 7.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .shadow(color: Color.orange.opacity(timer.isRunning ? 0.38 : 0), radius: 5)
                    .animation(IslandMotion.progress, value: timer.progress)

                VStack(spacing: 2) {
                    Text(timer.formattedRemaining)
                        .font(.system(size: 21, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundColor(.primary)
                    Text(timer.label)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.orange)
                }
            }
            .frame(width: 110, height: 110)

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    presetButton(title: "Focus 25m", mins: 25, name: "Focus")
                    presetButton(title: "Break 5m", mins: 5, name: "Break")
                    presetButton(title: "15m", mins: 15, name: "Sprint")
                    presetButton(title: "1m", mins: 1, name: "Quick")
                }

                HStack(spacing: 8) {
                    Button {
                        timer.adjustMinutes(-1)
                    } label: {
                        Text("-1m")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(timer.isRunning ? Color(NSColor.tertiaryLabelColor) : .primary)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 5.5)
                    }
                    .buttonStyle(AppleControlPillButtonStyle())
                    .disabled(timer.isRunning)

                    Button {
                        timer.adjustMinutes(1)
                    } label: {
                        Text("+1m")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(timer.isRunning ? Color(NSColor.tertiaryLabelColor) : .primary)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 5.5)
                    }
                    .buttonStyle(AppleControlPillButtonStyle())
                    .disabled(timer.isRunning)

                    Spacer()
                }

                HStack(spacing: 8) {
                    Button {
                        timer.toggle()
                    } label: {
                        Label(
                            timer.isRunning ? "Pause" : "Start",
                            systemImage: timer.isRunning ? "pause.fill" : "play.fill"
                        )
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 7)
                        .background(Capsule().fill(Color.orange))
                    }
                    .buttonStyle(SpringPressButtonStyle())

                    Button {
                        timer.reset()
                    } label: {
                        Text("Reset")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.primary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                    }
                    .buttonStyle(AppleControlPillButtonStyle())
                }
            }
        }
    }

    private func presetButton(title: String, mins: Int, name: String) -> some View {
        let active = timer.totalSeconds == mins * 60 && timer.label == name
        return Button {
            timer.selectPreset(minutes: mins, title: name)
        } label: {
            Text(title)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundColor(active ? colorScheme.solidActionText : .primary)
                .padding(.horizontal, 9)
                .padding(.vertical, 5.5)
        }
        .buttonStyle(
            AppleControlPillButtonStyle(
                fillColor: active ? colorScheme.solidActionFill : nil
            )
        )
    }
}

// MARK: - Shelf & Clipboard Tab

struct ShelfAndClipboardTabView: View {
    @ObservedObject var store: ShelfAndClipboardStore
    @Environment(\.colorScheme) private var colorScheme
    @Namespace private var segmentNamespace
    @State private var mode: Int = 0
    @State private var copiedID: UUID? = nil
    @State private var hoveredFileID: UUID? = nil

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                HStack(spacing: 3) {
                    segmentButton("Files (\(store.files.count))", index: 0)
                    segmentButton("Clipboard (\(store.clipboardHistory.count))", index: 1)
                }
                .padding(2.5)
                .background(Capsule().fill(colorScheme.moduleFill))

                Spacer()

                if mode == 0 && !store.files.isEmpty {
                    Button("Clear") {
                        store.clearFiles()
                    }
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3.5)
                    .buttonStyle(AppleHoverPillButtonStyle(cornerRadius: 8))
                } else if mode == 1 && !store.clipboardHistory.isEmpty {
                    Button("Clear") {
                        store.clearClipboard()
                    }
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3.5)
                    .buttonStyle(AppleHoverPillButtonStyle(cornerRadius: 8))
                }
            }

            if mode == 0 {
                fileShelfView
                    .transition(.opacity.combined(with: .scale(scale: 0.985, anchor: .top)))
            } else {
                clipboardView
                    .transition(.opacity.combined(with: .scale(scale: 0.985, anchor: .top)))
            }
        }
    }

    private func segmentButton(_ title: String, index: Int) -> some View {
        let isActive = mode == index
        return Button {
            withAnimation(IslandMotion.resolved(IslandMotion.quick)) {
                mode = index
            }
        } label: {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(isActive ? .primary : .secondary)
                .padding(.horizontal, 11)
                .padding(.vertical, 4.5)
                .background(
                    ZStack {
                        if isActive {
                            Capsule()
                                .fill(Color.primary.opacity(colorScheme == .dark ? 0.16 : 0.11))
                                .matchedGeometryEffect(id: "shelfSegment", in: segmentNamespace)
                        }
                    }
                )
        }
        .buttonStyle(SpringPressButtonStyle())
    }

    @ViewBuilder
    private var fileShelfView: some View {
        if store.files.isEmpty {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                .foregroundColor(Color.primary.opacity(0.20))
                .overlay(
                    VStack(spacing: 5) {
                        Image(systemName: "tray.and.arrow.down.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.secondary)
                        Text("Drop files onto the pill to stash them here")
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundColor(.primary)
                        Text("Drag out anytime, reveal in Finder, or AirDrop")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                )
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 6) {
                    ForEach(store.files) { item in
                        let isRowHover = hoveredFileID == item.id
                        HStack(spacing: 8) {
                            Image(nsImage: item.icon)
                                .resizable()
                                .frame(width: 22, height: 22)
                            Text(item.name)
                                .font(.system(size: 11.5, weight: .medium))
                                .foregroundColor(.primary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            Button {
                                store.airDropFile(item)
                            } label: {
                                Image(systemName: "paperplane.fill")
                                    .font(.system(size: 10.5))
                                    .foregroundColor(.accentColor)
                                    .frame(width: 22, height: 22)
                            }
                            .buttonStyle(AppleHoverCircleButtonStyle(tint: .accentColor, baseFillOpacity: 0.12))
                            .help("AirDrop")

                            Button {
                                store.revealInFinder(item)
                            } label: {
                                Image(systemName: "folder")
                                    .font(.system(size: 10.5))
                                    .foregroundColor(.secondary)
                                    .frame(width: 22, height: 22)
                            }
                            .buttonStyle(AppleHoverCircleButtonStyle(baseFillOpacity: 0.06))
                            .help("Reveal in Finder")

                            Button {
                                store.removeFile(item)
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 9.5, weight: .bold))
                                    .foregroundColor(.secondary)
                                    .frame(width: 20, height: 20)
                            }
                            .buttonStyle(AppleHoverCircleButtonStyle(baseFillOpacity: 0.04))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6.5)
                        .background(
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .fill(isRowHover ? Color.primary.opacity(colorScheme == .dark ? 0.12 : 0.08) : colorScheme.moduleFill)
                        )
                        .onHover { over in
                            withAnimation(IslandMotion.hover(over)) {
                                hoveredFileID = over ? item.id : (hoveredFileID == item.id ? nil : hoveredFileID)
                            }
                        }
                        .onTapGesture(count: 2) {
                            store.openFile(item)
                        }
                        .onDrag {
                            NSItemProvider(object: item.url as NSURL)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var clipboardView: some View {
        if store.clipboardHistory.isEmpty {
            VStack(spacing: 6) {
                Image(systemName: "doc.on.clipboard")
                    .font(.system(size: 20))
                    .foregroundColor(.secondary)
                Text("Clipboard history is empty")
                    .font(.system(size: 11.5))
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 5) {
                    ForEach(store.clipboardHistory) { entry in
                        Button {
                            store.copyToPasteboard(entry)
                            copiedID = entry.id
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                                if copiedID == entry.id { copiedID = nil }
                            }
                        } label: {
                            HStack(spacing: 8) {
                                Text(entry.text.replacingOccurrences(of: "\n", with: " "))
                                    .font(.system(size: 11.5))
                                    .foregroundColor(.primary)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                Spacer()
                                if copiedID == entry.id {
                                    Text("Copied")
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundColor(.green)
                                        .transition(.opacity.combined(with: .scale(scale: 0.9)))
                                } else {
                                    Image(systemName: "doc.on.doc")
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)
                                        .transition(.opacity.combined(with: .scale(scale: 0.9)))
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(colorScheme.moduleFill)
                            )
                            // Fluid remap: the "Copied" confirmation glides in beside the text
                            .animation(IslandMotion.resolved(IslandMotion.quick), value: copiedID)
                        }
                        .buttonStyle(AppleHoverPillButtonStyle(cornerRadius: 10))
                    }
                }
            }
        }
    }
}

// MARK: - System Stats Tab

struct SystemTabView: View {
    @ObservedObject var stats: SystemStatsMonitor
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 10) {
            let memFraction = stats.memoryTotalGB > 0 ? min(1.0, stats.memoryUsedGB / stats.memoryTotalGB) : 0
            let cpuFraction = min(1.0, Double(stats.cpuUsagePercent) / 100.0)
            let batFraction = stats.hasBattery ? min(1.0, Double(stats.batteryPercent) / 100.0) : 1.0

            StatModuleCard(
                icon: "cpu",
                title: "CPU Load",
                value: "\(stats.cpuUsagePercent)%",
                subtitle: "\(ProcessInfo.processInfo.activeProcessorCount) threads",
                progress: cpuFraction,
                accent: stats.cpuUsagePercent > 75 ? .red : .blue
            )

            StatModuleCard(
                icon: "memorychip",
                title: "Memory",
                value: String(format: "%.1f GB", stats.memoryUsedGB),
                subtitle: String(format: "of %.0f GB RAM", stats.memoryTotalGB),
                progress: memFraction,
                accent: .purple
            )

            StatModuleCard(
                icon: stats.isCharging ? "bolt.fill" : "battery.100",
                title: "Battery",
                value: stats.hasBattery ? "\(stats.batteryPercent)%" : "AC",
                subtitle: stats.isCharging ? "Charging" : (stats.isOnACPower ? "Plugged In" : "On Battery"),
                progress: batFraction,
                accent: stats.batteryPercent <= 20 && !stats.isCharging ? .orange : .green
            )
        }
    }
}

private struct StatModuleCard: View {
    let icon: String
    let title: String
    let value: String
    let subtitle: String
    let progress: Double
    let accent: Color

    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovered: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                ZStack {
                    Circle()
                        .fill(accent.opacity(isHovered ? 0.24 : 0.16))
                        .frame(width: 26, height: 26)
                    Image(systemName: icon)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundColor(accent)
                }
                Spacer()
            }

            Spacer()

            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundColor(.primary)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.primary)
                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(colorScheme.subtleTrack)
                        .frame(height: 3.5)
                    Capsule()
                        .fill(accent)
                        .frame(width: max(3.5, geo.size.width * CGFloat(progress)), height: 3.5)
                        .animation(IslandMotion.progress, value: progress)
                }
            }
            .frame(height: 4)
            .padding(.top, 2)
        }
        .padding(11)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(isHovered ? Color.primary.opacity(colorScheme == .dark ? 0.12 : 0.08) : colorScheme.moduleFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(
                            isHovered ? accent.opacity(0.38) : colorScheme.moduleStroke,
                            lineWidth: 0.6
                        )
                )
        )
        .scaleEffect(isHovered ? 1.018 : 1.0)
        .brightness(isHovered ? 0.015 : 0)
        .microPress(scale: 0.97)
        .animation(IslandMotion.hover(isHovered), value: isHovered)
        .animation(IslandMotion.progress, value: progress)
        .onHover { over in
            isHovered = over
        }
    }
}

// MARK: - Settings Tab

struct SettingsTabView: View {
    @ObservedObject var state: IslandState

    var body: some View {
        VStack(spacing: 5.5) {
            HStack {
                Text("Position")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundColor(.primary)
                Spacer()
                Picker("", selection: $state.placement) {
                    ForEach(PillPlacement.allCases) { placement in
                        Text(placement.label).tag(placement)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 196)
            }

            HStack {
                Text("Color Theme")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundColor(.primary)
                Spacer()
                Picker("", selection: $state.glassAppearance) {
                    ForEach(GlassAppearance.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 196)
            }

            settingRow("Expand on hover", isOn: $state.openOnHover)
            settingRow("Auto-hide with Menu Bar", isOn: $state.hideInFullScreen)
            settingRow("Toast banners", isOn: $state.showToasts)
            settingRow("Launch at login", isOn: $state.launchAtLogin)

            Rectangle()
                .fill(Color.primary.opacity(0.09))
                .frame(height: 0.5)

            HStack {
                Text(state.isHotKeyAvailable ? "Shortcut: ⌥ Space" : "Shortcut: ⌥ Space (in use)")
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundColor(state.isHotKeyAvailable ? .secondary : .orange)
                Spacer()
                Button {
                    NSApp.terminate(nil)
                } label: {
                    Text("Quit AirIsland")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.red)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4.5)
                }
                .buttonStyle(AppleControlPillButtonStyle(fillColor: Color.red.opacity(0.15)))
            }
        }
    }

    private func settingRow(_ label: String, isOn: Binding<Bool>) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(.primary)
            Spacer()
            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
    }
}
