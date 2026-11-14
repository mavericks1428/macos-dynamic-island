import Cocoa
import Darwin
import SwiftUI

struct LyricLine: Identifiable, Equatable {
    let id: Int
    let time: Double
    let text: String
}

final class MediaController: ObservableObject {
    final class PlaybackClock: ObservableObject {
        @Published var elapsedTime: Double = 0
        @Published var duration: Double = 0
    }

    let clock = PlaybackClock()

    @Published var title: String = ""
    @Published var artist: String = ""
    @Published var album: String = ""
    @Published var artwork: NSImage? = nil
    @Published var accentColor: Color = Color(red: 0.38, green: 0.78, blue: 1.00)
    @Published var secondaryColor: Color = Color(red: 0.62, green: 0.44, blue: 1.00)
    @Published var themeBackdropTop: Color = Color(red: 0.14, green: 0.22, blue: 0.38)
    @Published var themeBackdropBottom: Color = Color(red: 0.14, green: 0.10, blue: 0.28)
    @Published var isPlaying: Bool = false
    @Published var duration: Double = 0
    var elapsedTime: Double = 0

    // Synced Lyrics state
    @Published var lyricLines: [LyricLine] = []
    @Published var plainLyricsLines: [String] = []
    @Published var isLyricsLoading: Bool = false
    @Published var lyricsStatusMessage: String? = nil
    @Published var activeLyricIndex: Int? = nil
    @Published var lyricSyncOffset: Double = 0.0

    var hasTrack: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var hasSyncedLyrics: Bool {
        lyricLines.contains { !$0.text.isEmpty }
    }

    var onTrackChanged: ((String, String, Color) -> Void)?

    private var mrHandle: UnsafeMutableRawPointer?
    private typealias RegisterFn = @convention(c) (DispatchQueue) -> Void
    private typealias GetInfoFn = @convention(c) (DispatchQueue, @escaping @convention(block) (NSDictionary?) -> Void) -> Void
    private typealias GetIsPlayingFn = @convention(c) (DispatchQueue, @escaping @convention(block) (DarwinBoolean) -> Void) -> Void
    private typealias GetPIDFn = @convention(c) (DispatchQueue, @escaping @convention(block) (Int32) -> Void) -> Void
    private typealias SendCommandFn = @convention(c) (UInt32, AnyObject?) -> DarwinBoolean
    private typealias SetElapsedFn = @convention(c) (Double) -> Void

    private var registerFn: RegisterFn?
    private var getInfoFn: GetInfoFn?
    private var getIsPlayingFn: GetIsPlayingFn?
    private var getPIDFn: GetPIDFn?
    private var sendCommandFn: SendCommandFn?
    private var setElapsedFn: SetElapsedFn?

    private var infoTimestamp: Date = Date()
    private var baseElapsed: Double = 0
    private var playbackRateFactor: Double = 1.0
    private var sawFractionalPosition: Bool = false
    private var lastObservedRawPosition: Double? = nil
    private var lastRawPositionAdvanceDate: Date = Date()
    private var consecutiveDriftDirection: Int = 0
    private var consecutiveDriftCount: Int = 0
    private var lastDirectSyncDate: Date = .distantPast
    private var lastMediaRemoteRawElapsed: Double? = nil
    private var lastLyricsDurationQueried: Double = 0
    private var lastCommandPlayStateOverride: (isPlaying: Bool, date: Date)? = nil
    private var progressTimer: Timer?
    private var liveSyncTimer: Timer?
    private var activePlayerBundleID: String? = nil
    private var lastAnnouncedKey: String = ""
    private var currentTrackKey: String = ""
    private var artworkCache: [String: NSImage] = [:]
    private var observers: [NSObjectProtocol] = []

    private struct CachedLyrics {
        let synced: [LyricLine]
        let plain: [String]
        let statusMessage: String?
    }

    private var lyricsCache: [String: CachedLyrics] = [:]
    private var lyricOffsetsByTrack: [String: Double] = [:]
    private var activeLyricsTask: URLSessionDataTask?
    private var lyricsRequestToken = UUID()
    private var lyricsAutoFetchEnabled: Bool = false
    private var compiledLiveScripts: [String: NSAppleScript] = [:]

    private let defaultAccent = Color(red: 0.38, green: 0.78, blue: 1.00)
    private let defaultSecondary = Color(red: 0.62, green: 0.44, blue: 1.00)
    private let defaultBackdropTop = Color(red: 0.14, green: 0.22, blue: 0.38)
    private let defaultBackdropBottom = Color(red: 0.14, green: 0.10, blue: 0.28)

    init() {
        loadMediaRemote()
        registerNotifications()
        refreshNowPlaying()
    }

    deinit {
        progressTimer?.invalidate()
        liveSyncTimer?.invalidate()
        activeLyricsTask?.cancel()
        for obs in observers {
            NotificationCenter.default.removeObserver(obs)
        }
        if let mrHandle = mrHandle {
            dlclose(mrHandle)
        }
    }

    private func loadMediaRemote() {
        let path = "/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote"
        guard let handle = dlopen(path, RTLD_LAZY) else { return }
        mrHandle = handle

        if let sym = dlsym(handle, "MRMediaRemoteRegisterForNowPlayingNotifications") {
            registerFn = unsafeBitCast(sym, to: RegisterFn.self)
        }
        if let sym = dlsym(handle, "MRMediaRemoteGetNowPlayingInfo") {
            getInfoFn = unsafeBitCast(sym, to: GetInfoFn.self)
        }
        if let sym = dlsym(handle, "MRMediaRemoteGetNowPlayingApplicationIsPlaying") {
            getIsPlayingFn = unsafeBitCast(sym, to: GetIsPlayingFn.self)
        }
        if let sym = dlsym(handle, "MRMediaRemoteGetNowPlayingApplicationPID") {
            getPIDFn = unsafeBitCast(sym, to: GetPIDFn.self)
        }
        if let sym = dlsym(handle, "MRMediaRemoteSendCommand") {
            sendCommandFn = unsafeBitCast(sym, to: SendCommandFn.self)
        }
        if let sym = dlsym(handle, "MRMediaRemoteSetElapsedTime") {
            setElapsedFn = unsafeBitCast(sym, to: SetElapsedFn.self)
        }
    }

    private func resolveNotificationName(_ symbol: String, fallback: String) -> Notification.Name {
        if let handle = mrHandle, let sym = dlsym(handle, symbol) {
            if let cfStr = sym.assumingMemoryBound(to: CFString?.self).pointee {
                return Notification.Name(cfStr as String)
            }
        }
        return Notification.Name(fallback)
    }

