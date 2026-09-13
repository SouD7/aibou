import Darwin
import Foundation
import IOKit

struct CoreProcessIdentity: Hashable {
    var pid: Int32
    var startSeconds: UInt64
    var startMicroseconds: UInt64
}

struct CoreCPUTicks: Equatable {
    var user: UInt64
    var system: UInt64
    var nice: UInt64
    var idle: UInt64
}

struct CoreMemoryValues: Equatable {
    var occupied: UInt64
    var wired: UInt64
    var compressedPhysical: UInt64
    var nonCompressedOccupied: UInt64
    var fileBacked: UInt64
}

struct CoreGrowthPoint: Equatable {
    var uptime: Double
    var bytes: UInt64
}

struct CoreInterfaceCounters: Equatable {
    var receivedBytes: UInt64
    var sentBytes: UInt64
    var receivedPackets: UInt64
    var sentPackets: UInt64
    var inputErrors: UInt64
    var outputErrors: UInt64
}

struct CoreInterfaceReading: Equatable {
    var counters: CoreInterfaceCounters
    var flags: UInt32
}

struct CoreNetworkRates {
    var receivedBytesPerSecond: Double?
    var sentBytesPerSecond: Double?
    var status: ReadingStatus
}

struct CoreDiskDeviceCounters: Equatable {
    var readBytes: UInt64
    var writeBytes: UInt64
    var readErrors: UInt64?
    var writeErrors: UInt64?
}

struct CoreDiskRates {
    var readBytesPerSecond: Double?
    var writeBytesPerSecond: Double?
    var status: ReadingStatus
}

private struct CoreDiskSnapshot {
    var devices: [UInt64: CoreDiskDeviceCounters]
    var complete: Bool
}

enum CoreProcessIDEnumeration: Equatable {
    case success([Int32])
    case failure
}

struct CoreClockBaseline {
    var wall: Date
    var uptimeNanoseconds: UInt64
    var continuousNanoseconds: UInt64
}

struct CoreClockDelta {
    var uptimeInterval: Double
    var continuousInterval: Double
    var sleepGap: Double
    var jitter: Double?
    var wallStep: Double
}

struct CoreOptionalCounterResult {
    var value: UInt64?
    var status: ReadingStatus
}

final class CoreSampler {
    private struct ProcessCounters {
        var identity: CoreProcessIdentity
        var cpuNanoseconds: UInt64?
        var diskRead: UInt64?
        var diskWrite: UInt64?
    }

    private struct DiskCounters {
        var readBytes: UInt64
        var writeBytes: UInt64
        var errorCount: UInt64?
        var errorStatus: ReadingStatus
    }

    private struct AppMetadata {
        var bundleID: String?
        var displayName: String
    }

    private var previousProcesses: [Int32: ProcessCounters] = [:]
    private var previousProcessUptimeNanoseconds: UInt64?
    private var previousCoreTicks: [CoreCPUTicks]?
    private var previousInterfaces: [String: CoreInterfaceReading] = [:]
    private var previousDisks: [UInt64: CoreDiskDeviceCounters] = [:]
    private var previousDiskComplete = true
    private var previousClock: CoreClockBaseline?
    private var growthHistory: [CoreProcessIdentity: [CoreGrowthPoint]] = [:]
    private var appMetadataCache: [String: AppMetadata] = [:]
    private var timebase = mach_timebase_info_data_t()
    private let processIDLister: (UnsafeMutableRawPointer?, Int32) -> Int32
    private let cpuTickReader: () -> [CoreCPUTicks]?

    init(processIDLister: @escaping (UnsafeMutableRawPointer?, Int32) -> Int32 = { proc_listallpids($0, $1) },
         cpuTickReader: @escaping () -> [CoreCPUTicks]? = { CoreSampler.readPerCoreTicks() }) {
        self.processIDLister = processIDLister
        self.cpuTickReader = cpuTickReader
        mach_timebase_info(&timebase)
    }

    func reset(preservingClock: Bool = false) {
        previousProcesses.removeAll(keepingCapacity: true)
        previousProcessUptimeNanoseconds = nil
        previousCoreTicks = nil
        previousInterfaces.removeAll(keepingCapacity: true)
        previousDisks.removeAll(keepingCapacity: true)
        previousDiskComplete = true
        if !preservingClock { previousClock = nil }
        growthHistory.removeAll(keepingCapacity: true)
    }

    func sample(expectedInterval: Double = 2) -> CoreReading {
        let capturedAt = Date()
        let uptimeNanoseconds = nanoseconds(mach_absolute_time())
        let continuousNanoseconds = nanoseconds(mach_continuous_time())
        let elapsed = previousClock.flatMap {
            uptimeNanoseconds >= $0.uptimeNanoseconds
                ? Double(uptimeNanoseconds - $0.uptimeNanoseconds) / 1_000_000_000
                : nil
        }

        let processElapsed = previousProcessUptimeNanoseconds.flatMap {
            uptimeNanoseconds >= $0 ? Double(uptimeNanoseconds - $0) / 1_000_000_000 : nil
        }
        let processResult = readProcesses(capturedAt: capturedAt, uptime: Double(uptimeNanoseconds) / 1_000_000_000,
                                          elapsed: processElapsed)
        let coreTicks = cpuTickReader().flatMap { $0.isEmpty ? nil : $0 }
        let cpuPanel = makeCPUPanel(now: capturedAt, interval: elapsed, ticks: coreTicks,
                                    processes: processResult.samples,
                                    inaccessible: processResult.inaccessible,
                                    enumerationSucceeded: processResult.enumerationSucceeded)
        let memoryPanel = makeMemoryPanel(now: capturedAt, interval: elapsed,
                                          processes: processResult.samples)
        let clockPanel = makeClockPanel(now: capturedAt, expectedInterval: expectedInterval,
                                        uptimeNanoseconds: uptimeNanoseconds,
                                        continuousNanoseconds: continuousNanoseconds)
        let networkPanel = makeNetworkPanel(now: capturedAt, interval: elapsed)
        let storagePanel = makeStoragePanel(now: capturedAt, interval: elapsed,
                                            processes: processResult.samples)

        if processResult.enumerationSucceeded {
            previousProcesses = processResult.counters
            previousProcessUptimeNanoseconds = uptimeNanoseconds
        }
        previousCoreTicks = coreTicks
        previousClock = CoreClockBaseline(wall: capturedAt, uptimeNanoseconds: uptimeNanoseconds,
                                          continuousNanoseconds: continuousNanoseconds)

        return CoreReading(panels: [cpuPanel, memoryPanel, clockPanel, networkPanel, storagePanel],
                           processes: processResult.samples, capturedAt: capturedAt)
    }

