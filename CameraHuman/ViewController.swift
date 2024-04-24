//
//  ViewController.swift
//  CameraHuman
//
//  Created by Chun-Li Cheng on 2024/3/13.
//

import UIKit
import AVFoundation

class ViewController: UIViewController {
    
    @IBOutlet weak var checkButton: UIButton!
    var captureSession = AVCaptureSession()
    var videoPreviewLayer: AVCaptureVideoPreviewLayer?
    
    private let audioOutput = AVCaptureAudioDataOutput()
    
    var isShow: Bool = false
    let captureBtnTag = 101

    var soundLevelBar: UIView!
//    var soundLevelBarHeightConstraint: NSLayoutConstraint?
        
    @IBOutlet weak var captureBtn: UIButton!
    @IBOutlet weak var frameView: UIView!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        print("Hello World!")
        captureBtn.tag = captureBtnTag
        
        // Initial height of 1
        soundLevelBar = UIView(frame: CGRect(x: 0, y: 0, width: 50, height: 100))
        soundLevelBar.backgroundColor = .green // Or any color you prefer
        
        frameView.addSubview(soundLevelBar)
        soundLevelBar.center = frameView.center
        
//        soundLevelBar.center = view.center // Position it as needed
//        view.addSubview(soundLevelBar)
        
        soundLevelBar.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            soundLevelBar.leadingAnchor.constraint(equalTo: frameView.leadingAnchor,
                                                   constant: 44),
            soundLevelBar.bottomAnchor.constraint(equalTo: frameView.bottomAnchor,
                                                  constant: -44),
            soundLevelBar.widthAnchor.constraint(equalToConstant: 50), // Fixed width of 50 points
            soundLevelBar.heightAnchor.constraint(equalToConstant: 100) // Initial height of 100
        ])
//        soundLevelBar.isHidden = true
        
