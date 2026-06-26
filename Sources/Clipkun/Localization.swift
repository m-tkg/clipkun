import Foundation

/// SwiftPM のリソースバンドル位置を特定するためのトークン（`Bundle(for:)` 用）。
private final class BundleToken {}

/// ローカライズ済み文字列を SwiftPM のリソースバンドルから解決するヘルパー。
///
/// 新しい GUI 文字列を追加するときは、必ずキーを定義して
/// `Resources/en.lproj` と `Resources/ja.lproj` の両方に対訳を追加すること。
///
/// - Important: SwiftPM 生成の `Bundle.module` は使わない（見つからないと fatalError）。
///   `bundle.sh` が配置する `Contents/Resources/Clipkun_Clipkun.bundle` を含む複数候補を
///   自前で探索し、見つからなければ `.main` にフォールバックする。
enum L {
    private static let bundle: Bundle = {
        let bundleName = "Clipkun_Clipkun.bundle"
        let candidates: [URL?] = [
            Bundle.main.resourceURL,
            Bundle.main.bundleURL,
            Bundle(for: BundleToken.self).resourceURL,
            Bundle(for: BundleToken.self).bundleURL,
        ]
        for base in candidates.compactMap({ $0 }) {
            let url = base.appendingPathComponent(bundleName)
            if let bundle = Bundle(url: url) {
                return bundle
            }
        }
        return .main
    }()

    /// キーに対応するローカライズ文字列を返す。未定義時はキー自体を返す（抜け漏れを可視化）。
    static func string(_ key: String) -> String {
        bundle.localizedString(forKey: key, value: key, table: nil)
    }

    /// 書式付きローカライズ文字列。`%@`/`%d`/`%.1f` などのプレースホルダに値を埋め込む。
    static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: string(key), locale: .current, arguments: arguments)
    }
}
