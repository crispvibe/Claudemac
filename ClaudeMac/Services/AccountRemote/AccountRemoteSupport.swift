import Foundation

func accountRemoteAppVersion() -> String {
    let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""
    return build.isEmpty ? version : "\(version) (\(build))"
}

func accountRemoteDisplayAccount(_ user: RemoteAuthUser) -> String {
    user.displayAccount
}

func accountRemoteFormattedDeviceCode(_ code: String) -> String {
    let clean = code.replacingOccurrences(of: "-", with: "")
    guard clean.count > 4 else { return clean }
    var groups: [String] = []
    var current = ""
    for character in clean {
        current.append(character)
        if current.count == 4 {
            groups.append(current)
            current = ""
        }
    }
    if !current.isEmpty {
        groups.append(current)
    }
    return groups.joined(separator: "-")
}
