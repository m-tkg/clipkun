import Foundation

/// アプリ全体の設定。機能追加時はここにプロパティを足して拡張する。
/// 前方/後方互換のため Codable は欠損キーを既定値で補完する。
public struct Settings: Codable, Equatable {
    /// 履歴ポップアップを開くホットキー（既定 ⌥V）。
    public var popupHotKey: HotKeyConfig
    /// 履歴の保持期間（既定1日）。
    public var retention: RetentionPeriod
    /// 履歴の最大件数（既定200）。保持期間と併用し、超過分は最古から削除する。
    public var maxItemCount: Int

    /// 最大件数の許容範囲。
    public static let maxItemCountRange: ClosedRange<Int> = 10...1000

    public init(
        popupHotKey: HotKeyConfig = .defaultPopup,
        retention: RetentionPeriod = .default,
        maxItemCount: Int = 200
    ) {
        self.popupHotKey = popupHotKey
        self.retention = retention
        self.maxItemCount = min(
            max(maxItemCount, Settings.maxItemCountRange.lowerBound),
            Settings.maxItemCountRange.upperBound
        )
    }

    /// 既定設定。
    public static let `default` = Settings()

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let popupHotKey = try c.decodeIfPresent(HotKeyConfig.self, forKey: .popupHotKey) ?? .defaultPopup
        let retention = try c.decodeIfPresent(RetentionPeriod.self, forKey: .retention) ?? .default
        let maxItemCount = try c.decodeIfPresent(Int.self, forKey: .maxItemCount) ?? Settings.default.maxItemCount
        // クランプを通すため指定イニシャライザに委譲する。
        self.init(popupHotKey: popupHotKey, retention: retention, maxItemCount: maxItemCount)
    }

    private enum CodingKeys: String, CodingKey {
        case popupHotKey, retention, maxItemCount
    }
}
