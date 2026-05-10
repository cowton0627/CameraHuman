import AVFoundation
import CoreMedia

enum HUDFormatters {
    static func frameRate(for device: AVCaptureDevice) -> String {
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
