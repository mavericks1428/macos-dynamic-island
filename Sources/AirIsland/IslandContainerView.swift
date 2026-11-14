import Cocoa
import SwiftUI
import UniformTypeIdentifiers

// MARK: - 60fps Native macOS Behind-Window Glass (Zero per-frame maskImage churn)

final class MaskedVisualEffectView: NSVisualEffectView {
    private static var maskCache: [Int: NSImage] = [:]
    private var lastAppliedRadius: Int = -1
    private var collapseMaskWorkItem: DispatchWorkItem?

    var targetMaskSize: CGSize = CGSize(width: 194, height: 22)
    var targetMaskRadius: CGFloat = 11

    func updateDiscreteMask(size: CGSize, radius: CGFloat) {
        let oldArea = targetMaskSize.width * targetMaskSize.height
        let newArea = size.width * size.height
        let oldRadius = targetMaskRadius
        guard abs(targetMaskSize.width - size.width) > 0.5
                || abs(targetMaskSize.height - size.height) > 0.5
                || abs(oldRadius - radius) > 0.5 else {
            return
        }
        targetMaskSize = size
        targetMaskRadius = radius
        scheduleMaskUpdate(
            radius: radius,
            shrinking: newArea < oldArea,
            largeRadiusDrop: abs(oldRadius - radius) > 2.0
        )
    }

    override func layout() {
        super.layout()
        if lastAppliedRadius < 0 {
            applyMask(radius: targetMaskRadius)
        }
    }

    private func scheduleMaskUpdate(radius: CGFloat, shrinking: Bool, largeRadiusDrop: Bool) {
        collapseMaskWorkItem?.cancel()
        collapseMaskWorkItem = nil

        if shrinking {
            // Keep larger corner radius cleanly while SwiftUI .clipShape handles the smooth shrink morph
            let delay: TimeInterval = largeRadiusDrop ? 0.58 : 0.26
            let work = DispatchWorkItem { [weak self] in
                self?.applyMask(radius: radius)
            }
            collapseMaskWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        } else {
            applyMask(radius: radius)
        }
    }

    private func applyMask(radius desired: CGFloat) {
        let r = max(2, Int(round(desired)))
        guard r != lastAppliedRadius else { return }
        lastAppliedRadius = r

        wantsLayer = true
        layer?.masksToBounds = true
        layer?.cornerRadius = CGFloat(r)
        if #available(macOS 10.15, *) {
            layer?.cornerCurve = .continuous
        }
        maskImage = Self.cachedNineSliceMaskImage(radius: r)
    }

    /// 9-slice stretchable mask scales smoothly on the GPU across any intermediate frame size
    private static func cachedNineSliceMaskImage(radius r: Int) -> NSImage {
        if let cached = maskCache[r] {
            return cached
        }
        let dim = CGFloat(r * 2 + 4)
        let size = NSSize(width: dim, height: dim)
        let radius = CGFloat(r)
        let image = NSImage(size: size, flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        maskCache[r] = image
        return image
    }
}

struct SystemVisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode
    let targetMaskSize: CGSize
    let targetMaskRadius: CGFloat
    let isDark: Bool

    func makeNSView(context: Context) -> MaskedVisualEffectView {
        let view = MaskedVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        view.isEmphasized = true
        view.appearance = NSAppearance(named: isDark ? .darkAqua : .aqua)
        view.updateDiscreteMask(size: targetMaskSize, radius: targetMaskRadius)
        return view
    }

    func updateNSView(_ nsView: MaskedVisualEffectView, context: Context) {
        if nsView.material != material {
            nsView.material = material
        }
        if nsView.blendingMode != blendingMode {
            nsView.blendingMode = blendingMode
        }
        let targetAppearance = NSAppearance(named: isDark ? .darkAqua : .aqua)
        if nsView.appearance != targetAppearance {
            nsView.appearance = targetAppearance
        }
        nsView.updateDiscreteMask(size: targetMaskSize, radius: targetMaskRadius)
    }
}

// MARK: - Main Island Container

struct IslandContainerView: View {
    @ObservedObject var state: IslandState
    @ObservedObject var media: MediaController
    @ObservedObject var timer: TimerController
    @ObservedObject var shelf: ShelfAndClipboardStore
    @ObservedObject var systemStats: SystemStatsMonitor

    @State private var isDropTargeted: Bool = false

