import SwiftUI

enum IslandTab: String, CaseIterable, Identifiable {
    case nowPlaying = "Music"
    case timer = "Timer"
    case shelf = "Shelf"
    case system = "System"
    case settings = "Prefs"

    var id: String { rawValue }

    var iconName: String {
        switch self {
        case .nowPlaying: return "music.note"
        case .timer: return "timer"
        case .shelf: return "tray.and.arrow.down.fill"
        case .system: return "cpu"
        case .settings: return "gearshape.fill"
        }
    }
}

enum PillPlacement: String, CaseIterable, Identifiable {
    case menuBar = "menuBar"
    case belowMenuBar = "belowMenuBar"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .menuBar: return "Menu Bar"
        case .belowMenuBar: return "Floating"
        }
    }
}

enum GlassAppearance: String, CaseIterable, Identifiable {
    case auto = "auto"
    case dark = "dark"
    case light = "light"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .auto: return "Sync"
        case .dark: return "Dark"
        case .light: return "Light"
        }
    }
}

struct IslandToast: Equatable, Identifiable {
    let id = UUID()
    let icon: String
    let title: String
    let subtitle: String?
    let accent: Color
    let targetTab: IslandTab?

    static func == (lhs: IslandToast, rhs: IslandToast) -> Bool {
        lhs.id == rhs.id
    }
}

final class IslandState: ObservableObject {
    private enum DefaultsKey {
        static let placement = "airisland.placement"
        static let glassAppearance = "airisland.glassAppearance"
        static let syncMusicTheme = "airisland.syncMusicTheme"
        static let openOnHover = "airisland.openOnHover"
        static let showToasts = "airisland.showToasts"
        static let hideInFullScreen = "airisland.hideInFullScreen"
    }

    @Published var isExpanded: Bool = false
    @Published var activeTab: IslandTab = .nowPlaying
    @Published var isLyricsMode: Bool = false
    @Published var toast: IslandToast? = nil
    @Published var expandedBannerToast: IslandToast? = nil
    @Published var isHovered: Bool = false
    @Published var isHiddenForFullScreen: Bool = false
    @Published var isHotKeyAvailable: Bool = true
    @Published var menuBarIsDark: Bool = true {
        didSet {
            if oldValue != menuBarIsDark, glassAppearance == .auto {
                onAppearanceChanged?()
            }
        }
    }

    @Published var placement: PillPlacement {
        didSet {
            UserDefaults.standard.set(placement.rawValue, forKey: DefaultsKey.placement)
            onLayoutChanged?()
        }
    }

    @Published var glassAppearance: GlassAppearance {
        didSet {
            UserDefaults.standard.set(glassAppearance.rawValue, forKey: DefaultsKey.glassAppearance)
            onAppearanceChanged?()
        }
    }

    @Published var syncMusicTheme: Bool {
        didSet {
            UserDefaults.standard.set(syncMusicTheme, forKey: DefaultsKey.syncMusicTheme)
        }
    }

    @Published var openOnHover: Bool {
        didSet {
            UserDefaults.standard.set(openOnHover, forKey: DefaultsKey.openOnHover)
        }
    }

    @Published var showToasts: Bool {
        didSet {
            UserDefaults.standard.set(showToasts, forKey: DefaultsKey.showToasts)
        }
    }

    @Published var hideInFullScreen: Bool {
        didSet {
            UserDefaults.standard.set(hideInFullScreen, forKey: DefaultsKey.hideInFullScreen)
            onFullScreenSettingChanged?()
        }
    }

    @Published var launchAtLogin: Bool {
        didSet {
            Self.applyLaunchAtLogin(launchAtLogin)
        }
    }

    var resolvedIsDark: Bool {
        switch glassAppearance {
        case .auto:
            return menuBarIsDark
        case .dark:
            return true
        case .light:
            return false
        }
    }

    /// pointer position inside the island, republished on its own so tracking never
    /// invalidates the whole island hierarchy
    let pointerGlow = PointerGlow()

    var onGeometryChanged: (() -> Void)?
    var onLayoutChanged: (() -> Void)?
    var onFullScreenSettingChanged: (() -> Void)?
    var onAppearanceChanged: (() -> Void)?
    var onToastDismissed: (() -> Void)?

    private var toastDismissWorkItem: DispatchWorkItem?
    private var expandedBannerDismissWorkItem: DispatchWorkItem?

    // Single source of truth for collapsed / toast / expanded sizing shared by IslandPanel & IslandContainerView
    func collapsedPillSize(hasTrack: Bool, timerRunning: Bool) -> CGSize {
        let width: CGFloat
        if timerRunning || hasTrack {
            width = isHovered ? 204 : 194
        } else {
            width = isHovered ? 114 : 96
        }
        let baseHeight: CGFloat = placement == .menuBar ? 22 : 26
        let height: CGFloat = isHovered ? baseHeight + 2 : baseHeight
        return CGSize(width: width, height: height)
    }

    var expandedSize: CGSize {
        let h: CGFloat = (isLyricsMode && activeTab == .nowPlaying) ? 296 : 234
        return CGSize(width: 440, height: h)
    }

    func currentPillSize(hasTrack: Bool, timerRunning: Bool) -> CGSize {
        if isExpanded { return expandedSize }
        if toast != nil { return CGSize(width: 316, height: 40) }
        return collapsedPillSize(hasTrack: hasTrack, timerRunning: timerRunning)
    }

    func currentCornerRadius(hasTrack: Bool, timerRunning: Bool) -> CGFloat {
        if isExpanded { return 28 }
        if toast != nil { return 20 }
        return collapsedPillSize(hasTrack: hasTrack, timerRunning: timerRunning).height / 2.0
    }

