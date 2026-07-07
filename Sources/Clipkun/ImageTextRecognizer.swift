import Foundation
import Vision
import OSLog

private let log = Logger(subsystem: "com.mtkg.clipkun", category: "ocr")

/// 画像データから Vision（`VNRecognizeTextRequest`）で文字列を認識するヘルパー。
/// OS 連携（Vision 依存）のため App ターゲットに置く。
enum ImageTextRecognizer {
    /// 画像内のテキストを認識し、行を改行で連結して返す（見つからなければ空文字列）。
    /// Vision の実行は同期 API のため、バックグラウンドに逃がしてメインスレッドをブロックしない。
    ///
    /// OS 側の不具合対策: 同一プロセス内の2回目以降の認識が、Neural Engine 用モデルの
    /// 再利用（precompiled 経路）で `TextRecognition.CRImageReaderError` になることがある
    /// （新規プロセスの初回認識は常に成功することを確認済み）。失敗したら自分自身を
    /// `--ocr` モードの子プロセスとして起動し、新規プロセスで認識をやり直す。
    static func recognize(in data: Data) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            do {
                return try performSync(on: data)
            } catch {
                log.error("in-process OCR failed, retrying in helper process: \(error.localizedDescription, privacy: .public)")
                return try recognizeInHelperProcess(data: data)
            }
        }.value
    }

    /// `--ocr <画像パス> <出力パス>` で起動されたときの入口（main.swift から呼ばれる）。
    /// 認識テキストを出力パスへ UTF-8 で書いて終了コード 0、失敗なら標準エラーへ書いて 1 を返す。
    /// OS フレームワークが標準出力へ警告を吐くことがあるため、結果はファイル経由で受け渡す。
    static func helperMain(imagePath: String, outputPath: String) -> Int32 {
        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: imagePath))
            let text = try performSync(on: data)
            try text.write(toFile: outputPath, atomically: true, encoding: .utf8)
            return 0
        } catch {
            FileHandle.standardError.write(Data("\(error.localizedDescription)\n".utf8))
            return 1
        }
    }

    private static func performSync(on data: Data) throws -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["ja-JP", "en-US"]
        request.usesLanguageCorrection = true
        let handler = VNImageRequestHandler(data: data)
        try handler.perform([request])
        let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
        return lines.joined(separator: "\n")
    }

    /// 自分自身の実行バイナリを `--ocr` モードで起動し、新規プロセスで認識する。
    private static func recognizeInHelperProcess(data: Data) throws -> String {
        guard let executable = Bundle.main.executableURL else {
            throw CocoaError(.executableNotLoadable)
        }
        let workID = "clipkun-ocr-\(UUID().uuidString)"
        let tempDir = FileManager.default.temporaryDirectory
        let imageFile = tempDir.appendingPathComponent("\(workID).png")
        let outputFile = tempDir.appendingPathComponent("\(workID).txt")
        try data.write(to: imageFile)
        defer {
            try? FileManager.default.removeItem(at: imageFile)
            try? FileManager.default.removeItem(at: outputFile)
        }

        let process = Process()
        process.executableURL = executable
        process.arguments = ["--ocr", imageFile.path, outputFile.path]
        // OS フレームワークが標準出力へ警告を吐くため、stdout は捨てて結果はファイルで受け取る。
        process.standardOutput = FileHandle.nullDevice
        let stderr = Pipe()
        process.standardError = stderr
        try process.run()
        // モデル初回コンパイルで時間がかかることがあるため長めに待ち、ハングだけ防ぐ。
        DispatchQueue.global().asyncAfter(deadline: .now() + 60) {
            if process.isRunning { process.terminate() }
        }
        let errorOutput = stderr.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0,
              let text = try? String(contentsOf: outputFile, encoding: .utf8) else {
            let message = String(data: errorOutput, encoding: .utf8) ?? ""
            log.error("helper OCR failed (status \(process.terminationStatus)): \(message, privacy: .public)")
            throw NSError(
                domain: "com.mtkg.clipkun.ocr", code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: message.isEmpty ? "OCR helper failed" : message])
        }
        return text
    }
}