    static func processCPUPercent(previousIdentity: CoreProcessIdentity?, currentIdentity: CoreProcessIdentity,
                                  previousNanoseconds: UInt64?, currentNanoseconds: UInt64?,
                                  elapsedSeconds: Double?) -> Double? {
        guard previousIdentity == currentIdentity, let previousNanoseconds, let currentNanoseconds else { return nil }
        return CounterMath.cpuPercent(previous: previousNanoseconds, current: currentNanoseconds,
                                      seconds: elapsedSeconds)
    }

    static func cpuPercentages(previous: CoreCPUTicks?, current: CoreCPUTicks) -> (user: Double, system: Double, idle: Double)? {
        guard let previous,
              current.user >= previous.user, current.system >= previous.system,
              current.nice >= previous.nice, current.idle >= previous.idle else { return nil }
        let user = current.user - previous.user
        let nice = current.nice - previous.nice
        let system = current.system - previous.system
        let idle = current.idle - previous.idle
        let total = user.addingReportingOverflow(nice).partialValue
            .addingReportingOverflow(system).partialValue
            .addingReportingOverflow(idle).partialValue
        guard total > 0 else { return nil }
        let scale = 100 / Double(total)
        return (Double(user + nice) * scale, Double(system) * scale, Double(idle) * scale)
    }

    static func memoryValues(physical: UInt64, freePages: UInt64, wiredPages: UInt64,
                             compressedPages: UInt64, externalPages: UInt64,
                             pageSize: UInt64) -> CoreMemoryValues? {
        guard pageSize > 0,
              let free = multiplied(freePages, pageSize),
              let wired = multiplied(wiredPages, pageSize),
              let compressed = multiplied(compressedPages, pageSize),
              let external = multiplied(externalPages, pageSize) else { return nil }
        let occupied = physical - min(physical, free)
        let known = min(occupied, saturatedAdd(wired, compressed))
        return CoreMemoryValues(occupied: occupied, wired: min(wired, physical),
                                compressedPhysical: min(compressed, physical),
                                nonCompressedOccupied: occupied - known,
                                fileBacked: min(external, physical))
    }

    static func growthEvidence(_ points: [CoreGrowthPoint]) -> String? {
        guard let first = points.first, let last = points.last,
              last.uptime - first.uptime >= 600, last.bytes > first.bytes else { return nil }
        let increase = last.bytes - first.bytes
        guard increase >= 64 * 1024 * 1024,
              Double(increase) / Double(max(first.bytes, 1)) >= 0.20 else { return nil }
        let nonDecreasing = zip(points, points.dropFirst()).filter { $1.bytes >= $0.bytes }.count
        guard points.count < 3 || Double(nonDecreasing) / Double(points.count - 1) >= 0.75 else { return nil }
        return "メモリ増加が継続（\(Int((last.uptime - first.uptime) / 60))分で \(ByteCountFormatter.string(fromByteCount: Int64(increase), countStyle: .binary)) 増加）。リークの断定ではありません"
    }

    static func isPhysicalAggregateInterface(_ name: String, flags: UInt32) -> Bool {
        guard flags & UInt32(IFF_UP) != 0, flags & UInt32(IFF_LOOPBACK) == 0 else { return false }
        guard name.hasPrefix("en") else { return false }
        return name.dropFirst(2).allSatisfy(\.isNumber)
    }

    static func parseInterfaceMessages(_ data: Data,
                                       nameForIndex: (UInt32) -> String?) -> [String: CoreInterfaceReading] {
        data.withUnsafeBytes { bytes in
            var result: [String: CoreInterfaceReading] = [:]
            var offset = 0
            let minimumHeaderBytes = 4
            while offset <= bytes.count - minimumHeaderBytes {
                let messageLength = Int(bytes.loadUnaligned(fromByteOffset: offset, as: UInt16.self))
                guard messageLength >= minimumHeaderBytes, messageLength <= bytes.count - offset else { break }
                let messageVersion = bytes[offset + 2]
                let messageType = bytes[offset + 3]
                if messageVersion == UInt8(RTM_VERSION), messageType == UInt8(RTM_IFINFO2),
                   messageLength >= MemoryLayout<if_msghdr2>.size {
                    let header = bytes.loadUnaligned(fromByteOffset: offset, as: if_msghdr2.self)
                    let index = UInt32(header.ifm_index)
                    if let name = nameForIndex(index) {
                        let statistics = header.ifm_data
                        result[name] = CoreInterfaceReading(
                            counters: CoreInterfaceCounters(
                                receivedBytes: statistics.ifi_ibytes,
                                sentBytes: statistics.ifi_obytes,
                                receivedPackets: statistics.ifi_ipackets,
                                sentPackets: statistics.ifi_opackets,
                                inputErrors: statistics.ifi_ierrors,
                                outputErrors: statistics.ifi_oerrors),
                            flags: UInt32(bitPattern: Int32(header.ifm_flags)))
                    }
                }
                offset += messageLength
            }
            return result
        }
    }

    static func networkRates(previous: [String: CoreInterfaceReading],
                             current: [String: CoreInterfaceReading],
                             seconds: Double?) -> CoreNetworkRates {
        let previousNames = Set(previous.compactMap { name, reading in
            isPhysicalAggregateInterface(name, flags: reading.flags) ? name : nil
        })
        let currentNames = Set(current.compactMap { name, reading in
            isPhysicalAggregateInterface(name, flags: reading.flags) ? name : nil
        })
        guard !previousNames.isEmpty else {
            return CoreNetworkRates(receivedBytesPerSecond: nil, sentBytesPerSecond: nil, status: .waiting)
        }
        guard let seconds, seconds > 0, seconds.isFinite else {
            return CoreNetworkRates(receivedBytesPerSecond: nil, sentBytesPerSecond: nil, status: .unavailable)
        }

        let commonNames = previousNames.intersection(currentNames)
        var receivedRate = 0.0
        var sentRate = 0.0
        var validCount = 0
        var complete = previousNames == currentNames
        for name in commonNames {
            guard let old = previous[name]?.counters, let new = current[name]?.counters,
                  let received = CounterMath.rate(previous: old.receivedBytes, current: new.receivedBytes, seconds: seconds),
                  let sent = CounterMath.rate(previous: old.sentBytes, current: new.sentBytes, seconds: seconds) else {
                complete = false
                continue
            }
            receivedRate += received
            sentRate += sent
            validCount += 1
        }
        guard validCount > 0 else {
            return CoreNetworkRates(receivedBytesPerSecond: nil, sentBytesPerSecond: nil, status: .partial)
        }
        return CoreNetworkRates(receivedBytesPerSecond: receivedRate,
                                sentBytesPerSecond: sentRate,
                                status: complete ? .derived : .partial)
    }

