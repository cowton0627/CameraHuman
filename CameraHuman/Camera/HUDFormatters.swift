import AVFoundation
import CoreMedia

enum HUDFormatters {
    static func frameRate(for device: AVCaptureDevice) -> String {
        // 優先讀「實際生效的幀率」（手動鎖定後 activeVideoMaxFrameDuration 會反映），
        // 沒設定時才 fallback 到 format 支援的最高幀率。
        let maxDuration = device.activeVideoMaxFrameDuration
        if maxDuration.isValid, CMTimeGetSeconds(maxDuration) > 0 {
            return String(format: "%.0f", 1 / CMTimeGetSeconds(maxDuration))
        }
        let maxFrameRate = device.activeFormat.videoSupportedFrameRateRanges.map(\.maxFrameRate).max() ?? 0
        return String(format: "%.0f", maxFrameRate)
    }

    static func shutter(for device: AVCaptureDevice) -> String {
        let duration = CMTimeGetSeconds(device.exposureDuration)
        guard duration > 0 else { return "AUTO" }
        let denominator = max(1, Int(round(1 / duration)))
        return "1/\(denominator)"
    }

    static func iris(for device: AVCaptureDevice) -> String {
        if device.lensAperture > 0 {
            return String(format: "F%.1f", device.lensAperture)
        }
        return "FIXED"
    }

    static func whiteBalance(for device: AVCaptureDevice) -> String {
        switch device.whiteBalanceMode {
        case .locked:
            return "LOCK"
        case .autoWhiteBalance, .continuousAutoWhiteBalance:
            return "AUTO"
        @unknown default:
            return "--"
        }
    }

    static func resolution(for device: AVCaptureDevice) -> String {
        let dimensions = CMVideoFormatDescriptionGetDimensions(device.activeFormat.formatDescription)
        return "\(dimensions.width)×\(dimensions.height)"
    }
}
