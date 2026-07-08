# CLAUDE_base.md — メニューバー常駐アプリ作成の共通ガイド

snapperkun / whisperkun / keykun の知見をまとめた、macOS タスクトレイ（メニューバー常駐）
アプリを新規作成する際の共通方針。新規プロジェクトの `CLAUDE.md` はこれをベースに、
プロジェクト固有の事項を足して作る。

## 基本構成

- **Swift Package Manager** の 2 ターゲット構成。**純粋ロジックとプラットフォーム依存を分離**する。
  - `<Name>Core`（ライブラリ / テスト対象）: AppKit/Carbon/AX/CGEventTap に依存しないロジックとモデル。
    判定ロジックは時刻などを注入する純粋関数/状態機械にして **TDD（テスト先行）** で実装する。
  - `<Name>`（実行ファイル）: AppKit/SwiftUI/各種 OS 連携と UI。
- **メニューバー常駐**（Dock アイコンなし）。`Info.plist` に `LSUIElement = true`、
  `main.swift` で `NSApplication` を `.accessory` 起動（`MainActor.assumeIsolated`）。
- **多重起動防止**: 起動時に同じ bundle ID の他インスタンスがあれば、それを前面化して自分は `exit(0)`。
- `.app` 化は `Scripts/bundle.sh`（`swift build` → バンドル組み立て → 署名）。Xcode プロジェクトは持たない。
- リリースは GitHub Actions（`.github/workflows/release.yml`）。`Info.plist` の
  `CFBundleShortVersionString` を上げて `main` にマージした後、`make release-tag` で
  `v<version>` タグを作成・push すると、そのタグ push を契機に CI がビルド・署名・公証して
  リリースを自動作成する（main へのマージだけではリリースされない。同名リリースがあればスキップ）。

---

## 必須チェックリスト

### 1. Secrets は `setup-release-secrets.sh` で登録する
配布用の署名＋公証の Secrets（計6つ）は、上位ディレクトリの **`setup-release-secrets.sh`** で一括登録する。
```sh
~/git/github.com/m-tkg/setup-release-secrets.sh -r m-tkg/<repo>
```
- 署名: `SIGNING_IDENTITY` / `SIGNING_CERTIFICATE_PASSWORD` / `SIGNING_CERTIFICATE_P12_BASE64`
- 公証: `NOTARY_APPLE_ID` / `NOTARY_PASSWORD` / `NOTARY_TEAM_ID`
- 署名は Developer ID Application（Team ID `G72M73C546`）。**安定署名でアクセシビリティ権限(TCC)が
  アップデート越しに保持される**（ad-hoc は毎回変わり無効化される）。
- ワークフローは Secrets が無ければ ad-hoc 署名／公証スキップにフォールバックする。
- `setup-release-secrets.sh` は秘密鍵(.p12)を含むので**リポジトリにコミットしない**（上位ディレクトリは git 管理外）。

### 2. すべての UI を日英対応にする
GUI 文字列は **日本語・英語の 2 言語**に対応し、OS の優先言語に追従する（既定 `en`）。
- 文字列リテラルを `Text`/`Button`/`NSMenuItem`/`NSAlert`/ウィンドウタイトル/HUD 等に直接渡さない。
  `Resources/{en,ja}.lproj/Localizable.strings` の**両方**にキーと対訳を足し、
  コードは `L.string("キー")` / `L.format("キー", 値…)` で参照する（`Localization.swift` の `L`）。
- `Package.swift` に `defaultLocalization: "en"` と `resources: [.process("Resources")]`。
- **`Info.plist` に `CFBundleLocalizations`（en, ja）が必須**。無いと macOS がアプリ言語を
  開発リージョン(en)に固定し、ネスト文字列バンドルも en にフォールバックして日本語が一切出ない。
  ```xml
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleLocalizations</key><array><string>en</string><string>ja</string></array>
  ```
- `L` は SwiftPM 生成のリソースバンドル（`<Name>_<Name>.bundle`）を自前探索で解決し、
  見つからなければ `.main` にフォールバック（`Bundle.module` はクラッシュしうるので使わない）。
  `bundle.sh` がこのバンドルを `Contents/Resources/` にコピーする。

### 3. bundle ID は `com.mtkg.****` にする
本番の bundle ID は **`com.mtkg.<appname>`**（例: `com.mtkg.keykun` / `com.mtkg.snapperkun`）。
`Info.plist` の `CFBundleIdentifier`、各 `Logger(subsystem:)`、`UpdateService` 等で一貫させる。

### 4. アップデート機能を入れる
GitHub Releases から最新版を取得して自己更新する。
- `Core`: `ReleaseInfo`（`/releases/latest` の Decodable）と `VersionComparator`（タグの数値比較・純粋・テスト）。
- `App`: `UpdateService`（公開 GitHub API を URLSession で取得・zip DL。キャッシュ無効の ephemeral セッション）、
  `SelfUpdater`（zip を `ditto` 展開 → bundle ID 検証 → 旧プロセス終了待ち→入替の切り離しスクリプト→再起動）。
- メニューに「アップデートを確認…」を置き、起動時にサイレントチェック。新版があればメニュー文言を
  「アップデート v… をインストール…」に変える。
- 自己更新の bundle ID 検証は**基底ID（`.local` を除去）で比較**し、ローカルビルドからも本番へ更新できるようにする。

### 5. 自動起動（ログイン項目）機能を入れる
- `LoginItemController` で `SMAppService.mainApp`（macOS 13+）を register/unregister。
- **状態はシステム側が source of truth**。`Settings`/JSON には保存しない。表示時に `refresh()` で同期する。
- `.requiresApproval`（システム設定でログイン項目が無効）時は案内文を出す。
- トグルは設定の Apply/Cancel とは独立に**即時反映**する。

