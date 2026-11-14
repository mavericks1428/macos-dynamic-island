import Cocoa
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let state = IslandState()
    private let media = MediaController()
    private let timer = TimerController()
    private let shelf = ShelfAndClipboardStore()
    private let systemStats = SystemStatsMonitor()

    private var windowController: IslandWindowController?
    private var hotKeyManager: HotKeyManager?
    private var statusItem: NSStatusItem?
    private var hideInFullScreenMenuItem: NSMenuItem?
    private var launchAtLoginMenuItem: NSMenuItem?
    private var menuBarAppearanceObs: NSKeyValueObservation?
    private var themeObserver: NSObjectProtocol?
    private var globalClickMonitor: Any?
    private var localKeyMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        wireEvents()

        windowController = IslandWindowController(
            state: state,
            media: media,
            timer: timer,
            shelf: shelf,
            systemStats: systemStats
        )

        let hotKey = HotKeyManager()
        hotKey.onTrigger = { [weak self] in
            guard let self = self else { return }
            if self.state.isExpanded {
                self.state.collapse()
            } else {
                self.state.expand(forceReveal: true)
            }
        }
        state.isHotKeyAvailable = hotKey.isRegistered
        self.hotKeyManager = hotKey

        setupStatusBarItem()
        setupInputMonitors()

        state.presentToast(
            icon: "sparkles",
            title: "AirIsland Ready",
            subtitle: state.isHotKeyAvailable ? "Hover the pill or press ⌥ Space" : "Hover or click the top pill",
            accent: .cyan,
            duration: 2.5
        )
    }

    func applicationWillTerminate(_ notification: Notification) {
        menuBarAppearanceObs?.invalidate()
        if let themeObserver = themeObserver {
            DistributedNotificationCenter.default().removeObserver(themeObserver)
        }
        if let monitor = globalClickMonitor {
            NSEvent.removeMonitor(monitor)
        }
        if let monitor = localKeyMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    private func wireEvents() {
        media.onTrackChanged = { [weak self] title, artist, accent in
            self?.state.presentToast(
                icon: "music.note",
                title: title,
                subtitle: artist.isEmpty ? nil : artist,
                accent: accent,
                targetTab: .nowPlaying,
                duration: 2.4
            )
        }

        timer.onCompleted = { [weak self] label in
            self?.state.presentToast(
                icon: "checkmark.circle.fill",
                title: "\(label) Complete",
                subtitle: "Timer finished",
                accent: .orange,
                targetTab: .timer,
                duration: 3.6,
                important: true
            )
        }

        shelf.onFileAdded = { [weak self] filename in
            guard let self = self, !self.state.isExpanded else { return }
            self.state.presentToast(
                icon: "tray.and.arrow.down.fill",
                title: "Added to Shelf",
                subtitle: filename,
                accent: .blue,
                targetTab: .shelf,
                duration: 2.0
            )
        }

        systemStats.onPowerConnectionChanged = { [weak self] onAC, percent in
            self?.state.presentToast(
                icon: onAC ? "bolt.fill" : "battery.50",
                title: onAC ? "Power Connected" : "On Battery",
                subtitle: "Battery at \(percent)%",
                accent: onAC ? .green : .yellow,
                targetTab: .system,
                duration: 2.5
            )
        }
    }

    private func setupStatusBarItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            let image = NSImage(systemSymbolName: "capsule.fill", accessibilityDescription: "AirIsland")
            image?.isTemplate = true
            button.image = image

            syncMenuBarAppearance(from: button)
            menuBarAppearanceObs = button.observe(\.effectiveAppearance, options: [.initial, .new]) { [weak self] btn, _ in
                DispatchQueue.main.async {
                    self?.syncMenuBarAppearance(from: btn)
                }
            }
        }

        themeObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self, let btn = self.statusItem?.button else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                self.syncMenuBarAppearance(from: btn)
            }
        }

        let menu = NSMenu()
        menu.delegate = self
        let toggleTitle = state.isHotKeyAvailable ? "Toggle AirIsland (⌥ Space)" : "Toggle AirIsland"
        menu.addItem(withTitle: toggleTitle, action: #selector(toggleIsland), keyEquivalent: "")
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Music", action: #selector(openMusicTab), keyEquivalent: "")
        menu.addItem(withTitle: "Timer", action: #selector(openTimerTab), keyEquivalent: "")
        menu.addItem(withTitle: "File Shelf & Clipboard", action: #selector(openShelfTab), keyEquivalent: "")
        menu.addItem(withTitle: "System Stats", action: #selector(openSystemTab), keyEquivalent: "")
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Switch Position (Menu Bar / Below)", action: #selector(switchPlacement), keyEquivalent: "")
        let fsItem = NSMenuItem(title: "Auto-hide with Menu Bar", action: #selector(toggleHideInFullScreen), keyEquivalent: "")
        fsItem.state = state.hideInFullScreen ? .on : .off
        menu.addItem(fsItem)
        self.hideInFullScreenMenuItem = fsItem
        let loginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        loginItem.state = state.launchAtLogin ? .on : .off
        menu.addItem(loginItem)
        self.launchAtLoginMenuItem = loginItem
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Quit AirIsland", action: #selector(quitApp), keyEquivalent: "q")

        for menuItem in menu.items {
            menuItem.target = self
        }

        item.menu = menu
        self.statusItem = item
        self.windowController?.statusItem = item
    }

    private func setupInputMonitors() {
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self = self, self.state.isExpanded else { return }
            let location = NSEvent.mouseLocation
            if self.windowController?.containsScreenPoint(location) == false {
                DispatchQueue.main.async {
                    self.state.collapse()
                }
            }
        }

        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53, self?.state.isExpanded == true { // Escape
                self?.state.collapse()
                return nil
            }
            return event
        }
    }

    func menuWillOpen(_ menu: NSMenu) {
        hideInFullScreenMenuItem?.state = state.hideInFullScreen ? .on : .off
        launchAtLoginMenuItem?.state = state.launchAtLogin ? .on : .off
    }

    private func syncMenuBarAppearance(from button: NSStatusBarButton) {
        let name = button.effectiveAppearance.name.rawValue.lowercased()
        let isDark: Bool
        if name.contains("dark") {
            isDark = true
        } else if name.contains("aqua") {
            isDark = false
        } else {
            isDark = UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark"
        }
        state.menuBarIsDark = isDark
    }

    @objc private func toggleIsland() {
        if state.isExpanded {
            state.collapse()
        } else {
            state.expand(forceReveal: true)
        }
    }

    @objc private func openMusicTab() {
        state.expand(to: .nowPlaying, forceReveal: true)
    }

    @objc private func openTimerTab() {
        state.expand(to: .timer, forceReveal: true)
    }

    @objc private func openShelfTab() {
        state.expand(to: .shelf, forceReveal: true)
    }

    @objc private func openSystemTab() {
        state.expand(to: .system, forceReveal: true)
    }

    @objc private func switchPlacement() {
        state.placement = (state.placement == .menuBar) ? .belowMenuBar : .menuBar
    }

    @objc private func toggleHideInFullScreen() {
        state.hideInFullScreen.toggle()
        hideInFullScreenMenuItem?.state = state.hideInFullScreen ? .on : .off
    }

    @objc private func toggleLaunchAtLogin() {
        state.launchAtLogin.toggle()
        launchAtLoginMenuItem?.state = state.launchAtLogin ? .on : .off
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}
