import AVFoundation

/// 用 timer 輪詢 `AVCaptureConnection` 的 audio channels，把平均音量正規化成 0~1，回 callback 給 UI。
/// 不持有 capture session，只持有當前要讀的 connection（可隨時換）。
final class AudioLevelMonitor {
    /// (normalizedLevel 0~1, trackCount)
    typealias UpdateHandler = (_ level: Float, _ trackCount: Int) -> Void

    var connection: AVCaptureConnection? {
        didSet { latestTrackCount = 0 }
    }
    var isAuthorized: Bool = false
    private(set) var latestTrackCount: Int = 0

    private let onUpdate: UpdateHandler
    private var timer: Timer?
    private static let pollInterval: TimeInterval = 0.12

    init(onUpdate: @escaping UpdateHandler) {
        self.onUpdate = onUpdate
    }

    deinit {
        stop()
    }

    func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        guard isAuthorized else {
            latestTrackCount = 0
            onUpdate(0, 0)
            return
        }

        let channels = connection?.audioChannels ?? []
        let trackCount = channels.count
        latestTrackCount = trackCount
        let averageLevel = channels.map(\.averagePowerLevel).max() ?? -80
        let normalizedLevel = max(0, min(1, (averageLevel + 60) / 60))
        onUpdate(normalizedLevel, trackCount)
    }
}
