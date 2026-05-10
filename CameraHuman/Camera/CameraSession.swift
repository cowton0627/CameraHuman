import AVFoundation
import UIKit

/// 包裝 AVCaptureSession + 鏡頭管理 + 麥克風連線。VC 只透過 callback 拿到「設定好了 / 失敗了 / 鏡頭清單變了」的事件。
/// 注意：所有改動 capture session 的工作都跑在 `queue` 上，不要在 main thread 直接動 captureSession。
final class CameraSession {
    enum LensMode: CaseIterable {
        case ultraWide
        case wide
        case telephoto

        var deviceTypes: [AVCaptureDevice.DeviceType] {
            switch self {
            case .ultraWide: return [.builtInUltraWideCamera]
            case .wide: return [.builtInWideAngleCamera]
            case .telephoto: return [.builtInTelephotoCamera]
            }
        }

        var backCameraTitle: String {
            switch self {
            case .ultraWide: return "0.5x"
            case .wide: return "1x"
            case .telephoto: return "3x"
            }
        }
    }

    struct LensOption {
        let mode: LensMode
        let device: AVCaptureDevice
        let title: String
    }

    enum ConfigureError: Error {
        case noPermission
        case noLens
    }

    // MARK: - Callbacks (main thread)
    var onConfigured: ((AVCaptureDevice, String) -> Void)?
    var onConfigureFailed: ((String) -> Void)?
    var onLensesChanged: (() -> Void)?

    // MARK: - Public read-only state
    let captureSession = AVCaptureSession()
    let movieOutput = AVCaptureMovieFileOutput()
    let queue = DispatchQueue(label: "com.camerahuman.capture-session")

    private(set) var availableLensOptions: [LensOption] = []
    private(set) var currentLensOption: LensOption?
    private(set) var currentPosition: AVCaptureDevice.Position
    private(set) var cameraAuthorized = false
    private(set) var audioAuthorized = false
    private(set) var audioMeterConnection: AVCaptureConnection?

    // MARK: - Internals
    private let settings: CameraSettingsStore
    private let audioDataOutput = AVCaptureAudioDataOutput()
    private var currentVideoInput: AVCaptureDeviceInput?
    private var currentAudioInput: AVCaptureDeviceInput?

    init(settings: CameraSettingsStore = .shared) {
        self.settings = settings
        self.currentPosition = settings.startupCamera.capturePosition
    }

    deinit {
        stop()
    }

    // MARK: - Authorization