    private func registerNotifications() {
        registerFn?(DispatchQueue.main)

        let names = [
            resolveNotificationName("kMRMediaRemoteNowPlayingInfoDidChangeNotification", fallback: "kMRMediaRemoteNowPlayingInfoDidChangeNotification"),
            resolveNotificationName("kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification", fallback: "kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification"),
            resolveNotificationName("kMRMediaRemoteNowPlayingApplicationDidChangeNotification", fallback: "kMRMediaRemoteNowPlayingApplicationDidChangeNotification")
        ]

        for name in names {
            let obs = NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.refreshNowPlaying()
            }
            observers.append(obs)
        }
    }

    func setProgressUpdatesActive(_ active: Bool, highPrecision: Bool = false) {
        progressTimer?.invalidate()
        progressTimer = nil
        liveSyncTimer?.invalidate()
        liveSyncTimer = nil
        lyricsAutoFetchEnabled = highPrecision
        guard active else { return }

        updateInterpolatedElapsed()
        let interval: TimeInterval = highPrecision ? 0.04 : 1.0
        let pTimer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            self?.updateInterpolatedElapsed()
        }
        RunLoop.main.add(pTimer, forMode: .common)
        progressTimer = pTimer

        if highPrecision {
            syncPlaybackPositionDirectly()
            let sTimer = Timer(timeInterval: 0.35, repeats: true) { [weak self] _ in
                self?.syncPlaybackPositionDirectly()
            }
            RunLoop.main.add(sTimer, forMode: .common)
            liveSyncTimer = sTimer
        }
    }

    private func updateInterpolatedElapsed() {
        if isPlaying {
            let delta = max(0, Date().timeIntervalSince(infoTimestamp)) * playbackRateFactor
            let raw = baseElapsed + delta
            let updated = duration > 0 ? min(duration, raw) : raw
            elapsedTime = updated
            if abs(clock.elapsedTime - updated) >= 0.14 {
                clock.elapsedTime = updated
            }
        }
        updateActiveLyricIndex()
    }

    private func syncPlaybackPositionDirectly() {
        guard hasTrack else { return }
        let trackKey = currentTrackKey
        let expectedTitle = title
        let candidates = directPlayerCandidates()

        if !candidates.isEmpty {
            // NSAppleScript is strictly main-thread-only per Apple docs; pre-compiled scripts execute in ~1-3ms
            for appName in candidates {
                let start = Date()
                if let live = queryLivePlayerState(app: appName),
                   titlesRoughlyMatch(live.trackTitle, expectedTitle) {
                    let rtt = Date().timeIntervalSince(start)
                    let frac = abs(live.position - round(live.position)) > 0.002
                    let adjustedPos = live.position + (live.isPlaying ? min(0.06, rtt * 0.50) : 0)
                    reconcileLivePlayback(
                        isPlaying: live.isPlaying,
                        position: adjustedPos,
                        isDirectPlayerQuery: true,
                        isFractional: frac
                    )
                    return
                }
            }
            pollMediaRemotePosition(trackKey: trackKey)
            return
        }

        pollMediaRemotePosition(trackKey: trackKey)
    }

    private func directPlayerCandidates() -> [String] {
        let running = Set(NSWorkspace.shared.runningApplications.compactMap { $0.bundleIdentifier })
        if activePlayerBundleID == "com.spotify.client", running.contains("com.spotify.client") {
            return ["Spotify"]
        }
        if activePlayerBundleID == "com.apple.Music", running.contains("com.apple.Music") {
            return ["Music"]
        }
        if let activeID = activePlayerBundleID, activeID != "com.spotify.client", activeID != "com.apple.Music" {
            // Active player is explicitly a browser or third-party app — use MediaRemote, not background Spotify/Music
            return []
        }
        var list: [String] = []
        if running.contains("com.spotify.client") { list.append("Spotify") }
        if running.contains("com.apple.Music") { list.append("Music") }
        return list
    }

    private func pollMediaRemotePosition(trackKey: String) {
        guard let getInfo = getInfoFn else { return }
        getInfo(DispatchQueue.main) { [weak self] nsDict in
            guard let self = self,
                  self.currentTrackKey == trackKey,
                  let dict = nsDict as? [String: Any] else { return }
            let rawElapsedVal = (dict["kMRMediaRemoteNowPlayingInfoElapsedTime"] as? NSNumber)?.doubleValue
            let rawElapsed = (rawElapsedVal?.isFinite == true && (rawElapsedVal ?? -1) >= 0) ? rawElapsedVal : nil
            let rawRate = (dict["kMRMediaRemoteNowPlayingInfoPlaybackRate"] as? NSNumber)?.doubleValue
            let rawTimestamp = dict["kMRMediaRemoteNowPlayingInfoTimestamp"] as? Date

            if let r = rawRate, r.isFinite, r > 0.05 {
                self.playbackRateFactor = min(4.0, max(0.25, r))
            }

            let applyMR: (Bool) -> Void = { playing in
                guard self.currentTrackKey == trackKey else { return }
                if let rawElapsed = rawElapsed {
                    if let ts = rawTimestamp {
                        let age = Date().timeIntervalSince(ts)
                        if age >= -1.0 && age < 7200 {
                            let pos = rawElapsed + (playing ? max(0, age) * self.playbackRateFactor : 0)
                            self.lastMediaRemoteRawElapsed = rawElapsed
                            self.reconcileLivePlayback(isPlaying: playing, position: pos, isFractional: true)
                            return
                        }
                    }

                    let prevRaw = self.lastMediaRemoteRawElapsed
                    self.lastMediaRemoteRawElapsed = rawElapsed
                    let isFrac = abs(rawElapsed - round(rawElapsed)) > 0.002

                    if isFrac || self.sawFractionalPosition {
                        self.reconcileLivePlayback(isPlaying: playing, position: rawElapsed, isFractional: isFrac)
                    } else {
                        // Integer-quantized browser tick: advance smoothly, but also catch stalls & rewinds
                        let changed = prevRaw == nil || abs(rawElapsed - (prevRaw ?? rawElapsed)) > 0.35
                        let stalledFor = Date().timeIntervalSince(self.lastRawPositionAdvanceDate)
                        if changed || !playing || self.isPlaying != playing || (playing && stalledFor >= 1.35) || (self.elapsedTime - rawElapsed) >= 1.15 {
                            self.reconcileLivePlayback(isPlaying: playing, position: rawElapsed, isFractional: false)
                        }
                    }
                } else if self.isPlaying != playing {
                    self.reconcileLivePlayback(isPlaying: playing, position: self.elapsedTime, isFractional: self.sawFractionalPosition)
                }
            }

            if let rawRate = rawRate {
                applyMR(rawRate > 0)
            } else if let getIsPlaying = self.getIsPlayingFn {
                getIsPlaying(DispatchQueue.main) { playing in
                    applyMR(playing.boolValue)
                }
            } else {
                applyMR(self.isPlaying)
            }
        }
    }

    private func reconcileLivePlayback(
        isPlaying liveIsPlaying: Bool,
        position livePosition: Double,
        isDirectPlayerQuery: Bool = false,
        isFractional: Bool = true
    ) {
        guard livePosition.isFinite else { return }
        if isFractional {
            sawFractionalPosition = true
        }

        let clamped = duration > 0 ? max(0, min(duration, livePosition)) : max(0, livePosition)
        let inCommandGraceWindow: Bool
        if let override = lastCommandPlayStateOverride, Date().timeIntervalSince(override.date) < 0.70 {
            inCommandGraceWindow = (liveIsPlaying != override.isPlaying)
        } else {
            inCommandGraceWindow = false
            lastCommandPlayStateOverride = nil
        }

        let effectiveIsPlaying = inCommandGraceWindow ? self.isPlaying : liveIsPlaying
        let playingChanged = (self.isPlaying != effectiveIsPlaying)
        let signedDelta = clamped - elapsedTime
        let drift = abs(signedDelta)

        if isDirectPlayerQuery {
            lastDirectSyncDate = Date()
        }

        if playingChanged {
            self.isPlaying = effectiveIsPlaying
        }

        let now = Date()
        if let lastRaw = lastObservedRawPosition {
            if abs(clamped - lastRaw) > 0.25 {
                lastObservedRawPosition = clamped
                lastRawPositionAdvanceDate = now
            }
        } else {
            lastObservedRawPosition = clamped
            lastRawPositionAdvanceDate = now
        }
        let stalledDuration = now.timeIntervalSince(lastRawPositionAdvanceDate)

        let isRestart = (clamped <= 1.2 && elapsedTime > 2.5)
        let shouldAdjustClock: Bool

        if playingChanged || isRestart {
            shouldAdjustClock = true
            consecutiveDriftDirection = 0
            consecutiveDriftCount = 0
        } else if !effectiveIsPlaying {
            shouldAdjustClock = drift > 0.06
            consecutiveDriftDirection = 0
            consecutiveDriftCount = 0
        } else if sawFractionalPosition {
            // High-precision source (Spotify, Safari/timestamped MediaRemote, fractional Apple Music):
            // Re-sync symmetrically both forward and backward so lyrics never drift ahead or behind mid-song
            if drift >= 0.35 || signedDelta > 0.16 {
                shouldAdjustClock = true
                consecutiveDriftDirection = 0
                consecutiveDriftCount = 0
            } else if drift > 0.06 {
                let dir = signedDelta > 0 ? 1 : -1
                if dir == consecutiveDriftDirection {
                    consecutiveDriftCount += 1
                } else {
                    consecutiveDriftDirection = dir
                    consecutiveDriftCount = 1
                }
                if consecutiveDriftCount >= 2 {
                    shouldAdjustClock = true
                    consecutiveDriftDirection = 0
                    consecutiveDriftCount = 0
                } else {
                    shouldAdjustClock = false
                }
            } else {
                consecutiveDriftDirection = 0
                consecutiveDriftCount = 0
                shouldAdjustClock = false
            }
        } else {
            // Integer-quantized source (e.g. Chrome/integer Music ticks): avoid 1Hz intra-second jitter,
            // but re-sync cleanly on forward ticks, rewinds (>= 1.15s), or buffering stalls (>= 1.35s)
            if signedDelta > 0.08 || signedDelta <= -1.15 || (stalledDuration >= 1.35 && signedDelta < -0.15) {
                shouldAdjustClock = true
            } else {
                shouldAdjustClock = false
            }
        }

        if shouldAdjustClock {
            baseElapsed = clamped
            infoTimestamp = now
            elapsedTime = clamped
            clock.elapsedTime = clamped
            updateActiveLyricIndex()
        }
    }

    private func queryLivePlayerState(app: String) -> (isPlaying: Bool, trackTitle: String, position: Double)? {
        dispatchPrecondition(condition: .onQueue(.main))
        let script: NSAppleScript
        if let cached = compiledLiveScripts[app] {
            script = cached
        } else {
            let source = """
            with timeout of 1 seconds
                tell application "\(app)"
                    if player state is stopped then return ""
                    set st to (player state is playing) as string
                    set tr to name of current track
                    set po to player position
                    return st & "|||" & tr & "|||" & (po as string)
                end tell
            end timeout
            """
            guard let created = NSAppleScript(source: source) else { return nil }
            var compileErr: NSDictionary?
            created.compileAndReturnError(&compileErr)
            compiledLiveScripts[app] = created
            script = created
        }

        var error: NSDictionary?
        guard let result = script.executeAndReturnError(&error).stringValue,
              !result.isEmpty else {
            return nil
        }
        let parts = result.components(separatedBy: "|||")
        guard parts.count >= 3,
              let pos = Double(parts[2].replacingOccurrences(of: ",", with: ".")) else {
            return nil
        }
        return (parts[0] == "true", parts[1], pos)
    }

    private func titlesRoughlyMatch(_ a: String, _ b: String) -> Bool {
        let normA = normalizedCoreString(a)
        let normB = normalizedCoreString(b)
        if normA.isEmpty || normB.isEmpty { return false }
        return normA == normB || normA.contains(normB) || normB.contains(normA)
    }

    func refreshNowPlaying() {
        guard let getInfo = getInfoFn else {
            refreshViaAppleScriptFallback()
            return
        }

        getPIDFn?(DispatchQueue.main) { [weak self] pid in
            guard let self = self else { return }
            if pid > 0 {
                if let app = NSRunningApplication(processIdentifier: pid), let bundleID = app.bundleIdentifier {
                    self.activePlayerBundleID = bundleID
                } else {
                    // Subprocess / XPC media helper (e.g. WebKit/Safari/Chrome helper) — do not keep stale Spotify/Music ID
                    self.activePlayerBundleID = "subprocess.\(pid)"
                }
            }
        }

        if let getIsPlaying = getIsPlayingFn {
            getIsPlaying(DispatchQueue.main) { [weak self] playing in
                guard let self = self else { return }
                let newState = playing.boolValue
                let inOverrideWindow: Bool
                if let override = self.lastCommandPlayStateOverride, Date().timeIntervalSince(override.date) < 0.70 {
                    inOverrideWindow = (newState != override.isPlaying)
                } else {
                    inOverrideWindow = false
                    self.lastCommandPlayStateOverride = nil
                }

                let resolvedPlaying = inOverrideWindow ? self.isPlaying : newState
                if self.isPlaying != resolvedPlaying {
                    self.isPlaying = resolvedPlaying
                }
                self.fetchMediaRemoteInfo(getInfo: getInfo, authoritativeIsPlaying: resolvedPlaying)
            }
        } else {
            fetchMediaRemoteInfo(getInfo: getInfo, authoritativeIsPlaying: nil)
        }
    }

    private func fetchMediaRemoteInfo(getInfo: GetInfoFn, authoritativeIsPlaying: Bool?) {
        getInfo(DispatchQueue.main) { [weak self] nsDict in
            guard let self = self else { return }
            if let dict = nsDict as? [String: Any],
               let rawTitle = dict["kMRMediaRemoteNowPlayingInfoTitle"] as? String,
               !rawTitle.isEmpty {
                let rawArtist = dict["kMRMediaRemoteNowPlayingInfoArtist"] as? String ?? ""
                let rawAlbum = dict["kMRMediaRemoteNowPlayingInfoAlbum"] as? String ?? ""
                let rawDuration = (dict["kMRMediaRemoteNowPlayingInfoDuration"] as? NSNumber)?.doubleValue ?? 0
                let rawElapsed = (dict["kMRMediaRemoteNowPlayingInfoElapsedTime"] as? NSNumber)?.doubleValue ?? 0
                let rawRate = (dict["kMRMediaRemoteNowPlayingInfoPlaybackRate"] as? NSNumber)?.doubleValue
                let rawTimestamp = dict["kMRMediaRemoteNowPlayingInfoTimestamp"] as? Date

                var artImage: NSImage?
                if let artData = dict["kMRMediaRemoteNowPlayingInfoArtworkData"] as? Data {
                    artImage = NSImage(data: artData)
                }

                self.applyTrackUpdate(
                    title: rawTitle,
                    artist: rawArtist,
                    album: rawAlbum,
                    artwork: artImage,
                    duration: rawDuration,
                    elapsed: rawElapsed,
                    timestamp: rawTimestamp,
                    rate: rawRate,
                    authoritativeIsPlaying: authoritativeIsPlaying
                )

                if artImage == nil {
                    self.fetchFallbackArtworkIfNeeded(for: "\(rawTitle)|\(rawArtist)")
                }
            } else {
                self.refreshViaAppleScriptFallback()
            }
        }
    }

    private func applyTrackUpdate(
        title: String,
        artist: String,
        album: String,
        artwork: NSImage?,
        duration rawDuration: Double,
        elapsed rawElapsed: Double,
        timestamp: Date?,
        rate: Double?,
        authoritativeIsPlaying: Bool? = nil
    ) {
        let duration = (rawDuration.isFinite && rawDuration > 0) ? rawDuration : 0
        let elapsed = (rawElapsed.isFinite && rawElapsed > 0) ? rawElapsed : 0
        let key = "\(title)|\(artist)"
        let trackChangedSinceLast = key != currentTrackKey
        let trackChanged = !title.isEmpty && key != lastAnnouncedKey && !lastAnnouncedKey.isEmpty
        if !title.isEmpty {
            lastAnnouncedKey = key
        }

        let wasPlaying = self.isPlaying

        if self.title != title { self.title = title }
        if self.artist != artist { self.artist = artist }
        if self.album != album { self.album = album }
        self.currentTrackKey = key

        if let artwork = artwork {
            if trackChangedSinceLast || self.artwork == nil {
                applyPalette(from: artwork)
                self.artwork = artwork
            }
        } else if let cached = artworkCache[key] {
            if trackChangedSinceLast || self.artwork == nil {
                applyPalette(from: cached)
                self.artwork = cached
            }
        } else if trackChangedSinceLast {
            resetPalette()
            self.artwork = nil
        }

        if abs(self.duration - duration) > 0.01 {
            self.duration = duration
        }
        if abs(self.clock.duration - duration) > 0.01 {
            self.clock.duration = duration
        }
        if trackChangedSinceLast {
            lastDirectSyncDate = .distantPast
            lastMediaRemoteRawElapsed = nil
            lastLyricsDurationQueried = 0
            lastCommandPlayStateOverride = nil
            playbackRateFactor = 1.0
            sawFractionalPosition = false
            lastObservedRawPosition = nil
            lastRawPositionAdvanceDate = Date()
            consecutiveDriftDirection = 0
            consecutiveDriftCount = 0
            lyricSyncOffset = lyricOffsetsByTrack[key] ?? 0.0
        }

        if let r = rate, r.isFinite, r > 0.05 {
            playbackRateFactor = min(4.0, max(0.25, r))
        }

        let inOverrideWindow: Bool
        if let override = lastCommandPlayStateOverride, Date().timeIntervalSince(override.date) < 0.70 {
            inOverrideWindow = true
        } else {
            inOverrideWindow = false
            lastCommandPlayStateOverride = nil
        }

        let preserveRecentDirectSync = !trackChangedSinceLast && Date().timeIntervalSince(lastDirectSyncDate) < 2.0

        if !preserveRecentDirectSync {
            if !inOverrideWindow {
                if let auth = authoritativeIsPlaying {
                    if self.isPlaying != auth {
                        self.isPlaying = auth
                    }
                } else if let rate = rate {
                    let nowPlaying = rate > 0
                    if self.isPlaying != nowPlaying {
                        self.isPlaying = nowPlaying
                    }
                }
            }

            let prevRaw = lastMediaRemoteRawElapsed
            lastMediaRemoteRawElapsed = elapsed
            let rawElapsedChanged = trackChangedSinceLast || prevRaw == nil || abs(elapsed - (prevRaw ?? elapsed)) > 0.35

            if let ts = timestamp {
                let age = Date().timeIntervalSince(ts)
                let validAge = (age >= -1.0 && age < 7200) ? max(0, age) : 0
                if !self.isPlaying && wasPlaying && !trackChangedSinceLast && !rawElapsedChanged && age > 2.5 {
                    // Player paused without pushing a fresh elapsed snapshot: keep live frozen position instead of jumping back
                    self.baseElapsed = self.elapsedTime
                    self.infoTimestamp = Date()
                } else {
                    let syncedElapsed = duration > 0 && self.isPlaying
                        ? min(duration, elapsed + validAge * playbackRateFactor)
                        : (self.isPlaying ? elapsed + validAge * playbackRateFactor : elapsed)
                    self.baseElapsed = syncedElapsed
                    self.infoTimestamp = Date()
                    self.elapsedTime = syncedElapsed
                    self.sawFractionalPosition = true
                    if abs(self.clock.elapsedTime - syncedElapsed) >= 0.14 || trackChangedSinceLast {
                        self.clock.elapsedTime = syncedElapsed
                    }
                }
            } else if trackChangedSinceLast || rawElapsedChanged {
                let syncedElapsed = duration > 0 ? min(duration, max(0, elapsed)) : max(0, elapsed)
                self.baseElapsed = syncedElapsed
                self.infoTimestamp = Date()
                self.elapsedTime = syncedElapsed
                if abs(elapsed - round(elapsed)) > 0.002 {
                    self.sawFractionalPosition = true
                }
                if abs(self.clock.elapsedTime - syncedElapsed) >= 0.14 || trackChangedSinceLast {
                    self.clock.elapsedTime = syncedElapsed
                }
            }
        }

        if trackChangedSinceLast {
            resetLyricsState()
            if hasTrack {
                // Pre-warm synced lyrics right away once duration is ready (or after short metadata settle)
                let delay: TimeInterval = duration > 10 ? 0.12 : 0.42
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                    guard let self = self, self.currentTrackKey == key else { return }
                    self.ensureLyricsLoaded()
                }
            }
        } else {
            // If track initially queried without valid duration (or duration changed significantly), re-query immediately with true duration
            if duration > 15 && (lastLyricsDurationQueried <= 1 || abs(duration - lastLyricsDurationQueried) > 10) {
                ensureLyricsLoaded(forceRetry: true)
            }
            updateActiveLyricIndex()
        }

        if trackChanged {
            onTrackChanged?(title, artist, self.accentColor)
        }
    }

    // MARK: - Synced Lyrics (LRCLIB)

    private struct LRCLibRecord: Decodable {
        let trackName: String?
        let artistName: String?
        let duration: Double?
        let instrumental: Bool?
        let syncedLyrics: String?
        let plainLyrics: String?
    }

    private func resetLyricsState() {
        lyricsRequestToken = UUID()
        activeLyricsTask?.cancel()
        activeLyricsTask = nil
        lyricLines = []
        plainLyricsLines = []
        isLyricsLoading = false
        lyricsStatusMessage = nil
        activeLyricIndex = nil
    }

    func ensureLyricsLoaded(forceRetry: Bool = false) {
        guard hasTrack else { return }
        let key = currentTrackKey
        if !forceRetry, let cached = lyricsCache[key] {
            applyCachedLyrics(cached)
            return
        }
        if isLyricsLoading && !forceRetry { return }

        let token = UUID()
        lyricsRequestToken = token
        activeLyricsTask?.cancel()
        isLyricsLoading = true
        lyricsStatusMessage = nil
        lastLyricsDurationQueried = duration

        let trackTitle = title
        let trackArtist = artist
        let trackAlbum = album
        let trackDuration = duration

        fetchExactLyrics(
            key: key,
            token: token,
            title: trackTitle,
            artist: trackArtist,
            album: trackAlbum,
            duration: trackDuration
        )
    }

    private func applyCachedLyrics(_ cached: CachedLyrics) {
        lyricLines = cached.synced
        plainLyricsLines = cached.plain
        lyricsStatusMessage = cached.statusMessage
        isLyricsLoading = false
        updateActiveLyricIndex()
        if lyricsAutoFetchEnabled {
            syncPlaybackPositionDirectly()
        }
    }

    private func fetchExactLyrics(
        key: String,
        token: UUID,
        title: String,
        artist: String,
        album: String,
        duration: Double
    ) {
        let cleanTitle = sanitizeTrackTitle(title)
        let cleanArtist = sanitizeArtistName(artist)
        var components = URLComponents(string: "https://lrclib.net/api/get")
        var items = [
            URLQueryItem(name: "track_name", value: cleanTitle),
            URLQueryItem(name: "artist_name", value: cleanArtist.isEmpty ? cleanTitle : cleanArtist)
        ]
        if !album.isEmpty {
            items.append(URLQueryItem(name: "album_name", value: album))
        }
        if duration >= 10 && duration <= 3600 {
            items.append(URLQueryItem(name: "duration", value: String(Int(round(duration)))))
        }
        components?.queryItems = items

        guard !cleanArtist.isEmpty, !isGenericPlayerArtist(cleanArtist), let url = components?.url else {
            fetchSearchLyrics(key: key, token: token, rawTitle: title, rawArtist: artist, duration: duration, step: 0, hadNetworkError: false)
            return
        }

        var request = URLRequest(url: url, timeoutInterval: 8.0)
        request.setValue("AirIsland/1.0 (https://github.com/mavericks1428/macos-dynamic-island)", forHTTPHeaderField: "User-Agent")

        let task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }
            if let nsErr = error as NSError?, nsErr.domain == NSURLErrorDomain, nsErr.code == NSURLErrorCancelled {
                return
            }

            let http = response as? HTTPURLResponse
            let networkFailed = (error != nil) || (http == nil) || (http!.statusCode != 200 && http!.statusCode != 404)

            if let http = http,
               http.statusCode == 200,
               let data = data,
               let record = try? JSONDecoder().decode(LRCLibRecord.self, from: data),
               self.isStrictMatch(record: record, expectedTitle: cleanTitle, expectedArtist: cleanArtist, targetDuration: duration, requireDurationClose: true) {
                let parsed = self.buildCachedLyrics(from: record)
                if !parsed.synced.isEmpty {
                    DispatchQueue.main.async {
                        guard self.lyricsRequestToken == token, self.currentTrackKey == key else { return }
                        self.lyricsCache[key] = parsed
                        self.applyCachedLyrics(parsed)
                    }
                    return
                }
            }

            DispatchQueue.main.async {
                guard self.lyricsRequestToken == token, self.currentTrackKey == key else { return }
                self.fetchSearchLyrics(key: key, token: token, rawTitle: title, rawArtist: artist, duration: duration, step: 0, hadNetworkError: networkFailed)
            }
        }
        activeLyricsTask = task
        task.resume()
    }

    private func fetchSearchLyrics(
        key: String,
        token: UUID,
        rawTitle: String,
        rawArtist: String,
        duration: Double,
        step: Int,
        hadNetworkError: Bool
    ) {
        guard lyricsRequestToken == token, currentTrackKey == key else { return }

        let cleanTitle = sanitizeTrackTitle(rawTitle)
        let cleanArtist = sanitizeArtistName(rawArtist)
        let artistUsable = !cleanArtist.isEmpty && !isGenericPlayerArtist(cleanArtist)

        var components = URLComponents(string: "https://lrclib.net/api/search")
        var validationTitle = cleanTitle
        var validationArtist = artistUsable ? cleanArtist : ""

        switch step {
        case 0:
            // Search by cleaned track_name + full artist_name (preserves "Tyler, The Creator", etc.)
            var items = [URLQueryItem(name: "track_name", value: cleanTitle)]
            if artistUsable {
                items.append(URLQueryItem(name: "artist_name", value: cleanArtist))
            }
            components?.queryItems = items

        case 1:
            // Handle YouTube/browser titles shaped "Artist - Track Name" when player didn't supply a real artist
            if !artistUsable, let split = splitArtistAndTitle(cleanTitle) {
                let parsedArtist = sanitizeArtistName(split.artist)
                let parsedTitle = sanitizeTrackTitle(split.title)
                validationTitle = parsedTitle
                validationArtist = parsedArtist
                components?.queryItems = [
                    URLQueryItem(name: "track_name", value: parsedTitle),
                    URLQueryItem(name: "artist_name", value: parsedArtist)
                ]
            } else {
                fetchSearchLyrics(key: key, token: token, rawTitle: rawTitle, rawArtist: rawArtist, duration: duration, step: step + 1, hadNetworkError: hadNetworkError)
                return
            }

        case 2:
            // If artist lists multiple comma-separated collaborators ("Artist A, Artist B"), fall back to primary artist
            if artistUsable, let commaIdx = cleanArtist.firstIndex(of: ",") {
                let primaryArtist = String(cleanArtist[..<commaIdx]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !primaryArtist.isEmpty && primaryArtist.count >= 2 {
                    validationArtist = primaryArtist
                    components?.queryItems = [
                        URLQueryItem(name: "track_name", value: cleanTitle),
                        URLQueryItem(name: "artist_name", value: primaryArtist)
                    ]
                    break
                }
            }
            fetchSearchLyrics(key: key, token: token, rawTitle: rawTitle, rawArtist: rawArtist, duration: duration, step: step + 1, hadNetworkError: hadNetworkError)
            return

        case 3:
            // Targeted query fallback, still strictly validated against title + artist + duration
            let q = artistUsable ? "\(cleanTitle) \(cleanArtist)" : cleanTitle
            components?.queryItems = [URLQueryItem(name: "q", value: q)]

        default:
            if hadNetworkError {
                let retryNotice = CachedLyrics(synced: [], plain: [], statusMessage: "Could not reach lyrics service. Tap Retry.")
                // Never poison lyricsCache on network errors
                applyCachedLyrics(retryNotice)
            } else {
                let fallback = CachedLyrics(synced: [], plain: [], statusMessage: "No matching synced lyrics found for this track.")
                if duration > 10 {
                    lyricsCache[key] = fallback
                }
                applyCachedLyrics(fallback)
            }
            return
        }

        guard let url = components?.url else {
            fetchSearchLyrics(key: key, token: token, rawTitle: rawTitle, rawArtist: rawArtist, duration: duration, step: step + 1, hadNetworkError: hadNetworkError)
            return
        }

        var request = URLRequest(url: url, timeoutInterval: 8.0)
        request.setValue("AirIsland/1.0 (https://github.com/mavericks1428/macos-dynamic-island)", forHTTPHeaderField: "User-Agent")

        let task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }
            if let nsErr = error as NSError?, nsErr.domain == NSURLErrorDomain, nsErr.code == NSURLErrorCancelled {
                return
            }

            let http = response as? HTTPURLResponse
            let stepFailed = (error != nil) || (http == nil) || (http!.statusCode != 200 && http!.statusCode != 404)

            if let http = http,
               http.statusCode == 200,
               let data = data,
               let records = try? JSONDecoder().decode([LRCLibRecord].self, from: data),
               let best = self.pickBestRecord(from: records, expectedTitle: validationTitle, expectedArtist: validationArtist, targetDuration: duration) {
                let parsed = self.buildCachedLyrics(from: best)
                if !parsed.synced.isEmpty || !parsed.plain.isEmpty || best.instrumental == true {
                    DispatchQueue.main.async {
                        guard self.lyricsRequestToken == token, self.currentTrackKey == key else { return }
                        self.lyricsCache[key] = parsed
                        self.applyCachedLyrics(parsed)
                    }
                    return
                }
            }

            DispatchQueue.main.async {
                guard self.lyricsRequestToken == token, self.currentTrackKey == key else { return }
                self.fetchSearchLyrics(
                    key: key,
                    token: token,
                    rawTitle: rawTitle,
                    rawArtist: rawArtist,
                    duration: duration,
                    step: step + 1,
                    hadNetworkError: hadNetworkError || stepFailed
                )
            }
        }
        activeLyricsTask = task
        task.resume()
    }

    private func pickBestRecord(
        from records: [LRCLibRecord],
        expectedTitle: String,
        expectedArtist: String,
        targetDuration: Double
    ) -> LRCLibRecord? {
        var bestSynced: (record: LRCLibRecord, score: Double)?
        var bestPlain: (record: LRCLibRecord, score: Double)?

        for record in records {
            let hasSynced = !(record.syncedLyrics ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let hasPlain = !(record.plainLyrics ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            guard hasSynced || hasPlain || record.instrumental == true else { continue }

            guard let matchScore = matchConfidenceScore(
                record: record,
                expectedTitle: expectedTitle,
                expectedArtist: expectedArtist,
                targetDuration: targetDuration,
                forSynced: hasSynced
            ) else {
                continue
            }

            if hasSynced {
                if bestSynced == nil || matchScore > bestSynced!.score {
                    bestSynced = (record, matchScore)
                }
            } else if hasPlain {
                if bestPlain == nil || matchScore > bestPlain!.score {
                    bestPlain = (record, matchScore)
                }
            }
        }

        if let bestSynced = bestSynced {
            return bestSynced.record
        }
        if let bestPlain = bestPlain {
            return bestPlain.record
        }
        return nil
    }

    private func isStrictMatch(
        record: LRCLibRecord,
        expectedTitle: String,
        expectedArtist: String,
        targetDuration: Double,
        requireDurationClose: Bool
    ) -> Bool {
        return matchConfidenceScore(
            record: record,
            expectedTitle: expectedTitle,
            expectedArtist: expectedArtist,
            targetDuration: targetDuration,
            forSynced: requireDurationClose
        ) != nil
    }

    private func matchConfidenceScore(
        record: LRCLibRecord,
        expectedTitle: String,
        expectedArtist: String,
        targetDuration: Double,
        forSynced: Bool
    ) -> Double? {
        let recTitle = normalizedCoreString(sanitizeTrackTitle(record.trackName ?? ""))
        let expTitle = normalizedCoreString(expectedTitle)
        guard !recTitle.isEmpty, !expTitle.isEmpty else { return nil }

        let expTitleWords = tokenSet(expTitle)
        let recTitleWords = tokenSet(recTitle)
        let titleOverlap = tokenOverlapRatio(expTitleWords, recTitleWords)
        let titleMatches = (recTitle == expTitle)
            || recTitle.contains(expTitle)
            || expTitle.contains(recTitle)
            || titleOverlap >= 0.68
        guard titleMatches else { return nil }

        // Reject obvious wrong-version tags unless the playing title itself asks for them
        let versionTags = ["sped up", "slowed", "reverb", "nightcore", "8d", "instrumental", "karaoke", "remix", "cover", "acoustic", "live"]
        for tag in versionTags {
            if recTitle.contains(tag) && !expTitle.contains(tag) {
                return nil
            }
        }

        var score: Double = (recTitle == expTitle) ? 100.0 : (55.0 + titleOverlap * 30.0)

        let expArtist = normalizedCoreString(expectedArtist)
        let recArtist = normalizedCoreString(sanitizeArtistName(record.artistName ?? ""))
        if !expArtist.isEmpty {
            guard !recArtist.isEmpty else { return nil }
            let expArtWords = tokenSet(expArtist)
            let recArtWords = tokenSet(recArtist)
            let artOverlap = tokenOverlapRatio(expArtWords, recArtWords)
            let artistMatches = (recArtist == expArtist)
                || recArtist.contains(expArtist)
                || expArtist.contains(recArtist)
                || artOverlap >= 0.50
            guard artistMatches else { return nil }
            score += (recArtist == expArtist) ? 80.0 : (40.0 + artOverlap * 25.0)
        }

        if targetDuration >= 15, let recDuration = record.duration, recDuration > 10 {
            let diff = abs(recDuration - targetDuration)
            // For synced lyrics, reject versions off by > 8.5s so radio/album edits never drift mid-song
            if forSynced && diff > 8.5 {
                return nil
            }
            if diff <= 1.5 {
                score += 90.0
            } else if diff <= 3.5 {
                score += 65.0
            } else if diff <= 7.0 {
                score += 30.0
            } else {
                score -= diff * 2.5
            }
        }

        return score
    }

    private func splitArtistAndTitle(_ raw: String) -> (artist: String, title: String)? {
        let separators = [" - ", " — ", " – "]
        for sep in separators {
            let parts = raw.components(separatedBy: sep)
            if parts.count >= 2 {
                let first = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
                let rest = parts.dropFirst().joined(separator: sep).trimmingCharacters(in: .whitespacesAndNewlines)
                if !first.isEmpty && !rest.isEmpty {
                    return (first, rest)
                }
            }
        }
        return nil
    }

    private func isGenericPlayerArtist(_ artist: String) -> Bool {
        let low = artist.lowercased()
        return low.isEmpty
            || low == "unknown artist"
            || low == "youtube"
            || low == "safari"
            || low == "google chrome"
            || low == "spotify"
            || low == "music"
    }

    private func normalizedCoreString(_ input: String) -> String {
        let folded = input.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        let allowed = folded.unicodeScalars.map { scalar -> Character in
            CharacterSet.alphanumerics.contains(scalar) ? Character(scalar) : " "
        }
        return String(allowed)
            .components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private func tokenSet(_ normalized: String) -> Set<String> {
        Set(normalized.components(separatedBy: " ").filter { !$0.isEmpty })
    }

    private func tokenOverlapRatio(_ a: Set<String>, _ b: Set<String>) -> Double {
        guard !a.isEmpty, !b.isEmpty else { return 0 }
        let shared = a.intersection(b).count
        return Double(shared) / Double(max(a.count, b.count))
    }

    private func buildCachedLyrics(from record: LRCLibRecord) -> CachedLyrics {
        if record.instrumental == true && (record.syncedLyrics ?? "").isEmpty && (record.plainLyrics ?? "").isEmpty {
            return CachedLyrics(synced: [], plain: [], statusMessage: "Instrumental track")
        }
        if let synced = record.syncedLyrics, !synced.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let parsed = parseLRC(synced)
            if !parsed.isEmpty {
                return CachedLyrics(synced: parsed, plain: [], statusMessage: nil)
            }
        }
        if let plain = record.plainLyrics, !plain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let lines = plain
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            return CachedLyrics(synced: [], plain: lines, statusMessage: lines.isEmpty ? "No lyrics found" : nil)
        }
        return CachedLyrics(synced: [], plain: [], statusMessage: "No lyrics available")
    }

    private func parseLRC(_ raw: String) -> [LyricLine] {
        guard let lineRegex = try? NSRegularExpression(pattern: "\\[(\\d{1,3}):(\\d{1,2}(?:\\.\\d{1,3})?)\\]") else {
            return []
        }
        let inlineWordRegex = try? NSRegularExpression(pattern: "<\\d{1,3}:\\d{1,2}(?:\\.\\d{1,3})?>")

        var entries: [(Double, String)] = []
        var lrcOffsetSeconds: Double = 0
        let lines = raw.components(separatedBy: .newlines)

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.lowercased().hasPrefix("[offset:"), trimmed.hasSuffix("]") {
                let inner = String(trimmed.dropFirst(8).dropLast(1)).trimmingCharacters(in: .whitespaces)
                if let ms = Double(inner) {
                    lrcOffsetSeconds = ms / 1000.0
                }
                continue
            }

            let nsLine = line as NSString
            let matches = lineRegex.matches(in: line, range: NSRange(location: 0, length: nsLine.length))
            guard !matches.isEmpty, let lastMatch = matches.last else { continue }

            let textStart = lastMatch.range.location + lastMatch.range.length
            var text = nsLine.substring(from: textStart)
            if let inlineWordRegex = inlineWordRegex {
                let range = NSRange(location: 0, length: (text as NSString).length)
                text = inlineWordRegex.stringByReplacingMatches(in: text, range: range, withTemplate: "")
            }
            text = text
                .components(separatedBy: .whitespaces)
                .filter { !$0.isEmpty }
                .joined(separator: " ")

            for match in matches {
                let minStr = nsLine.substring(with: match.range(at: 1))
                let secStr = nsLine.substring(with: match.range(at: 2))
                guard let mins = Double(minStr), let secs = Double(secStr) else { continue }
                entries.append((mins * 60.0 + secs, text))
            }
        }

        if abs(lrcOffsetSeconds) > 0.0001 {
            entries = entries.map { (max(0, $0.0 - lrcOffsetSeconds), $0.1) }
        }

        entries.sort {
            if abs($0.0 - $1.0) < 0.0001 {
                return $0.1.isEmpty && !$1.1.isEmpty
            }
            return $0.0 < $1.0
        }

        // Drop leading blank entries while keeping mid-song instrumental rest markers
        while let first = entries.first, first.1.isEmpty {
            entries.removeFirst()
        }

        return entries.enumerated().map { idx, item in
            LyricLine(id: idx, time: item.0, text: item.1)
        }
    }

    func nudgeLyricSync(_ delta: Double) {
        let rounded = (max(-5.0, min(5.0, lyricSyncOffset + delta)) * 20.0).rounded() / 20.0
        lyricSyncOffset = rounded
        if !currentTrackKey.isEmpty {
            lyricOffsetsByTrack[currentTrackKey] = rounded
        }
        updateActiveLyricIndex()
    }

    func resetLyricSync() {
        lyricSyncOffset = 0.0
        if !currentTrackKey.isEmpty {
            lyricOffsetsByTrack.removeValue(forKey: currentTrackKey)
        }
        updateActiveLyricIndex()
    }

    private func updateActiveLyricIndex() {
        guard !lyricLines.isEmpty else {
            if activeLyricIndex != nil { activeLyricIndex = nil }
            return
        }

        // 120ms transition lead (~half of 0.20s cubic transition) so lines settle centered right as the vocal hits
        let targetTime = elapsedTime + 0.12 + lyricSyncOffset
        var matched: Int? = nil
        for line in lyricLines {
            if line.time <= targetTime {
                matched = line.text.isEmpty ? nil : line.id
            } else {
                break
            }
        }

        if activeLyricIndex != matched {
            activeLyricIndex = matched
        }
    }

    private func sanitizeTrackTitle(_ input: String) -> String {
        var result = input
        let patterns = [
            "\\s*[\\(\\[]\\s*\\b(?:feat\\.|ft\\.|featuring\\b|official\\b|remaster(?:ed)?\\b|live\\b|acoustic\\b|audio\\b|video\\b|lyric(?:s)?\\b|hd\\b|4k\\b|visualizer\\b).*?[\\)\\]]",
            "\\s*-\\s*\\b(?:remaster(?:ed)?\\b|live\\b|radio edit\\b|single version\\b|acoustic\\b|official\\b).*$"
        ]
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                let range = NSRange(location: 0, length: (result as NSString).length)
                result = regex.stringByReplacingMatches(in: result, range: range, withTemplate: "")
            }
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func sanitizeArtistName(_ input: String) -> String {
        var cleaned = input
            .replacingOccurrences(of: " - Topic", with: "", options: [.caseInsensitive])
            .replacingOccurrences(of: "VEVO", with: "", options: [.caseInsensitive])
        if let featRange = cleaned.range(of: " feat.", options: [.caseInsensitive]) {
            cleaned = String(cleaned[..<featRange.lowerBound])
        }
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func clearCurrentTrack() {
        guard !title.isEmpty || !currentTrackKey.isEmpty || isPlaying else { return }
        title = ""
        artist = ""
        album = ""
        artwork = nil
        resetPalette()
        isPlaying = false
        duration = 0
        elapsedTime = 0
        clock.duration = 0
        clock.elapsedTime = 0
        currentTrackKey = ""
        activePlayerBundleID = nil
        playbackRateFactor = 1.0
        sawFractionalPosition = false
        lastObservedRawPosition = nil
        lastRawPositionAdvanceDate = Date()
        consecutiveDriftDirection = 0
        consecutiveDriftCount = 0
        resetLyricsState()
    }

    // MARK: - Artwork & AppleScript Fallback

    private func fetchFallbackArtworkIfNeeded(for trackKey: String) {
        if let cached = artworkCache[trackKey] {
            self.artwork = cached
            self.applyPalette(from: cached)
            return
        }

        let running = NSWorkspace.shared.runningApplications.compactMap { $0.bundleIdentifier }
        if running.contains("com.spotify.client") {
            guard let urlStr = querySpotifyArtworkURL(),
                  let url = URL(string: urlStr) else { return }
            URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
                guard let data = data, let img = NSImage(data: data) else { return }
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    self.artworkCache[trackKey] = img
                    if self.currentTrackKey == trackKey {
                        self.artwork = img
                        self.applyPalette(from: img)
                    }
                }
            }.resume()
        } else if running.contains("com.apple.Music") {
            if let img = queryMusicArtworkImage() {
                artworkCache[trackKey] = img
                if currentTrackKey == trackKey {
                    artwork = img
                    applyPalette(from: img)
                }
            }
        }
    }

    private func querySpotifyArtworkURL() -> String? {
        dispatchPrecondition(condition: .onQueue(.main))
        let source = """
        with timeout of 1 seconds
            tell application "Spotify"
                if player state is stopped then return ""
                return artwork url of current track
            end tell
        end timeout
        """
        var error: NSDictionary?
        guard let script = NSAppleScript(source: source),
              let str = script.executeAndReturnError(&error).stringValue,
              !str.isEmpty else {
            return nil
        }
        return str
    }

    private func queryMusicArtworkImage() -> NSImage? {
        dispatchPrecondition(condition: .onQueue(.main))
        let source = """
        with timeout of 1 seconds
            tell application "Music"
                if player state is stopped then return ""
                if (count of artworks of current track) > 0 then
                    return raw data of artwork 1 of current track
                end if
            end tell
        end timeout
        """
        var error: NSDictionary?
        guard let script = NSAppleScript(source: source) else { return nil }
        let descriptor = script.executeAndReturnError(&error)
        let data = descriptor.data
        guard !data.isEmpty else { return nil }
        return NSImage(data: data)
    }

    private func refreshViaAppleScriptFallback() {
        dispatchPrecondition(condition: .onQueue(.main))
        let running = NSWorkspace.shared.runningApplications.compactMap { $0.bundleIdentifier }
        let isSpotifyRunning = running.contains("com.spotify.client")
        let isMusicRunning = running.contains("com.apple.Music")

        guard isSpotifyRunning || isMusicRunning else {
            clearCurrentTrack()
            return
        }

        if isSpotifyRunning, let info = queryAppleScript(app: "Spotify") {
            let key = "\(info.title)|\(info.artist)"
            applyTrackUpdate(
                title: info.title,
                artist: info.artist,
                album: info.album,
                artwork: nil,
                duration: info.duration,
                elapsed: info.position,
                timestamp: Date(),
                rate: info.isPlaying ? 1.0 : 0.0
            )
            fetchFallbackArtworkIfNeeded(for: key)
            return
        }

        if isMusicRunning, let info = queryAppleScript(app: "Music") {
            let key = "\(info.title)|\(info.artist)"
            applyTrackUpdate(
                title: info.title,
                artist: info.artist,
                album: info.album,
                artwork: nil,
                duration: info.duration,
                elapsed: info.position,
                timestamp: Date(),
                rate: info.isPlaying ? 1.0 : 0.0
            )
            fetchFallbackArtworkIfNeeded(for: key)
            return
        }

        // Players are open but stopped/empty — clear stale ghost metadata
        clearCurrentTrack()
    }

    private struct ScriptTrackInfo {
        let isPlaying: Bool
        let title: String
        let artist: String
        let album: String
        let duration: Double
        let position: Double
    }

    private func queryAppleScript(app: String) -> ScriptTrackInfo? {
        dispatchPrecondition(condition: .onQueue(.main))
        let source: String
        if app == "Spotify" {
            source = """
            with timeout of 1 seconds
                tell application "Spotify"
                    if player state is stopped then return ""
                    set st to (player state is playing) as string
                    set tr to name of current track
                    set ar to artist of current track
                    set al to album of current track
                    set du to (duration of current track) / 1000
                    set po to player position
                    return st & "|||" & tr & "|||" & ar & "|||" & al & "|||" & (du as string) & "|||" & (po as string)
                end tell
            end timeout
            """
        } else {
            source = """
            with timeout of 1 seconds
                tell application "Music"
                    if player state is stopped then return ""
                    set st to (player state is playing) as string
                    set tr to name of current track
                    set ar to artist of current track
                    set al to album of current track
                    set du to duration of current track
                    set po to player position
                    return st & "|||" & tr & "|||" & ar & "|||" & al & "|||" & (du as string) & "|||" & (po as string)
                end tell
            end timeout
            """
        }

        var error: NSDictionary?
        guard let script = NSAppleScript(source: source),
              let result = script.executeAndReturnError(&error).stringValue,
              !result.isEmpty else {
            return nil
        }

        let parts = result.components(separatedBy: "|||")
        guard parts.count >= 6 else { return nil }
        return ScriptTrackInfo(
            isPlaying: parts[0] == "true",
            title: parts[1],
            artist: parts[2],
            album: parts[3],
            duration: Double(parts[4].replacingOccurrences(of: ",", with: ".")) ?? 0,
            position: Double(parts[5].replacingOccurrences(of: ",", with: ".")) ?? 0
        )
    }

    // MARK: - Playback & App Focus Controls

    func openNowPlayingApp() {
        if activePlayerBundleID == "com.spotify.client" || activePlayerBundleID == "com.apple.Music" {
            if let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == activePlayerBundleID }) {
                app.activate(options: .activateIgnoringOtherApps)
                return
            }
        }
        if let getPID = getPIDFn {
            getPID(DispatchQueue.main) { [weak self] pid in
                if pid > 0,
                   let app = NSRunningApplication(processIdentifier: pid),
                   let bid = app.bundleIdentifier,
                   !bid.lowercased().contains("helper"),
                   !bid.lowercased().contains("webkit") {
                    app.activate(options: .activateIgnoringOtherApps)
                    return
                }
                self?.activateFallbackPlayerApp()
            }
            return
        }
        activateFallbackPlayerApp()
    }

    private func activateFallbackPlayerApp() {
        let running = NSWorkspace.shared.runningApplications
        let priority = [
            "com.spotify.client",
            "com.apple.Music",
            "com.google.Chrome",
            "com.apple.Safari",
            "company.thebrowser.Browser",
            "com.brave.Browser",
            "org.mozilla.firefox"
        ]
        for bid in priority {
            if let match = running.first(where: { $0.bundleIdentifier == bid }) {
                match.activate(options: .activateIgnoringOtherApps)
                return
            }
        }
    }

    func togglePlayPause() {
        let targetPlaying = !isPlaying
        baseElapsed = elapsedTime
        infoTimestamp = Date()
        clock.elapsedTime = elapsedTime
        isPlaying = targetPlaying
        lastCommandPlayStateOverride = (targetPlaying, Date())

        let directApp = resolvedDirectControlApp()
        if let appName = directApp {
            let verb = targetPlaying ? "play" : "pause"
            runControlAppleScript(verb, targetApp: appName) { [weak self] success in
                guard let self = self else { return }
                if !success, let send = self.sendCommandFn {
                    let cmd: UInt32 = targetPlaying ? 0 : 1
                    if !send(cmd, nil).boolValue {
                        _ = send(2, nil)
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                        self.refreshNowPlaying()
                    }
                }
            }
            return
        }

        if let send = sendCommandFn {
            // Browsers / MediaSession apps on macOS 12 reliably handle kMRTogglePlayPause (2)
            let sent = send(2, nil).boolValue
            if !sent {
                _ = send(targetPlaying ? 0 : 1, nil)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { [weak self] in
                self?.refreshNowPlaying()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.50) { [weak self] in
                self?.syncPlaybackPositionDirectly()
            }
        } else {
            runControlAppleScript("playpause", targetApp: nil)
        }
    }

    func nextTrack() {
        if let appName = resolvedDirectControlApp() {
            runControlAppleScript("next track", targetApp: appName) { [weak self] success in
                if !success, let send = self?.sendCommandFn {
                    _ = send(4, nil)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                        self?.refreshNowPlaying()
                    }
                }
            }
            return
        }
        if let send = sendCommandFn {
            _ = send(4, nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                self?.refreshNowPlaying()
            }
        } else {
            runControlAppleScript("next track", targetApp: nil)
        }
    }

    func previousTrack() {
        if let appName = resolvedDirectControlApp() {
            runControlAppleScript("previous track", targetApp: appName) { [weak self] success in
                if !success, let send = self?.sendCommandFn {
                    _ = send(5, nil)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                        self?.refreshNowPlaying()
                    }
                }
            }
            return
        }
        if let send = sendCommandFn {
            _ = send(5, nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                self?.refreshNowPlaying()
            }
        } else {
            runControlAppleScript("previous track", targetApp: nil)
        }
    }

    func seek(to seconds: Double) {
        guard seconds.isFinite else { return }
        let safeDuration = (duration.isFinite && duration > 0) ? duration : 0
        let clamped = safeDuration > 0 ? max(0, min(safeDuration, seconds)) : max(0, seconds)
        baseElapsed = clamped
        infoTimestamp = Date()
        elapsedTime = clamped
        clock.elapsedTime = clamped
        lastObservedRawPosition = clamped
        lastRawPositionAdvanceDate = Date()
        consecutiveDriftDirection = 0
        consecutiveDriftCount = 0
        updateActiveLyricIndex()

        if let appName = resolvedDirectControlApp() {
            lastDirectSyncDate = Date()
            runControlAppleScript("set player position to \(clamped)", targetApp: appName) { [weak self] success in
                if !success {
                    self?.setElapsedFn?(clamped)
                }
            }
            return
        }

        if let setElapsedFn = setElapsedFn {
            setElapsedFn(clamped)
        } else {
            runControlAppleScript("set player position to \(clamped)", targetApp: nil)
        }
    }

    private func resolvedDirectControlApp() -> String? {
        let running = Set(NSWorkspace.shared.runningApplications.compactMap { $0.bundleIdentifier })
        if activePlayerBundleID == "com.spotify.client", running.contains("com.spotify.client") {
            return "Spotify"
        }
        if activePlayerBundleID == "com.apple.Music", running.contains("com.apple.Music") {
            return "Music"
        }
        return nil
    }

    private func runControlAppleScript(_ verb: String, targetApp: String? = nil, completion: ((Bool) -> Void)? = nil) {
        let running = NSWorkspace.shared.runningApplications.compactMap { $0.bundleIdentifier }
        let appName: String?
        if let targetApp = targetApp {
            appName = targetApp
        } else if running.contains("com.spotify.client") {
            appName = "Spotify"
        } else if running.contains("com.apple.Music") {
            appName = "Music"
        } else {
            appName = nil
        }
        guard let target = appName else {
            completion?(false)
            return
        }
        DispatchQueue.main.async { [weak self] in
            let script = NSAppleScript(source: "with timeout of 1 seconds\ntell application \"\(target)\" to \(verb)\nend timeout")
            var err: NSDictionary?
            let ok = script?.executeAndReturnError(&err) != nil && err == nil
            completion?(ok)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                self?.refreshNowPlaying()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.48) {
                self?.syncPlaybackPositionDirectly()
            }
        }
    }

    // MARK: - Dominant Album Palette Extraction

    private struct AlbumPalette {
        let primary: Color
        let secondary: Color
        let backdropTop: Color
        let backdropBottom: Color
    }

    private func applyPalette(from image: NSImage) {
        let palette = extractAlbumPalette(from: image)
        withAnimation(IslandMotion.resolved(IslandMotion.theme)) {
            accentColor = palette?.primary ?? defaultAccent
            secondaryColor = palette?.secondary ?? defaultSecondary
            themeBackdropTop = palette?.backdropTop ?? defaultBackdropTop
            themeBackdropBottom = palette?.backdropBottom ?? defaultBackdropBottom
        }
    }

    private func resetPalette() {
        withAnimation(IslandMotion.resolved(IslandMotion.theme)) {
            accentColor = defaultAccent
            secondaryColor = defaultSecondary
            themeBackdropTop = defaultBackdropTop
            themeBackdropBottom = defaultBackdropBottom
        }
    }

    private func extractAlbumPalette(from image: NSImage) -> AlbumPalette? {
        let size = 16
        let bytesPerPixel = 4
        let bytesPerRow = size * bytesPerPixel
        var raw = [UInt8](repeating: 0, count: size * bytesPerRow)

        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }

        let drew = raw.withUnsafeMutableBytes { buf -> Bool in
            guard let base = buf.baseAddress,
                  let ctx = CGContext(
                      data: base,
                      width: size,
                      height: size,
                      bitsPerComponent: 8,
                      bytesPerRow: bytesPerRow,
                      space: colorSpace,
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                  ) else {
                return false
            }
            ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: size, height: size))
            return true
        }
        guard drew else { return nil }

        struct HueBucket {
            var score: Double = 0
            var rSum: Double = 0
            var gSum: Double = 0
            var bSum: Double = 0
            var weightSum: Double = 0
        }

        let bucketCount = 12
        var buckets = [HueBucket](repeating: HueBucket(), count: bucketCount)
        var chromaticPixels = 0
        var totalOpaquePixels = 0

        for i in stride(from: 0, to: raw.count, by: 4) {
            let a = Double(raw[i + 3]) / 255.0
            guard a > 0.25 else { continue }
            totalOpaquePixels += 1

            let r = Double(raw[i]) / 255.0
            let g = Double(raw[i + 1]) / 255.0
            let b = Double(raw[i + 2]) / 255.0
            let maxC = max(r, g, b)
            let minC = min(r, g, b)
            let delta = maxC - minC
            let sat = maxC > 0 ? delta / maxC : 0

            // Ignore near-black, pure white, and JPEG compression noise on B&W covers
            if maxC < 0.16 || sat < 0.18 || delta < 0.08 {
                continue
            }
            chromaticPixels += 1

            var hue: Double = 0
            if delta > 0 {
                if maxC == r {
                    hue = ((g - b) / delta).truncatingRemainder(dividingBy: 6)
                } else if maxC == g {
                    hue = ((b - r) / delta) + 2
                } else {
                    hue = ((r - g) / delta) + 4
                }
                hue /= 6.0
                if hue < 0 { hue += 1.0 }
            }

            let idx = min(bucketCount - 1, max(0, Int(hue * Double(bucketCount))))
            let weight = pow(sat, 1.35) * (0.45 + maxC * 0.85)
            buckets[idx].score += weight
            buckets[idx].rSum += r * weight
            buckets[idx].gSum += g * weight
            buckets[idx].bSum += b * weight
            buckets[idx].weightSum += weight
        }

        // Monochrome / B&W album cover (e.g. Arctic Monkeys - AM): crisp luminous electric cyan-indigo instead of muddy tint
        if totalOpaquePixels == 0 || Double(chromaticPixels) / Double(max(1, totalOpaquePixels)) < 0.04 {
            return AlbumPalette(
                primary: Color(red: 0.42, green: 0.82, blue: 1.00),
                secondary: Color(red: 0.68, green: 0.48, blue: 1.00),
                backdropTop: Color(red: 0.12, green: 0.22, blue: 0.36),
                backdropBottom: Color(red: 0.15, green: 0.10, blue: 0.28)
            )
        }

        let ranked = buckets.enumerated()
            .filter { $0.element.weightSum > 0 }
            .sorted { $0.element.score > $1.element.score }

        guard let top = ranked.first else { return nil }
        let b1 = top.element
        let primaryNS = NSColor(
            calibratedRed: b1.rSum / b1.weightSum,
            green: b1.gSum / b1.weightSum,
            blue: b1.bSum / b1.weightSum,
            alpha: 1.0
        )

        var hue: CGFloat = 0
        var sat: CGFloat = 0
        var bri: CGFloat = 0
        var alpha: CGFloat = 1
        primaryNS.getHue(&hue, saturation: &sat, brightness: &bri, alpha: &alpha)

        let secondBucket = ranked.first { candidate in
            let dist = min(abs(candidate.offset - top.offset), bucketCount - abs(candidate.offset - top.offset))
            return dist >= 2 && candidate.element.score >= b1.score * 0.22
        }?.element

        var secHue: CGFloat
        var secSat: CGFloat
        var secBri: CGFloat
        if let b2 = secondBucket {
            let secNS = NSColor(
                calibratedRed: b2.rSum / b2.weightSum,
                green: b2.gSum / b2.weightSum,
                blue: b2.bSum / b2.weightSum,
                alpha: 1.0
            )
            var h: CGFloat = 0, s: CGFloat = 0, br: CGFloat = 0
            secNS.getHue(&h, saturation: &s, brightness: &br, alpha: &alpha)
            secHue = h
            secSat = s
            secBri = br
        } else {
            secHue = (hue + 0.11).truncatingRemainder(dividingBy: 1.0)
            secSat = sat
            secBri = bri
        }

        let tunedAccent = NSColor(
            calibratedHue: hue,
            saturation: min(1.0, max(0.68, sat * 1.32)),
            brightness: min(1.0, max(0.84, bri * 1.24)),
            alpha: 1.0
        )
        let tunedSecondary = NSColor(
            calibratedHue: secHue,
            saturation: min(1.0, max(0.64, secSat * 1.26)),
            brightness: min(1.0, max(0.78, secBri * 1.18)),
            alpha: 1.0
        )
        // Rich, vibrant Apple Music glass backdrop tones
        let backdropTop = NSColor(
            calibratedHue: hue,
            saturation: min(0.92, max(0.62, sat * 1.22)),
            brightness: min(0.48, max(0.28, bri * 0.58)),
            alpha: 1.0
        )
        let backdropBottom = NSColor(
            calibratedHue: secHue,
            saturation: min(0.90, max(0.56, secSat * 1.18)),
            brightness: min(0.34, max(0.18, secBri * 0.42)),
            alpha: 1.0
        )

        return AlbumPalette(
            primary: Color(tunedAccent),
            secondary: Color(tunedSecondary),
            backdropTop: Color(backdropTop),
            backdropBottom: Color(backdropBottom)
        )
    }
}