### 6. 設定は「設定」メニュー/ダイアログに集約する
- メニューバーのメニューは入口だけ（設定… / 権限確認 / アップデート確認 / 終了 など）。
  設定項目そのものはメニューに展開せず、**設定ダイアログ**に集約する。
- 設定ダイアログは SwiftUI を `NSWindow` にホストし、**タブ**で機能ごとに分割（機能追加はタブを足す）。
  「一般」タブ（自動起動・バージョン等）は**左端**に置く。
- **設定ダイアログ表示中は Dock アイコンを出す**。`SettingsWindowController` が表示時に
  `NSApp.setActivationPolicy(.regular)`、クローズ時に `.accessory` へ戻す。
- 設定の永続化は `Core` の `Settings`（機能ごとにサブ構造体）＋ `SettingsStore`（JSON、読込失敗で既定にフォールバック）。
  Codable は `decodeIfPresent ?? 既定値` で欠損キーを補完し前方/後方互換にする。
- SwiftUI を import するファイルでは `Settings`/`Binding` が SwiftUI と名前衝突するため
  `<Name>Core.Settings` / `@SwiftUI.Binding` と明示する。

### 7. ローカルビルドは「ローカル」表示で本番と区別する
- `bundle.sh` に `LOCAL=1` モードを設ける: bundle ID を `com.mtkg.<app>.local`、表示名を `<App> (Local)` にする。
- アプリは bundle ID が `.local` で終わるかで `isLocalBuild` を判定し、**メニューバーアイコンに「ローカル」を併記**、
  メニューのバージョン項目にも「(ローカル)」を付ける。
- 本番と bundle ID が違うので **TCC 権限が別エントリになり衝突しない**（独立して許可できる）。

### 8. ローカルの公証に気をつける
- 公証(notarization)は **CI のリリースビルドのみ**。ローカルビルド（`LOCAL=1` / `bundle.sh` 手元実行）は
  **署名はされるが公証されない**。配布物と取り違えない。
- ローカルビルドは bundle ID が `.local` で**別アプリ扱い**のため、**アクセシビリティ権限を別途付与**する必要がある。
- ローカルは未公証なので Gatekeeper の quarantine が付くと起動を阻まれることがある。必要なら
  `xattr -dr com.apple.quarantine <App>.app`（自己更新の入替スクリプトでも実施している）。
- ローカルでも Developer ID 署名（`SIGN_IDENTITY` 既定）にしておくと、再ビルドで TCC 権限が保持され検証が楽。

### 9. メニューにバージョン情報を入れる
- メニューバーのメニュー**先頭に操作不可のバージョン項目**（例: `Keykun 1.1.1`）を置き、区切り線を続ける。
- 文言は `Bundle.main` の `CFBundleShortVersionString`（`UpdateService.currentVersion`）から生成し、ローカルは「(ローカル)」を付す。
- 設定ダイアログ「一般」タブにもバージョンを表示する。

---

## イベントタップ系（keykun のような CGEventTap を使う場合）

- **イベントタップは1つを共有**し、機能ごとにハンドラを登録する（別タップを作らない）。
- **コールバック内で重い処理や再入しうる post を同期実行しない**。重い処理は `tapDisabledByTimeout` を招き
  イベントを取りこぼして状態が固着する。副作用は `DispatchQueue.main.async` でコールバック復帰後に逃がす。
- **タップ無効化時はハンドラ状態をリセット**して取りこぼし後の固着を防ぐ。
- **合成キーイベントは `.cghidEventTap`（HID 相当）に post**する（`.cgSessionEventTap` だと IME 等に届かない）。
- 入力モード切替は **英数/かなキー送出**が確実（`TISSelectInputSource` は「選択中の再選択が no-op」で
  複数モード IME では切り替わらない）。

## ブランチ運用（必須）

- **`main` ブランチへ直接コミット/push しない**。変更は必ず **Pull Request 経由**で行う。
- 作業ブランチは**必ずその時点の最新の `main` から切る**。ブランチ作成前に
  `git fetch origin && git switch main && git pull --ff-only`（または `git fetch && git switch -c <branch> origin/main`）
  で main を最新化してから分岐する。
- PR は `gh pr create` で作成し、マージはレビュー後に行う。
- **PR 作成後に追加の修正を行うときは、まずその PR が既にマージされていないか確認する**
  （`gh pr view <番号> --json state,mergedAt`）。マージ済みの場合、その PR の作業ブランチへ
  push しても main には反映されない（孤立コミットになる）。マージ済みなら**最新 `main` から
  新しいブランチを切り直し**、必要な修正と（リリースが要るなら）バージョン更新を入れて別 PR を出す。
- リリース用 Actions は `push: tags: ["v*"]` で発火する。main へのマージだけではリリースされず、
  `make release-tag` で明示的に v タグを作成・push した時だけリリースが走る。とはいえ main
  直 push は避け、PR マージ経由にする運用は変わらない。

## 開発の進め方

- 純粋ロジック（`Core`）は **TDD**（テスト先行）。UI/OS 連携は手動確認（実機で権限付与が必要）。
- 新機能の追加手順: ①判定ロジックを `Core` に純粋実装＋テスト → ②`Settings` にサブ構造体を足す →
  ③設定 UI にタブを足す → ④GUI 文字列を en/ja 両方に対訳追加。
- リリースは `Info.plist` の `CFBundleShortVersionString` を上げて `main` にマージした後、
  `make release-tag` でタグを作成・push（署名＋公証は CI が実施）。

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