    private var isDark: Bool { state.resolvedIsDark }

    private var isShowingLyrics: Bool {
        state.isExpanded && state.isLyricsMode && state.activeTab == .nowPlaying
    }

    private var isMusicThemeActive: Bool {
        guard state.syncMusicTheme, media.hasTrack else { return false }
        if state.isExpanded {
            return state.activeTab == .nowPlaying
        }
        return state.toast == nil
    }

    private var effectiveColorScheme: ColorScheme {
        (isDark || isMusicThemeActive) ? .dark : .light
    }

    private var collapsedSize: CGSize {
        state.collapsedPillSize(hasTrack: media.hasTrack, timerRunning: timer.isRunning)
    }

    private var collapsedWidth: CGFloat { collapsedSize.width }
    private var collapsedHeight: CGFloat { collapsedSize.height }

    private var expandedHeight: CGFloat {
        state.expandedSize.height
    }

    private var currentSize: CGSize {
        state.currentPillSize(hasTrack: media.hasTrack, timerRunning: timer.isRunning)
    }

    private var currentWidth: CGFloat { currentSize.width }
    private var currentHeight: CGFloat { currentSize.height }

    private var cornerRadius: CGFloat {
        state.currentCornerRadius(hasTrack: media.hasTrack, timerRunning: timer.isRunning)
    }

    // Target size & radius update ONCE per discrete state (never per animation frame)
    private var staticMaskSize: CGSize {
        CGSize(width: currentWidth, height: currentHeight)
    }

    private var staticMaskRadius: CGFloat {
        cornerRadius
    }

    private var activeMaterial: NSVisualEffectView.Material {
        if !state.isExpanded && state.toast == nil && state.placement == .menuBar {
            return .menu
        }
        return .popover
    }

    private var ambientTint: Color {
        if let toast = state.toast, !state.isExpanded {
            return toast.accent
        }
        if media.hasTrack {
            return media.accentColor
        }
        if timer.isRunning {
            return .orange
        }
        return .clear
    }

    private var hasAmbientTint: Bool {
        (state.toast != nil && !state.isExpanded) || media.hasTrack || timer.isRunning
    }

    private var ambientTintOpacity: Double {
        guard hasAmbientTint else { return 0 }
        if state.isExpanded { return isDark ? 0.16 : 0.11 }
        if state.isHovered { return 0.16 }
        return 0.09
    }

    // MARK: - Cursor Tracking Fidelity

    /// How present the cursor sheen is. Curves up on hover and settles while expanded;
    /// the NSView fades its layer over 0.34s so the transition layering stays smooth.
    private var sheenIntensity: Double {
        if state.isHiddenForFullScreen { return 0 }
        if state.isExpanded { return isDark ? 0.055 : 0.13 }
        if state.isHovered { return isDark ? 0.16 : 0.24 }
        return isDark ? 0.02 : 0.05
    }

    /// Pointer-proximity rim warmth.
    private var hoverRimOpacity: Double {
        if state.isExpanded { return isDark ? 0.05 : 0.20 }
        if state.isHovered { return isDark ? 0.12 : 0.34 }
        return isDark ? 0.03 : 0.10
    }