    static func diskRates(previous: [UInt64: CoreDiskDeviceCounters],
                          current: [UInt64: CoreDiskDeviceCounters],
                          seconds: Double?, previousComplete: Bool = true,
                          currentComplete: Bool = true) -> CoreDiskRates {
        guard !previous.isEmpty else {
            return CoreDiskRates(readBytesPerSecond: nil, writeBytesPerSecond: nil, status: .waiting)
        }
        guard let seconds, seconds > 0, seconds.isFinite else {
            return CoreDiskRates(readBytesPerSecond: nil, writeBytesPerSecond: nil, status: .unavailable)
        }
        let commonIDs = Set(previous.keys).intersection(current.keys)
        var readRate = 0.0
        var writeRate = 0.0
        var validCount = 0
        var complete = previousComplete && currentComplete
            && previous.keys.count == current.keys.count && commonIDs.count == previous.count
        for id in commonIDs {
            guard let old = previous[id], let new = current[id],
                  let read = CounterMath.rate(previous: old.readBytes, current: new.readBytes, seconds: seconds),
                  let write = CounterMath.rate(previous: old.writeBytes, current: new.writeBytes, seconds: seconds) else {
                complete = false
                continue
            }
            readRate += read
            writeRate += write
            validCount += 1
        }
        guard validCount > 0 else {
            return CoreDiskRates(readBytesPerSecond: nil, writeBytesPerSecond: nil, status: .partial)
        }
        return CoreDiskRates(readBytesPerSecond: readRate, writeBytesPerSecond: writeRate,
                             status: complete ? .derived : .partial)
    }

    static func optionalCounterTotal(_ values: [UInt64?]) -> CoreOptionalCounterResult {
        guard !values.isEmpty else { return CoreOptionalCounterResult(value: nil, status: .unavailable) }
        let known = values.compactMap { $0 }
        guard !known.isEmpty else { return CoreOptionalCounterResult(value: nil, status: .unavailable) }
        let total = known.reduce(0, saturatedAdd)
        return CoreOptionalCounterResult(value: total,
                                         status: known.count == values.count ? .measured : .partial)
    }

    static func clockDelta(previous: CoreClockBaseline, current: CoreClockBaseline,
                           expectedInterval: Double) -> CoreClockDelta? {
        guard current.uptimeNanoseconds >= previous.uptimeNanoseconds,
              current.continuousNanoseconds >= previous.continuousNanoseconds else { return nil }
        let uptime = Double(current.uptimeNanoseconds - previous.uptimeNanoseconds) / 1e9
        let continuous = Double(current.continuousNanoseconds - previous.continuousNanoseconds) / 1e9
        let sleep = max(0, continuous - uptime)
        let paused = sleep > max(0.25, expectedInterval * 0.25)
        return CoreClockDelta(uptimeInterval: uptime,
                              continuousInterval: continuous,
                              sleepGap: sleep,
                              jitter: paused ? nil : uptime - expectedInterval,
                              wallStep: current.wall.timeIntervalSince(previous.wall) - continuous)
    }

    private static func multiplied(_ lhs: UInt64, _ rhs: UInt64) -> UInt64? {
        let result = lhs.multipliedReportingOverflow(by: rhs)
        return result.overflow ? nil : result.partialValue
    }

    private static func saturatedAdd(_ lhs: UInt64, _ rhs: UInt64) -> UInt64 {
        let result = lhs.addingReportingOverflow(rhs)
        return result.overflow ? UInt64.max : result.partialValue
    }

    private func nanoseconds(_ absolute: UInt64) -> UInt64 {
        guard timebase.denom != 0 else { return absolute }
        let quotient = absolute / UInt64(timebase.denom)
        let remainder = absolute % UInt64(timebase.denom)
        return Self.saturatedAdd(quotient * UInt64(timebase.numer),
                                 remainder * UInt64(timebase.numer) / UInt64(timebase.denom))
    }

    private func readProcesses(capturedAt: Date, uptime: Double, elapsed: Double?)
        -> (samples: [ProcessSample], counters: [Int32: ProcessCounters], inaccessible: Int,
            enumerationSucceeded: Bool) {
        var samples: [ProcessSample] = []
        var counters: [Int32: ProcessCounters] = [:]
        var inaccessible = 0

        guard case let .success(processIDs) = listProcessIDs() else {
            return ([], [:], 0, false)
        }
        for pid in processIDs where pid > 0 {
            guard let bsd = readBSDInfo(pid), let task = readTaskInfo(pid) else {
                inaccessible += 1
                continue
            }
            let identity = CoreProcessIdentity(pid: pid, startSeconds: bsd.pbi_start_tvsec,
                                               startMicroseconds: bsd.pbi_start_tvusec)
            let usage = readRUsage(pid)
            let cpuTime = usage.map { Self.saturatedAdd($0.ri_user_time, $0.ri_system_time) }
                ?? Self.saturatedAdd(task.pti_total_user, task.pti_total_system)
            let old = previousProcesses[pid]
            let cpu = Self.processCPUPercent(previousIdentity: old?.identity, currentIdentity: identity,
                                             previousNanoseconds: old?.cpuNanoseconds,
                                             currentNanoseconds: cpuTime, elapsedSeconds: elapsed)
            let readRate = old?.identity == identity
                ? CounterMath.rate(previous: old?.diskRead, current: usage?.ri_diskio_bytesread ?? 0, seconds: elapsed) : nil
            let writeRate = old?.identity == identity
                ? CounterMath.rate(previous: old?.diskWrite, current: usage?.ri_diskio_byteswritten ?? 0, seconds: elapsed) : nil
            let path = processPath(pid)
            let metadata = appMetadata(path: path)
            let name = processName(pid, path: path)
            let owner = attribution(path: path, uid: bsd.pbi_uid, metadata: metadata)
            let footprint = usage?.ri_phys_footprint

            if let footprint {
                var history = growthHistory[identity] ?? []
                history.append(CoreGrowthPoint(uptime: uptime, bytes: footprint))
                history.removeAll { uptime - $0.uptime > 1_800 }
                if history.count > 900 { history.removeFirst(history.count - 900) }
                growthHistory[identity] = history
            }
            let growth = growthHistory[identity].flatMap(Self.growthEvidence)
            samples.append(ProcessSample(pid: pid, parentPID: Int32(bitPattern: bsd.pbi_ppid),
                                         startTime: Date(timeIntervalSince1970: TimeInterval(bsd.pbi_start_tvsec) + TimeInterval(bsd.pbi_start_tvusec) / 1_000_000),
                                         name: name, path: path, owner: owner, bundleID: metadata?.bundleID,
                                         cpuPercent: cpu, threadCount: Int(task.pti_threadnum),
                                         residentBytes: usage?.ri_resident_size ?? task.pti_resident_size,
                                         footprintBytes: footprint,
                                         diskReadBytes: usage?.ri_diskio_bytesread,
                                         diskWriteBytes: usage?.ri_diskio_byteswritten,
                                         readBytesPerSecond: usage == nil ? nil : readRate,
                                         writeBytesPerSecond: usage == nil ? nil : writeRate,
                                         growthNote: growth,
                                         measurementInterval: elapsed))
            counters[pid] = ProcessCounters(identity: identity, cpuNanoseconds: cpuTime,
                                             diskRead: usage?.ri_diskio_bytesread,
                                             diskWrite: usage?.ri_diskio_byteswritten)
        }
        let identities = Set(counters.values.map(\.identity))
        growthHistory = growthHistory.filter { identities.contains($0.key) }
        samples.sort { ($0.cpuPercent ?? -1, $0.residentBytes ?? 0) > ($1.cpuPercent ?? -1, $1.residentBytes ?? 0) }
        return (samples, counters, inaccessible, true)
    }

