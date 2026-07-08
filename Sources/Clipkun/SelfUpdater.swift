import AppKit
import KunUpdateKit
import OSLog
import ClipkunCore

private let logger = Logger(subsystem: "com.mtkg.clipkun", category: "SelfUpdater")

/// 最新リリースの zip をダウンロード・展開し、起動中の `.app` を上書きして再起動する。
///
/// 実行中のバンドルは自プロセスでは上書きできないため、旧プロセスの終了を待ってから
/// 入れ替える切り離しシェルスクリプトを起動し、自身は `NSApp.terminate` で終了する。
@MainActor
final class SelfUpdater {

    enum UpdateError: LocalizedError {
        case notWritable(String)
        case archiveNotFound
        case commandFailed(String)
        case bundleNotFound
        case bundleIDMismatch

        var errorDescription: String? {
            switch self {
            case .notWritable(let path):
                return L.format("error.not_writable", path)
            case .archiveNotFound:
                return L.string("error.no_zip")
            case .commandFailed(let msg):
                return L.format("error.command_failed", msg)
            case .bundleNotFound:
                return L.string("error.no_app_in_archive")
            case .bundleIDMismatch:
                return L.string("error.bundle_id_mismatch")
            }
        }
    }

    private let service: UpdateService

    init(service: UpdateService) {
        self.service = service
    }

    /// 更新を実行する。成功した場合はアプリを終了するため、呼び出し元には戻らない。
    func performUpdate(to release: ReleaseInfo) async throws {
        let bundleURL = Bundle.main.bundleURL
        try ensureWritable(bundleURL)

        let fm = FileManager.default
        let workDir = fm.temporaryDirectory
            .appendingPathComponent("clipkun-update-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: workDir, withIntermediateDirectories: true)

        let zipURL = try await service.downloadReleaseZip(release, into: workDir)

        let extractDir = workDir.appendingPathComponent("extracted", isDirectory: true)
        try fm.createDirectory(at: extractDir, withIntermediateDirectories: true)
        try await runAndWait("/usr/bin/ditto", ["-x", "-k", zipURL.path, extractDir.path])

        guard let newApp = try firstFile(in: extractDir, pathExtension: "app") else {
            throw UpdateError.bundleNotFound
        }
        // ローカルビルド（`.local` サフィックス）でも本番リリースへ更新できるよう、基底IDで比較する。
        guard let newBundleID = Bundle(url: newApp)?.bundleIdentifier,
              Self.baseBundleID(newBundleID) == Self.baseBundleID(Bundle.main.bundleIdentifier) else {
            throw UpdateError.bundleIDMismatch
        }

        try launchReplaceScript(newApp: newApp, dest: bundleURL)
        logger.info("Relaunch script started; terminating for update to \(release.tagName, privacy: .public)")
        NSApp.terminate(nil)
    }

    private static func baseBundleID(_ id: String?) -> String {
        guard let id else { return "" }
        return id.hasSuffix(".local") ? String(id.dropLast(".local".count)) : id
    }

    private func ensureWritable(_ bundleURL: URL) throws {
        let fm = FileManager.default
        let parent = bundleURL.deletingLastPathComponent().path
        guard fm.isWritableFile(atPath: parent), fm.isWritableFile(atPath: bundleURL.path) else {
            throw UpdateError.notWritable(bundleURL.path)
        }
    }

    private func firstFile(in directory: URL, pathExtension: String) throws -> URL? {
        let entries = try FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil)
        return entries.first { $0.pathExtension == pathExtension }
    }

    /// 旧プロセス終了を待って `.app` を入れ替え、再起動する切り離しスクリプトを起動する。
    private func launchReplaceScript(newApp: URL, dest: URL) throws {
        let pid = ProcessInfo.processInfo.processIdentifier
        let script = """
        while kill -0 \(pid) 2>/dev/null; do sleep 0.2; done
        rm -rf "$DEST.bak"
        mv "$DEST" "$DEST.bak" || exit 1
        if ! mv "$NEW" "$DEST"; then
          mv "$DEST.bak" "$DEST"
          exit 1
        fi
        rm -rf "$DEST.bak"
        xattr -dr com.apple.quarantine "$DEST" 2>/dev/null
        open "$DEST"
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script]
        process.environment = [
            "DEST": dest.path,
            "NEW": newApp.path,
            "PATH": "/usr/bin:/bin",
        ]
        try process.run()
    }

    private func runAndWait(_ executable: String, _ arguments: [String]) async throws {
        do {
            _ = try await ProcessRunner.run(executable: executable, arguments: arguments)
        } catch let failure as ProcessRunner.Failure {
            let msg = failure.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            logger.error("Command failed (\(executable, privacy: .public) exit=\(failure.exitCode)): \(msg)")
            throw UpdateError.commandFailed(msg.isEmpty ? "exit \(failure.exitCode)" : msg)
        }
    }
}
