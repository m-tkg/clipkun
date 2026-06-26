import Foundation

/// 設定の JSON 永続化。読み込み失敗時は既定設定にフォールバックする（壊れた設定で起動不能にしない）。
public struct SettingsStore {
    private let url: URL

    public init(url: URL) {
        self.url = url
    }

    /// 既定の保存先（`~/Library/Application Support/Clipkun/settings.json`）。
    public static func defaultURL() -> URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base
            .appendingPathComponent("Clipkun", isDirectory: true)
            .appendingPathComponent("settings.json")
    }

    /// 設定を読み込む。ファイルが無い/壊れている場合は `Settings.default`。
    public func load() -> Settings {
        guard let data = try? Data(contentsOf: url) else { return .default }
        return (try? JSONDecoder().decode(Settings.self, from: data)) ?? .default
    }

    /// 設定を保存する（親ディレクトリは必要に応じて作成）。
    public func save(_ settings: Settings) throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(settings)
        try data.write(to: url, options: .atomic)
    }
}