    /// Content swaps cross-fade with a hair of scale so incoming/outgoing views never jump.
    private var contentSwapTransition: AnyTransition {
        .opacity.combined(with: .scale(scale: 0.985, anchor: .top))
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color.clear

            ZStack(alignment: .top) {
                // Collapsed Idle / Active Pill (pauses spectrum ticker the moment island expands)
                CollapsedPillView(
                    media: media,
                    timer: timer,
                    systemStats: systemStats,
                    isHovered: state.isHovered,
                    isHotKeyAvailable: state.isHotKeyAvailable,
                    isActiveVisible: !state.isExpanded && state.toast == nil
                )
                .frame(width: collapsedWidth, height: collapsedHeight)
                .opacity(!state.isExpanded && state.toast == nil ? 1.0 : 0.0)
                .allowsHitTesting(!state.isExpanded && state.toast == nil)

                // Transient Toast Banner
                if let toast = state.toast, !state.isExpanded {
                    ToastPillView(toast: toast)
                        .frame(width: 316, height: 40)
                        .transition(contentSwapTransition)
                }

                // Expanded Apple Control Center Hub
                if state.isExpanded {
                    ExpandedIslandView(
                        state: state,
                        media: media,
                        timer: timer,
                        shelf: shelf,
                        systemStats: systemStats
                    )
                    .frame(width: 440, height: expandedHeight)
                    .transition(contentSwapTransition)
                }
            }
            .frame(width: currentWidth, height: currentHeight, alignment: .top)
            .background(islandGlassSurface)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(rimBorderGradient, lineWidth: isDropTargeted ? 1.6 : 1.0)
                    // Rim warmth rides the same spring as the frame so the border never steps ahead of the glass
                    .animation(IslandMotion.hover(state.isHovered), value: state.isHovered)
                    .animation(IslandMotion.resolved(IslandMotion.layout), value: state.isExpanded)
                    .animation(IslandMotion.resolved(IslandMotion.quick), value: isDropTargeted)
            )
            .overlay(
                // Pointer-proximity rim response: the rim warms subtly as the cursor engages
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(hoverRimOpacity), lineWidth: 0.8)
                    .animation(IslandMotion.hover(state.isHovered), value: state.isHovered)
                    .animation(IslandMotion.resolved(IslandMotion.layout), value: state.isExpanded)
                    .allowsHitTesting(false)
            )
            .shadow(
                color: Color.black.opacity(
                    state.isExpanded
                        ? (effectiveColorScheme == .dark ? 0.36 : 0.16)
                        : (effectiveColorScheme == .dark ? 0.22 : 0.12)
                ),
                radius: state.isExpanded ? 5 : 2,
                x: 0,
                y: state.isExpanded ? 2.5 : 1
            )
            .padding(.top, 2)
            .offset(y: state.isHiddenForFullScreen ? -32 : 0)
            .scaleEffect(state.isHiddenForFullScreen ? 0.96 : 1.0, anchor: .top)
            .opacity(state.isHiddenForFullScreen ? 0.0 : 1.0)
            .animation(
                IslandMotion.resolved(.spring(response: 0.42, dampingFraction: 0.90, blendDuration: 0.10)),
                value: state.isHiddenForFullScreen
            )
            // isExpanded / isLyricsMode / toast are wrapped in explicit withAnimation transactions
            // inside IslandState — animating them here would override the slower collapse spring.
            .animation(IslandMotion.hover(state.isHovered), value: state.isHovered)
            // Content that appears without an explicit transaction still glides instead of jumping
            .animation(IslandMotion.resolved(IslandMotion.layout), value: media.hasTrack)
            .animation(IslandMotion.resolved(IslandMotion.layout), value: timer.isRunning)
            .allowsHitTesting(!state.isHiddenForFullScreen)
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .onTapGesture {
                if !state.isExpanded {
                    if let target = state.toast?.targetTab {
                        state.expand(to: target)
                    } else {
                        state.expand()
                    }
                }
            }
            .onDrop(of: [UTType.fileURL], isTargeted: $isDropTargeted) { providers in
                let handled = shelf.handleDrop(providers: providers)
                if handled {
                    state.expand(to: .shelf)
                }
                return handled
            }
            .onChange(of: isDropTargeted) { targeted in
                if targeted && !state.isExpanded {
                    state.expand(to: .shelf)
                }
            }
            .contextMenu {
                Button(state.isExpanded ? "Collapse Island" : "Expand Island") {
                    state.toggle()
                }
                Divider()
                Button(state.placement == .menuBar ? "Float Below Menu Bar" : "Tuck Inside Menu Bar") {
                    state.placement = (state.placement == .menuBar) ? .belowMenuBar : .menuBar
                }
                Toggle("Sync Music Theme", isOn: $state.syncMusicTheme)
                Toggle("Expand on Hover", isOn: $state.openOnHover)
                Toggle("Auto-hide with Menu Bar", isOn: $state.hideInFullScreen)
                Toggle("Toast Banners", isOn: $state.showToasts)
                Divider()
                Button("Quit AirIsland") {
                    NSApp.terminate(nil)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .environment(\.colorScheme, effectiveColorScheme)
        .animation(IslandMotion.resolved(IslandMotion.quick), value: state.activeTab)
        .animation(IslandMotion.resolved(IslandMotion.layout), value: state.isLyricsMode)
        .onChange(of: state.isExpanded) { expanded in
            syncActivePollers(expanded: expanded, tab: state.activeTab, lyrics: state.isLyricsMode)
            if expanded && state.isLyricsMode && state.activeTab == .nowPlaying {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
                    guard state.isExpanded && state.isLyricsMode else { return }
                    media.refreshNowPlaying()
                    media.ensureLyricsLoaded()
                }
            }
        }
        .onChange(of: state.activeTab) { tab in
            syncActivePollers(expanded: state.isExpanded, tab: tab, lyrics: state.isLyricsMode)
        }
        .onChange(of: state.isLyricsMode) { lyrics in
            syncActivePollers(expanded: state.isExpanded, tab: state.activeTab, lyrics: lyrics)
            if lyrics && state.isExpanded {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
                    guard state.isExpanded && state.isLyricsMode else { return }
                    media.refreshNowPlaying()
                    media.ensureLyricsLoaded()
                }
            }
        }
        .onChange(of: media.isPlaying) { _ in
            syncActivePollers(expanded: state.isExpanded, tab: state.activeTab, lyrics: state.isLyricsMode)
        }
        .onChange(of: media.duration) { _ in
            syncActivePollers(expanded: state.isExpanded, tab: state.activeTab, lyrics: state.isLyricsMode)
        }
    }

    private var islandGlassSurface: some View {
        ZStack {
            SystemVisualEffectView(
                material: activeMaterial,
                blendingMode: .behindWindow,
                targetMaskSize: staticMaskSize,
                targetMaskRadius: staticMaskRadius,
                isDark: isDark || isMusicThemeActive
            )

            if isMusicThemeActive {
                LinearGradient(
                    gradient: Gradient(colors: [
                        media.themeBackdropTop.opacity(state.isExpanded ? 0.84 : 0.56),
                        media.themeBackdropBottom.opacity(state.isExpanded ? 0.90 : 0.62)
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .animation(IslandMotion.resolved(IslandMotion.layout), value: state.isExpanded)
                .animation(IslandMotion.resolved(IslandMotion.theme), value: media.themeBackdropTop)

                RadialGradient(
                    gradient: Gradient(colors: [
                        media.secondaryColor.opacity(state.isExpanded ? 0.22 : 0.16),
                        Color.clear
                    ]),
                    center: .bottomTrailing,
                    startRadius: 8,
                    endRadius: state.isExpanded ? 260 : 120
                )
                .animation(IslandMotion.resolved(IslandMotion.layout), value: state.isExpanded)
            } else {
                (isDark ? Color.black : Color.white)
                    .opacity(
                        isDark
                            ? (state.isExpanded ? 0.34 : 0.28)
                            : (state.isExpanded ? 0.22 : 0.14)
                    )
                    .animation(IslandMotion.resolved(IslandMotion.layout), value: state.isExpanded)
            }

            RadialGradient(
                gradient: Gradient(colors: [
                    ambientTint.opacity(isMusicThemeActive ? (state.isExpanded ? 0.28 : 0.20) : ambientTintOpacity),
                    Color.clear
                ]),
                center: isMusicThemeActive && state.isExpanded ? .topLeading : .top,
                startRadius: 4,
                endRadius: state.isExpanded ? 250 : 110
            )
            .animation(IslandMotion.hover(state.isHovered), value: ambientTintOpacity)

            // A static presence glow at the crown of the glass
            RadialGradient(
                gradient: Gradient(colors: [
                    Color.white.opacity(sheenIntensity * 0.40),
                    Color.clear
                ]),
                center: .top,
                startRadius: 2,
                endRadius: state.isExpanded ? 300 : 130
            )
            .animation(IslandMotion.hover(state.isHovered), value: state.isHovered)
            .animation(IslandMotion.resolved(IslandMotion.layout), value: state.isExpanded)

            // Cursor-tracking specular sheen — glides after the pointer with spring physics,
            // sits under all content so text stays razor sharp, and never intercepts events.
            PointerSheenView(
                glow: state.pointerGlow,
                intensity: sheenIntensity,
                spread: state.isExpanded ? 0.95 : 1.7
            )
            .animation(IslandMotion.hover(state.isHovered), value: sheenIntensity)
        }
    }

    private var rimBorderGradient: LinearGradient {
        if isDropTargeted {
            return LinearGradient(
                gradient: Gradient(colors: [Color.accentColor.opacity(0.95), Color.accentColor.opacity(0.55)]),
                startPoint: .top,
                endPoint: .bottom
            )
        }
        if isMusicThemeActive {
            return LinearGradient(
                gradient: Gradient(colors: [
                    media.accentColor.opacity(state.isExpanded ? 0.68 : (state.isHovered ? 0.62 : 0.48)),
                    media.secondaryColor.opacity(state.isExpanded ? 0.26 : 0.20)
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        let topAlpha: Double = isDark
            ? (state.isExpanded ? 0.26 : (state.isHovered ? 0.32 : 0.18))
            : (state.isExpanded ? 0.74 : (state.isHovered ? 0.82 : 0.58))
        let bottomAlpha: Double = isDark
            ? (state.isExpanded ? 0.08 : 0.06)
            : (state.isExpanded ? 0.16 : 0.14)
        let bottomColor: Color = isDark ? .white : .black

        return LinearGradient(
            gradient: Gradient(colors: [
                Color.white.opacity(topAlpha),
                bottomColor.opacity(bottomAlpha)
            ]),
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private func syncActivePollers(expanded: Bool, tab: IslandTab, lyrics: Bool) {
        let lyricsActive = expanded && lyrics && tab == .nowPlaying
        let musicActive = expanded && tab == .nowPlaying && (lyricsActive || (media.isPlaying && media.duration > 0))
        media.setProgressUpdatesActive(musicActive, highPrecision: lyricsActive)
        systemStats.setActivePolling(expanded && tab == .system)
    }
}

// MARK: - Collapsed Apple Pill

struct CollapsedPillView: View {
    @ObservedObject var media: MediaController
    @ObservedObject var timer: TimerController
    @ObservedObject var systemStats: SystemStatsMonitor
    let isHovered: Bool
    var isHotKeyAvailable: Bool = true
    var isActiveVisible: Bool = true

    var body: some View {
        HStack(spacing: 7) {
            if media.hasTrack {
                miniArtwork
                FluidTextSwap(
                    text: media.title,
                    font: .system(size: 11.5, weight: .medium)
                )
                Spacer(minLength: 4)
                if timer.isRunning {
                    timerBadge
                } else {
                    AudioWaveformView(
                        isPlaying: media.isPlaying && isActiveVisible,
                        color: media.accentColor,
                        secondaryColor: media.secondaryColor,
                        seed: media.title.hashValue,
                        isBoosted: isHovered
                    )
                }
            } else if timer.isRunning {
                ZStack {
                    Circle()
                        .stroke(Color.orange.opacity(0.28), lineWidth: 2)
                    Circle()
                        .trim(from: 0, to: CGFloat(timer.progress))
                        .stroke(Color.orange, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(IslandMotion.progress, value: timer.progress)
                }
                .frame(width: 12, height: 12)

                FluidTextSwap(
                    text: timer.label,
                    font: .system(size: 11, weight: .medium)
                )
                Spacer(minLength: 4)
                timerBadge
            } else {
                Circle()
                    .fill(
                        systemStats.isCharging
                            ? Color.green.opacity(0.92)
                            : Color.primary.opacity(isHovered ? 0.80 : 0.38)
                    )
                    .frame(width: 5.5, height: 5.5)

                if isHovered {
                    Text("Open")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.primary)
                    Spacer(minLength: 2)
                    Text(isHotKeyAvailable ? "⌥Space" : "Click")
                        .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                        .foregroundColor(.secondary)
                } else {
                    Spacer(minLength: 2)
                    Image(systemName: "waveform")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary.opacity(0.88))
                }
            }
        }
        .padding(.horizontal, 10)
        // Fluid layout remap: hover label set fades while the pill frame springs open
        .animation(IslandMotion.hover(isHovered), value: isHovered)
        .animation(IslandMotion.resolved(IslandMotion.layout), value: media.hasTrack)
        .animation(IslandMotion.resolved(IslandMotion.layout), value: timer.isRunning)
    }

    @ViewBuilder
    private var miniArtwork: some View {
        if let art = media.artwork {
            Image(nsImage: art)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 15, height: 15)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.14), lineWidth: 0.5)
                )
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(media.accentColor.opacity(0.22))
                Image(systemName: "music.note")
                    .font(.system(size: 8.5, weight: .bold))
                    .foregroundColor(media.accentColor)
            }
            .frame(width: 15, height: 15)
        }
    }

    private var timerBadge: some View {
        Text(timer.formattedRemaining)
            .font(.system(size: 11, weight: .semibold, design: .rounded).monospacedDigit())
            .foregroundColor(.orange)
    }
}

// MARK: - Toast Pill

struct ToastPillView: View {
    let toast: IslandToast

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(toast.accent.opacity(0.20))
                    .frame(width: 25, height: 25)
                    .overlay(
                        Circle()
                            .strokeBorder(toast.accent.opacity(0.38), lineWidth: 0.5)
                    )
                Image(systemName: toast.icon)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundColor(toast.accent)
            }

            VStack(alignment: .leading, spacing: 1) {
                FluidTextSwap(
                    text: toast.title,
                    font: .system(size: 12, weight: .semibold)
                )
                if let subtitle = toast.subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .transition(.opacity.combined(with: .offset(y: 2)))
                }
            }
            .animation(IslandMotion.resolved(IslandMotion.layout), value: toast.id)

            Spacer(minLength: 4)

            Image(systemName: "chevron.right")
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundColor(Color(NSColor.tertiaryLabelColor))
        }
        .padding(.horizontal, 12)
    }
}

