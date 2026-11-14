import Cocoa
import Darwin
import IOKit.ps

final class SystemStatsMonitor: ObservableObject {
    @Published var cpuUsagePercent: Int = 0
    @Published var memoryUsedGB: Double = 0
    @Published var memoryTotalGB: Double = Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824.0
    @Published var batteryPercent: Int = 100
    @Published var isCharging: Bool = false
    @Published var isOnACPower: Bool = false
    @Published var hasBattery: Bool = false

    var onPowerConnectionChanged: ((Bool, Int) -> Void)?

    private var statsTimer: Timer?
    private var prevCPUInfo: host_cpu_load_info?
    private var powerSourceRunLoop: CFRunLoopSource?
    private var lastACState: Bool?

    init() {
        refreshBattery(notifyChange: false)
        refreshCPUAndMemory()
        startPowerNotifications()
    }

    deinit {
        statsTimer?.invalidate()
        if let src = powerSourceRunLoop {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), src, .defaultMode)
        }
    }

    func setActivePolling(_ active: Bool) {
        statsTimer?.invalidate()
        statsTimer = nil
        guard active else { return }
        refreshCPUAndMemory()
        refreshBattery(notifyChange: false)
        statsTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.refreshCPUAndMemory()
            self?.refreshBattery(notifyChange: false)
        }
    }

    private func startPowerNotifications() {
        let callback: IOPowerSourceCallbackType = { context in
            guard let context = context else { return }
            let monitor = Unmanaged<SystemStatsMonitor>.fromOpaque(context).takeUnretainedValue()
            DispatchQueue.main.async {
                monitor.refreshBattery(notifyChange: true)
            }
        }
        let context = Unmanaged.passUnretained(self).toOpaque()
        if let source = IOPSNotificationCreateRunLoopSource(callback, context)?.takeRetainedValue() {
            powerSourceRunLoop = source
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
        }
    }

    func refreshBattery(notifyChange: Bool) {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef],
              let first = list.first,
              let info = IOPSGetPowerSourceDescription(blob, first)?.takeUnretainedValue() as? [String: Any] else {
            hasBattery = false
            return
        }

        hasBattery = true
        let current = info[kIOPSCurrentCapacityKey] as? Int ?? 0
        let maxCap = max(1, info[kIOPSMaxCapacityKey] as? Int ?? 100)
        let pct = min(100, max(0, Int(round(Double(current) * 100.0 / Double(maxCap)))))

        let charging = (info[kIOPSIsChargingKey] as? Bool) ?? ((info[kIOPSIsChargingKey] as? Int ?? 0) != 0)
        let stateStr = info[kIOPSPowerSourceStateKey] as? String ?? ""
        let onAC = stateStr == kIOPSACPowerValue

        self.batteryPercent = pct
        self.isCharging = charging
        self.isOnACPower = onAC

        if notifyChange, let prevAC = lastACState, prevAC != onAC {
            onPowerConnectionChanged?(onAC, pct)
        }
        lastACState = onAC
    }

    func refreshCPUAndMemory() {
        // CPU Delta via Mach host_statistics64
        var cpuInfo = host_cpu_load_info()
        var cpuCount = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        let cpuResult = withUnsafeMutablePointer(to: &cpuInfo) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(cpuCount)) {
                host_statistics64(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &cpuCount)
            }
        }
        if cpuResult == KERN_SUCCESS {
            if let prev = prevCPUInfo {
                let userDiff = cpuInfo.cpu_ticks.0 >= prev.cpu_ticks.0 ? Double(cpuInfo.cpu_ticks.0 - prev.cpu_ticks.0) : 0
                let sysDiff = cpuInfo.cpu_ticks.1 >= prev.cpu_ticks.1 ? Double(cpuInfo.cpu_ticks.1 - prev.cpu_ticks.1) : 0
                let idleDiff = cpuInfo.cpu_ticks.2 >= prev.cpu_ticks.2 ? Double(cpuInfo.cpu_ticks.2 - prev.cpu_ticks.2) : 0
                let niceDiff = cpuInfo.cpu_ticks.3 >= prev.cpu_ticks.3 ? Double(cpuInfo.cpu_ticks.3 - prev.cpu_ticks.3) : 0
                let total = userDiff + sysDiff + idleDiff + niceDiff
                if total > 0 {
                    let active = userDiff + sysDiff + niceDiff
                    cpuUsagePercent = min(100, max(0, Int(round((active / total) * 100.0))))
                }
            }
            prevCPUInfo = cpuInfo
        }

        // Memory via Mach HOST_VM_INFO64
        var pageSize: vm_size_t = 4096
        host_page_size(mach_host_self(), &pageSize)

        var vmStats = vm_statistics64()
        var vmCount = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let vmResult = withUnsafeMutablePointer(to: &vmStats) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(vmCount)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &vmCount)
            }
        }
        if vmResult == KERN_SUCCESS {
            // Activity Monitor App Memory (internal - purgeable) + Wired + Compressed
            let internalPages = UInt64(vmStats.internal_page_count)
            let purgeablePages = UInt64(vmStats.purgeable_count)
            let appPages = internalPages > purgeablePages ? (internalPages - purgeablePages) : 0
            let usedPages = appPages + UInt64(vmStats.wire_count) + UInt64(vmStats.compressor_page_count)
            let usedBytes = Double(usedPages) * Double(pageSize)
            memoryUsedGB = usedBytes / 1_073_741_824.0
        }
    }
}
