import Foundation

enum LanSubnetProbe {
    static func discoverHealthHost(port: Int, preferredHost: String? = nil, session: URLSession = .shared) async -> String? {
        if let preferredHost, !preferredHost.isEmpty, await healthOK(host: preferredHost, port: port, session: session) {
            return preferredHost
        }
        guard let prefix = LanNetworkSelector.wifiSubnetPrefix() else { return nil }
        for host in 1...254 {
            let ip = "\(prefix).\(host)"
            if ip == preferredHost { continue }
            if await healthOK(host: ip, port: port, session: session) {
                return ip
            }
        }
        return nil
    }

    private static func healthOK(host: String, port: Int, session: URLSession) async -> Bool {
        guard let url = URL(string: "http://\(host):\(port)/health") else { return false }
        var request = URLRequest(url: url)
        request.timeoutInterval = 1
        do {
            let (_, response) = try await session.data(for: request)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }
}