// MARK: - Responsive Dynamic Music Spectrum Bars (40fps GPU Scale)

struct AudioWaveformView: View {
    let isPlaying: Bool
    let color: Color
    var secondaryColor: Color? = nil
    var seed: Int = 0
    var isBoosted: Bool = false

    private var trackTempoScale: Double {
        let normalized = Double(abs(seed % 100)) / 100.0
        return 0.88 + normalized * 0.28
    }

    var body: some View {
        let topColor = color
        let bottomColor = secondaryColor ?? color.opacity(0.82)

        TimelineView(.animation(minimumInterval: 1.0 / 40.0, paused: !isPlaying)) { context in
            let t = context.date.timeIntervalSinceReferenceDate * trackTempoScale
            HStack(spacing: 2.2) {
                ForEach(0..<5, id: \.self) { idx in
                    let factor = barLevel(index: idx, time: t)
                    Capsule()
                        .fill(
                            LinearGradient(
                                gradient: Gradient(colors: [topColor, bottomColor]),
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: 2.2, height: 14)
                        .scaleEffect(y: factor, anchor: .center)
                        .opacity(isPlaying ? (0.78 + Double(factor) * 0.22) : 0.48)
                }
            }
            .frame(height: 14)
        }
        .animation(IslandMotion.resolved(IslandMotion.quick), value: isPlaying)
    }

    private func barLevel(index: Int, time t: TimeInterval) -> CGFloat {
        guard isPlaying else {
            return 0.25
        }

        // Five distinct frequency profiles (sub-bass, punch, center vocal, presence, air)
        let freqs1: [Double] = [5.2, 6.9, 8.1, 6.3, 9.4]
        let freqs2: [Double] = [11.3, 13.7, 15.1, 12.4, 17.2]
        let phases: [Double] = [0.0, 1.35, 2.70, 0.85, 2.15]
        let weights: [Double] = [0.84, 0.96, 1.00, 0.92, 0.80]

        let seedOffset = Double(abs((seed &+ index * 31) % 628)) / 100.0
        let p = phases[index] + seedOffset

        // Asymmetric punchy beat envelope (sharp peaks, wide dynamic range, smooth decay)
        let primary = pow(0.5 + 0.5 * sin(t * freqs1[index] + p), 2.15)
        let harmonic = pow(0.5 + 0.5 * sin(t * freqs2[index] + p * 1.4), 1.45)
        let beatPulse = pow(0.5 + 0.5 * sin(t * 2.8 + Double(index) * 0.55), 1.8)

        let raw = primary * 0.54 + harmonic * 0.28 + beatPulse * 0.18
        let energy = (isBoosted ? 1.08 : 1.0) * weights[index]
        let scaled = 0.18 + raw * 0.82 * energy
        return CGFloat(min(1.0, max(0.18, scaled)))
    }
}

// MARK: - Expanded Control Center Hub

struct ExpandedIslandView: View {
    @ObservedObject var state: IslandState
    @ObservedObject var media: MediaController
    @ObservedObject var timer: TimerController
    @ObservedObject var shelf: ShelfAndClipboardStore
    @ObservedObject var systemStats: SystemStatsMonitor

