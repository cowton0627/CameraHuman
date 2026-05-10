import AVFoundation

enum CameraDiagnostics {
    struct Inputs {
        let recordingState: String
        let quality: String
        let aspect: String
        let lensTitle: String?
        let position: AVCaptureDevice.Position
        let device: AVCaptureDevice?
        let audioAuthorized: Bool
        let audioTrackCount: Int
    }

    static func report(from inputs: Inputs) -> String {
        let position = inputs.position == .front ? "FRONT" : "BACK"
        let lens = inputs.lensTitle ?? "--"
        let resolution = inputs.device.map(HUDFormatters.resolution(for:)) ?? "--"
        let micState = inputs.audioAuthorized ? "ON" : "OFF"
        let trackCount = max(inputs.audioTrackCount, inputs.audioAuthorized ? 1 : 0)

        return [
            "Recording  \(inputs.recordingState)",
            "Quality    \(inputs.quality) · \(inputs.aspect)",
            "Lens       \(lens) · \(position)",
            "Resolution \(resolution)",
            "Mic        \(micState) · \(trackCount) track\(trackCount == 1 ? "" : "s")"
        ].joined(separator: "\n")
    }
}