    static let expandAnimation = IslandMotion.expand
    static let collapseAnimation = IslandMotion.collapse

    init() {
        let savedPlacement = UserDefaults.standard.string(forKey: DefaultsKey.placement)
        self.placement = PillPlacement(rawValue: savedPlacement ?? "") ?? .menuBar

        let savedGlass = UserDefaults.standard.string(forKey: DefaultsKey.glassAppearance)
        self.glassAppearance = GlassAppearance(rawValue: savedGlass ?? "") ?? .auto

        if UserDefaults.standard.object(forKey: DefaultsKey.syncMusicTheme) != nil {
            self.syncMusicTheme = UserDefaults.standard.bool(forKey: DefaultsKey.syncMusicTheme)
        } else {
            self.syncMusicTheme = true
        }

        if UserDefaults.standard.object(forKey: DefaultsKey.openOnHover) != nil {
            self.openOnHover = UserDefaults.standard.bool(forKey: DefaultsKey.openOnHover)
        } else {
            self.openOnHover = true
        }

        if UserDefaults.standard.object(forKey: DefaultsKey.showToasts) != nil {
            self.showToasts = UserDefaults.standard.bool(forKey: DefaultsKey.showToasts)
        } else {
            self.showToasts = true
        }

        if UserDefaults.standard.object(forKey: DefaultsKey.hideInFullScreen) != nil {
            self.hideInFullScreen = UserDefaults.standard.bool(forKey: DefaultsKey.hideInFullScreen)
        } else {
            self.hideInFullScreen = true
        }

        self.launchAtLogin = FileManager.default.fileExists(atPath: Self.launchAgentURL.path)
    }

    private static var launchAgentURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents", isDirectory: true)
            .appendingPathComponent("com.airisland.app.plist")
    }

    private static func applyLaunchAtLogin(_ enabled: Bool) {
        let fm = FileManager.default
        let plistURL = launchAgentURL
        if enabled {
            let appsExec = "/Applications/AirIsland.app/Contents/MacOS/AirIsland"
            let execPath = fm.isExecutableFile(atPath: appsExec)
                ? appsExec
                : (Bundle.main.executablePath ?? appsExec)
            let dirURL = plistURL.deletingLastPathComponent()
            try? fm.createDirectory(at: dirURL, withIntermediateDirectories: true)
            let plist: [String: Any] = [
                "Label": "com.airisland.app",
                "ProgramArguments": [execPath],
                "RunAtLoad": true,
                "KeepAlive": false
            ]
            if let data = try? PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0) {
                try? data.write(to: plistURL, options: .atomic)
            }
        } else {
            try? fm.removeItem(at: plistURL)
        }
    }

    func expand(to tab: IslandTab? = nil, forceReveal: Bool = false) {
        if isHiddenForFullScreen && !forceReveal { return }
        if forceReveal && isHiddenForFullScreen {
            isHiddenForFullScreen = false
        }
        if let tab = tab {
            activeTab = tab
            if tab != .nowPlaying {
                isLyricsMode = false
            }
        }
        toastDismissWorkItem?.cancel()
        toast = nil
        if let tab = tab, expandedBannerToast?.targetTab == tab {
            expandedBannerDismissWorkItem?.cancel()
            expandedBannerToast = nil
        }
        withAnimation(Self.expandAnimation) {
            isHovered = false
            isExpanded = true
        }
        pointerGlow.reset(expanded: true)
        onGeometryChanged?()
    }

    func collapse() {
        guard isExpanded else { return }
        withAnimation(Self.collapseAnimation) {
            isExpanded = false
            isHovered = false
        }
        pointerGlow.reset(expanded: false)
        onGeometryChanged?()
    }

    func setLyricsMode(_ enabled: Bool) {
        withAnimation(enabled ? Self.expandAnimation : Self.collapseAnimation) {
            isLyricsMode = enabled
            if enabled {
                activeTab = .nowPlaying
            }
        }
        onGeometryChanged?()
    }

    func toggle() {
        if isExpanded {
            collapse()
        } else {
            expand()
        }
    }

    func presentToast(
        icon: String,
        title: String,
        subtitle: String? = nil,
        accent: Color = .green,
        targetTab: IslandTab? = nil,
        duration: TimeInterval = 2.4,
        important: Bool = false
    ) {
        let newToast = IslandToast(
            icon: icon,
            title: title,
            subtitle: subtitle,
            accent: accent,
            targetTab: targetTab
        )

        if isExpanded {
            guard important else { return }
            expandedBannerDismissWorkItem?.cancel()
            withAnimation(IslandMotion.resolved(IslandMotion.layout)) {
                self.expandedBannerToast = newToast
            }
            let work = DispatchWorkItem { [weak self] in
                guard let self = self else { return }
                withAnimation(IslandMotion.resolved(IslandMotion.layout)) {
                    if self.expandedBannerToast?.id == newToast.id {
                        self.expandedBannerToast = nil
                    }
                }
            }
            expandedBannerDismissWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
            return
        }

        if !important {
            guard showToasts, !isHiddenForFullScreen else { return }
        }

        toastDismissWorkItem?.cancel()
        withAnimation(Self.expandAnimation) {
            if important && self.isHiddenForFullScreen {
                self.isHiddenForFullScreen = false
            }
            self.toast = newToast
        }
        onGeometryChanged?()

        let work = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            withAnimation(Self.collapseAnimation) {
                if self.toast?.id == newToast.id {
                    self.toast = nil
                }
            }
            self.onGeometryChanged?()
            self.onToastDismissed?()
        }
        toastDismissWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
    }
}
