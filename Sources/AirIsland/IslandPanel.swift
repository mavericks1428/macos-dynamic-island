import Cocoa
import SwiftUI

final class IslandPanel: NSPanel {
    var allowKeyFocus: Bool = false
    override var canBecomeKey: Bool { allowKeyFocus }
    override var canBecomeMain: Bool { false }
}

final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true
    }
}

final class IslandWindowController {
    let panel: IslandPanel
    private let state: IslandState
    private let media: MediaController
    private let timer: TimerController
    private let shelf: ShelfAndClipboardStore
    private let systemStats: SystemStatsMonitor

    // Fixed panel canvas — never resized during morph animations so there is zero frame lag or late background
    private let canvasSize = CGSize(width: 492, height: 336)
    private let topCanvasPadding: CGFloat = 2

    private var globalMouseMonitor: Any?
    private var localMouseMonitor: Any?
    private var hitTestTimer: Timer?
    private var spaceCheckTimer: Timer?
    private var hoverExpandWorkItem: DispatchWorkItem?
    private var menuBarRevealWorkItem: DispatchWorkItem?
    private var menuBarHideWorkItem: DispatchWorkItem?
    private var resignKeyWorkItem: DispatchWorkItem?
    private var observers: [NSObjectProtocol] = []
    private var workspaceObservers: [NSObjectProtocol] = []

    private var lastMouseInteractiveState: Bool = false
    private var requiresMenuBarAutoReveal: Bool = false
    private var forceHideSystemOverlay: Bool = false
    private var isMenuBarPulledDown: Bool = false
    weak var statusItem: NSStatusItem?

    init(
        state: IslandState,
        media: MediaController,
        timer: TimerController,
        shelf: ShelfAndClipboardStore,
        systemStats: SystemStatsMonitor
    ) {
        self.state = state
        self.media = media
        self.timer = timer
        self.shelf = shelf
        self.systemStats = systemStats

        let initialFrame = NSRect(origin: .zero, size: canvasSize)
        self.panel = IslandPanel(
            contentRect: initialFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        configurePanel()
        applyAppearance()
        bindStateCallbacks()

        let rootView = IslandContainerView(
            state: state,
            media: media,
            timer: timer,
            shelf: shelf,
            systemStats: systemStats
        )
        let hostingView = FirstMouseHostingView(rootView: rootView)
        panel.contentView = hostingView

        repositionPanelFrame()
        panel.ignoresMouseEvents = true
        panel.alphaValue = 1.0
        panel.orderFrontRegardless()

        installMouseTracking()
        installSpaceAndScreenObservers()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.evaluateMenuBarContext()
        }
    }

    deinit {
        hoverExpandWorkItem?.cancel()
        menuBarRevealWorkItem?.cancel()
        menuBarHideWorkItem?.cancel()
        resignKeyWorkItem?.cancel()
        if let monitor = globalMouseMonitor {
            NSEvent.removeMonitor(monitor)
        }
        if let monitor = localMouseMonitor {
            NSEvent.removeMonitor(monitor)
        }
        hitTestTimer?.invalidate()
        spaceCheckTimer?.invalidate()
        for obs in observers {
            NotificationCenter.default.removeObserver(obs)
        }
        for obs in workspaceObservers {
            NSWorkspace.shared.notificationCenter.removeObserver(obs)
        }
    }