    @Environment(\.colorScheme) private var colorScheme
    @Namespace private var tabNamespace

    var body: some View {
        ZStack(alignment: .top) {
            if state.isLyricsMode && state.activeTab == .nowPlaying {
                LyricsCapsuleView(state: state, media: media)
                    .transition(.opacity.combined(with: .scale(scale: 0.99, anchor: .top)))
            } else {
                VStack(spacing: 0) {
                    topTabBar
                        .padding(.horizontal, 14)
                        .padding(.top, 11)
                        .padding(.bottom, 8)

                    Rectangle()
                        .fill(Color.primary.opacity(colorScheme == .dark ? 0.10 : 0.09))
                        .frame(height: 0.5)

                    Group {
                        switch state.activeTab {
                        case .nowPlaying:
                            NowPlayingTabView(state: state, media: media)
                        case .timer:
                            TimerTabView(timer: timer)
                        case .shelf:
                            ShelfAndClipboardTabView(store: shelf)
                        case .system:
                            SystemTabView(stats: systemStats)
                        case .settings:
                            SettingsTabView(state: state)
                        }
                    }
                    .id(state.activeTab)
                    .transition(.opacity.combined(with: .scale(scale: 0.985, anchor: .top)))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                }
                .transition(.opacity)
            }

            if let banner = state.expandedBannerToast {
                VStack {
                    Spacer()
                    Button {
                        if let tab = banner.targetTab {
                            state.expand(to: tab)
                        } else {
                            state.expandedBannerToast = nil
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: banner.icon)
                                .font(.system(size: 11.5, weight: .semibold))
                                .foregroundColor(banner.accent)
                            Text(banner.title)
                                .font(.system(size: 11.5, weight: .semibold))
                                .foregroundColor(.primary)
                            if let sub = banner.subtitle, !sub.isEmpty {
                                Text("· \(sub)")
                                    .font(.system(size: 10.5))
                                    .foregroundColor(.secondary)
                            }
                            Spacer(minLength: 4)
                            Image(systemName: "xmark")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            Capsule()
                                .fill(colorScheme == .dark ? Color.black.opacity(0.76) : Color.white.opacity(0.90))
                                .overlay(
                                    Capsule()
                                        .strokeBorder(banner.accent.opacity(0.45), lineWidth: 0.8)
                                )
                        )
                    }
                    .buttonStyle(SpringPressButtonStyle())
                    .padding(.horizontal, 14)
                    .padding(.bottom, 10)
                }
                .transition(.opacity)
            }
        }
    }

