import Foundation
import Darwin

enum LanNetworkAddress {
    /// Returns the preferred private IPv4 address for LAN publishing (e.g. Wi‑Fi `en0`).
    static func primaryIPv4() -> String? {
        var ifaddrPointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddrPointer) == 0, let first = ifaddrPointer else { return nil }
        defer { freeifaddrs(ifaddrPointer) }

        var candidates: [(priority: Int, address: String)] = []
        var pointer: UnsafeMutablePointer<ifaddrs>? = first
        while let current = pointer {
            defer { pointer = current.pointee.ifa_next }

            let interface = current.pointee
            guard let addr = interface.ifa_addr else { continue }
            guard addr.pointee.sa_family == UInt8(AF_INET) else { continue }

            let name = String(cString: interface.ifa_name)
            guard name != "lo0" else { continue }

            var hostBuffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let result = getnameinfo(
                addr,
                socklen_t(addr.pointee.sa_len),
                &hostBuffer,
                socklen_t(hostBuffer.count),
                nil,
                0,
                NI_NUMERICHOST
            )
            guard result == 0 else { continue }
            let address = String(cString: hostBuffer)
            guard isPrivateIPv4(address) else { continue }

            let priority: Int
            switch name {
            case "en0": priority = 0
            case let value where value.hasPrefix("en"): priority = 1
            default: priority = 2
            }
            candidates.append((priority, address))
        }

        return candidates.sorted { $0.priority < $1.priority }.first?.address
    }

    private static func isPrivateIPv4(_ address: String) -> Bool {
        let octets = address.split(separator: ".").compactMap { Int($0) }
        guard octets.count == 4, octets.allSatisfy({ (0...255).contains($0) }) else { return false }
        switch (octets[0], octets[1]) {
        case (10, _):
            return true
        case (172, let second) where (16...31).contains(second):
            return true
        case (192, 168):
            return true
        default:
            return false
        }
    }
}
