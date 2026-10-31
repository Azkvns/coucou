import Darwin
import Foundation

enum ProcessLookup {
    static func bsdInfo(for pid: pid_t) -> proc_bsdinfo? {
        var info = proc_bsdinfo()
        let size = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, Int32(MemoryLayout.size(ofValue: info)))
        guard size == MemoryLayout.size(ofValue: info) else { return nil }
        return info
    }

    static func uid(for pid: pid_t) -> uid_t? {
        bsdInfo(for: pid)?.pbi_uid
    }

    static func startedAt(for pid: pid_t) -> Date? {
        guard let info = bsdInfo(for: pid) else { return nil }
        let seconds = TimeInterval(info.pbi_start_tvsec)
        let microseconds = TimeInterval(info.pbi_start_tvusec) / 1_000_000
        guard seconds > 0 else { return nil }
        return Date(timeIntervalSince1970: seconds + microseconds)
    }

    static func path(for pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        return String(cString: buffer)
    }

    static func commandLine(for pid: pid_t) -> String? {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size: Int = 0
        guard sysctl(&mib, u_int(mib.count), nil, &size, nil, 0) == 0, size > 0 else { return nil }

        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, u_int(mib.count), &buffer, &size, nil, 0) == 0 else { return nil }

        guard size >= MemoryLayout<Int32>.size else { return nil }
        let argc = buffer.withUnsafeBytes { $0.load(as: Int32.self) }
        guard argc > 0 else { return nil }

        var strings: [String] = []
        var index = MemoryLayout<Int32>.size
        while index < buffer.count, strings.count < argc {
            while index < buffer.count, buffer[index] == 0 { index += 1 }
            guard index < buffer.count else { break }
            var end = index
            while end < buffer.count, buffer[end] != 0 { end += 1 }
            guard end > index else { break }
            if let piece = String(bytes: buffer[index..<end], encoding: .utf8), !piece.isEmpty {
                strings.append(piece)
            }
            index = end + 1
        }
        guard !strings.isEmpty else { return nil }
        return strings.joined(separator: " ")
    }

    static func isAlive(_ pid: pid_t) -> Bool {
        kill(pid, 0) == 0
    }

    static func verify(_ binding: PortBinding) -> Bool {
        guard isAlive(binding.pid) else { return false }
        var info = proc_bsdinfo()
        let size = proc_pidinfo(binding.pid, PROC_PIDTBSDINFO, 0, &info, Int32(MemoryLayout.size(ofValue: info)))
        guard size == MemoryLayout.size(ofValue: info) else { return false }
        let rawName = info.pbi_name
        let name = withUnsafePointer(to: rawName) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: MemoryLayout.size(ofValue: rawName)) {
                String(cString: $0)
            }
        }
        return name == binding.processName
    }
}