    private var topTabBar: some View {
        HStack(spacing: 5) {
            ForEach(IslandTab.allCases) { tab in
                let isSelected = state.activeTab == tab
                Button {
                    withAnimation(IslandMotion.resolved(IslandMotion.quick)) {
                        state.activeTab = tab
                    }
                } label: {
                    HStack(spacing: 4.5) {
                        Image(systemName: tab.iconName)
                            .font(.system(size: 10.5, weight: .semibold))
                        if isSelected {
                            Text(tab.rawValue)
                                .font(.system(size: 11, weight: .semibold))
                                .transition(.opacity.combined(with: .scale(scale: 0.92)))
                        }
                    }
                    .animation(IslandMotion.resolved(IslandMotion.quick), value: isSelected)
                    .foregroundColor(isSelected ? .primary : .secondary)
                    .padding(.horizontal, isSelected ? 10.5 : 9)
                    .padding(.vertical, 5.5)
                    .background(
                        ZStack {
                            if isSelected {
                                Capsule()
                                    .fill(Color.primary.opacity(colorScheme == .dark ? 0.16 : 0.10))
                                    .overlay(
                                        Capsule()
                                            .strokeBorder(
                                                Color.white.opacity(colorScheme == .dark ? 0.18 : 0.65),
                                                lineWidth: 0.5
                                            )
                                    )
                                    .matchedGeometryEffect(id: "activeTabPill", in: tabNamespace)
                            }
                        }
                    )
                }
                .buttonStyle(AppleHoverPillButtonStyle(cornerRadius: 14))
            }

            Spacer()

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
    }
}

// MARK: - Tactile Apple Interactive Button Styles

struct SpringPressButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .brightness(configuration.isPressed ? -0.035 : 0)
            .animation(IslandMotion.pressedAnimation(configuration.isPressed), value: configuration.isPressed)
    }
}

