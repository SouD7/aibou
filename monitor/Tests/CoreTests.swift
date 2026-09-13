import Darwin
import Foundation

private func coreAssert(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() {
        throw NSError(domain: "AIBOU.CoreTests", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}

func runCoreTests() throws {
    let identity = CoreProcessIdentity(pid: 42, startSeconds: 100, startMicroseconds: 5)
    let reused = CoreProcessIdentity(pid: 42, startSeconds: 200, startMicroseconds: 5)
    try coreAssert(CoreSampler.processCPUPercent(previousIdentity: identity, currentIdentity: identity,
                                                 previousNanoseconds: 1_000_000_000,
                                                 currentNanoseconds: 2_500_000_000,
                                                 elapsedSeconds: 1) == 150,
                   "process CPU must use one-core=100% scale")
    try coreAssert(CoreSampler.processCPUPercent(previousIdentity: identity, currentIdentity: reused,
                                                 previousNanoseconds: 1, currentNanoseconds: 2,
                                                 elapsedSeconds: 1) == nil,
                   "PID reuse must reset process deltas")
    try coreAssert(CoreSampler.processCPUPercent(previousIdentity: identity, currentIdentity: identity,
                                                 previousNanoseconds: 2, currentNanoseconds: 1,
                                                 elapsedSeconds: 1) == nil,
                   "counter reset must not produce a negative CPU rate")

    let oldTicks = CoreCPUTicks(user: 10, system: 5, nice: 0, idle: 85)
    let newTicks = CoreCPUTicks(user: 30, system: 15, nice: 10, idle: 145)
    var tickFixture: [CoreCPUTicks]? = [oldTicks]
    let tickSampler = CoreSampler(processIDLister: { _, _ in 0 }, cpuTickReader: { tickFixture })
    func checkTickStatus(_ expected: ReadingStatus) throws {
        let metrics = tickSampler.sample().panels.first { $0.tab == .cpu }!.metrics
        for id in ["user", "system", "idle"] {
            let metric = metrics.first { $0.id == id }
            try coreAssert(metric?.status == expected, "CPU \(id): expected \(expected)")
            try coreAssert((metric?.value != nil) == (expected == .derived), "CPU value/status mismatch")
        }
    }
    try checkTickStatus(.waiting)
    tickFixture = [newTicks]; try checkTickStatus(.derived)
    tickFixture = nil; try checkTickStatus(.unavailable)
    tickFixture = [oldTicks]; try checkTickStatus(.waiting)
    tickFixture = [newTicks]; try checkTickStatus(.derived)
    tickFixture = []; try checkTickStatus(.unavailable)
    let percentages = CoreSampler.cpuPercentages(previous: oldTicks, current: newTicks)
    try coreAssert(abs((percentages?.user ?? -1) - 30) < 0.0001, "core user+nice percentage is incorrect")
    try coreAssert(abs((percentages?.system ?? -1) - 10) < 0.0001, "core system percentage is incorrect")
    try coreAssert(abs((percentages?.idle ?? -1) - 60) < 0.0001, "core idle percentage is incorrect")
    try coreAssert(CoreSampler.cpuPercentages(previous: newTicks, current: oldTicks) == nil,
                   "core counter reset must wait for a fresh baseline")

    let memory = CoreSampler.memoryValues(physical: 1_000, freePages: 10, wiredPages: 20,
                                          compressedPages: 5, externalPages: 15, pageSize: 10)
    try coreAssert(memory == CoreMemoryValues(occupied: 900, wired: 200, compressedPhysical: 50,
                                              nonCompressedOccupied: 650, fileBacked: 150),
                   "memory partitions must remain physical RAM semantics")
    try coreAssert(CoreSampler.memoryValues(physical: 100, freePages: UInt64.max, wiredPages: 0,
                                            compressedPages: 0, externalPages: 0, pageSize: 2) == nil,
                   "overflowing page conversion must be unavailable")

    let shortGrowth = [CoreGrowthPoint(uptime: 0, bytes: 100), CoreGrowthPoint(uptime: 599, bytes: 200_000_000)]
    try coreAssert(CoreSampler.growthEvidence(shortGrowth) == nil, "growth needs at least ten minutes")
    let sustained = [CoreGrowthPoint(uptime: 0, bytes: 100_000_000),
                     CoreGrowthPoint(uptime: 200, bytes: 125_000_000),
                     CoreGrowthPoint(uptime: 400, bytes: 150_000_000),
                     CoreGrowthPoint(uptime: 600, bytes: 175_000_000)]
    try coreAssert(CoreSampler.growthEvidence(sustained) != nil, "sustained material growth should be tagged")
    let oscillating = [CoreGrowthPoint(uptime: 0, bytes: 100_000_000),
                       CoreGrowthPoint(uptime: 200, bytes: 220_000_000),
                       CoreGrowthPoint(uptime: 400, bytes: 110_000_000),
                       CoreGrowthPoint(uptime: 600, bytes: 180_000_000)]
    try coreAssert(CoreSampler.growthEvidence(oscillating) == nil, "oscillation must not be called sustained growth")

    try coreAssert(CoreSampler.isPhysicalAggregateInterface("en0", flags: UInt32(IFF_UP)), "en0 should be in physical aggregate")
    try coreAssert(!CoreSampler.isPhysicalAggregateInterface("lo0", flags: UInt32(IFF_UP | IFF_LOOPBACK)), "loopback must be excluded")
    try coreAssert(!CoreSampler.isPhysicalAggregateInterface("utun3", flags: UInt32(IFF_UP)), "VPN must be excluded")

    var routeHeader = if_msghdr2()
    routeHeader.ifm_msglen = UInt16(MemoryLayout<if_msghdr2>.stride)
    routeHeader.ifm_version = UInt8(RTM_VERSION)
    routeHeader.ifm_type = UInt8(RTM_IFINFO2)
    routeHeader.ifm_index = 7
    routeHeader.ifm_flags = IFF_UP
    routeHeader.ifm_data.ifi_ibytes = 5 * 1_024 * 1_024 * 1_024
    routeHeader.ifm_data.ifi_obytes = 6 * 1_024 * 1_024 * 1_024
    let routeData = withUnsafeBytes(of: &routeHeader) { Data($0) }
    let parsed64 = CoreSampler.parseInterfaceMessages(routeData) { $0 == 7 ? "en7" : nil }
    try coreAssert(parsed64["en7"]?.counters.receivedBytes == 5 * 1_024 * 1_024 * 1_024,
                   "NET_RT_IFLIST2 parser must preserve counters above 4 GiB")
    let malformedRouteData = Data([1, 0, UInt8(RTM_VERSION), UInt8(RTM_IFINFO2)])
    try coreAssert(CoreSampler.parseInterfaceMessages(malformedRouteData) { _ in "en0" }.isEmpty,
                   "malformed routing messages must be rejected without an out-of-bounds read")
    var wrongVersionHeader = routeHeader
    wrongVersionHeader.ifm_version = 0
    let wrongVersionData = withUnsafeBytes(of: &wrongVersionHeader) { Data($0) }
    try coreAssert(CoreSampler.parseInterfaceMessages(wrongVersionData) { _ in "en7" }.isEmpty,
                   "unknown routing message versions must not be decoded as if_msghdr2")

    let up = UInt32(IFF_UP)
    let previousNetwork = [
        "en0": CoreInterfaceReading(counters: CoreInterfaceCounters(receivedBytes: 5_000_000_000,
            sentBytes: 6_000_000_000, receivedPackets: 10, sentPackets: 20, inputErrors: 0, outputErrors: 0), flags: up)
    ]
    let changedNetwork = [
        "en0": CoreInterfaceReading(counters: CoreInterfaceCounters(receivedBytes: 5_000_001_000,
            sentBytes: 6_000_002_000, receivedPackets: 11, sentPackets: 21, inputErrors: 0, outputErrors: 0), flags: up),
        "en1": CoreInterfaceReading(counters: CoreInterfaceCounters(receivedBytes: 9_000_000_000,
            sentBytes: 8_000_000_000, receivedPackets: 30, sentPackets: 40, inputErrors: 0, outputErrors: 0), flags: up)
    ]
    let changedRates = CoreSampler.networkRates(previous: previousNetwork, current: changedNetwork, seconds: 2)
    try coreAssert(changedRates.receivedBytesPerSecond == 500 && changedRates.sentBytesPerSecond == 1_000,
                   "new interfaces must not inject their cumulative counters into aggregate rates")
    try coreAssert(changedRates.status == .partial,
                   "an interface-set change must be disclosed as a partial aggregate interval")
    let removedRates = CoreSampler.networkRates(previous: changedNetwork, current: previousNetwork, seconds: 2)
    try coreAssert(removedRates.receivedBytesPerSecond == nil && removedRates.status == .partial,
                   "counter reset after an interface removal must not create a negative or wrapped rate")

    let diskA = CoreDiskDeviceCounters(readBytes: 1_000, writeBytes: 2_000, readErrors: 0, writeErrors: 0)
    let diskANext = CoreDiskDeviceCounters(readBytes: 1_200, writeBytes: 2_400, readErrors: 0, writeErrors: 0)
    let diskB = CoreDiskDeviceCounters(readBytes: 1_000_000_000, writeBytes: 2_000_000_000, readErrors: nil, writeErrors: nil)
    let diskAdded = CoreSampler.diskRates(previous: [1: diskA], current: [1: diskANext, 2: diskB], seconds: 2)
    try coreAssert(diskAdded.readBytesPerSecond == 100 && diskAdded.writeBytesPerSecond == 200,
                   "a newly added disk must not inject its lifetime counters into the interval rate")
    try coreAssert(diskAdded.status == .partial, "a disk addition must mark the aggregate interval partial")
    let diskRemoved = CoreSampler.diskRates(previous: [1: diskA, 2: diskB], current: [1: diskANext], seconds: 2)
    try coreAssert(diskRemoved.readBytesPerSecond == 100 && diskRemoved.status == .partial,
                   "a removed disk must leave only continuing-disk deltas and mark them partial")
    let diskMissing = CoreSampler.diskRates(previous: [1: diskA], current: [:], seconds: 2)
    try coreAssert(diskMissing.readBytesPerSecond == nil && diskMissing.status == .partial,
                   "a temporarily missing disk must not be measured as zero")
    let diskReappeared = CoreSampler.diskRates(previous: [:], current: [1: diskANext], seconds: 2)
    try coreAssert(diskReappeared.readBytesPerSecond == nil && diskReappeared.status == .waiting,
                   "a reappeared disk needs a new adjacent baseline")
    let resetDisk = CoreDiskDeviceCounters(readBytes: 10, writeBytes: 20, readErrors: 0, writeErrors: 0)
    let continuingB = CoreDiskDeviceCounters(readBytes: diskB.readBytes + 600, writeBytes: diskB.writeBytes + 800,
                                             readErrors: nil, writeErrors: nil)
    let diskReset = CoreSampler.diskRates(previous: [1: diskA, 2: diskB], current: [1: resetDisk, 2: continuingB], seconds: 2)
    try coreAssert(diskReset.readBytesPerSecond == 300 && diskReset.writeBytesPerSecond == 400,
                   "a reset disk counter must be excluded while continuing disks still contribute")
    try coreAssert(diskReset.status == .partial, "an individual disk reset must mark the interval partial")
    let stableIncomplete = CoreSampler.diskRates(previous: [1: diskA], current: [1: diskANext], seconds: 2,
                                                 previousComplete: false, currentComplete: false)
    try coreAssert(stableIncomplete.readBytesPerSecond == 100 && stableIncomplete.status == .partial,
                   "stable readable disks must remain partial when other enumerated entries were unreadable")

    let missingErrors = CoreSampler.optionalCounterTotal([nil, nil])
    try coreAssert(missingErrors.value == nil && missingErrors.status == .unavailable,
                   "missing disk error counters must not be measured as zero")
    let partialErrors = CoreSampler.optionalCounterTotal([3, nil])
    try coreAssert(partialErrors.value == 3 && partialErrors.status == .partial,
                   "one missing disk error direction must be reported as partial")
    let completeErrors = CoreSampler.optionalCounterTotal([3, 4])
    try coreAssert(completeErrors.value == 7 && completeErrors.status == .measured,
                   "complete disk error counters should be summed")

    let clockBefore = CoreClockBaseline(wall: Date(timeIntervalSince1970: 1_000),
                                        uptimeNanoseconds: 100_000_000_000,
                                        continuousNanoseconds: 100_000_000_000)
    let clockAfterSleep = CoreClockBaseline(wall: Date(timeIntervalSince1970: 1_602),
                                            uptimeNanoseconds: 102_000_000_000,
                                            continuousNanoseconds: 702_000_000_000)
    let sleepDelta = CoreSampler.clockDelta(previous: clockBefore, current: clockAfterSleep,
                                            expectedInterval: 2)
    try coreAssert(sleepDelta?.sleepGap == 600 && sleepDelta?.jitter == nil,
                   "clock baseline must isolate a synthetic sleep gap from scheduling jitter")

    let sampler = CoreSampler()
    _ = sampler.sample(expectedInterval: 2)
    sampler.reset()
    let afterReset = sampler.sample(expectedInterval: 2)
    try coreAssert(afterReset.panels.count == 5, "core sampler must return its five panels")
    try coreAssert(afterReset.panels.first(where: { $0.tab == .clock })?.metrics.first(where: { $0.id == "jitter" })?.status == .waiting,
                   "reset must clear the clock baseline")
    sampler.reset(preservingClock: true)
    let preservedClock = sampler.sample(expectedInterval: 2)
    try coreAssert(preservedClock.panels.first(where: { $0.tab == .clock })?.metrics.first(where: { $0.id == "jitter" })?.status != .waiting,
                   "sleep resume must be able to preserve only the clock baseline")
    let memoryPanel = afterReset.panels.first { $0.tab == .memory }
    let physical = memoryPanel?.metrics.first { $0.id == "physical" }?.value
    let occupied = memoryPanel?.metrics.first { $0.id == "occupied" }?.value
    try coreAssert((physical ?? 0) > 1_000_000_000,
                   "physical memory must be a numeric byte conversion, not a Double bit pattern")
    try coreAssert((occupied ?? 0) > 64 * 1_024 * 1_024 && (occupied ?? .infinity) <= (physical ?? 0),
                   "occupied memory must remain a plausible numeric byte count")
    let residentValues = memoryPanel?.rows.compactMap { $0.metric("resident")?.value } ?? []
    try coreAssert(residentValues.contains { $0 > 4_096 },
                   "process resident memory must be a numeric byte conversion")
    if let processRow = memoryPanel?.rows.first {
        try coreAssert(processRow.metric("pid")?.value != nil && processRow.metric("parent")?.value != nil,
                       "memory process rows must expose PID and parent PID")
        try coreAssert(!(processRow.metric("owner")?.text ?? "").isEmpty,
                       "memory process rows must expose application or system attribution")
    }

    let enumerationFailure = CoreSampler(processIDLister: { _, _ in -1 }).sample()
    let failedCPU = enumerationFailure.panels.first { $0.tab == .cpu }
    let failedProcessCount = failedCPU?.metrics.first { $0.id == "processCount" }
    let failedThreadCount = failedCPU?.metrics.first { $0.id == "threadCount" }
    try coreAssert(failedProcessCount?.value == nil && failedProcessCount?.status == .unavailable,
                   "process enumeration failure must remain unavailable instead of becoming a measured zero")
    try coreAssert(failedThreadCount?.value == nil && failedThreadCount?.status == .unavailable,
                   "thread count must remain unavailable when PID enumeration fails")

    for failEstimate in [true, false] {
        let zeroFailure = CoreSampler(processIDLister: { buffer, _ in
            if !failEstimate && buffer == nil { return 1 }
            errno = EIO
            return 0
        }).sample()
        let count = zeroFailure.panels.first { $0.tab == .cpu }?.metrics.first { $0.id == "processCount" }
        try coreAssert(count?.value == nil && count?.status == .unavailable,
                       "libproc zero plus errno must be treated as failure in both enumeration calls")
    }
    errno = EIO // A stale thread-local error must not taint a successful zero result.
    let emptyEnumeration = CoreSampler(processIDLister: { _, _ in 0 }).sample()
    let emptyCPU = emptyEnumeration.panels.first { $0.tab == .cpu }
    let emptyProcessCount = emptyCPU?.metrics.first { $0.id == "processCount" }
    try coreAssert(emptyProcessCount?.value == 0 && emptyProcessCount?.status == .measured,
                   "a successful empty enumeration must remain distinguishable from enumeration failure")

    let currentPID = getpid()
    let partialEnumeration = CoreSampler(processIDLister: { buffer, byteCount in
        guard let buffer else { return 2 }
        let output = buffer.bindMemory(to: Int32.self, capacity: Int(byteCount) / MemoryLayout<Int32>.stride)
        output[0] = currentPID
        output[1] = Int32.max
        return 2
    }).sample()
    let partialCPU = partialEnumeration.panels.first { $0.tab == .cpu }
    let partialProcessCount = partialCPU?.metrics.first { $0.id == "processCount" }
    let partialThreadCount = partialCPU?.metrics.first { $0.id == "threadCount" }
    try coreAssert(partialProcessCount?.value == 1 && partialProcessCount?.status == .partial,
                   "successful enumeration with an unreadable PID must preserve the partial process count")
    try coreAssert(partialThreadCount?.value != nil && partialThreadCount?.status == .partial,
                   "successful enumeration with partial PID details must preserve the known thread subtotal")

    var enumerationCall = 0
    let failedThenSuccessful = CoreSampler(processIDLister: { buffer, byteCount in
        enumerationCall += 1
        guard enumerationCall > 1 else { return -1 }
        guard let buffer else { return 1 }
        buffer.bindMemory(to: Int32.self, capacity: Int(byteCount) / MemoryLayout<Int32>.stride)[0] = currentPID
        return 1
    })
    _ = failedThenSuccessful.sample()
    let firstValidProcesses = failedThenSuccessful.sample().processes
    try coreAssert(firstValidProcesses.first?.measurementInterval == nil,
                   "the first valid process sample after enumeration failure must not invent a rate window")

    let successfulSampler = CoreSampler(processIDLister: { buffer, byteCount in
        guard let buffer else { return 1 }
        buffer.bindMemory(to: Int32.self, capacity: Int(byteCount) / MemoryLayout<Int32>.stride)[0] = currentPID
        return 1
    })
    try coreAssert(successfulSampler.sample().processes.first?.measurementInterval == nil,
                   "the first successful process sample must wait for a rate baseline")
    let measuredProcesses = successfulSampler.sample().processes
    try coreAssert((measuredProcesses.first?.measurementInterval ?? 0) > 0,
                   "a subsequent real process sample must carry its actual elapsed rate window")

    var recoveryCall = 0
    let recoverySampler = CoreSampler(processIDLister: { buffer, byteCount in
        recoveryCall += 1
        if recoveryCall == 3 { return -1 }
        guard let buffer else { return 1 }
        buffer.bindMemory(to: Int32.self, capacity: Int(byteCount) / MemoryLayout<Int32>.stride)[0] = currentPID
        return 1
    })
    _ = recoverySampler.sample()
    _ = recoverySampler.sample()
    let recovered = recoverySampler.sample()
    let recoveredProcess = try recovered.processes.first.unwrapCore("process recovery sample missing")
    let recoveredCPUPanel = try recovered.panels.first(where: { $0.tab == .cpu }).unwrapCore("process recovery CPU panel missing")
    let recoveredCPU = try recoveredCPUPanel.rows.first.unwrapCore("process recovery CPU row missing")
    let hostInterval = recoveredCPUPanel.metrics.first(where: { $0.id == "user" })?.interval
    try coreAssert(recoveredCPU.metric("cpu")?.interval == recoveredProcess.measurementInterval,
                   "process CPU UI interval must use the process baseline window")
    try coreAssert((recoveredProcess.measurementInterval ?? 0) > (hostInterval ?? .infinity),
                   "process recovery must measure from the last successful process baseline, not the failed sample")
    if let recoveredStorage = recovered.panels.first(where: { $0.tab == .storage })?.rows.first(where: { $0.id == recoveredProcess.id }) {
        try coreAssert(recoveredStorage.metric("readRate")?.interval == recoveredProcess.measurementInterval
                           && recoveredStorage.metric("writeRate")?.interval == recoveredProcess.measurementInterval,
                       "process storage UI intervals must use the process baseline window")
    }
}

private extension Optional {
    func unwrapCore(_ message: String) throws -> Wrapped {
        guard let self else {
            throw NSError(domain: "AIBOU.CoreTests", code: 2, userInfo: [NSLocalizedDescriptionKey: message])
        }
        return self
    }
}