    private func makeCPUPanel(now: Date, interval: Double?, ticks: [CoreCPUTicks]?,
                              processes: [ProcessSample], inaccessible: Int,
                              enumerationSucceeded: Bool) -> PanelReading {
        let inventoryStatus: ReadingStatus = enumerationSucceeded
            ? (inaccessible == 0 ? .measured : .partial) : .unavailable
        let inventoryDetail = enumerationSucceeded
            ? (inaccessible == 0 ? "短命・権限制限のプロセスは含まれない場合があります" : "列挙には成功しましたが、\(inaccessible)件の詳細を取得できませんでした")
            : "libprocでプロセス一覧を取得できませんでした。0件とは扱いません"
        var metrics: [Metric] = [
            Metric("logicalCores", "論理コア数", value: Double(ProcessInfo.processInfo.activeProcessorCount), unit: "個",
                   source: "ProcessInfo.activeProcessorCount", recordedAt: now),
            Metric("processCount", "取得できたプロセス数", value: enumerationSucceeded ? Double(processes.count) : nil, unit: "個",
                   status: inventoryStatus, source: "libproc", detail: inventoryDetail, recordedAt: now),
            Metric("threadCount", "取得できた総スレッド数", value: enumerationSucceeded ? Double(processes.compactMap(\.threadCount).reduce(0, +)) : nil, unit: "本",
                   status: inventoryStatus, source: "proc_pidinfo(PROC_PIDTASKINFO)", detail: inventoryDetail, recordedAt: now)
        ]
        let currentTotal = ticks.map(sumTicks)
        let previousTotal = previousCoreTicks.map(sumTicks)
        let total = currentTotal.flatMap { Self.cpuPercentages(previous: previousTotal, current: $0) }
        for (id, label, value) in [("user", "ユーザー利用", total?.user), ("system", "システム利用", total?.system), ("idle", "アイドル", total?.idle)] {
            metrics.append(Metric(id, label, value: value, unit: "%", status: ticks == nil ? .unavailable : (value == nil ? .waiting : .derived),
                                  source: "host_processor_info(PROCESSOR_CPU_LOAD_INFO)",
                                  detail: ticks == nil ? "Mach APIからCPU tickを取得できませんでした" : "論理コアのtick差分から算出", recordedAt: now, interval: interval))
        }
        if let ticks {
            for index in ticks.indices {
                let value = previousCoreTicks.flatMap { index < $0.count ? Self.cpuPercentages(previous: $0[index], current: ticks[index]) : nil }
                metrics.append(Metric("core\(index)", "論理コア \(index)", value: value.map { $0.user + $0.system }, unit: "%",
                                      status: value == nil ? .waiting : .derived,
                                      source: "host_processor_info(PROCESSOR_CPU_LOAD_INFO)", recordedAt: now, interval: interval))
            }
        } else {
            metrics.append(Metric("cores", "論理コア別稼働率", status: .unavailable,
                                  source: "host_processor_info", detail: "Mach APIからCPU tickを取得できませんでした", recordedAt: now))
        }
        let rows = processes.map { process in
            ReadingRow(id: process.id, name: process.name, metrics: [
                Metric("cpu", "%CPU", value: process.cpuPercent, unit: "%", status: process.cpuPercent == nil ? .waiting : .derived,
                       source: "proc_pid_rusage/proc_pidinfo", detail: "1論理コアを使い切ると100%。複数コア利用時は100%超", recordedAt: now, interval: process.measurementInterval),
                Metric("threads", "スレッド", value: process.threadCount.map { Double($0) }, unit: "本", status: process.threadCount == nil ? .unavailable : .measured,
                       source: "proc_pidinfo(PROC_PIDTASKINFO)", recordedAt: now),
                Metric("pid", "PID", value: Double(process.pid), source: "proc_bsdinfo", recordedAt: now),
                Metric("parent", "親PID", value: Double(process.parentPID), source: "proc_bsdinfo", recordedAt: now),
                Metric("started", "起動日時", text: ISO8601DateFormatter().string(from: process.startTime), source: "proc_bsdinfo", recordedAt: now),
                Metric("owner", "帰属", text: process.owner, status: process.bundleID == nil ? .estimated : .derived,
                       source: "実行パス・bundle metadata・UID",
                       detail: process.bundleID == nil ? "実行パスとUIDによる分類。親PIDとは別情報" : "bundle identifierを確認したアプリ帰属。親PIDとは別情報",
                       recordedAt: now)
            ], path: process.path, bundleID: process.bundleID)
        }
        return PanelReading(tab: .cpu, metrics: metrics,
                            columns: [TableColumn("cpu", "%CPU"), TableColumn("threads", "スレッド"), TableColumn("pid", "PID"), TableColumn("parent", "親PID"), TableColumn("started", "起動日時", width: 190), TableColumn("owner", "帰属", width: 180)],
                            rows: rows, notes: ["プロセスCPUの分母は経過時間1秒です。ホストCPUは全論理コアのtick割合です。", enumerationSucceeded ? "取得不可プロセス: \(inaccessible)" : "プロセス一覧の取得に失敗しました"], capturedAt: now)
    }

