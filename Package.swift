// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Clipkun",
    // ローカライズ済みリソース（en/ja）を持つため既定言語を指定する。
    defaultLocalization: "en",
    platforms: [
        .macOS(.v13)
    ],
    dependencies: [
        // kuntraykun 連携（プロトコル定数・Bridge・アイコン/メニュー書き出し）の共有ライブラリ。
        .package(url: "https://github.com/m-tkg/kunkit.git", from: "1.0.0")
    ],
    targets: [
        // 純粋ロジック（テスト対象）: AppKit/Carbon/NSPasteboard に依存しない
        // 履歴モデル・保持期間ポリシー・配置計算・設定モデル・バージョン比較。
        .target(
            name: "ClipkunCore"
        ),
        // 実行ファイル本体: メニューバー常駐・クリップボード監視・ポップアップ・ホットキー・設定UI。
        .executableTarget(
            name: "Clipkun",
            dependencies: [
                "ClipkunCore",
                .product(name: "KunIntegrationBridge", package: "kunkit"),
            ],
            // en.lproj / ja.lproj の Localizable.strings をリソースバンドルに含める。
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "ClipkunCoreTests",
            dependencies: ["ClipkunCore"]
        ),
    ]
)
