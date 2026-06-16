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

    // MARK: - ISO stops（1/3 級標準段位）

    /// 1/3 stop 標準 ISO 序列。低到 10、高到 51200 涵蓋所有 iPhone 鏡頭範圍。
    static let isoStopBase: [Float] = [
        10, 12, 16, 20, 25, 32, 40, 50, 64, 80,
        100, 125, 160, 200, 250, 320, 400, 500, 640, 800,
        1000, 1250, 1600, 2000, 2500, 3200, 4000, 5000, 6400, 8000,
        10000, 12800, 16000, 20000, 25600, 32000, 40000, 51200
    ]

    /// 依鏡頭實際 min/max 產生 ISO 段位。端點用硬體實際值（iPhone minISO 常是 34 之類非標準值，
    /// 保留它才能用到最低光），中間鋪標準 1/3 stop。
    static func isoStops(min lower: Float, max upper: Float) -> [Float] {
        guard upper > lower, lower > 0 else { return [lower].filter { $0 > 0 } }
        var stops = isoStopBase.filter { $0 > lower && $0 < upper }
        stops.insert(lower, at: 0)
        stops.append(upper)
        return stops
    }

    // MARK: - Shutter angle（電影機快門角度制）

    /// 常用快門角度。180° 是電影感標準甜蜜點。
    static let shutterAngles: [Double] = [45, 90, 172.8, 180, 270, 360]
    static let recommendedShutterAngle: Double = 180

    /// 快門角度 → 快門速度（秒）。180° @ 24fps = 1/48。
    static func shutterSeconds(forAngle angle: Double, fps: Double) -> Double {
        guard fps > 0, angle > 0 else { return 0 }
        return angle / (360 * fps)
    }

    /// 快門速度（秒）→ 最接近的快門角度（建面板時把當前快門擺到對的段位）。
    static func nearestShutterAngle(forSeconds seconds: Double, fps: Double) -> Double {
        guard seconds > 0, fps > 0 else { return recommendedShutterAngle }
        let angle = seconds * 360 * fps
        return shutterAngles.min(by: { abs($0 - angle) < abs($1 - angle) }) ?? recommendedShutterAngle
    }

    /// 角度顯示文字：整數不帶小數，172.8 保留一位。
    static func angleText(_ angle: Double) -> String {
        if abs(angle - angle.rounded()) < 0.05 {
            return "\(Int(angle.rounded()))°"
        }
        return String(format: "%.1f°", angle)
    }

    /// 60Hz 電網下是否為防閃爍安全快門（≈1/60 或 1/120）。台灣是 60Hz。
    static func isFlickerSafe60Hz(seconds: Double) -> Bool {
        guard seconds > 0 else { return false }
        let denominator = 1 / seconds
        return abs(denominator - 60) < 1.5 || abs(denominator - 120) < 1.5
    }
}