    private func makeMemoryPanel(now: Date, interval: Double?, processes: [ProcessSample]) -> PanelReading {
        let physical = ProcessInfo.processInfo.physicalMemory
        let vm = readVMStatistics()
        let swap = readSwap()
        var metrics: [Metric] = [
            Metric("physical", "物理メモリ", value: Double(physical), unit: "B", source: "ProcessInfo.physicalMemory", recordedAt: now)
        ]
        let values = vm.flatMap { Self.memoryValues(physical: physical, freePages: UInt64($0.free_count), wiredPages: UInt64($0.wire_count), compressedPages: UInt64($0.compressor_page_count), externalPages: UInt64($0.external_page_count), pageSize: UInt64(vm_kernel_page_size)) }
        for (id, label, value, detail) in [
            ("occupied", "RAM占有量", values?.occupied, "物理RAM−free。キャッシュを含む現在占有量"),
            ("wired", "ワイヤード", values?.wired, "RAM内のwire_count"),
            ("uncompressed", "非圧縮占有量", values?.nonCompressedOccupied, "占有量−ワイヤード−物理コンプレッサ領域"),
            ("compressed", "圧縮メモリ（物理）", values?.compressedPhysical, "compressor_page_count。圧縮前相当量ではない"),
            ("fileCache", "ファイルバックページ", values?.fileBacked, "external_page_count。解放可能量と同義ではない")
        ] {
            metrics.append(Metric(id, label, value: value.map { Double($0) }, unit: "B", status: value == nil ? .unavailable : .measured,
                                  source: "host_statistics64(HOST_VM_INFO64)", detail: detail, recordedAt: now, interval: interval))
        }
        metrics.append(Metric("swapTotal", "スワップ総量", value: swap.map { Double($0.total) }, unit: "B", status: swap == nil ? .unavailable : .measured, source: "sysctl vm.swapusage", recordedAt: now))
        metrics.append(Metric("swapUsed", "スワップ使用量", value: swap.map { Double($0.used) }, unit: "B", status: swap == nil ? .unavailable : .measured, source: "sysctl vm.swapusage", recordedAt: now))
        metrics.append(Metric("ramBandwidth", "RAM読み書き速度", status: .unsupported, source: "macOS公開API", detail: "プロセス別・全体RAM帯域を安定して公開するAPIがありません", recordedAt: now))
        metrics.append(Metric("ramLatency", "RAMレイテンシ", status: .unsupported, source: "macOS公開API", detail: "リアルタイムのRAMアクセスレイテンシを公開するAPIがありません", recordedAt: now))

        let rows = processes.map { process in
            ReadingRow(id: process.id, name: process.name, metrics: [
                Metric("resident", "常駐量", value: process.residentBytes.map { Double($0) }, unit: "B", status: process.residentBytes == nil ? .unavailable : .measured, source: "proc_pid_rusage/proc_taskinfo", recordedAt: now),
                Metric("footprint", "物理フットプリント", value: process.footprintBytes.map { Double($0) }, unit: "B", status: process.footprintBytes == nil ? .unavailable : .measured, source: "proc_pid_rusage", recordedAt: now),
                Metric("wired", "ワイヤード内訳", status: .unsupported, source: "macOSプロセス情報API", detail: "信頼できるプロセス別内訳を取得できません", recordedAt: now),
                Metric("compressed", "圧縮内訳", status: .unsupported, source: "macOSプロセス情報API", detail: "信頼できるプロセス別内訳を取得できません", recordedAt: now),
                Metric("cache", "キャッシュ内訳", status: .unsupported, source: "macOSプロセス情報API", detail: "信頼できるプロセス別内訳を取得できません", recordedAt: now),
                Metric("growth", "増加傾向", text: process.growthNote ?? "観測中", status: process.growthNote == nil ? .waiting : .estimated,
                       source: "物理フットプリントの最大30分履歴", detail: "10分以上・64MiB以上・20%以上・75%以上の区間で非減少の場合のみタグ付け。診断ではありません", recordedAt: now),
                Metric("pid", "PID", value: Double(process.pid), source: "proc_bsdinfo", recordedAt: now),
                Metric("parent", "親PID", value: Double(process.parentPID), source: "proc_bsdinfo", recordedAt: now),
                Metric("owner", "帰属", text: process.owner, status: process.bundleID == nil ? .estimated : .derived,
                       source: "実行パス・bundle metadata・UID",
                       detail: process.bundleID == nil ? "実行パスとUIDによる分類。親PIDとは別情報" : "bundle identifierを確認したアプリ帰属。親PIDとは別情報",
                       recordedAt: now)
            ], path: process.path, bundleID: process.bundleID)
        }
        return PanelReading(tab: .memory, metrics: metrics,
                            columns: [TableColumn("resident", "常駐量"), TableColumn("footprint", "フットプリント"), TableColumn("wired", "ワイヤード"), TableColumn("compressed", "圧縮"), TableColumn("cache", "キャッシュ"), TableColumn("growth", "増加傾向", width: 260), TableColumn("pid", "PID"), TableColumn("parent", "親PID"), TableColumn("owner", "帰属", width: 180)],
                            rows: rows, notes: ["ワイヤードはRAM内の領域で、スワップとは合算しません。プロセス別内訳の欠損を0で埋めません。"], capturedAt: now)
    }

    private func makeClockPanel(now: Date, expectedInterval: Double, uptimeNanoseconds: UInt64,
                                continuousNanoseconds: UInt64) -> PanelReading {
        let current = CoreClockBaseline(wall: now, uptimeNanoseconds: uptimeNanoseconds,
                                        continuousNanoseconds: continuousNanoseconds)
        guard let previous = previousClock,
              let delta = Self.clockDelta(previous: previous, current: current,
                                          expectedInterval: expectedInterval) else {
            return PanelReading(tab: .clock, metrics: waitingClockMetrics(now), notes: ["初回は差分計測待ちです。動作周波数は追加収集（powermetrics）側で扱います。"], capturedAt: now)
        }
        let paused = delta.jitter == nil
        return PanelReading(tab: .clock, metrics: [
            Metric("uptimeInterval", "稼働中の計測間隔", value: delta.uptimeInterval, unit: "s", status: .derived, source: "mach_absolute_time", recordedAt: now, interval: delta.uptimeInterval),
            Metric("continuousInterval", "スリープを含む間隔", value: delta.continuousInterval, unit: "s", status: .derived, source: "mach_continuous_time", recordedAt: now, interval: delta.continuousInterval),
            Metric("sleepGap", "停止・スリープ相当", value: delta.sleepGap, unit: "s", status: .derived, source: "continuous−uptime", detail: paused ? "通常のスケジュール遅延から分離しました" : "大きな停止は検出されませんでした", recordedAt: now),
            Metric("jitter", "スケジュールジッター", value: delta.jitter, unit: "s", status: delta.jitter == nil ? .stale : .derived, source: "uptime間隔−期待間隔", detail: paused ? "停止・スリープ区間のため評価しません" : "CPUクロック回路の異常判定ではありません", recordedAt: now, interval: delta.uptimeInterval),
            Metric("wallStep", "壁時計との差", value: delta.wallStep, unit: "s", status: .derived, source: "Date差分−mach_continuous_time差分", detail: "時計補正や計測誤差の候補。故障診断ではありません", recordedAt: now, interval: delta.continuousInterval),
            Metric("frequency", "CPU動作周波数", status: .waiting, source: "追加収集 powermetrics", detail: "公開APIの安定した瞬時周波数ではないため、この基本収集では値を作りません", recordedAt: now)
        ], capturedAt: now)
    }

    private func waitingClockMetrics(_ now: Date) -> [Metric] {
        [Metric("uptimeInterval", "稼働中の計測間隔", status: .waiting, source: "mach_absolute_time", recordedAt: now),
         Metric("continuousInterval", "スリープを含む間隔", status: .waiting, source: "mach_continuous_time", recordedAt: now),
         Metric("sleepGap", "停止・スリープ相当", status: .waiting, source: "continuous−uptime", recordedAt: now),
         Metric("jitter", "スケジュールジッター", status: .waiting, source: "uptime間隔−期待間隔", recordedAt: now),
         Metric("wallStep", "壁時計との差", status: .waiting, source: "Date差分−mach_continuous_time差分", recordedAt: now),
         Metric("frequency", "CPU動作周波数", status: .waiting, source: "追加収集 powermetrics", recordedAt: now)]
    }

