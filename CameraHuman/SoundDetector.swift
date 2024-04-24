//
//  SoundDetector.swift
//  CameraHuman
//
//  Created by Chun-Li Cheng on 2024/3/13.
//

import Foundation
import AVFoundation

class SoundDetector: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate {
    private var session = AVCaptureSession()
    private let audioOutput = AVCaptureAudioDataOutput()
    

    func startListening() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            setupSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                if granted {
                    self.setupSession()
                }
            }
        default:
            // Handle error or denial
            break
        }
    }

    private func setupSession() {
        DispatchQueue.global(qos: .userInitiated).async {
            guard let audioDevice = AVCaptureDevice.default(for: .audio),
                  let audioInput = try? AVCaptureDeviceInput(device: audioDevice) else {
                return
            }

            self.session.beginConfiguration()
            if self.session.canAddInput(audioInput) {
                self.session.addInput(audioInput)
            }
            if self.session.canAddOutput(self.audioOutput) {
                self.session.addOutput(self.audioOutput)
            }
            self.audioOutput.setSampleBufferDelegate(self, 
                                                     queue: DispatchQueue(label: "audioQueue"))
            self.session.commitConfiguration()
            self.session.startRunning()
        }
//        guard let audioDevice = AVCaptureDevice.default(for: .audio),
//              let audioInput = try? AVCaptureDeviceInput(device: audioDevice) else {
//            return
//        }
//        session.beginConfiguration()
//        if session.canAddInput(audioInput) {
//            session.addInput(audioInput)
//        }
//        if session.canAddOutput(audioOutput) {
//            session.addOutput(audioOutput)
//        }
//        audioOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "audioQueue"))
//        session.commitConfiguration()
//        session.startRunning()
    }

    // Function to start capturing audio
    func startAudioCapture() {
        let session = AVCaptureSession()
        self.session = session

        guard let audioDevice = AVCaptureDevice.default(for: .audio),
              let audioInput = try? AVCaptureDeviceInput(device: audioDevice) else {
            print("Unable to access the microphone.")
            return
        }

        if session.canAddInput(audioInput) {
            session.addInput(audioInput)
        }

        if session.canAddOutput(audioOutput) {
            session.addOutput(audioOutput)
            audioOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "audioQueue"))
        }

        DispatchQueue.global(qos: .userInitiated).async {
            session.startRunning()
        }
    }
    
    

    func stopAudioCapture() {
        session.stopRunning()
    }

    // Delegate method to analyze captured audio
    func captureOutput(_ output: AVCaptureOutput, 
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        // Here you could analyze the audio levels, frequencies, etc.
        // This is a placeholder for where you'd implement your analysis.
        var audioLevel = getAudioLevel(from: sampleBuffer)
        // Do something with the audio level or other analysis results
  
    }
    
    func getAudioLevel(from sampleBuffer: CMSampleBuffer) -> Float {
        // This function is a placeholder. Implement your own logic to analyze the audio level.
        return 1.0 // Example fixed value, replace with actual audio analysis
    }
}
