import Foundation
import KunUpdateKit
import OSLog
import ClipkunCore

private let log = Logger(subsystem: "com.mtkg.clipkun", category: "update")

/// 外部プロセスを起動し、終了を待って標準出力を返す簡易ランナー（`.app` 展開の ditto などに使用）。
enum ProcessRunner {
    struct Failure: Error {
        let exitCode: Int32
        let stderr: String
    }

    static func run(executable: String, arguments: [String]) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            let stdout = Pipe()
            let stderr = Pipe()
            process.standardOutput = stdout
            process.standardError = stderr
            process.terminationHandler = { proc in
                let outData = stdout.fileHandleForReading.readDataToEndOfFile()
                let errData = stderr.fileHandleForReading.readDataToEndOfFile()
                if proc.terminationStatus == 0 {
                    continuation.resume(returning: String(decoding: outData, as: UTF8.self))
                } else {
                    continuation.resume(throwing: Failure(
                        exitCode: proc.terminationStatus,
                        stderr: String(decoding: errData, as: UTF8.self)
                    ))
                }
            }
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}

/// 公開 GitHub API（api.github.com）へ URLSession でアクセスし、リリースの取得・ダウンロードを行う。
struct UpdateService {
    static let repoFullName = "m-tkg/clipkun"
    static let apiBase = "https://api.github.com"
    private static let userAgent = "Clipkun"

    /// 更新チェックは常に最新を取得したいので、キャッシュを使わない専用セッションを用いる。
    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.urlCache = nil
        return URLSession(configuration: config)
    }()

    enum ServiceError: LocalizedError {
        case requestFailed(Int)
        case decodeFailed
        case noZipAsset
        case downloadFailed(Int)

        var errorDescription: String? {
            switch self {
            case .requestFailed(let code):
                return L.format("error.fetch_release_http", code)
            case .decodeFailed:
                return L.string("error.parse_release")
            case .noZipAsset:
                return L.string("error.no_zip_asset")
            case .downloadFailed(let code):
                return L.format("error.download_http", code)
            }
        }
    }

    /// 現在のアプリバージョン（CFBundleShortVersionString）。
    static var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

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

    /// リリースの zip アセットを `directory` にダウンロードし、保存先 URL を返す。
    func downloadReleaseZip(_ release: ReleaseInfo, into directory: URL) async throws -> URL {
        guard let assetURL = release.zipAssetURL else {
            throw ServiceError.noZipAsset
        }
        log.info("Downloading release \(release.tagName, privacy: .public) from \(assetURL.absoluteString, privacy: .public)")

        var request = URLRequest(url: assetURL)
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")

        let (tempURL, response) = try await session.download(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw ServiceError.downloadFailed(http.statusCode)
        }

        let destination = directory.appendingPathComponent("Clipkun.zip")
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: tempURL, to: destination)
        return destination
    }
}
