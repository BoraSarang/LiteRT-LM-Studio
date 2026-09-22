import Darwin
import Foundation

// MARK: - 데몬 측정 (타입 본문 길이 관리용 분리, T-073)
extension SystemMonitor {
    /// 데몬 샘플 묶음 (lint large_tuple 회피용 구조체, T-073 진단 포함).
    struct DaemonSample {
        let cpu: Double
        let rssGB: Double
        let pidCount: Int
        let rusageFails: Int
    }

    /// 불일치 보고 판정 (순수, 테스트 가능, T-073): 실행 중+0개+미기록일 때만.
    nonisolated static func shouldReportDaemonMismatch(
        running: Bool,
        pidCount: Int,
        alreadyLogged: Bool
    ) -> Bool {
        running && pidCount == 0 && !alreadyLogged
    }

    /// :9379 리스너 PID (동기, 5틱마다만 호출). -n -P로 이름 해석 없이 빠르게.
    static func listenerPIDs() -> [pid_t] {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        proc.arguments = ["-n", "-P", "-i", ":9379", "-sTCP:LISTEN", "-t"]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice
        guard (try? proc.run()) != nil else { return [] }
        proc.waitUntilExit()
        let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return pids(fromLsof: out)
    }

    /// 리스너 + 모든 자손 (ppid 워크).
    static func daemonPIDs(listeners: [pid_t]) -> [pid_t] {
        guard !listeners.isEmpty else { return [] }
        var ppidMap: [pid_t: pid_t] = [:]
        let bufSize = Int(proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0))
        guard bufSize > 0 else { return listeners }
        var pids = [pid_t](repeating: 0, count: bufSize / MemoryLayout<pid_t>.size)
        let count = Int(proc_listpids(UInt32(PROC_ALL_PIDS), 0, &pids, Int32(bufSize)))
        var info = proc_bsdinfo()
        for pid in pids.prefix(max(0, count)) where pid > 0 {
            let size = proc_pidinfo(pid, Int32(PROC_PIDTBSDINFO), 0, &info, Int32(MemoryLayout<proc_bsdinfo>.size))
            guard size == MemoryLayout<proc_bsdinfo>.size else { continue }
            ppidMap[pid] = pid_t(info.pbi_ppid)
        }
        return descendants(of: listeners, in: ppidMap)
    }

    /// 순수: ppid 맵에서 roots + 자손 전부.
    nonisolated static func descendants(of roots: [pid_t], in ppidMap: [pid_t: pid_t]) -> [pid_t] {
        var out = Set(roots)
        var queue = roots
        while let cur = queue.popLast() {
            for (pid, ppid) in ppidMap where ppid == cur && !out.contains(pid) {
                out.insert(pid)
                queue.append(pid)
            }
        }
        return Array(out)
    }

    /// 순수: lsof -t 출력 파싱.
    nonisolated static func pids(fromLsof out: String) -> [pid_t] {
        out.split(separator: "\n").compactMap { pid_t($0.trimmingCharacters(in: .whitespaces)) }
    }

    /// 리스너 프로세스 명령행 (동기, T-374): 식별 불가면 nil.
    /// litert-lm이 uv shim의 python 스크립트라 comm/pidpath가 `python3`으로 나오므로
    /// 프로세스명이 아닌 인자로 판정한다.
    static func processArgs(_ pid: pid_t) -> String? {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/ps")
        proc.arguments = ["-p", "\(pid)", "-o", "args="]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice
        guard (try? proc.run()) != nil else { return nil }
        proc.waitUntilExit()
        let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let out, !out.isEmpty else { return nil }
        return out
    }

    /// 순수: 자사 serve 인자 판정 (T-374).
    /// :9379 LISTEN 상태의 프로세스가 litert-lm이면 자사로 본다
    /// (명시 --port가 없어도 리스너 자체가 포트 증거).
    nonisolated static func isLitertArgs(_ args: String) -> Bool {
        args.contains("litert-lm")
    }

    /// 진단용 lsof 원문 앞부분 (T-073): 불일치 로그용, 최대 120자.
    nonisolated static func lsofHead() -> String {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        proc.arguments = ["-n", "-P", "-i", ":9379", "-sTCP:LISTEN"]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice
        guard (try? proc.run()) != nil else { return "lsof 실행 실패" }
        proc.waitUntilExit()
        let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let head = out.split(separator: "\n").prefix(3).joined(separator: "|")
        return head.isEmpty ? "(빈 출력)" : String(head.prefix(120))
    }
}