    private func makeNetworkPanel(now: Date, interval: Double?) -> PanelReading {
        guard let current = readInterfaces() else {
            previousInterfaces.removeAll(keepingCapacity: true)
            return PanelReading(tab: .network,
                                metrics: [Metric("interfaceIO", "ネットワークI/O", status: .unavailable,
                                                 source: "sysctl NET_RT_IFLIST2 / if_msghdr2",
                                                 detail: "64bitインターフェース統計を取得できませんでした。0として扱いません",
                                                 recordedAt: now)],
                                notes: ["取得失敗後は速度の基準を破棄し、次の成功サンプルを新しい基準にします。"],
                                capturedAt: now)
        }
        let physicalNames = current.keys.filter { Self.isPhysicalAggregateInterface($0, flags: current[$0]!.flags) }
        let physical = physicalNames.reduce(CoreInterfaceCounters(receivedBytes: 0, sentBytes: 0, receivedPackets: 0, sentPackets: 0, inputErrors: 0, outputErrors: 0)) { result, name in
            let value = current[name]!.counters
            return CoreInterfaceCounters(receivedBytes: Self.saturatedAdd(result.receivedBytes, value.receivedBytes), sentBytes: Self.saturatedAdd(result.sentBytes, value.sentBytes), receivedPackets: Self.saturatedAdd(result.receivedPackets, value.receivedPackets), sentPackets: Self.saturatedAdd(result.sentPackets, value.sentPackets), inputErrors: Self.saturatedAdd(result.inputErrors, value.inputErrors), outputErrors: Self.saturatedAdd(result.outputErrors, value.outputErrors))
        }
        let aggregateRates = Self.networkRates(previous: previousInterfaces, current: current, seconds: interval)
        let source = "sysctl NET_RT_IFLIST2 / if_msghdr2"
        let metrics = [
            Metric("rxBytes", "物理IF受信量", value: Double(physical.receivedBytes), unit: "B", source: source, recordedAt: now),
            Metric("txBytes", "物理IF送信量", value: Double(physical.sentBytes), unit: "B", source: source, recordedAt: now),
            Metric("rxRate", "物理IF受信速度", value: aggregateRates.receivedBytesPerSecond, unit: "B/s", status: aggregateRates.status, source: "64bit IFカウンタのインターフェース別差分合計", detail: aggregateRates.status == .partial ? "IF追加・削除またはカウンタリセットを除外した部分値" : "", recordedAt: now, interval: interval),
            Metric("txRate", "物理IF送信速度", value: aggregateRates.sentBytesPerSecond, unit: "B/s", status: aggregateRates.status, source: "64bit IFカウンタのインターフェース別差分合計", detail: aggregateRates.status == .partial ? "IF追加・削除またはカウンタリセットを除外した部分値" : "", recordedAt: now, interval: interval)
        ]
        let rows = current.keys.sorted().map { name -> ReadingRow in
            let value = current[name]!
            let old = previousInterfaces[name]
            return ReadingRow(id: name, name: name, metrics: [
                Metric("rxBytes", "受信バイト", value: Double(value.counters.receivedBytes), unit: "B", source: source, recordedAt: now),
                Metric("txBytes", "送信バイト", value: Double(value.counters.sentBytes), unit: "B", source: source, recordedAt: now),
                Metric("rxPackets", "受信パケット", value: Double(value.counters.receivedPackets), unit: "個", source: source, recordedAt: now),
                Metric("txPackets", "送信パケット", value: Double(value.counters.sentPackets), unit: "個", source: source, recordedAt: now),
                Metric("rxRate", "受信速度", value: CounterMath.rate(previous: old?.counters.receivedBytes, current: value.counters.receivedBytes, seconds: interval), unit: "B/s", status: rateStatus(previous: old?.counters.receivedBytes, current: value.counters.receivedBytes, interval: interval), source: "64bit IFカウンタ差分", recordedAt: now, interval: interval),
                Metric("txRate", "送信速度", value: CounterMath.rate(previous: old?.counters.sentBytes, current: value.counters.sentBytes, seconds: interval), unit: "B/s", status: rateStatus(previous: old?.counters.sentBytes, current: value.counters.sentBytes, interval: interval), source: "64bit IFカウンタ差分", recordedAt: now, interval: interval),
                Metric("errors", "入出力エラー", value: Double(Self.saturatedAdd(value.counters.inputErrors, value.counters.outputErrors)), unit: "個", source: source, recordedAt: now),
                Metric("aggregate", "物理集計", text: Self.isPhysicalAggregateInterface(name, flags: value.flags) ? "対象" : "対象外", status: .derived, source: "AIBOU集計規則", recordedAt: now)
            ])
        }
        previousInterfaces = current
        return PanelReading(tab: .network, metrics: metrics,
                            columns: [TableColumn("rxBytes", "受信量"), TableColumn("txBytes", "送信量"), TableColumn("rxPackets", "受信packet"), TableColumn("txPackets", "送信packet"), TableColumn("rxRate", "受信速度"), TableColumn("txRate", "送信速度"), TableColumn("errors", "エラー"), TableColumn("aggregate", "物理集計")],
                            rows: rows, notes: ["全IFを64bitカウンタで個別表示します。物理集計はUP状態の en+数字 のみを合算し、loopback・VPN・awdl・bridge等の二重計上候補を除外します。IF集合が変わった区間は継続IFだけの部分速度です。"], capturedAt: now)
    }

