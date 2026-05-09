import AppKit
import Foundation

enum ProjectStoreError: LocalizedError {
    case applicationSupportUnavailable
    case bookmarkInvalid

    var errorDescription: String? {
        switch self {
        case .applicationSupportUnavailable: "无法访问 Application Support 目录。"
        case .bookmarkInvalid: "项目目录权限已失效，请重新添加项目。"
        }
    }
}

struct ProjectStore {
    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    static var appSupportDirectory: URL {
        get throws {
            guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
                throw ProjectStoreError.applicationSupportUnavailable
            }
            let directory = base.appendingPathComponent("Acode", isDirectory: true)
            let legacyDirectory = base.appendingPathComponent("ClaudeMac", isDirectory: true)
            let sandboxDirectory = sandboxAppSupportDirectory(named: "Acode")
                ?? sandboxAppSupportDirectory(named: "ClaudeMac")
            if !FileManager.default.fileExists(atPath: directory.path) {
                if let sandboxDirectory, FileManager.default.fileExists(atPath: sandboxDirectory.path) {
                    try? FileManager.default.copyItem(at: sandboxDirectory, to: directory)
                } else if FileManager.default.fileExists(atPath: legacyDirectory.path) {
                    try? FileManager.default.copyItem(at: legacyDirectory, to: directory)
                }
            }
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            return directory
        }
    }

    private static func sandboxAppSupportDirectory(named name: String) -> URL? {
        guard let identifier = Bundle.main.bundleIdentifier,
              let home = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first?.deletingLastPathComponent() else { return nil }
        return home
            .appendingPathComponent("Containers", isDirectory: true)
            .appendingPathComponent(identifier, isDirectory: true)
            .appendingPathComponent("Data/Library/Application Support", isDirectory: true)
            .appendingPathComponent(name, isDirectory: true)
    }

    private static var projectsURL: URL { get throws { try appSupportDirectory.appendingPathComponent("projects.json") } }
    private static var settingsURL: URL { get throws { try appSupportDirectory.appendingPathComponent("settings.json") } }
    private static var fileTreeStateURL: URL { get throws { try appSupportDirectory.appendingPathComponent("file-tree-state.json") } }
    private static var configProfilesURL: URL { get throws { try appSupportDirectory.appendingPathComponent("config-profiles.json") } }

    static func loadProjects() -> [ProjectItem] {
        do {
            let url = try projectsURL
            guard FileManager.default.fileExists(atPath: url.path) else { return [] }
            let data = try Data(contentsOf: url)
            return try decoder.decode([ProjectItem].self, from: data)
        } catch {
            return []
        }
    }

    static func saveProjects(_ projects: [ProjectItem]) throws {
        let data = try encoder.encode(projects)
        try data.write(to: projectsURL, options: [.atomic])
    }

    static func loadSettings() -> AppSettings {
        do {
            let url = try settingsURL
            guard FileManager.default.fileExists(atPath: url.path) else { return .default }
            let data = try Data(contentsOf: url)
            return try decoder.decode(AppSettings.self, from: data)
        } catch {
            return .default
        }
    }

    static func saveSettings(_ settings: AppSettings) throws {
        let data = try encoder.encode(settings)
        try data.write(to: settingsURL, options: [.atomic])
    }

    static func loadExpandedFileTreePaths(for projectPath: String) -> Set<String> {
        do {
            let url = try fileTreeStateURL
            guard FileManager.default.fileExists(atPath: url.path) else { return [] }
            let data = try Data(contentsOf: url)
            let state = try decoder.decode([String: [String]].self, from: data)
            return Set(state[normalizedProjectPath(projectPath)] ?? [])
        } catch {
            return []
        }
    }

    static func saveExpandedFileTreePaths(_ paths: Set<String>, for projectPath: String) throws {
        let url = try fileTreeStateURL
        var state: [String: [String]] = [:]
        if FileManager.default.fileExists(atPath: url.path) {
            let data = try Data(contentsOf: url)
            state = (try? decoder.decode([String: [String]].self, from: data)) ?? [:]
        }
        state[normalizedProjectPath(projectPath)] = paths.sorted()
        let data = try encoder.encode(state)
        try data.write(to: url, options: [.atomic])
    }

    static func loadConfigProfiles() -> ConfigProfileCollection {
        do {
            let url = try configProfilesURL
            guard FileManager.default.fileExists(atPath: url.path) else { return .empty }
            let data = try Data(contentsOf: url)
            return try decoder.decode(ConfigProfileCollection.self, from: data)
        } catch {
            return .empty
        }
    }

    static func saveConfigProfiles(_ profiles: ConfigProfileCollection) throws {
        let data = try encoder.encode(profiles)
        let url = try configProfilesURL
        try data.write(to: url, options: [.atomic])
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    private static func normalizedProjectPath(_ value: String) -> String {
        (value as NSString).standardizingPath
    }

    static func resolveURL(for project: ProjectItem) throws -> URL {
        var isStale = false
        let url = try URL(
            resolvingBookmarkData: project.bookmarkData,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
        if isStale { throw ProjectStoreError.bookmarkInvalid }
        return url
    }

    @MainActor
    static func chooseProjectDirectory() throws -> ProjectItem? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.prompt = "添加项目"
        panel.message = "选择要在 AI CLI 工作台中管理的项目目录。"

        guard panel.runModal() == .OK, let url = panel.url else { return nil }

        let bookmark = try url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        let now = Date()
        return ProjectItem(
            id: UUID(),
            name: url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent,
            path: url.path,
            bookmarkData: bookmark,
            defaultCLI: .claude,
            defaultTerminal: .terminal,
            createdAt: now,
            updatedAt: now,
            lastOpenedAt: now
        )
    }
}
