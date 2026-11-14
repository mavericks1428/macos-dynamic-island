import Cocoa
import SwiftUI

final class TimerController: ObservableObject {
    @Published var totalSeconds: Int = 25 * 60
    @Published var remainingSeconds: Int = 25 * 60
    @Published var isRunning: Bool = false
    @Published var label: String = "Focus"

    var onCompleted: ((String) -> Void)?

    private var timer: Timer?
    private var endDate: Date?
    private var wakeObserver: NSObjectProtocol?

    var hasActiveSession: Bool {
        isRunning || (remainingSeconds > 0 && remainingSeconds < totalSeconds)
    }

    var progress: Double {
        guard totalSeconds > 0 else { return 0 }
        return max(0, min(1, Double(totalSeconds - remainingSeconds) / Double(totalSeconds)))
    }

    var formattedRemaining: String {
        let clamped = max(0, remainingSeconds)
        let mins = clamped / 60
        let secs = clamped % 60
        return String(format: "%02d:%02d", mins, secs)
    }

    init() {
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.syncFromEndDate()
        }
    }

    func selectPreset(minutes: Int, title: String) {
        pause()
        let secs = max(60, minutes * 60)
        totalSeconds = secs
        remainingSeconds = secs
        label = title
    }

    func adjustMinutes(_ delta: Int) {
        guard !isRunning else { return }
        let deltaSecs = delta * 60
        if remainingSeconds < totalSeconds && remainingSeconds > 0 {
            // Preserve partial progress when paused mid-session
            let newRemaining = max(60, min(180 * 60, remainingSeconds + deltaSecs))
            let newTotal = max(newRemaining, min(180 * 60, totalSeconds + deltaSecs))
            remainingSeconds = newRemaining
            totalSeconds = newTotal
        } else {
            let updated = max(60, min(180 * 60, totalSeconds + deltaSecs))
            totalSeconds = updated
            remainingSeconds = updated
        }
    }

    func toggle() {
        if isRunning {
            pause()
        } else {
            start()
        }
    }

    func start() {
        if remainingSeconds <= 0 {
            remainingSeconds = totalSeconds
        }
        guard !isRunning else { return }
        endDate = Date().addingTimeInterval(TimeInterval(remainingSeconds))
        isRunning = true
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            self?.syncFromEndDate()
        }
        if let timer = timer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    func pause() {
        if isRunning, let end = endDate {
            remainingSeconds = max(0, Int(ceil(end.timeIntervalSinceNow)))
        }
        endDate = nil
        isRunning = false
        timer?.invalidate()
        timer = nil
    }

    func reset() {
        pause()
        remainingSeconds = totalSeconds
    }

    private func syncFromEndDate() {
        guard isRunning, let end = endDate else { return }
        let left = Int(ceil(end.timeIntervalSinceNow))
        if left > 0 {
            if remainingSeconds != left {
                remainingSeconds = left
            }
        } else {
            remainingSeconds = 0
            endDate = nil
            isRunning = false
            timer?.invalidate()
            timer = nil
            NSSound(named: NSSound.Name("Glass"))?.play()
            onCompleted?(label)
        }
    }

    deinit {
        timer?.invalidate()
        if let wakeObserver = wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
        }
    }
}
