import AVFoundation
import AudioToolbox
import QuartzCore

/// 用 timer 輪詢 `AVCaptureConnection` 的 audio channels，把平均音量正規化成 0~1，回 callback 給 UI。
/// 不持有 capture session，只持有當前要讀的 connection（可隨時換）。
final class AudioLevelMonitor: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate {
    /// (normalizedLevel 0~1, trackCount)
    typealias UpdateHandler = (_ level: Float, _ trackCount: Int) -> Void

    var isAuthorized: Bool = false
    private(set) var latestTrackCount: Int = 0
    let sampleQueue = DispatchQueue(label: "com.camerahuman.audio-meter")

    private let onUpdate: UpdateHandler
    private var lastUpdateTime: CFTimeInterval = 0
    private static let updateInterval: CFTimeInterval = 0.10

    init(onUpdate: @escaping UpdateHandler) {
        self.onUpdate = onUpdate
        super.init()
    }

    deinit {
        stop()
    }

    func start() {
        // 音量由 captureOutput(_:didOutput:from:) 的真實 PCM sample 驅動。
    }

    func stop() {
        latestTrackCount = 0
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard isAuthorized else { return }
        let now = CACurrentMediaTime()
        guard now - lastUpdateTime >= Self.updateInterval else { return }
        lastUpdateTime = now

        guard let format = CMSampleBufferGetFormatDescription(sampleBuffer),
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(format)?.pointee else { return }

        var bufferListSize = 0
        var blockBuffer: CMBlockBuffer?
        CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: &bufferListSize,
            bufferListOut: nil,
            bufferListSize: 0,
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: 0,
            blockBufferOut: &blockBuffer
        )
        guard bufferListSize > 0 else { return }
        let rawBufferList = UnsafeMutableRawPointer.allocate(
            byteCount: bufferListSize,
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { rawBufferList.deallocate() }
        let bufferList = rawBufferList.bindMemory(to: AudioBufferList.self, capacity: 1)
        let status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: nil,
            bufferListOut: bufferList,
            bufferListSize: bufferListSize,
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: 0,
            blockBufferOut: &blockBuffer
        )
        guard status == noErr else { return }

        let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
        var sumSquares: Double = 0
        var sampleCount = 0
        for buffer in buffers {
            guard let data = buffer.mData else { continue }
            if (asbd.mFormatFlags & kAudioFormatFlagIsFloat) != 0, asbd.mBitsPerChannel == 32 {
                let samples = data.bindMemory(to: Float.self, capacity: Int(buffer.mDataByteSize) / 4)
                let count = Int(buffer.mDataByteSize) / 4
                for index in 0..<count { sumSquares += Double(samples[index] * samples[index]) }
                sampleCount += count
            } else if asbd.mBitsPerChannel == 16 {
                let samples = data.bindMemory(to: Int16.self, capacity: Int(buffer.mDataByteSize) / 2)
                let count = Int(buffer.mDataByteSize) / 2
                for index in 0..<count {
                    let value = Double(samples[index]) / Double(Int16.max)
                    sumSquares += value * value
                }
                sampleCount += count
            }
        }
        guard sampleCount > 0 else { return }
        let rms = sqrt(sumSquares / Double(sampleCount))
        let decibels = max(-60, 20 * log10(max(rms, 0.000_001)))
        let normalized = Float((decibels + 60) / 60)
        let trackCount = max(1, Int(asbd.mChannelsPerFrame))
        latestTrackCount = trackCount
        DispatchQueue.main.async { [weak self] in
            self?.onUpdate(normalized, trackCount)
        }
    }
}
