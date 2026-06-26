import Foundation

/// 保持期間に基づき、期限切れの履歴を判定する純粋関数群。
///
/// `now` を引数で注入してテスト可能にする（実時刻に依存しない）。
public enum RetentionPolicy {
    /// `items` を保持対象と期限切れに分ける。
    ///
    /// 「作成時刻からの経過が保持期間を超えた」項目を期限切れとする。
    /// ちょうど期限（経過 == 保持期間）の項目は **保持する**（境界は含む）。
    /// - Returns: `kept`（保持・元の順序を維持）と `expired`（期限切れ・実体ファイルの後始末用）。
    public static func prune(
        _ items: [ClipItem],
        now: Date,
        period: RetentionPeriod
    ) -> (kept: [ClipItem], expired: [ClipItem]) {
        let cutoff = now.addingTimeInterval(-period.timeInterval)
        var kept: [ClipItem] = []
        var expired: [ClipItem] = []
        for item in items {
            if item.createdAt < cutoff {
                expired.append(item)
            } else {
                kept.append(item)
            }
        }
        return (kept, expired)
    }
}
