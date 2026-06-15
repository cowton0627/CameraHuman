//
//  CameraManualControls.swift
//  CameraHuman
//

import AVFoundation
import CoreMedia

/// 手動控制的純換算 / clamp 邏輯，抽出來不依賴實體 `AVCaptureDevice`，方便單元測試。
/// 真正去 `lockForConfiguration` 設定 device 的部分在 `CameraSession`。
enum CameraManualControls {
    /// 拍攝常用的標準幀率。實機支援哪些由 device 的 frame rate range 再篩一次。
    static let standardFrameRates: [Double] = [24, 30, 60]

    /// 從 device 回報的 frame rate range 篩出落在範圍內的標準幀率。
    static func supportedStandardFrameRates(minFrameRate: Double, maxFrameRate: Double) -> [Double] {
        guard maxFrameRate > 0 else { return [] }
        return standardFrameRates.filter { $0 >= minFrameRate && $0 <= maxFrameRate }
    }

    /// fps → `CMTime` frame duration（設 `activeVideoMin/MaxFrameDuration` 用）。
    static func frameDuration(forFPS fps: Double) -> CMTime {
        let rounded = max(1, fps.rounded())
        return CMTime(value: 1, timescale: Int32(rounded))
    }

    /// 點 chip 循環切換：回傳支援清單裡的下一個幀率。
    /// 當前值不在清單時回第一個；清單空回 nil。
    static func nextFrameRate(after current: Double, in supported: [Double]) -> Double? {
        guard !supported.isEmpty else { return nil }
        guard let index = supported.firstIndex(where: { abs($0 - current) < 0.5 }) else {
            return supported.first
        }
        return supported[(index + 1) % supported.count]
    }

    static func clamp(_ value: Float, min lower: Float, max upper: Float) -> Float {
        guard upper > lower else { return lower }
        return Swift.max(lower, Swift.min(upper, value))
    }

    static func clamp(_ value: Double, min lower: Double, max upper: Double) -> Double {
        guard upper > lower else { return lower }
        return Swift.max(lower, Swift.min(upper, value))
    }

    /// 把滑桿的 0~1 位置映射到 [min, max] 線性區間。
    static func value(forSliderPosition position: Float, min lower: Float, max upper: Float) -> Float {
        lower + clamp(position, min: 0, max: 1) * (upper - lower)
    }

    /// 反向：把實際值映射回 0~1 滑桿位置（建面板時把滑桿擺到當前值）。
    static func sliderPosition(forValue value: Float, min lower: Float, max upper: Float) -> Float {
        guard upper > lower else { return 0 }
        return clamp((value - lower) / (upper - lower), min: 0, max: 1)
    }

    /// 快門速度顯示文字：1/N 秒。
    static func shutterText(forSeconds seconds: Double) -> String {
        guard seconds > 0 else { return "AUTO" }
        let denominator = max(1, Int((1 / seconds).rounded()))
        return "1/\(denominator)"
    }
}
