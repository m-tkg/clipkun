import Foundation
import Vision

/// 画像データから Vision（`VNRecognizeTextRequest`）で文字列を認識するヘルパー。
/// OS 連携（Vision 依存）のため App ターゲットに置く。
enum ImageTextRecognizer {
    /// 画像内のテキストを認識し、行を改行で連結して返す（見つからなければ空文字列）。
    /// Vision の実行は同期 API のため、バックグラウンドに逃がしてメインスレッドを塞がない。
    static func recognize(in data: Data) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["ja-JP", "en-US"]
            request.usesLanguageCorrection = true
            let handler = VNImageRequestHandler(data: data)
            try handler.perform([request])
            let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
            return lines.joined(separator: "\n")
        }.value
    }
}
