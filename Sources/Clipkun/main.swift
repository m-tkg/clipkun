import AppKit
import KunAppKit

// OCR ヘルパーモード: `--ocr <画像パス> <出力パス>` で起動されたら認識だけ行って終了する
// （ImageTextRecognizer が新規プロセスでの認識やり直しに使う。常駐処理は一切通さない）。
if CommandLine.arguments.count >= 4, CommandLine.arguments[1] == "--ocr" {
    exit(ImageTextRecognizer.helperMain(
        imagePath: CommandLine.arguments[2], outputPath: CommandLine.arguments[3]))
}

// メニューバー常駐アプリとして起動する（Dock アイコンなし）。
// トップレベルはメインスレッドで実行されるため、MainActor として扱う。
MainActor.assumeIsolated {
    // 多重起動防止: 同じ bundle ID の他インスタンスが既に動いていたら、そちらを前面に出して起動しない。
    KunAppLaunch.terminateIfAlreadyRunning()

    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