//        soundLevelBarHeightConstraint = soundLevelBar.heightAnchor.constraint(equalToConstant: 100)
//        soundLevelBarHeightConstraint?.isActive = true
    }

    @IBAction func checkButtonTapped(_ sender: UIButton) {
        // 定義鏡頭類型的陣列，包含前置和後置鏡頭
        let deviceTypes: [AVCaptureDevice.DeviceType] = [.builtInWideAngleCamera,
                                                         .builtInTelephotoCamera,
                                                         .builtInUltraWideCamera,
                                                         .builtInDualCamera,
                                                         .builtInTrueDepthCamera]
            
        // 設置查詢條件，包括鏡頭類型和位置（前置或後置）
        let discoverySession = AVCaptureDevice.DiscoverySession(deviceTypes: deviceTypes,
                                                                mediaType: .video,
                                                                position: .unspecified)

        // 獲取滿足條件的設備數量
        let devices = discoverySession.devices
        let frontCameras = devices.filter { $0.position == .front }.count
        let backCameras = devices.filter { $0.position == .back }.count
        
        
        for device in devices {
            do {
                try device.lockForConfiguration()
                
                let positionString = device.position == .front ? "前置" : "後置"
                let lensAperture = device.lensAperture
                let activeFormatDescription = device.activeFormat.formatDescription
                let maxIso = device.activeFormat.maxISO
                let minIso = device.activeFormat.minISO
                let maxExposureDuration = device.activeFormat.maxExposureDuration
                let minExposureDuration = device.activeFormat.minExposureDuration
                
//                let lensPosition = device.lensPosition
//                let videoMaxZoomFactor = device.activeFormat.videoMaxZoomFactor
                
//            ISO范围: \(minIso) - \(maxIso)
//            曝光时长范围: \(CMTimeGetSeconds(minExposureDuration)) - \(CMTimeGetSeconds(maxExposureDuration)) 秒

                print("""
                      \(positionString)鏡頭, 类型: \(device.deviceType.rawValue)
                      光圈: \(lensAperture)
                      
                      \(positionString),
                      \(lensAperture)
                      """)
                
                
                //            let focalLength = device.lensfocalLength
                //            print("\(positionString)鏡頭，類型：\(device.deviceType.rawValue)，焦距：\(focalLength)mm")
                
                device.unlockForConfiguration()

            } catch {
                print("无法锁定设备配置: \(error)")
            }
            
            // 輸出前置和後置鏡頭的數量
//            print("前置鏡頭數量: \(frontCameras), 後置鏡頭數量: \(backCameras)")
        }
        
        
    }
    
    @IBAction func captureBtnTapped(_ sender: UIButton) {
//        let detector = SoundDetector()
//        detector.startListening()
//        detector.captureOutput(<#T##output: AVCaptureOutput##AVCaptureOutput#>,
//                               didOutput: <#T##CMSampleBuffer#>,
//                               from: <#T##AVCaptureConnection#>)
//        detector.startAudioCapture()
        
        
        // 設置 AVCaptureDevice 來獲取鏡頭
//        guard let captureDevice = AVCaptureDevice.default(for: .video) else { return }
        
        // 設置 AVCaptureDevice 來獲取麥克風
        guard let captureDevice = AVCaptureDevice.default(for: .audio) else { return }
        
//        guard let captureDevice = AVCaptureDevice.default(for: .text) else { return }
//        guard let captureDevice = AVCaptureDevice.default(for: .closedCaption) else { return }
//        guard let captureDevice = AVCaptureDevice.default(for: .subtitle) else { return }
//        guard let captureDevice = AVCaptureDevice.default(for: .timecode) else { return }
//        guard let captureDevice = AVCaptureDevice.default(for: .metadata) else { return }
//        guard let captureDevice = AVCaptureDevice.default(for: .muxed) else { return }
//        guard let captureDevice = AVCaptureDevice.default(for: .haptic) else { return }
        guard !isShow else { return }
        
        do {
            // 將鏡頭設備加入輸入設備中
            // 將麥克風設備加入輸入設備中
            let input = try AVCaptureDeviceInput(device: captureDevice)
            
//            captureSession.addInput(input)
            // Only add input if there are no inputs
            if captureSession.inputs.isEmpty { captureSession.addInput(input) }
            
            
            // MARK: - Video Preview Layer
            // 設置 AVCaptureVideoPreviewLayer 以顯示鏡頭捕捉到的畫面
//            setupVideoPreviewLayer()
            

//            videoPreviewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
//            videoPreviewLayer?.videoGravity = .resizeAspectFill
//            videoPreviewLayer?.frame = view.layer.bounds
//            view.layer.addSublayer(videoPreviewLayer!)

            
            // 開始捕捉畫面
            /*
                -[AVCaptureSession startRunning] should be called from background thread.
                Calling it on the main thread can lead to UI unresponsiveness
             */
//            captureSession.startRunning()
            
            // Similarly, add output if not already added
            if captureSession.outputs.isEmpty {
                captureSession.addOutput(audioOutput)
                audioOutput.setSampleBufferDelegate(self, 
                                                    queue: DispatchQueue(label: "audioQueue"))
            }
            
//            self.audioOutput.setSampleBufferDelegate(self,
//                                                     queue: DispatchQueue(label: "audioQueue"))

            DispatchQueue.global(qos: .userInitiated).async {
                self.captureSession.startRunning()
            }
            
            isShow = true
            sender.isEnabled = false // Disable the button to prevent multiple taps
            
        } catch {
            print(error)
            return
        }
    }
    
    
    @IBAction func stopCaptureTapped(_ sender: UIButton) {
        if isShow {
            captureSession.stopRunning()
            
            captureSession.inputs.forEach { input in
                captureSession.removeInput(input)
            }
            
            // MARK: - Viedeo Preview Layer
//            videoPreviewLayer?.removeFromSuperlayer()
            isShow = false
            
            // Re-enable the capture button
            if let captureButton = self.view.viewWithTag(captureBtnTag) as? UIButton {
                captureButton.isEnabled = true
            }
            
            print("Stop Capture!")
        }
    }
    
    private func setupVideoPreviewLayer() {
        videoPreviewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        videoPreviewLayer?.videoGravity = .resizeAspectFill
        videoPreviewLayer?.frame = frameView.layer.bounds
        DispatchQueue.main.async {
            self.frameView.layer.addSublayer(self.videoPreviewLayer!)
        }
    }
    
    
    
    
}

