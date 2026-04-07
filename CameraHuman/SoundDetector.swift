//
//  SoundDetector.swift
//  CameraHuman
//
//  Created by Chun-Li Cheng on 2024/3/13.
//

import Foundation
import AVFoundation

final class SoundDetector {
    struct LevelSnapshot {
        let decibels: Float
        let normalizedLevel: Float
    }

    enum State {
        case idle
        case requestingPermission
        case running
        case permissionDenied
        case failed(String)
    }

    var onStateChange: ((State) -> Void)?
    var onLevelUpdate: ((LevelSnapshot) -> Void)?

    private let audioEngine = AVAudioEngine()
    private let engineQueue = DispatchQueue(label: "com.camerahuman.audio-engine")

    private var isRunning = false
    private var smoothedLevel: Float = 0

    func startMonitoring() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            startEngine()
        case .notDetermined:
            publish(state: .requestingPermission)
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                guard let self else { return }
                granted ? self.startEngine() : self.publish(state: .permissionDenied)
            }
        case .denied, .restricted:
            publish(state: .permissionDenied)
        @unknown default:
            publish(state: .failed("未知的麥克風權限狀態"))
        }
    }

    func stopMonitoring() {
        engineQueue.async { [weak self] in
            guard let self else { return }
            guard self.isRunning else {
                self.publish(state: .idle)
                return
            }

            self.audioEngine.inputNode.removeTap(onBus: 0)
            self.audioEngine.stop()
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)

            self.isRunning = false
            self.smoothedLevel = 0
            self.publish(level: LevelSnapshot(decibels: -80, normalizedLevel: 0))
            self.publish(state: .idle)
        }
    }

    private func startEngine() {
        engineQueue.async { [weak self] in
            guard let self else { return }
            guard !self.isRunning else {
                self.publish(state: .running)
                return
            }

            let session = AVAudioSession.sharedInstance()

            do {
                try session.setCategory(.record, mode: .measurement, options: [.duckOthers])
                try session.setActive(true, options: .notifyOthersOnDeactivation)

                let inputNode = self.audioEngine.inputNode
                let format = inputNode.inputFormat(forBus: 0)

                inputNode.removeTap(onBus: 0)
                inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
                    self?.handleAudioBuffer(buffer)
                }

                self.audioEngine.prepare()
                try self.audioEngine.start()

                self.isRunning = true
                self.publish(state: .running)
            } catch {
                self.audioEngine.inputNode.removeTap(onBus: 0)
                self.audioEngine.stop()
                try? session.setActive(false, options: .notifyOthersOnDeactivation)
                self.isRunning = false
                self.publish(state: .failed(error.localizedDescription))
            }
        }
    }

    private func handleAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData?.pointee else { return }

        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return }

        var sum: Float = 0
        for frame in 0..<frameLength {
            let sample = channelData[frame]
            sum += sample * sample
        }

        let rms = sqrt(sum / Float(frameLength))
        let decibels = max(20 * log10(max(rms, 0.000_01)), -80)
        let normalized = max(0, min(1, (decibels + 80) / 80))

        smoothedLevel = (smoothedLevel * 0.75) + (normalized * 0.25)
        publish(level: LevelSnapshot(decibels: decibels, normalizedLevel: smoothedLevel))
    }

    private func publish(state: State) {
        DispatchQueue.main.async {
            self.onStateChange?(state)
        }
    }

    private func publish(level: LevelSnapshot) {
        DispatchQueue.main.async {
            self.onLevelUpdate?(level)
        }
    }
}