    private func makeStoragePanel(now: Date, interval: Double?, processes: [ProcessSample]) -> PanelReading {
        let diskSnapshot = readDiskCounters()
        var metrics: [Metric]
        if let diskSnapshot {
            let disks = diskSnapshot.devices
            let disk = Self.aggregateDiskCounters(diskSnapshot)
            let rates = Self.diskRates(previous: previousDisks, current: disks, seconds: interval,
                                       previousComplete: previousDiskComplete,
                                       currentComplete: diskSnapshot.complete)
            let cumulativeStatus: ReadingStatus = diskSnapshot.complete ? .measured : .partial
            metrics = [
                Metric("deviceRead", "デバイス累積読込", value: Double(disk.readBytes), unit: "B", status: cumulativeStatus, source: "IORegistry IOBlockStorageDriver/Statistics", detail: diskSnapshot.complete ? "" : "一部IORegistry entryの統計を取得できませんでした", recordedAt: now),
                Metric("deviceWrite", "デバイス累積書込", value: Double(disk.writeBytes), unit: "B", status: cumulativeStatus, source: "IORegistry IOBlockStorageDriver/Statistics", detail: diskSnapshot.complete ? "" : "一部IORegistry entryの統計を取得できませんでした", recordedAt: now),
                Metric("deviceReadRate", "デバイス読込速度", value: rates.readBytesPerSecond, unit: "B/s", status: rates.status, source: "IORegistry entry別カウンタ差分", detail: rates.status == .partial ? "追加・削除・一時欠損・カウンタリセットを除外した部分値" : "", recordedAt: now, interval: interval),
                Metric("deviceWriteRate", "デバイス書込速度", value: rates.writeBytesPerSecond, unit: "B/s", status: rates.status, source: "IORegistry entry別カウンタ差分", detail: rates.status == .partial ? "追加・削除・一時欠損・カウンタリセットを除外した部分値" : "", recordedAt: now, interval: interval),
                Metric("deviceErrors", "デバイスI/Oエラー", value: disk.errorCount.map { Double($0) }, unit: "個",
                       status: disk.errorStatus, source: "IORegistry IOBlockStorageDriver/Statistics",
                       detail: disk.errorStatus == .partial ? "一部デバイスまたは読み書き片側のエラーカウンタが未公開です" :
                           (disk.errorStatus == .unavailable ? "エラーカウンタが公開されていません。0件とは扱いません" : ""),
                       recordedAt: now)
            ]
        } else {
            metrics = [Metric("deviceIO", "デバイスI/O", status: .unavailable, source: "IORegistry IOBlockStorageDriver/Statistics", detail: "対応するIORegistry統計を取得できませんでした。0として扱いません", recordedAt: now)]
        }
        // APFS shares container space. This is the writable startup volume's filesystem
        // free space, not Finder's purgeable/important-usage estimate or SSD health.
        let volumePath = FileManager.default.fileExists(atPath: "/System/Volumes/Data") ? "/System/Volumes/Data" : "/"
        let attributes = try? FileManager.default.attributesOfFileSystem(forPath: volumePath)
        metrics += Self.volumeMetrics(total: (attributes?[.systemSize] as? NSNumber)?.doubleValue,
                                      free: (attributes?[.systemFreeSize] as? NSNumber)?.doubleValue, at: now)
        previousDisks = diskSnapshot?.devices ?? [:]
        previousDiskComplete = diskSnapshot?.complete ?? true
        let rows = processes.filter { $0.diskReadBytes != nil || $0.diskWriteBytes != nil }.map { process in
            ReadingRow(id: process.id, name: process.name, metrics: [
                Metric("read", "累積読込", value: process.diskReadBytes.map { Double($0) }, unit: "B", source: "proc_pid_rusage(RUSAGE_INFO_V2)", recordedAt: now),
                Metric("write", "累積書込", value: process.diskWriteBytes.map { Double($0) }, unit: "B", source: "proc_pid_rusage(RUSAGE_INFO_V2)", recordedAt: now),
                Metric("readRate", "読込速度", value: process.readBytesPerSecond, unit: "B/s", status: process.readBytesPerSecond == nil ? .waiting : .derived, source: "libprocカウンタ差分", recordedAt: now, interval: process.measurementInterval),
                Metric("writeRate", "書込速度", value: process.writeBytesPerSecond, unit: "B/s", status: process.writeBytesPerSecond == nil ? .waiting : .derived, source: "libprocカウンタ差分", recordedAt: now, interval: process.measurementInterval),
                Metric("owner", "帰属", text: process.owner, status: process.bundleID == nil ? .estimated : .derived,
                       source: "実行パス・bundle metadata・UID", recordedAt: now)
            ], path: process.path, bundleID: process.bundleID)
        }
        return PanelReading(tab: .storage, metrics: metrics,
                            columns: [TableColumn("read", "読込量"), TableColumn("write", "書込量"), TableColumn("readRate", "読込速度"), TableColumn("writeRate", "書込速度"), TableColumn("owner", "帰属")],
                            rows: rows, notes: ["これはIOBlockStorageDriverの累積カウンタ合計です。速度は同じIORegistry entryが両時点にある場合だけ差分化し、構成変更区間は部分取得とします。APFS論理ボリューム別やファイル走査の値ではありません。プロセス値とデバイス値は集計範囲が異なります。"], capturedAt: now)
    }

    static func volumeMetrics(total: Double?, free: Double?, at now: Date) -> [Metric] {
        let valid = total.map { $0.isFinite && $0 > 0 } == true &&
            free.map { $0.isFinite && $0 >= 0 && $0 <= (total ?? 0) } == true
        return [("volumeTotal", "起動データ領域の総容量", total), ("volumeFree", "起動データ領域の空き", free)].map { id, label, value in
            Metric(id, label, value: valid ? value : nil, unit: "B", status: valid ? .measured : .unavailable,
                   source: "FileManager.attributesOfFileSystem",
                   detail: "起動データ領域のファイルシステム容量。APFS共有領域・消去可能領域の扱いによりFinderの表示とは異なります。SSD故障の指標ではありません。",
                   recordedAt: now)
        }
    }

