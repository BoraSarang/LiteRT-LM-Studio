import Darwin
import Foundation
import IOKit

extension SystemMonitor {
    // MARK: - 라이브 샘플 (nonisolated, GCD 호출)
    /// CPU 틱 묶음 (lint 파라미터 수 회피용 구조체).
    struct CPUTicks {
        let user: UInt64
        let sys: UInt64
        let nice: UInt64
        let idle: UInt64
    }

    /// CPU 성분 샘플. cpu_ticks 인덱스: [0]=user [1]=system [2]=idle [3]=nice.
    nonisolated static func sampleCPUSplit(
        prevUser: inout UInt64,
        prevSys: inout UInt64,
        prevNice: inout UInt64,
        prevIdle: inout UInt64
    ) -> (userPct: Double, sysPct: Double)? {
        var cpuCount: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        guard host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO,
                                  &cpuCount, &info, &infoCount) == KERN_SUCCESS,
              let info else { return nil }
        defer {
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info),
                          vm_size_t(infoCount) * vm_size_t(MemoryLayout<integer_t>.size))
        }
        var user: UInt64 = 0
        var sys: UInt64 = 0
        var nice: UInt64 = 0
        var idle: UInt64 = 0
        info.withMemoryRebound(to: processor_cpu_load_info.self, capacity: Int(cpuCount)) { ptr in
            for idx in 0 ..< Int(cpuCount) {
                let ticks = ptr[idx].cpu_ticks
                user += UInt64(ticks.0)
                sys += UInt64(ticks.1)
                idle += UInt64(ticks.2)
                nice += UInt64(ticks.3)
            }
        }
        let hadPrev = prevUser > 0 || prevSys > 0 || prevNice > 0 || prevIdle > 0
        defer {
            prevUser = user
            prevSys = sys
            prevNice = nice
            prevIdle = idle
        }
        guard hadPrev else { return nil } // 첫 샘플은 델타 없음
        let cur = CPUTicks(user: user, sys: sys, nice: nice, idle: idle)
        let prev = CPUTicks(user: prevUser, sys: prevSys, nice: prevNice, idle: prevIdle)
        return cpuSplit(cur: cur, prev: prev)
    }

    /// CPU 성분 분리 (순수, 테스트 가능). nice는 사용자로 합산 (활성 상태 보기와 동일).
    nonisolated static func cpuSplit(
        cur: CPUTicks,
        prev: CPUTicks
    ) -> (userPct: Double, sysPct: Double)? {
        let du = (cur.user >= prev.user ? cur.user - prev.user : 0)
            + (cur.nice >= prev.nice ? cur.nice - prev.nice : 0)
        let ds = cur.sys >= prev.sys ? cur.sys - prev.sys : 0
        let di = cur.idle >= prev.idle ? cur.idle - prev.idle : 0
        let total = du + ds + di
        guard total > 0 else { return nil }
        return (Double(du) / Double(total) * 100.0, Double(ds) / Double(total) * 100.0)
    }

    /// RAM 스냅샷 (lint large_tuple 회피용 구조체).
    struct RAMSample {
        let usedGB: Double
        let pct: Double
        let inactiveGB: Double
        let appGB: Double
        let wiredGB: Double
        let compGB: Double
        let appPct: Double
        let wiredPct: Double
        let compPct: Double
    }

    /// RAM 성분 바이트 묶음 (lint large_tuple 회피용 구조체).
    struct RAMComponents {
        let app: UInt64
        let wired: UInt64
        let comp: UInt64
    }

    /// RAM 성분 바이트 (순수, 테스트 가능). App=active, inactive는 캐시된 파일로 별도.
    nonisolated static func ramComponentBytes(
        active: UInt64,
        wired: UInt64,
        compressed: UInt64,
        pageSize: UInt64
    ) -> RAMComponents {
        RAMComponents(app: active * pageSize, wired: wired * pageSize, comp: compressed * pageSize)
    }

    nonisolated static func sampleRAM(totalGB: Double) -> RAMSample {
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        var stats = vm_statistics64()
        let ok: kern_return_t = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard ok == KERN_SUCCESS else {
            return RAMSample(usedGB: 0, pct: 0, inactiveGB: 0, appGB: 0, wiredGB: 0, compGB: 0,
                             appPct: 0, wiredPct: 0, compPct: 0)
        }
        var pageSize: vm_size_t = 0
        host_page_size(mach_host_self(), &pageSize)
        let ps = UInt64(pageSize)
        let comp = ramComponentBytes(active: UInt64(stats.active_count), wired: UInt64(stats.wire_count),
                                     compressed: UInt64(stats.compressor_page_count), pageSize: ps)
        let used = ramUsedBytes(active: UInt64(stats.active_count), inactive: UInt64(stats.inactive_count),
                                wired: UInt64(stats.wire_count), compressed: UInt64(stats.compressor_page_count),
                                pageSize: ps)
        let div = 1024.0 * 1024.0 * 1024.0
        let usedGB = Double(used) / div
        let appGB = Double(comp.app) / div
        let wiredGB = Double(comp.wired) / div
        let compGB = Double(comp.comp) / div
        let inactiveGB = Double(ramInactiveBytes(inactive: UInt64(stats.inactive_count),
                                                pageSize: ps)) / div
        func pct(_ v: Double) -> Double { totalGB > 0 ? v / totalGB * 100.0 : 0 }
        return RAMSample(usedGB: usedGB, pct: pct(usedGB), inactiveGB: inactiveGB,
                         appGB: appGB, wiredGB: wiredGB, compGB: compGB,
                         appPct: pct(appGB), wiredPct: pct(wiredGB), compPct: pct(compGB))
    }

    nonisolated static func sampleGPU() -> Double? {
        guard let matching = IOServiceMatching("IOAccelerator") else { return nil }
        var iter: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iter) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iter) }
        var best: Double?
        var svc = IOIteratorNext(iter)
        while svc != 0 {
            defer {
                IOObjectRelease(svc)
                svc = IOIteratorNext(iter)
            }
            var props: Unmanaged<CFMutableDictionary>?
            guard IORegistryEntryCreateCFProperties(svc, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                  let dict = props?.takeRetainedValue() as? [String: Any],
                  let stats = dict["PerformanceStatistics"] as? [String: Any],
                  let val = gpuFromStats(stats)
            else { continue }
            best = max(best ?? 0, val)
        }
        return best
    }
}