extension ViewController: AVCaptureAudioDataOutputSampleBufferDelegate {
    

    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        // Here you could analyze the audio levels, frequencies, etc.
        // This is a placeholder for where you'd implement your analysis.
        var audioLevel = getAudioLevel(from: sampleBuffer)
        
        let maxHeight: CGFloat = 300 // Maximum height of the bar
        let minHeight: CGFloat = 1 // Minimum height of the bar
        
        // Map the audioLevel to a height value (example calculation, adjust as needed)
        // This is a simple mapping; adjust based on your audioLevel range
        var newHeight = (CGFloat(audioLevel) + 50) * (maxHeight / 100)
        // Clamp the value to be within minHeight and maxHeight
        newHeight = min(max(newHeight, minHeight), maxHeight)
        
        
        DispatchQueue.main.async {
            self.soundLevelBar.transform =
            CGAffineTransform.identity
                .translatedBy(x: 0, y: -newHeight/2)
            self.soundLevelBar.transform =
            CGAffineTransform.identity
                .scaledBy(x: 1, y: newHeight / self.soundLevelBar.frame.height)
            

            
//            self.soundLevelBarHeightConstraint?.constant = newHeight
//            UIView.animate(withDuration: 0.1) {
//                self.view.layoutIfNeeded()
//            }

//            UIView.animate(withDuration: 0.1) {
//                self.soundLevelBar.frame.size.height = newHeight
//                self.soundLevelBar.center = CGPoint(x: self.soundLevelBar.center.x,
//                                                    y: self.soundLevelBar.frame.size.height - newHeight / 2)
//                self.soundLevelBar.center = CGPoint(x: self.view.center.x, y: self.view.frame.size.height - newHeight / 2) // Adjust position if needed
//            }
        }
        // Do something with the audio level or other analysis results
    }
    
    func getAudioLevel(from sampleBuffer: CMSampleBuffer) -> Float {
        // This function is a placeholder. Implement your own logic to analyze the audio level.
        // Example fixed value, replace with actual audio analysis
//        return 1.0
        guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else {
            return 0.0
        }

        var length = 0
        var totalBytes = 0
        var data: UnsafeMutablePointer<Int8>?
        
        CMBlockBufferGetDataPointer(blockBuffer, 
                                    atOffset: 0,
                                    lengthAtOffsetOut: &length,
                                    totalLengthOut: &totalBytes,
                                    dataPointerOut: &data)
        
        guard let samples = data else { return 0.0 }
        
        let dataBuffer = UnsafeBufferPointer(start: data, count: totalBytes)
        
        var sum: Float = 0
        
        // Assuming 16-bit samples, iterate over the buffer to compute RMS
        // Assuming 8-bit samples, iterate over the buffer to compute RMS (stride by: 1)
        for i in stride(from: 0, to: totalBytes, by: 2) {
            // Assuming the samples are unsigned 8-bit values
//            let sample = UInt8(bitPattern: dataBuffer.baseAddress!.advanced(by: i).pointee) // Convert to UInt8
//            let signedSample = Float(sample) - 128.0 // Convert to signed float ranging from -128 to 127
//            sum += signedSample * signedSample
            
            let sample = dataBuffer.baseAddress!.advanced(by: i).withMemoryRebound(to: Int16.self, capacity: 1) { $0.pointee }
            sum += Float(sample) * Float(sample)
        }
        
        let rms = sqrt(sum / Float(totalBytes / 2)) // Divide by 2 to account for 16-bit samples
//        let rms = sqrt(sum / Float(totalBytes)) // Use totalBytes directly since each sample is 1 byte
        
        let level = 20 * log10(rms)
            
//        if level > 0 { print(level) }
        
        return level.isFinite ? level : 0.0
        
//        for i in 0..<length / MemoryLayout<Int16>.size {
//            let sample = Float(Int16(bitPattern: CFSwapInt16BigToHost(UInt16(bitPattern: samples.advanced(by: i * MemoryLayout<Int16>.size).assumingMemoryBound(to: Int16.self).pointee))))
//            sum += sample * sample
//        }
//        let rms = sqrt(sum / Float(length / MemoryLayout<Int16>.size))
//        let level = 20 * log10(rms)
//        return level
    }
    
    
    
}