    private static func readPerCoreTicks() -> [CoreCPUTicks]? {
        var count: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        let result = host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &count, &info, &infoCount)
        guard result == KERN_SUCCESS, let info else { return nil }
        defer {
            vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: info)), vm_size_t(infoCount) * vm_size_t(MemoryLayout<integer_t>.stride))
        }
        let stride = Int(CPU_STATE_MAX)
        guard infoCount >= count * natural_t(stride) else { return nil }
        return (0..<Int(count)).map { core in
            let offset = core * stride
            return CoreCPUTicks(user: UInt64(UInt32(bitPattern: info[offset + Int(CPU_STATE_USER)])),
                                system: UInt64(UInt32(bitPattern: info[offset + Int(CPU_STATE_SYSTEM)])),
                                nice: UInt64(UInt32(bitPattern: info[offset + Int(CPU_STATE_NICE)])),
                                idle: UInt64(UInt32(bitPattern: info[offset + Int(CPU_STATE_IDLE)])))
        }
    }

    private func rateStatus(previous: UInt64?, current: UInt64, interval: Double?) -> ReadingStatus {
        guard let previous else { return .waiting }
        guard let interval, interval > 0, interval.isFinite, current >= previous else { return .unavailable }
        return .derived
    }

    private func sumTicks(_ values: [CoreCPUTicks]) -> CoreCPUTicks {
        values.reduce(CoreCPUTicks(user: 0, system: 0, nice: 0, idle: 0)) { result, item in
            CoreCPUTicks(user: Self.saturatedAdd(result.user, item.user), system: Self.saturatedAdd(result.system, item.system), nice: Self.saturatedAdd(result.nice, item.nice), idle: Self.saturatedAdd(result.idle, item.idle))
        }
    }

    private func listProcessIDs() -> CoreProcessIDEnumeration {
        // libproc can translate syscall failure into zero while preserving errno.
        errno = 0
        let estimate = processIDLister(nil, 0)
        let estimateError = errno
        guard estimate >= 0, !(estimate == 0 && estimateError != 0) else { return .failure }
        guard estimate > 0 else { return .success([]) }
        var pids = [Int32](repeating: 0, count: Int(estimate) + 128)
        let result: (count: Int32, error: Int32) = pids.withUnsafeMutableBytes {
            errno = 0
            let count = processIDLister($0.baseAddress, Int32($0.count))
            return (count, errno)
        }
        let returned = result.count
        guard returned >= 0, !(returned == 0 && result.error != 0) else { return .failure }
        return .success(Array(pids.prefix(min(Int(returned), pids.count))))
    }

    private func readBSDInfo(_ pid: Int32) -> proc_bsdinfo? {
        var value = proc_bsdinfo()
        let size = MemoryLayout<proc_bsdinfo>.stride
        let result = withUnsafeMutablePointer(to: &value) { proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, $0, Int32(size)) }
        return result == size ? value : nil
    }

    private func readTaskInfo(_ pid: Int32) -> proc_taskinfo? {
        var value = proc_taskinfo()
        let size = MemoryLayout<proc_taskinfo>.stride
        let result = withUnsafeMutablePointer(to: &value) { proc_pidinfo(pid, PROC_PIDTASKINFO, 0, $0, Int32(size)) }
        return result == size ? value : nil
    }

    private func readRUsage(_ pid: Int32) -> rusage_info_v2? {
        var value = rusage_info_v2()
        let result = withUnsafeMutablePointer(to: &value) { pointer in
            proc_pid_rusage(pid, RUSAGE_INFO_V2, UnsafeMutableRawPointer(pointer).assumingMemoryBound(to: rusage_info_t?.self))
        }
        return result == 0 ? value : nil
    }

    private func processPath(_ pid: Int32) -> String {
        var bytes = [CChar](repeating: 0, count: Int(4 * MAXPATHLEN))
        let count = bytes.withUnsafeMutableBufferPointer { proc_pidpath(pid, $0.baseAddress, UInt32($0.count)) }
        return count > 0 ? String(cString: bytes) : ""
    }

    private func processName(_ pid: Int32, path: String) -> String {
        var bytes = [CChar](repeating: 0, count: Int(2 * MAXCOMLEN + 1))
        let count = bytes.withUnsafeMutableBufferPointer { proc_name(pid, $0.baseAddress, UInt32($0.count)) }
        if count > 0 { return String(cString: bytes) }
        return path.isEmpty ? "PID \(pid)" : URL(fileURLWithPath: path).lastPathComponent
    }

    private func appMetadata(path: String) -> AppMetadata? {
        guard let range = path.range(of: ".app/", options: [.caseInsensitive, .backwards]) else { return nil }
        let appPath = String(path[..<range.lowerBound]) + ".app"
        if let cached = appMetadataCache[appPath] { return cached }
        let bundle = Bundle(path: appPath)
        let fallback = URL(fileURLWithPath: appPath).deletingPathExtension().lastPathComponent
        let metadata = AppMetadata(bundleID: bundle?.bundleIdentifier,
                                   displayName: (bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                                       ?? (bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String) ?? fallback)
        appMetadataCache[appPath] = metadata
        return metadata
    }

    private func attribution(path: String, uid: uid_t, metadata: AppMetadata?) -> String {
        if let metadata { return "アプリ: \(metadata.displayName)" }
        if path.hasPrefix("/System/") || path.hasPrefix("/usr/libexec/") { return "OS" }
        if uid == 0 { return "システム" }
        if let user = getpwuid(uid), let name = user.pointee.pw_name { return "ユーザー: \(String(cString: name))" }
        return "ユーザーUID: \(uid)"
    }

    private func readVMStatistics() -> vm_statistics64_data_t? {
        var value = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &value) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        return result == KERN_SUCCESS ? value : nil
    }

    private func readSwap() -> (total: UInt64, used: UInt64)? {
        var value = xsw_usage()
        var size = MemoryLayout<xsw_usage>.stride
        return sysctlbyname("vm.swapusage", &value, &size, nil, 0) == 0 ? (value.xsu_total, value.xsu_used) : nil
    }

    private func readInterfaces() -> [String: CoreInterfaceReading]? {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        var length = 0
        let sizeResult = mib.withUnsafeMutableBufferPointer {
            sysctl($0.baseAddress, u_int($0.count), nil, &length, nil, 0)
        }
        guard sizeResult == 0, length > 0 else { return nil }
        var data = Data(count: length)
        let readResult = mib.withUnsafeMutableBufferPointer { mibBuffer in
            data.withUnsafeMutableBytes { dataBuffer in
                sysctl(mibBuffer.baseAddress, u_int(mibBuffer.count), dataBuffer.baseAddress,
                       &length, nil, 0)
            }
        }
        guard readResult == 0, length <= data.count else { return nil }
        if length < data.count { data.removeSubrange(length..<data.count) }
        return Self.parseInterfaceMessages(data) { index in
            var name = [CChar](repeating: 0, count: Int(IFNAMSIZ))
            guard if_indextoname(index, &name) != nil else { return nil }
            return String(cString: name)
        }
    }

    private static func aggregateDiskCounters(_ snapshot: CoreDiskSnapshot) -> DiskCounters {
        let errors = optionalCounterTotal(snapshot.devices.values.flatMap { [$0.readErrors, $0.writeErrors] })
        let errorStatus: ReadingStatus = !snapshot.complete && errors.value != nil ? .partial : errors.status
        return DiskCounters(readBytes: snapshot.devices.values.reduce(0) { saturatedAdd($0, $1.readBytes) },
                            writeBytes: snapshot.devices.values.reduce(0) { saturatedAdd($0, $1.writeBytes) },
                            errorCount: errors.value, errorStatus: errorStatus)
    }

    private func readDiskCounters() -> CoreDiskSnapshot? {
        guard let matching = IOServiceMatching("IOBlockStorageDriver") else { return nil }
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }
        var devices: [UInt64: CoreDiskDeviceCounters] = [:]
        var complete = true
        while true {
            let service = IOIteratorNext(iterator)
            guard service != 0 else { break }
            defer { IOObjectRelease(service) }
            var entryID: UInt64 = 0
            guard IORegistryEntryGetRegistryEntryID(service, &entryID) == KERN_SUCCESS else {
                complete = false
                continue
            }
            guard let property = IORegistryEntryCreateCFProperty(service, "Statistics" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue(),
                  let stats = property as? [String: Any],
                  let read = (stats["Bytes (Read)"] as? NSNumber)?.uint64Value,
                  let write = (stats["Bytes (Write)"] as? NSNumber)?.uint64Value else {
                complete = false
                continue
            }
            devices[entryID] = CoreDiskDeviceCounters(
                readBytes: read, writeBytes: write,
                readErrors: (stats["Errors (Read)"] as? NSNumber)?.uint64Value,
                writeErrors: (stats["Errors (Write)"] as? NSNumber)?.uint64Value)
        }
        return devices.isEmpty ? nil : CoreDiskSnapshot(devices: devices, complete: complete)
    }
}
