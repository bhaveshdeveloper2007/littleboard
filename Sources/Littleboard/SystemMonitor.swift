import Darwin
import Foundation

/// One shared system sampler behind every Activity widget: CPU load (total and
/// per core), memory breakdown, and the busiest programs by name. Samples every
/// two seconds while at least one widget is on screen; all widgets subscribe to
/// the same published sample so they update together.
@MainActor
final class SystemMonitor: ObservableObject {
    static let shared = SystemMonitor()

    struct Program: Identifiable {
        var name: String
        var percent: Double
        var id: String { name }
    }

    struct Sample {
        var cpuPercent: Double
        var corePercents: [Double]
        var usedBytes: Int64
        var totalBytes: Int64
        var appBytes: Int64
        var wiredBytes: Int64
        var compressedBytes: Int64
        var pressure: String
        var topPrograms: [Program]
    }

    @Published private(set) var sample: Sample?
    @Published private(set) var history: [Double] = []

    private var timer: Timer?
    private var lastCoreTicks: [[UInt32]] = []
    private var lastProcTimes: [Int32: UInt64] = [:]
    private var lastProcNames: [Int32: String] = [:]
    private var lastSampleDate = Date.distantPast
    private var subscriberCount = 0

    private init() {}

    func retainSampler() {
        subscriberCount += 1
        if timer == nil {
            timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.takeSample() }
            }
            timer?.tolerance = 0.5
            takeSample()
        }
    }

    func releaseSampler() {
        subscriberCount = max(0, subscriberCount - 1)
        if subscriberCount == 0 {
            timer?.invalidate()
            timer = nil
        }
    }

    private func takeSample() {
        let corePercents = sampleCPU()
        let cpuPercent = corePercents.isEmpty ? 0 : corePercents.reduce(0, +) / Double(max(1, corePercents.count))
        let memory = sampleMemory()
        let programs = samplePrograms(coreCount: max(1, corePercents.count))
        let used = memory.app + memory.wired + memory.compressed
        let ratio = memory.total > 0 ? Double(used) / Double(memory.total) : 0
        let pressure = ratio > 0.9 ? "Critical" : (ratio > 0.75 ? "Warning" : "Normal")
        let current = Sample(
            cpuPercent: cpuPercent,
            corePercents: corePercents,
            usedBytes: used,
            totalBytes: memory.total,
            appBytes: memory.app,
            wiredBytes: memory.wired,
            compressedBytes: memory.compressed,
            pressure: pressure,
            topPrograms: programs
        )
        sample = current
        history = (history + [cpuPercent]).suffix(26)
    }

    private func sampleCPU() -> [Double] {
        var cpuInfo: processor_info_array_t?
        var coreCount: natural_t = 0
        var messageCount: mach_msg_type_number_t = 0
        guard host_processor_info(mach_host_self(), HOST_CPU_LOAD_INFO, &coreCount, &cpuInfo, &messageCount) == KERN_SUCCESS,
              let cpuInfo else { return [] }
        defer {
            vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: cpuInfo)), vm_size_t(Int(coreCount)) * vm_size_t(MemoryLayout<processor_cpu_load_info_data_t>.stride))
        }
        let loadInfo = UnsafeRawPointer(cpuInfo)!.assumingMemoryBound(to: processor_cpu_load_info_data_t.self)
        var percents: [Double] = []
        var newTicks: [[UInt32]] = []
        for core in 0..<Int(coreCount) {
            let ticks = loadInfo[core].cpu_ticks
            let user = UInt32(max(0, ticks.0))
            let system = UInt32(max(0, ticks.1))
            let idle = UInt32(max(0, ticks.2))
            let nice = UInt32(max(0, ticks.3))
            newTicks.append([user, system, idle, nice])
            let previous = lastCoreTicks.count == Int(coreCount) ? lastCoreTicks[core] : nil
            guard let previous else { percents.append(0); continue }
            let deltaBusy = Int64(user - previous[0]) + Int64(system - previous[1]) + Int64(nice - previous[3])
            let deltaIdle = Int64(idle - previous[2])
            let total = deltaBusy + deltaIdle
            percents.append(total > 0 ? min(100, Double(deltaBusy) / Double(total) * 100) : 0)
        }
        lastCoreTicks = newTicks
        return percents
    }

    private func sampleMemory() -> (app: Int64, wired: Int64, compressed: Int64, total: Int64) {
        var stats = vm_statistics64()
        let integerCount = MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride
        var count = mach_msg_type_number_t(integerCount)
        let pointer = withUnsafeMutablePointer(to: &stats) { pointer -> integer_tPointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: integerCount) { $0 }
        }
        typealias integer_tPointer = UnsafeMutablePointer<integer_t>
        let status = host_statistics64(mach_host_self(), HOST_VM_INFO64, pointer, &count)
        guard status == KERN_SUCCESS else {
            return (0, 0, 0, Int64(ProcessInfo.processInfo.physicalMemory))
        }
        let pageSize = Int64(vm_kernel_page_size)
        let app = Int64(stats.active_count + stats.inactive_count + stats.speculative_count) * pageSize
        let wired = Int64(stats.wire_count) * pageSize
        let compressed = Int64(stats.compressor_page_count) * pageSize
        return (app, wired, compressed, Int64(ProcessInfo.processInfo.physicalMemory))
    }

    private func samplePrograms(coreCount: Int) -> [Program] {
        let pidCount = Int(proc_listallpids(nil, 0))
        guard pidCount > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: pidCount + 32)
        let real = Int(proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.stride)))
        guard real > 0 else { return [] }

        var currentTimes: [Int32: UInt64] = [:]
        for pid in pids.prefix(Int(real)) where pid > 0 {
            var info = proc_taskinfo()
            let size = Int32(MemoryLayout<proc_taskinfo>.stride)
            guard proc_pidinfo(pid, 4, 0, &info, size) == size else { continue } // PROC_PIDTASKINFO
            currentTimes[pid] = info.pti_total_user + info.pti_total_system
        }
        // Names are only needed for processes that consumed CPU this window.
        var currentNames: [Int32: String] = [:]
        for (pid, total) in currentTimes {
            guard let previous = lastProcTimes[pid], total > previous else { continue }
            var nameBuffer = [CChar](repeating: 0, count: 256)
            proc_name(pid, &nameBuffer, UInt32(nameBuffer.count))
            currentNames[pid] = String(cString: nameBuffer)
        }

        let elapsed = Date.now.timeIntervalSince(lastSampleDate)
        guard elapsed > 0.5 else {
            lastProcTimes = currentTimes
            lastProcNames = currentNames
            return []
        }
        var deltas: [String: Double] = [:]
        for (pid, total) in currentTimes {
            guard let previous = lastProcTimes[pid] else { continue }
            let delta = total > previous ? total - previous : 0
            guard delta > 0 else { continue }
            let name = baseProgramName(currentNames[pid] ?? lastProcNames[pid] ?? "?")
            deltas[name, default: 0] += Double(delta)
        }
        lastProcTimes = currentTimes
        lastProcNames = currentNames

        let elapsedNanos = elapsed * 1_000_000_000
        return deltas
            .map { Program(name: $0.key, percent: min(Double(coreCount) * 100, max(0, $0.value / elapsedNanos / Double(coreCount) * 100))) }
            .filter { $0.percent >= 0.4 }
            .sorted { $0.percent > $1.percent }
            .prefix(6)
            .map { $0 }
    }

    private func baseProgramName(_ raw: String) -> String {
        var name = raw
        if let range = name.range(of: " Helper") { name = String(name[..<range.lowerBound]) }
        if let range = name.range(of: ".helper") { name = String(name[..<range.lowerBound]) }
        if name.contains(".") { name = name.components(separatedBy: ".").last ?? name }
        return name
    }
}
