import Foundation
import Vision
import CoreML

/// 画像データから Vision（`VNRecognizeTextRequest`）で文字列を認識するヘルパー。
/// OS 連携（Vision 依存）のため App ターゲットに置く。
enum ImageTextRecognizer {
    /// 画像内のテキストを認識し、行を改行で連結して返す（見つからなければ空文字列）。
    /// Vision の実行は同期 API のため、バックグラウンドに逃がしてメインスレッドをブロックしない。
    static func recognize(in data: Data) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            do {
                return try perform(on: data, restrictToCPU: false)
            } catch {
                // Neural Engine 用モデルの読み込みが OS 側の問題で失敗することがある
                // （TextRecognition.CRImageReaderError。beta OS でモデル欠落を確認）。
                // Apple の推奨ワークアラウンドに従い、CPU に限定して再試行する。
                return try perform(on: data, restrictToCPU: true)
            }
        }.value
    }

    private static func perform(on data: Data, restrictToCPU: Bool) throws -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["ja-JP", "en-US"]
        request.usesLanguageCorrection = true
        if restrictToCPU, #available(macOS 14.0, *) {
            for (stage, devices) in try request.supportedComputeStageDevices {
                let cpu = devices.first { if case .cpu = $0 { return true } else { return false } }
                if let cpu { request.setComputeDevice(cpu, for: stage) }
            }
        }
        let handler = VNImageRequestHandler(data: data)
        try handler.perform([request])
        let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
        return lines.joined(separator: "\n")
    }
}