    func requestAuthorizations(completion: @escaping () -> Void) {
        let group = DispatchGroup()
        var resolvedCamera = AVCaptureDevice.authorizationStatus(for: .video) == .authorized
        var resolvedAudio = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized

        if AVCaptureDevice.authorizationStatus(for: .video) == .notDetermined {
            group.enter()
            AVCaptureDevice.requestAccess(for: .video) { granted in
                resolvedCamera = granted
                group.leave()
            }
        }

        if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
            group.enter()
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                resolvedAudio = granted
                group.leave()
            }
        }

        group.notify(queue: .main) { [weak self] in
            guard let self else { return }
            self.cameraAuthorized = resolvedCamera
            self.audioAuthorized = resolvedAudio
            completion()
        }
    }

    // MARK: - Lens management

    func switchPosition() {
        currentPosition = currentPosition == .back ? .front : .back
        refreshLenses()
    }

    func resetPositionFromSettings() {
        currentPosition = settings.startupCamera.capturePosition
        refreshLenses()
    }

    func selectLens(at index: Int) {
        guard availableLensOptions.indices.contains(index) else { return }
        currentLensOption = availableLensOptions[index]
    }

    func refreshLenses() {
        let previouslySelectedMode = currentLensOption?.mode
        let resolvedOptions = currentPosition == .front ? frontLensOptions() : backLensOptions()

        var seenIDs = Set<String>()
        availableLensOptions = resolvedOptions.filter { option in
            seenIDs.insert(option.device.uniqueID).inserted
        }

        if let mode = previouslySelectedMode,
           let match = availableLensOptions.first(where: { $0.mode == mode }) {
            currentLensOption = match
        } else {
            currentLensOption = availableLensOptions.first
        }

        onLensesChanged?()
    }

    private func frontLensOptions() -> [LensOption] {
        let types: [AVCaptureDevice.DeviceType] = [.builtInTrueDepthCamera, .builtInWideAngleCamera]
        for type in types {
            if let device = AVCaptureDevice.default(type, for: .video, position: .front) {
                return [LensOption(mode: .wide, device: device, title: "FRONT")]
            }
        }
        return []
    }

    private func backLensOptions() -> [LensOption] {
        LensMode.allCases.compactMap { mode in
            for type in mode.deviceTypes {
                if let device = AVCaptureDevice.default(type, for: .video, position: .back) {
                    return LensOption(mode: mode, device: device, title: mode.backCameraTitle)
                }
            }
            return nil
        }
    }

    // MARK: - Session configuration

    func configure(interfaceOrientation: UIInterfaceOrientation?) {
        if availableLensOptions.isEmpty {
            refreshLenses()
        }

        guard cameraAuthorized else {
            onConfigureFailed?("沒有相機權限")
            return
        }

        guard let lensOption = currentLensOption else {
            onConfigureFailed?("目前方向沒有可用鏡頭")
            return
        }

        queue.async { [weak self] in
            guard let self else { return }

            do {
                let videoInput = try AVCaptureDeviceInput(device: lensOption.device)
                let audioDevice = self.audioAuthorized ? AVCaptureDevice.default(for: .audio) : nil
                let audioInput = try audioDevice.map { try AVCaptureDeviceInput(device: $0) }

                self.captureSession.beginConfiguration()

                let preferredPreset = self.settings.videoPreset.capturePreset
                self.captureSession.sessionPreset = self.captureSession.canSetSessionPreset(preferredPreset) ? preferredPreset : .high

                if let currentVideoInput = self.currentVideoInput {
                    self.captureSession.removeInput(currentVideoInput)
                }
                if self.captureSession.canAddInput(videoInput) {
                    self.captureSession.addInput(videoInput)
                    self.currentVideoInput = videoInput
                }

                if let currentAudioInput = self.currentAudioInput {
                    self.captureSession.removeInput(currentAudioInput)
                    self.currentAudioInput = nil
                }
                if let audioInput, self.captureSession.canAddInput(audioInput) {
                    self.captureSession.addInput(audioInput)
                    self.currentAudioInput = audioInput
                }

                if !self.captureSession.outputs.contains(where: { $0 === self.movieOutput }),
                   self.captureSession.canAddOutput(self.movieOutput) {
                    self.captureSession.addOutput(self.movieOutput)
                }

                if !self.captureSession.outputs.contains(where: { $0 === self.audioDataOutput }),
                   self.captureSession.canAddOutput(self.audioDataOutput) {
                    self.captureSession.addOutput(self.audioDataOutput)
                }

                self.audioDataOutput.connection(with: .audio)?.isEnabled = self.audioAuthorized

                if let videoConnection = self.movieOutput.connection(with: .video),
                   videoConnection.isVideoOrientationSupported,
                   let interfaceOrientation {
                    videoConnection.videoOrientation = AVCaptureVideoOrientation(interfaceOrientation)
                }

                self.captureSession.commitConfiguration()
                self.audioMeterConnection = self.audioDataOutput.connection(with: .audio)

                if !self.captureSession.isRunning {
                    self.captureSession.startRunning()
                }

                DispatchQueue.main.async {
                    self.onConfigured?(lensOption.device, lensOption.title)
                }
            } catch {
                DispatchQueue.main.async {
                    self.onConfigureFailed?(error.localizedDescription)
                }
            }
        }
    }

    func stop() {
        queue.async { [weak self] in
            guard let self, self.captureSession.isRunning else { return }
            self.captureSession.stopRunning()
        }
    }
}
