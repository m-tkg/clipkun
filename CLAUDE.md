# CLAUDE.md — clipkun

このリポジトリで作業する際のガイド。

**メニューバー常駐アプリ（kun シリーズ）共通の方針は上位ディレクトリの [`../kun-template/CLAUDE_base.md`](../kun-template/CLAUDE_base.md) を参照**
（Swift Package 構成・日英ローカライズ・アップデート・kunkit 連携・リリース手順・ブランチ運用など）。
共通方針を変えるときは `CLAUDE_base.md`（[kun-template](https://github.com/m-tkg/kun-template) が canonical）を編集する。
本ファイルには clipkun 固有の事項のみを記す。

---

# clipkun 固有事項

**概要**: Mac で動くクリップボード履歴ツール。bundle ID は `com.mtkg.clipkun`。
ターゲットは `ClipkunCore`（純粋ロジック）＋ `Clipkun`（App）。

## 機能
- ユーザ指定可能なグローバルホットキー（既定 ⌥V）で、クリップボード履歴をカーソル位置にポップアップ表示。
- 各行に番号を表示（最新＝1）。カーソルキー / クリックで選択（端で止まりループしない）、ESC または外側クリックでキャンセル。
- 選んだ履歴を最新のクリップボードへ書き戻す。**テキストに限り、書き戻しと同時に前面アプリへ自動ペースト**（⌘V 合成送出）。
- テキスト / ファイル / 画像など多様な型を保持。画像はリストにサムネ表示。
- 保持期間: 既定1日（1〜23時間 / 1〜30日から選択可能）。期限切れは破棄。
- メニューバーから履歴の全削除。各履歴行の右のゴミ箱アイコンで個別削除（削除後は一覧を再描画）。
- 最大件数の上限（既定200件）。保持期間と併用し、超過分は最古から evict。

## 技術メモ
- **ホットキー**: Carbon `RegisterEventHotKey`（アクセシビリティ権限不要・ユーザ設定可）。
- **クリップボード監視**: `NSPasteboard.general.changeCount` を 0.5 秒ポーリング（変更通知 API は無い）。
  自分の書き戻しは `lastChangeCount` 追跡で二重取り込みを防ぐ。ポップアップ表示直前に `captureNow()` で
  即時取り込みし、コピー直後でも最新を取りこぼさない。
- **ポップアップ**: `.nonactivatingPanel` の `NSPanel`（`canBecomeKey` override）。
  `.accessory` のままキー入力を受け取り、前面アプリのフォーカス文脈を壊さない。
  表示・個別削除のたびに `NSHostingView` を作り直して確実に再描画する（offscreen の取りこぼし対策）。
  ホバーでは選択ハイライトのみ更新し、スクロールはキーボード操作時だけにする。
- **自動ペースト**: テキスト選択時に `CGEvent` で ⌘V を `.cghidEventTap` へ合成送出（`AutoPaster`）。
  **アクセシビリティ許可が必要**（未許可なら初回に許可ダイアログ）。
- **ファイル書き戻しと TCC**: `writeObjects([NSURL])` はファイル本体へアクセスするため、保護フォルダ
  （~/Downloads 等）でアクセス権が無いと file-url が剥がされる。`NSPasteboardItem` の public.file-url
  文字列として載せ、書き戻し前にファイルへ軽くアクセスして「ファイルとフォルダ」許可ダイアログを誘発する。
  ローカルビルドも **Developer ID 署名**（`AD_HOC` を付けない）にして許可を保持する。
- **画像**: 取り込みは `public.image` 準拠の全形式（PNG/TIFF/JPEG/GIF/HEIC 等）。書き戻しは `NSImage` を
  `writeObjects` し TIFF を含む各種フレーバーを提供。PNG 化できない画像（PDF ベース等）はスキップ。
- **永続化**: `~/Library/Application Support/Clipkun/` に `index.json`（メタデータ）＋
  `blobs/`（画像PNG・ファイルパス群・長文）＋ `thumbnails/`。dedup は `contentHash`（SHA-256）。

## アップデート（定期監視＋赤バッジ）

`CLAUDE_base.md`「### 4. アップデート機能を入れる」の方式に準拠。要点と実装箇所:
- **チェックの単一経路**: `AppDelegate.startUpdateCheck(interactive:)`。起動時1回 ＋ `startUpdateTimer()` の
  `Timer.scheduledTimer(withTimeInterval: 3600, repeats: true)`（未認証 API 60回/時に余裕を持って1時間・`tolerance` 360）
  ＋ `NSWorkspace.didWakeNotification`（`systemDidWake`）でスリープ復帰時も即チェック。タイマーは
  `MainActor.assumeIsolated` で `@MainActor` のチェックを呼ぶ。
- **赤バッジ**: `Sources/Clipkun/UpdateBadgeView.swift`（`NSView`＋`CALayer` の赤丸・白縁取り）を
  `StatusBarController.installBadge(on:)` で `statusItem.button` にオーバーレイ。ベース画像は `isTemplate` 維持。
  位置は **アイコン画像の幅基準**（`leading = button.leading + (iconWidth − badgeSize)`, `bottom = button.bottom`）で、
  「ローカル」併記時（`imagePosition = .imageLeading`）でもアイコングリフの右下に固定。
- **表示/非表示の集約**: `StatusBarController.setUpdateAvailable`（表示）/ `clearUpdateAvailable`（非表示）に
  `badgeView?.isHidden` のトグルを置き、起動・定期・手動・復帰の全経路で同期。
- 注意: kuntraykun 集約でアイコンを隠している間（`setManagedHidden(true)`）はバッジも見えない。

## Kuntraykun 連携（実装済み・kunkit 利用）

本アプリは kuntraykun（`com.mtkg.kuntraykun`）にメニューバーアイコンを集約させる連携（v1〜v4:
アイコン集約・実アイコン書き出し・アップデート集約・サブメニュー表示）に対応している。
- **実装は共有ライブラリ [kunkit](https://github.com/m-tkg/kunkit)**（SPM 依存、`KunIntegrationBridge` プロダクト）。
  `KuntraykunBridge` / `KuntraykunIconExport` / `KuntraykunMenuExport` を提供し、アプリ側に連携ロジックの複製は持たない。
- 配線: `StatusBarController.makeKuntraykunBridge()`（`KuntraykunBridge(statusItem:menu:)` の標準配線）を
  `AppDelegate` が `bridge.start()` する。start() が観測開始・`appLaunched` 送信・初回メニュー書き出しまで行う。
  アイコン書き出し（v2）は `StatusBarController` init の `KuntraykunIconExport.export(_:)`、
  アップデート報告（v3）は `kuntraykunBridge?.reportUpdate(_:)`、
  メニュー文言の変化（v4）は `statusBar.onMenuContentChanged` → `bridge.exportMenuSnapshot()`（表示中は自動保留）。
- 仕様: kuntraykun リポジトリ `docs/kun-integration-protocol.md`、共通方針は `CLAUDE_base.md`「Kuntraykun 連携」。
- 管理対象フラグは kunkit が `UserDefaults`（キー `KuntraykunManaged`）に永続化する。
- **kunkit 由来の共通実装**: 自己更新（`SelfUpdater`）・ログイン項目（`LoginItemController`）・多重起動防止（`KunAppLaunch`、`main.swift`）・設定永続化（`KunSettingsStore`）・外部プロセス実行（`ProcessRunner`）・更新チェック（`GitHubReleaseFetcher` / `ReleaseInfo` / `VersionComparator` / `KunUpdateSchedule` / `ReleaseDownloader`）は kunkit（`KunAppKit` / `KunSupport` / `KunUpdateKit`）が提供する。アプリ側に複製は持たず、アプリ名・文言・repo は注入する。
- **kunkit の更新運用**: 連携プロトコルの変更・修正は kunkit 側（TDD）で行って semver タグを発行し、
  各アプリは `swift package update kunkit` で追従する（`from: "1.0.0"` 指定のため 1.x は自動追従、
  破壊的変更はメジャーを上げる）。本リポジトリは `Package.resolved` を追跡しているので、
  更新時は resolved の変更もコミットする。
- **連携のデバッグ**: まず `~/Library/Application Support/Kuntraykun/Menus/<基底ID>.json` の中身
  （空なら書き出し側の問題）と、Console の subsystem `com.mtkg.clipkun` / category `kuntraykun` の
  ログを確認する。