    private func configurePanel() {
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 3)
        // Must include .fullScreenAuxiliary so the island can slide down WITH the Menu Bar inside Full-Screen Spaces
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.animationBehavior = .none
        panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate = false
        panel.acceptsMouseMovedEvents = true
        panel.ignoresMouseEvents = true
    }

    private func bindStateCallbacks() {
        state.onGeometryChanged = { [weak self] in
            guard let self = self else { return }
            if self.state.isExpanded {
                self.resignKeyWorkItem?.cancel()
                self.resignKeyWorkItem = nil
                self.panel.allowKeyFocus = true
                if !self.panel.isKeyWindow {
                    self.panel.makeKey()
                }
            } else {
                self.panel.allowKeyFocus = false
                if self.panel.isKeyWindow {
                    // Defer resigning key status until after the shrink spring finishes;
                    // synchronous orderOut(nil) aborts CoreAnimation mid-collapse and makes shrinking snap.
                    self.resignKeyWorkItem?.cancel()
                    let work = DispatchWorkItem { [weak self] in
                        guard let self = self else { return }
                        self.resignKeyWorkItem = nil
                        guard !self.state.isExpanded, !self.state.isHiddenForFullScreen, self.panel.isKeyWindow else { return }
                        self.panel.orderOut(nil)
                        self.panel.orderFrontRegardless()
                    }
                    self.resignKeyWorkItem = work
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.68, execute: work)
                }
                if self.requiresMenuBarAutoReveal {
                    self.evaluatePointerMenuBarReveal(mouse: NSEvent.mouseLocation)
                }
            }
            self.updatePointerInteraction()
        }
        state.onToastDismissed = { [weak self] in
            guard let self = self else { return }
            if self.requiresMenuBarAutoReveal && !self.state.isExpanded {
                self.evaluatePointerMenuBarReveal(mouse: NSEvent.mouseLocation, immediate: true)
            }
        }
        state.onLayoutChanged = { [weak self] in
            self?.repositionPanelFrame()
            self?.updatePointerInteraction()
        }
        state.onFullScreenSettingChanged = { [weak self] in
            self?.evaluateMenuBarContext()
        }
        state.onAppearanceChanged = { [weak self] in
            self?.applyAppearance()
        }
    }

    private func applyAppearance() {
        panel.appearance = NSAppearance(named: state.resolvedIsDark ? .darkAqua : .aqua)
    }

    private func installSpaceAndScreenObservers() {
        let screenObs = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.repositionPanelFrame()
            self?.evaluateMenuBarContext()
        }
        observers.append(screenObs)

        let spaceObs = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleSpaceDidChange()
        }
        workspaceObservers.append(spaceObs)

        let appObs = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.scheduleMenuBarContextChecks()
        }
        workspaceObservers.append(appObs)

        let timer = Timer(timeInterval: 0.35, repeats: true) { [weak self] _ in
            self?.evaluateMenuBarContext()
        }
        RunLoop.main.add(timer, forMode: .common)
        spaceCheckTimer = timer
    }

    private func handleSpaceDidChange() {
        if state.isExpanded {
            state.collapse()
        }
        isMenuBarPulledDown = false
        menuBarRevealWorkItem?.cancel()
        menuBarRevealWorkItem = nil
        menuBarHideWorkItem?.cancel()
        menuBarHideWorkItem = nil
        scheduleMenuBarContextChecks()
    }

    private func scheduleMenuBarContextChecks() {
        evaluateMenuBarContext()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.evaluateMenuBarContext()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            self?.evaluateMenuBarContext()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.70) { [weak self] in
            self?.evaluateMenuBarContext()
        }
    }

    private func installMouseTracking() {
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged]
        ) { [weak self] _ in
            self?.handlePointerActivity()
        }

        localMouseMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .mouseExited]
        ) { [weak self] event in
            self?.handlePointerActivity()
            return event
        }
    }

    private func handlePointerActivity() {
        if requiresMenuBarAutoReveal {
            evaluatePointerMenuBarReveal(mouse: NSEvent.mouseLocation)
        }
        updatePointerInteraction()
        updatePointerGlow()
    }

    /// Publish the pointer's position relative to the visible island so the specular
    /// sheen can trail the cursor (normalised 0…1, top-left origin).
    private func updatePointerGlow() {
        guard !state.isHiddenForFullScreen else { return }
        let rect = currentPillScreenRect()
        guard rect.width > 1, rect.height > 1, rect.contains(NSEvent.mouseLocation) else { return }
        let mouse = NSEvent.mouseLocation
        state.pointerGlow.update(
            x: (mouse.x - rect.minX) / rect.width,
            y: (rect.maxY - mouse.y) / rect.height
        )
    }

    private func repositionPanelFrame() {
        let screen = NSScreen.screens.first ?? NSScreen.main
        guard let screen = screen else { return }

        let anchorTopY: CGFloat
        switch state.placement {
        case .menuBar:
            anchorTopY = screen.frame.maxY - 1
        case .belowMenuBar:
            anchorTopY = screen.visibleFrame.maxY - 6
        }

        let originX = round(screen.frame.midX - (canvasSize.width / 2.0))
        let originY = round((anchorTopY + topCanvasPadding) - canvasSize.height)
        panel.setFrame(NSRect(origin: NSPoint(x: originX, y: originY), size: canvasSize), display: true)
    }

    // MARK: - Live Hit-Testing & Smooth Pointer Hover

    private func currentVisiblePillSize() -> CGSize {
        state.currentPillSize(hasTrack: media.hasTrack, timerRunning: timer.isRunning)
    }

    func currentPillScreenRect(paddedForDrag: Bool = false) -> NSRect {
        let size = currentVisiblePillSize()
        let originX = panel.frame.midX - (size.width / 2.0)
        let originY = (panel.frame.maxY - topCanvasPadding) - size.height
        var rect = NSRect(x: originX, y: originY, width: size.width, height: size.height)
        if paddedForDrag {
            rect = rect.insetBy(dx: -18, dy: -14)
        } else if state.isExpanded {
            rect = rect.insetBy(dx: -6, dy: -6)
        } else {
            rect = rect.insetBy(dx: -4, dy: -4)
        }
        return rect
    }

    func updatePointerInteraction() {
        if state.isHiddenForFullScreen {
            if !panel.ignoresMouseEvents {
                panel.ignoresMouseEvents = true
                lastMouseInteractiveState = false
            }
            setHoverState(false)
            stopFallbackHitTimer()
            return
        }

        let mouse = NSEvent.mouseLocation
        let isDraggingMouse = (NSEvent.pressedMouseButtons & 1) != 0 && !state.isExpanded
        let targetRect = currentPillScreenRect(paddedForDrag: isDraggingMouse)
        let isInside = targetRect.contains(mouse)

        if isInside != lastMouseInteractiveState || panel.ignoresMouseEvents == isInside {
            lastMouseInteractiveState = isInside
            panel.ignoresMouseEvents = !isInside
        }

        if !state.isExpanded && state.toast == nil {
            setHoverState(isInside)
        } else if state.isExpanded && state.isHovered {
            // Clear hover cleanly without launching a competing hover-collapse spring mid-expand
            hoverExpandWorkItem?.cancel()
            hoverExpandWorkItem = nil
            state.isHovered = false
        }

        if isInside || state.isExpanded || (requiresMenuBarAutoReveal && isMenuBarPulledDown) {
            ensureFallbackHitTimer()
        } else {
            stopFallbackHitTimer()
        }
    }

    private func setHoverState(_ hovering: Bool) {
        if !hovering {
            state.pointerGlow.reset(expanded: state.isExpanded)
        }
        if state.isHovered != hovering {
            withAnimation(IslandMotion.hover(hovering)) {
                state.isHovered = hovering
            }
        }

        if hovering && state.openOnHover && !state.isExpanded && state.toast == nil && !state.isHiddenForFullScreen {
            if hoverExpandWorkItem == nil {
                let work = DispatchWorkItem { [weak self] in
                    guard let self = self else { return }
                    self.hoverExpandWorkItem = nil
                    guard self.state.isHovered, self.state.openOnHover, !self.state.isExpanded, !self.state.isHiddenForFullScreen else { return }
                    self.state.expand()
                }
                hoverExpandWorkItem = work
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.22, execute: work)
            }
        } else if !hovering {
            hoverExpandWorkItem?.cancel()
            hoverExpandWorkItem = nil
        }
    }

    private func ensureFallbackHitTimer() {
        guard hitTestTimer == nil else { return }
        hitTestTimer = Timer.scheduledTimer(withTimeInterval: 0.12, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            let mouse = NSEvent.mouseLocation
            if self.requiresMenuBarAutoReveal {
                self.evaluatePointerMenuBarReveal(mouse: mouse)
            }
            let isDraggingMouse = (NSEvent.pressedMouseButtons & 1) != 0 && !self.state.isExpanded
            let inside = self.currentPillScreenRect(paddedForDrag: isDraggingMouse).contains(mouse)
            if !inside {
                if !self.panel.ignoresMouseEvents {
                    self.panel.ignoresMouseEvents = true
                    self.lastMouseInteractiveState = false
                }
                if self.state.isHovered {
                    self.setHoverState(false)
                }
                if !self.state.isExpanded && !(self.requiresMenuBarAutoReveal && self.isMenuBarPulledDown) {
                    self.stopFallbackHitTimer()
                }
            }
        }
    }

    private func stopFallbackHitTimer() {
        hitTestTimer?.invalidate()
        hitTestTimer = nil
    }

    func containsScreenPoint(_ point: NSPoint) -> Bool {
        currentPillScreenRect(paddedForDrag: false).contains(point)
    }

    // MARK: - Full-Screen / Spaces / Notification Center Sync

    private struct ScreenVisibilityContext {
        var requiresAutoReveal: Bool
        var forceHideOverlay: Bool
        var menuBarHardHidden: Bool
    }

    private func evaluateMenuBarContext() {
        guard let screen = NSScreen.screens.first ?? NSScreen.main else { return }
        let context = evaluateScreenContext(on: screen)

        if context.forceHideOverlay {
            forceHideSystemOverlay = true
            isMenuBarPulledDown = false
            menuBarRevealWorkItem?.cancel()
            menuBarRevealWorkItem = nil
            menuBarHideWorkItem?.cancel()
            menuBarHideWorkItem = nil
            if state.isExpanded {
                state.collapse()
            }
            setIslandVisible(false)
            return
        }

        let overlayJustClosed = forceHideSystemOverlay
        forceHideSystemOverlay = false

        guard state.hideInFullScreen else {
            requiresMenuBarAutoReveal = false
            isMenuBarPulledDown = false
            menuBarRevealWorkItem?.cancel()
            menuBarRevealWorkItem = nil
            menuBarHideWorkItem?.cancel()
            menuBarHideWorkItem = nil
            setIslandVisible(true)
            return
        }

        if context.requiresAutoReveal {
            let enteredAutoHide = !requiresMenuBarAutoReveal
            requiresMenuBarAutoReveal = true

            if context.menuBarHardHidden {
                isMenuBarPulledDown = false
                menuBarRevealWorkItem?.cancel()
                menuBarRevealWorkItem = nil
                if state.isExpanded {
                    state.collapse()
                }
                setIslandVisible(false)
                return
            }

            if enteredAutoHide || overlayJustClosed {
                if enteredAutoHide && state.isExpanded {
                    state.collapse()
                }
                isMenuBarPulledDown = false
                evaluatePointerMenuBarReveal(mouse: NSEvent.mouseLocation, immediate: true)
            } else if !isMenuBarPulledDown && !state.isHiddenForFullScreen && !state.isExpanded && state.toast == nil {
                evaluatePointerMenuBarReveal(mouse: NSEvent.mouseLocation, immediate: true)
            } else {
                evaluatePointerMenuBarReveal(mouse: NSEvent.mouseLocation)
            }
        } else {
            requiresMenuBarAutoReveal = false
            menuBarRevealWorkItem?.cancel()
            menuBarRevealWorkItem = nil
            menuBarHideWorkItem?.cancel()
            menuBarHideWorkItem = nil
            isMenuBarPulledDown = false
            setIslandVisible(true)
        }
    }

    private func evaluatePointerMenuBarReveal(mouse: NSPoint, immediate: Bool = false) {
        guard !forceHideSystemOverlay,
              requiresMenuBarAutoReveal,
              let screen = NSScreen.screens.first ?? NSScreen.main else {
            return
        }

        let screenTop = screen.frame.maxY
        // Exclude far-right corner where users click Clock / Notification Center / Control Center
        let inMenuTriggerX = mouse.x >= screen.frame.minX && mouse.x <= screen.frame.maxX - 52.0
        let inScreenX = mouse.x >= screen.frame.minX && mouse.x <= screen.frame.maxX
        let atTopTriggerEdge = inMenuTriggerX && mouse.y >= screenTop - 4.0
        let insideMenuStripOrPill = (inScreenX && mouse.y >= screenTop - 32.0)
            || currentPillScreenRect(paddedForDrag: false).contains(mouse)
            || state.isExpanded

        if !isMenuBarPulledDown {
            if state.isExpanded {
                menuBarHideWorkItem?.cancel()
                menuBarHideWorkItem = nil
                isMenuBarPulledDown = true
                setIslandVisible(true)
                return
            }

            if atTopTriggerEdge {
                if menuBarRevealWorkItem == nil {
                    let delay: TimeInterval = immediate ? 0.0 : 0.10
                    let work = DispatchWorkItem { [weak self] in
                        guard let self = self else { return }
                        self.menuBarRevealWorkItem = nil
                        guard !self.forceHideSystemOverlay, self.requiresMenuBarAutoReveal else { return }
                        let currentMouse = NSEvent.mouseLocation
                        if currentMouse.y >= screenTop - 28.0 && currentMouse.x <= screen.frame.maxX - 52.0 {
                            self.isMenuBarPulledDown = true
                            self.setIslandVisible(true)
                        }
                    }
                    menuBarRevealWorkItem = work
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
                }
            } else {
                menuBarRevealWorkItem?.cancel()
                menuBarRevealWorkItem = nil
                if immediate && state.toast == nil {
                    setIslandVisible(false)
                }
            }
        } else {
            if insideMenuStripOrPill {
                menuBarHideWorkItem?.cancel()
                menuBarHideWorkItem = nil
            } else if menuBarHideWorkItem == nil {
                let work = DispatchWorkItem { [weak self] in
                    guard let self = self else { return }
                    self.menuBarHideWorkItem = nil
                    guard self.requiresMenuBarAutoReveal, !self.state.isExpanded, self.state.toast == nil else { return }
                    let currentMouse = NSEvent.mouseLocation
                    let stillInside = (currentMouse.y >= screenTop - 32.0)
                        || self.currentPillScreenRect(paddedForDrag: false).contains(currentMouse)
                    if !stillInside {
                        self.isMenuBarPulledDown = false
                        self.setIslandVisible(false)
                    }
                }
                menuBarHideWorkItem = work
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.28, execute: work)
            }
        }
    }

    private func cgScreenBounds(for screen: NSScreen) -> CGRect {
        if let num = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
            let displayID = CGDirectDisplayID(num.uint32Value)
            let bounds = CGDisplayBounds(displayID)
            if !bounds.isEmpty {
                return bounds
            }
        }
        return CGRect(x: 0, y: 0, width: screen.frame.width, height: screen.frame.height)
    }

    private func evaluateScreenContext(on screen: NSScreen) -> ScreenVisibilityContext {
        var requiresAutoReveal = false
        var forceHideOverlay = false
        var menuBarHardHidden = false

        // 1. Desktop auto-hide Menu Bar enabled in System Preferences
        if (screen.frame.maxY - screen.visibleFrame.maxY) < 8.0 {
            requiresAutoReveal = true
        }

        // 2. macOS global presentation state for active Full-Screen apps / Spaces / Presentation mode
        let sysOpts = NSApp.currentSystemPresentationOptions
        if sysOpts.contains(.hideMenuBar) {
            requiresAutoReveal = true
            menuBarHardHidden = true
        }
        if sysOpts.contains(.fullScreen) || sysOpts.contains(.autoHideMenuBar) {
            requiresAutoReveal = true
        }

        // 3. Status bar window slid off the top edge by macOS Menu Bar auto-hide
        if let sbWin = statusItem?.button?.window,
           sbWin.frame.height > 4,
           sbWin.frame.maxX > screen.frame.minX,
           sbWin.frame.minX < screen.frame.maxX,
           sbWin.frame.minY >= screen.frame.maxY - 4,
           sbWin.frame.minY <= screen.frame.maxY + 40 {
            requiresAutoReveal = true
        }

        // 4. Live onscreen non-desktop CGWindow inspection (Full-Screen Spaces, Browser Full-Screen Video, Notification Center, Mission Control, Control Center, Spotlight)
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return ScreenVisibilityContext(
                requiresAutoReveal: requiresAutoReveal,
                forceHideOverlay: forceHideOverlay,
                menuBarHardHidden: menuBarHardHidden
            )
        }

        let screenCG = cgScreenBounds(for: screen)
        let targetW = screenCG.width
        let targetH = screenCG.height
        let statusLevel = Int(CGWindowLevelForKey(.statusWindow))

        for info in list {
            let owner = info[kCGWindowOwnerName as String] as? String ?? ""
            if owner == "AirIsland" || owner == "Window Server" { continue }

            let layer = info[kCGWindowLayer as String] as? Int ?? 0
            let alpha = info[kCGWindowAlpha as String] as? Double ?? 1.0
            let isOnscreen = (info[kCGWindowIsOnscreen as String] as? Bool) ?? true
            guard isOnscreen, alpha > 0.05, layer >= 0 else { continue }

            guard let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict),
                  bounds.intersects(screenCG) else {
                continue
            }

            // Notification Center sidebar/widgets drawer on the right side (never dormant Desktop helper windows)
            if owner == "NotificationCenter" || owner == "Notification Center" {
                if layer >= 18
                    && alpha >= 0.85
                    && bounds.width >= 300 && bounds.width <= 460
                    && bounds.height >= 360
                    && bounds.minX >= screenCG.maxX - 480
                    && bounds.maxX <= screenCG.maxX + 6 {
                    forceHideOverlay = true
                }
                continue
            }

            // Control Center popover/drawer (ignore small top-right status icons <= 36pt)
            if owner == "ControlCenter" || owner == "Control Center" {
                if layer >= 18
                    && alpha >= 0.85
                    && bounds.height >= 100 && bounds.height <= 750
                    && bounds.width >= 160 && bounds.width <= 480 {
                    forceHideOverlay = true
                }
                continue
            }

            // Spotlight search bar
            if owner == "Spotlight" {
                if layer >= 18
                    && alpha >= 0.85
                    && bounds.height >= 48 && bounds.height <= 650
                    && bounds.width >= 320 && bounds.width <= 800 {
                    forceHideOverlay = true
                }
                continue
            }

            // Mission Control top Space bar & Launchpad (never full-screen Desktop Dock backdrops or bottom/side Dock bar)
            if owner == "Dock" {
                let winName = info[kCGWindowName as String] as? String
                if winName == "Mission Control" || winName == "Launchpad" {
                    forceHideOverlay = true
                } else if layer >= 18
                            && alpha >= 0.75
                            && bounds.minY <= screenCG.minY + 12
                            && bounds.height >= 70 && bounds.height <= 240
                            && bounds.width >= targetW * 0.70 {
                    forceHideOverlay = true
                }
                continue
            }

            // Lock Screen / Screen Saver
            if owner == "loginwindow" || owner == "ScreenSaverEngine" {
                if bounds.width >= targetW - 8 && bounds.height >= targetH - 8 {
                    forceHideOverlay = true
                }
                continue
            }

            // Full-Screen App or Full-Screen Browser Video across any layer >= 0
            if abs(bounds.minX - screenCG.minX) <= 6
                && abs(bounds.minY - screenCG.minY) <= 6
                && bounds.width >= targetW - 6
                && bounds.height >= targetH - 6 {
                requiresAutoReveal = true
                if layer >= statusLevel {
                    forceHideOverlay = true
                }
            }
        }

        return ScreenVisibilityContext(
            requiresAutoReveal: requiresAutoReveal,
            forceHideOverlay: forceHideOverlay,
            menuBarHardHidden: menuBarHardHidden
        )
    }

    private func setIslandVisible(_ visible: Bool) {
        let shouldHide = !visible
        if state.isHiddenForFullScreen == shouldHide {
            return
        }

        if shouldHide {
            hoverExpandWorkItem?.cancel()
            hoverExpandWorkItem = nil
            resignKeyWorkItem?.cancel()
            resignKeyWorkItem = nil
            panel.ignoresMouseEvents = true
            lastMouseInteractiveState = false
            withAnimation(IslandMotion.resolved(.spring(response: 0.42, dampingFraction: 0.90, blendDuration: 0.10))) {
                state.isHiddenForFullScreen = true
                state.isHovered = false
            }
        } else {
            panel.orderFrontRegardless()
            withAnimation(IslandMotion.resolved(.spring(response: 0.34, dampingFraction: 0.86, blendDuration: 0.08))) {
                state.isHiddenForFullScreen = false
            }
            updatePointerInteraction()
        }
    }
}
