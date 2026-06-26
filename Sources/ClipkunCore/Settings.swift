import Foundation

/// ポップアップの表示位置。
public enum PopupPosition: String, Codable, Equatable, CaseIterable {
    /// マウスカーソルの位置。
    case cursor
    /// 画面中央。
    case screenCenter
}

/// アプリ全体の設定。機能追加時はここにプロパティを足して拡張する。
/// 前方/後方互換のため Codable は欠損キーを既定値で補完する。
public struct Settings: Codable, Equatable {
    /// 履歴ポップアップを開くホットキー（既定 ⌥V）。
    public var popupHotKey: HotKeyConfig
    /// 履歴の保持期間（既定1日）。
    public var retention: RetentionPeriod
    /// 履歴の最大件数（既定200）。保持期間と併用し、超過分は最古から削除する。
    public var maxItemCount: Int
    /// ポップアップの表示位置（既定: カーソル位置）。
    public var popupPosition: PopupPosition
    /// ポップアップ背景の不透明度（0=透明〜1=不透明、既定0.9）。
    public var popupBackgroundOpacity: Double

    /// 最大件数の許容範囲。
    public static let maxItemCountRange: ClosedRange<Int> = 10...1000
    /// 背景不透明度の許容範囲。
    public static let backgroundOpacityRange: ClosedRange<Double> = 0.2...1.0

    public init(
        popupHotKey: HotKeyConfig = .defaultPopup,
        retention: RetentionPeriod = .default,
        maxItemCount: Int = 200,
        popupPosition: PopupPosition = .cursor,
        popupBackgroundOpacity: Double = 0.9
    ) {
        self.popupHotKey = popupHotKey
        self.retention = retention
        self.maxItemCount = min(
            max(maxItemCount, Settings.maxItemCountRange.lowerBound),
            Settings.maxItemCountRange.upperBound
        )
        self.popupPosition = popupPosition
        self.popupBackgroundOpacity = min(
            max(popupBackgroundOpacity, Settings.backgroundOpacityRange.lowerBound),
            Settings.backgroundOpacityRange.upperBound
        )
    }

    /// 既定設定。
    public static let `default` = Settings()

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Settings.default
        let popupHotKey = try c.decodeIfPresent(HotKeyConfig.self, forKey: .popupHotKey) ?? .defaultPopup
        let retention = try c.decodeIfPresent(RetentionPeriod.self, forKey: .retention) ?? .default
        let maxItemCount = try c.decodeIfPresent(Int.self, forKey: .maxItemCount) ?? d.maxItemCount
        let popupPosition = try c.decodeIfPresent(PopupPosition.self, forKey: .popupPosition) ?? d.popupPosition
        let opacity = try c.decodeIfPresent(Double.self, forKey: .popupBackgroundOpacity) ?? d.popupBackgroundOpacity
        // クランプを通すため指定イニシャライザに委譲する。
        self.init(
            popupHotKey: popupHotKey,
            retention: retention,
            maxItemCount: maxItemCount,
            popupPosition: popupPosition,
            popupBackgroundOpacity: opacity
        )
    }

    private enum CodingKeys: String, CodingKey {
        case popupHotKey, retention, maxItemCount, popupPosition, popupBackgroundOpacity
    }
}
