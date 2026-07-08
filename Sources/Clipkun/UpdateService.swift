import Foundation
import KunUpdateKit

/// 公開 GitHub API（api.github.com）へアクセスし、最新リリースを取得する。
/// HTTP 取得は kunkit の `GitHubReleaseFetcher`、zip ダウンロードは kunkit の `SelfUpdater` が担う。
struct UpdateService {
    static let repoFullName = "m-tkg/clipkun"
    private static let userAgent = "Clipkun"

    enum ServiceError: LocalizedError {
        case decodeFailed

        var errorDescription: String? {
            switch self {
            case .decodeFailed:
                return L.string("error.parse_release")
            }
        }
    }

    /// 現在のアプリバージョン（CFBundleShortVersionString）。
    static var currentVersion: String { ReleaseInfo.currentAppVersion }

    /// 最新リリース情報を取得する。
    /// HTTP 部分は kunkit の ETag 条件付き取得（304 は GitHub のレート制限を消費しない）。
    /// レート制限時は `GitHubReleaseFetcher.RateLimitedError`（リセット時刻付き文言）が投げられる。
    func fetchLatestRelease() async throws -> ReleaseInfo {
        let fetcher = GitHubReleaseFetcher(repoFullName: Self.repoFullName, userAgent: Self.userAgent)
        let data = try await fetcher.fetchLatestReleaseData()
        guard let release = try? JSONDecoder().decode(ReleaseInfo.self, from: data) else {
            throw ServiceError.decodeFailed
        }
        return release
    }
}