struct AppleHoverPillButtonStyle: ButtonStyle {
    var cornerRadius: CGFloat = 10

    func makeBody(configuration: Configuration) -> some View {
        HoverPillWrapper(configuration: configuration, cornerRadius: cornerRadius)
    }

    private struct HoverPillWrapper: View {
        let configuration: Configuration
        let cornerRadius: CGFloat
        @Environment(\.colorScheme) private var colorScheme
        @State private var hovering: Bool = false

        var body: some View {
            configuration.label
                .background(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(Color.primary.opacity(hovering ? (colorScheme == .dark ? 0.10 : 0.06) : 0.0))
                )
                .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .scaleEffect(configuration.isPressed ? 0.97 : (hovering ? 1.022 : 1.0))
                .brightness(configuration.isPressed ? -0.03 : (hovering ? 0.015 : 0))
                .animation(IslandMotion.pressedAnimation(configuration.isPressed), value: configuration.isPressed)
                .animation(IslandMotion.hover(hovering), value: hovering)
                .onHover { over in
                    hovering = over
                }
        }
    }
}

struct AppleHoverCircleButtonStyle: ButtonStyle {
    var tint: Color = .primary
    var baseFillOpacity: Double? = nil

    func makeBody(configuration: Configuration) -> some View {
        HoverCircleWrapper(configuration: configuration, tint: tint, baseFillOpacity: baseFillOpacity)
    }

