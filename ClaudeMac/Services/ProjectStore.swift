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
            let directory = base.appendingPathComponent("ClaudeMac", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            return directory
        }
    }

    private static var projectsURL: URL { get throws { try appSupportDirectory.appendingPathComponent("projects.json") } }
    private static var settingsURL: URL { get throws { try appSupportDirectory.appendingPathComponent("settings.json") } }

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
