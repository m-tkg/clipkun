import Foundation

/// 履歴の保持期間。1〜23時間 もしくは 1〜30日 を表現する。
///
/// 設定 UI の「単位 Picker + 数値」に素直にマップできる `{unit, amount}` 構造体。
/// `init` で範囲外の値をクランプし、不正な状態を作れないようにする。
public struct RetentionPeriod: Codable, Equatable {
    public enum Unit: String, Codable {
        case hours
        case days
    }

    /// 単位。
    public let unit: Unit
    /// 数量。hours は 1...23、days は 1...30 にクランプされる。
    public let amount: Int

    /// 各単位で許容される数量の範囲。
    public static func validRange(for unit: Unit) -> ClosedRange<Int> {
        switch unit {
        case .hours: return 1...23
        case .days: return 1...30
        }
    }

    public init(unit: Unit, amount: Int) {
        self.unit = unit
        let range = RetentionPeriod.validRange(for: unit)
        self.amount = min(max(amount, range.lowerBound), range.upperBound)
    }

    /// 既定の保持期間（1日）。
    public static let `default` = RetentionPeriod(unit: .days, amount: 1)

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let unit = try c.decodeIfPresent(Unit.self, forKey: .unit) ?? RetentionPeriod.default.unit
        let amount = try c.decodeIfPresent(Int.self, forKey: .amount) ?? RetentionPeriod.default.amount
        // クランプを通すため指定イニシャライザに委譲する。
        self.init(unit: unit, amount: amount)
    }

    private enum CodingKeys: String, CodingKey {
        case unit, amount
    }

    /// 保持期間を秒に換算した値（期限判定に使用）。
    public var timeInterval: TimeInterval {
        switch unit {
        case .hours: return TimeInterval(amount) * 3600
        case .days: return TimeInterval(amount) * 86_400
        }
    }
}