    private struct HoverCircleWrapper: View {
        let configuration: Configuration
        let tint: Color
        let baseFillOpacity: Double?
        @Environment(\.colorScheme) private var colorScheme
        @State private var hovering: Bool = false

        var body: some View {
            let idleOpacity = baseFillOpacity ?? (colorScheme == .dark ? 0.08 : 0.055)
            let hoverOpacity = min(0.32, idleOpacity + (colorScheme == .dark ? 0.08 : 0.05))
            configuration.label
                .background(
                    Circle()
                        .fill(tint.opacity(hovering ? hoverOpacity : idleOpacity))
                        .overlay(
                            Circle()
                                .strokeBorder(
                                    Color.white.opacity(hovering ? (colorScheme == .dark ? 0.20 : 0.55) : (colorScheme == .dark ? 0.08 : 0.25)),
                                    lineWidth: 0.5
                                )
                        )
                )
                .contentShape(Circle())
                .scaleEffect(configuration.isPressed ? 0.97 : (hovering ? 1.045 : 1.0))
                .brightness(configuration.isPressed ? -0.04 : (hovering ? 0.02 : 0))
                .animation(IslandMotion.pressedAnimation(configuration.isPressed), value: configuration.isPressed)
                .animation(IslandMotion.hover(hovering), value: hovering)
                .onHover { over in
                    hovering = over
                }
        }
    }
}

struct AppleControlPillButtonStyle: ButtonStyle {
    var fillColor: Color? = nil

    func makeBody(configuration: Configuration) -> some View {
        ControlPillWrapper(configuration: configuration, fillColor: fillColor)
    }

    private struct ControlPillWrapper: View {
        let configuration: Configuration
        let fillColor: Color?
        @Environment(\.colorScheme) private var colorScheme
        @State private var hovering: Bool = false

        var body: some View {
            let base = fillColor ?? (colorScheme == .dark ? Color.white.opacity(0.09) : Color.black.opacity(0.06))
            configuration.label
                .background(
                    ZStack {
                        Capsule().fill(base)
                        Capsule().fill(Color.white.opacity(hovering ? (colorScheme == .dark ? 0.09 : 0.14) : 0.0))
                    }
                    .overlay(
                        Capsule()
                            .strokeBorder(
                                Color.white.opacity(hovering ? (colorScheme == .dark ? 0.24 : 0.65) : (colorScheme == .dark ? 0.11 : 0.26)),
                                lineWidth: 0.5
                            )
                    )
                )
                .contentShape(Capsule())
                .scaleEffect(configuration.isPressed ? 0.97 : (hovering ? 1.024 : 1.0))
                .brightness(configuration.isPressed ? -0.03 : (hovering ? 0.015 : 0))
                .animation(IslandMotion.pressedAnimation(configuration.isPressed), value: configuration.isPressed)
                .animation(IslandMotion.hover(hovering), value: hovering)
                .onHover { over in
                    hovering = over
                }
        }
    }
}
