//
//  CameraViewController.swift
//  CameraHuman
//

import UIKit
import AVFoundation

final class CameraViewController: UIViewController, AVCaptureFileOutputRecordingDelegate {
    private let settings = CameraSettingsStore.shared

    private enum LensMode: CaseIterable {
        case ultraWide
        case wide
        case telephoto

        var deviceTypes: [AVCaptureDevice.DeviceType] {
            switch self {
            case .ultraWide:
                return [.builtInUltraWideCamera]
            case .wide:
                return [.builtInWideAngleCamera]
            case .telephoto:
                return [.builtInTelephotoCamera]
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

    private struct LensOption {
        let mode: LensMode
        let device: AVCaptureDevice
        let title: String
    }

    private enum RecordingState {
        case idle
        case starting
        case recording
        case stopping
    }

    private let captureSession = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "com.camerahuman.capture-session")

    private let movieOutput = AVCaptureMovieFileOutput()
    private let audioDataOutput = AVCaptureAudioDataOutput()

    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var currentVideoInput: AVCaptureDeviceInput?
    private var currentAudioInput: AVCaptureDeviceInput?
    private var audioMeterConnection: AVCaptureConnection?

    private var cameraAuthorized = false
    private var audioAuthorized = false
    private var currentPosition: AVCaptureDevice.Position = CameraSettingsStore.shared.startupCamera.capturePosition
    private var currentLensOption: LensOption?
    private var availableLensOptions: [LensOption] = []
    private var recordingState: RecordingState = .idle
    private var recordingStartDate: Date?
    private var recordingTimer: Timer?
    private var audioMeterTimer: Timer?
    private let previewContainerView = UIView()
    private let vignetteView = UIView()
    private let aspectMaskTopView = UIView()
    private let aspectMaskBottomView = UIView()
    private let aspectFrameView = UIView()
    private let aspectFrameLabel = UILabel()
    private var aspectMaskTopHeightConstraint: NSLayoutConstraint?
    private var aspectMaskBottomHeightConstraint: NSLayoutConstraint?

    private let topHUDView = UIStackView()
    private let primaryStatusStackView = UIStackView()
    private let technicalStatusStackView = UIStackView()
    private let topTitleLabel = UILabel()
    private let secondaryStatusLabel = UILabel()

    private let bottomHUDView = UIView()
    private let lensStackView = UIStackView()
    private let leftControlsStackView = UIStackView()
    private let bottomStatusLabel = UILabel()
    private let recordButton = UIButton(type: .system)
    private let switchCameraButton = UIButton(type: .system)
    private let inspectButton = UIButton(type: .system)
    private let audioMeterCardView = UIView()
    private let audioTitleLabel = UILabel()
    private let audioTrackLabel = UILabel()
    private let audioLevelLabel = UILabel()
    private let audioBarsStackView = UIStackView()
    private let toastLabel = UILabel()
    private var audioBarViews: [UIView] = []
    private var audioBarHeightConstraints: [NSLayoutConstraint] = []

    private let guideLines = [UIView(), UIView(), UIView(), UIView()]

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        NotificationCenter.default.addObserver(self, selector: #selector(cameraSettingsDidChange), name: .cameraSettingsDidChange, object: nil)
        configureUI()
        refreshLensOptions()
        configurePermissionsAndSession()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = previewContainerView.bounds
        updateAspectMaskLayout()
        updateGuideFrames()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        stopRecordingTimer()
        stopAudioMeterTimer()
        stopCameraSession()
    }

    @objc private func lensButtonTapped(_ sender: UIButton) {
        guard sender.tag >= 0, sender.tag < availableLensOptions.count else { return }
        currentLensOption = availableLensOptions[sender.tag]
        configureCaptureSession()
        updateLensButtons()
    }

    @objc private func switchCameraTapped(_ sender: UIButton) {
        guard recordingState == .idle else { return }
        currentPosition = currentPosition == .back ? .front : .back
        refreshLensOptions()
        configureCaptureSession()
    }

    @objc private func inspectTapped(_ sender: UIButton) {
        bottomStatusLabel.text = buildCameraReport()
    }

    @objc private func recordButtonTapped(_ sender: UIButton) {
        switch recordingState {
        case .idle:
            startRecording()
        case .recording:
            stopRecording()
        case .starting, .stopping:
            break
        }
    }

    @objc private func cameraSettingsDidChange() {
        applyGuideVisibility()
        updateAspectMaskLayout()

        guard recordingState == .idle else {
            updatePrimaryHUD()
            bottomStatusLabel.text = "部份設定會在結束目前錄影後套用。"
            return
        }

        currentPosition = settings.startupCamera.capturePosition
        refreshLensOptions()
        configureCaptureSession()
    }

    @objc private func audioMeterTimerFired() {
        guard audioAuthorized else {
            updateAudioMeter(level: 0, trackCount: 0)
            return
        }

        let channels = audioMeterConnection?.audioChannels ?? []
        let trackCount = channels.count
        let averageLevel = channels.map(\.averagePowerLevel).max() ?? -80
        let normalizedLevel = max(0, min(1, (averageLevel + 60) / 60))
        updateAudioMeter(level: normalizedLevel, trackCount: trackCount)
    }

    @objc private func recordingTimerFired() {
        guard let recordingStartDate else {
            updatePrimaryHUD()
            return
        }

        let elapsed = Int(Date().timeIntervalSince(recordingStartDate))
        let minutes = elapsed / 60
        let seconds = elapsed % 60
        updatePrimaryHUD(timerText: String(format: "REC %02d:%02d", minutes, seconds))
    }

    private func configureUI() {
        configurePreview()
        configureTopHUD()
        configureBottomHUD()
        configureToast()
        configureGuides()
        applyGuideVisibility()
        updatePrimaryHUD()
        replaceTechnicalChips(with: [
            "LENS --",
            "FPS --",
            "SHUTTER --",
            "IRIS FIXED",
            "ISO --",
            "WB --"
        ])
        updateAudioMeter(level: 0, trackCount: 0)
        updateRecordButtonAppearance()
    }

    private func configurePreview() {
        previewContainerView.translatesAutoresizingMaskIntoConstraints = false
        previewContainerView.backgroundColor = .black
        previewContainerView.clipsToBounds = true

        vignetteView.translatesAutoresizingMaskIntoConstraints = false
        vignetteView.backgroundColor = UIColor.black.withAlphaComponent(0.18)
        aspectMaskTopView.translatesAutoresizingMaskIntoConstraints = false
        aspectMaskTopView.backgroundColor = UIColor.black.withAlphaComponent(0.46)
        aspectMaskBottomView.translatesAutoresizingMaskIntoConstraints = false
        aspectMaskBottomView.backgroundColor = UIColor.black.withAlphaComponent(0.46)
        aspectFrameView.translatesAutoresizingMaskIntoConstraints = false
        aspectFrameView.layer.borderWidth = 1
        aspectFrameView.layer.borderColor = UIColor.white.withAlphaComponent(0.42).cgColor
        aspectFrameView.isUserInteractionEnabled = false
        aspectFrameLabel.translatesAutoresizingMaskIntoConstraints = false
        aspectFrameLabel.font = .monospacedSystemFont(ofSize: 11, weight: .semibold)
        aspectFrameLabel.textColor = UIColor.white.withAlphaComponent(0.88)

        view.addSubview(previewContainerView)
        previewContainerView.addSubview(vignetteView)
        previewContainerView.addSubview(aspectMaskTopView)
        previewContainerView.addSubview(aspectMaskBottomView)
        previewContainerView.addSubview(aspectFrameView)
        aspectFrameView.addSubview(aspectFrameLabel)

        aspectMaskTopHeightConstraint = aspectMaskTopView.heightAnchor.constraint(equalToConstant: 0)
        aspectMaskBottomHeightConstraint = aspectMaskBottomView.heightAnchor.constraint(equalToConstant: 0)

        NSLayoutConstraint.activate([
            previewContainerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            previewContainerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            previewContainerView.topAnchor.constraint(equalTo: view.topAnchor),
            previewContainerView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            vignetteView.leadingAnchor.constraint(equalTo: previewContainerView.leadingAnchor),
            vignetteView.trailingAnchor.constraint(equalTo: previewContainerView.trailingAnchor),
            vignetteView.topAnchor.constraint(equalTo: previewContainerView.topAnchor),
            vignetteView.bottomAnchor.constraint(equalTo: previewContainerView.bottomAnchor),

            aspectMaskTopView.leadingAnchor.constraint(equalTo: previewContainerView.leadingAnchor),
            aspectMaskTopView.trailingAnchor.constraint(equalTo: previewContainerView.trailingAnchor),
            aspectMaskTopView.topAnchor.constraint(equalTo: previewContainerView.topAnchor),
            aspectMaskTopHeightConstraint!,

            aspectMaskBottomView.leadingAnchor.constraint(equalTo: previewContainerView.leadingAnchor),
            aspectMaskBottomView.trailingAnchor.constraint(equalTo: previewContainerView.trailingAnchor),
            aspectMaskBottomView.bottomAnchor.constraint(equalTo: previewContainerView.bottomAnchor),
            aspectMaskBottomHeightConstraint!,

            aspectFrameView.leadingAnchor.constraint(equalTo: previewContainerView.leadingAnchor),
            aspectFrameView.trailingAnchor.constraint(equalTo: previewContainerView.trailingAnchor),
            aspectFrameView.topAnchor.constraint(equalTo: aspectMaskTopView.bottomAnchor),
            aspectFrameView.bottomAnchor.constraint(equalTo: aspectMaskBottomView.topAnchor),

            aspectFrameLabel.leadingAnchor.constraint(equalTo: aspectFrameView.leadingAnchor, constant: 10),
            aspectFrameLabel.topAnchor.constraint(equalTo: aspectFrameView.topAnchor, constant: 10)
        ])
    }

    private func configureTopHUD() {
        topHUDView.translatesAutoresizingMaskIntoConstraints = false
        topHUDView.axis = .vertical
        topHUDView.spacing = 8
        topHUDView.layoutMargins = UIEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        topHUDView.isLayoutMarginsRelativeArrangement = true
        topHUDView.backgroundColor = UIColor.black.withAlphaComponent(0.62)
        topHUDView.layer.cornerRadius = 18

        topTitleLabel.font = .monospacedSystemFont(ofSize: 12, weight: .semibold)
        topTitleLabel.textColor = .white
        topTitleLabel.text = "CAMERA"

        primaryStatusStackView.axis = .horizontal
        primaryStatusStackView.spacing = 6
        primaryStatusStackView.distribution = .fillEqually

        technicalStatusStackView.axis = .vertical
        technicalStatusStackView.spacing = 6
        technicalStatusStackView.distribution = .fillEqually

        secondaryStatusLabel.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
        secondaryStatusLabel.textColor = UIColor.white.withAlphaComponent(0.84)
        secondaryStatusLabel.numberOfLines = 1
        secondaryStatusLabel.text = "等待相機與麥克風權限"

        topHUDView.addArrangedSubview(topTitleLabel)
        topHUDView.addArrangedSubview(primaryStatusStackView)
        topHUDView.addArrangedSubview(technicalStatusStackView)
        topHUDView.addArrangedSubview(secondaryStatusLabel)
        view.addSubview(topHUDView)

        NSLayoutConstraint.activate([
            topHUDView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 14),
            topHUDView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -14),
            topHUDView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12)
        ])
    }

    private func configureBottomHUD() {
        bottomHUDView.translatesAutoresizingMaskIntoConstraints = false
        bottomHUDView.backgroundColor = UIColor.black.withAlphaComponent(0.62)
        bottomHUDView.layer.cornerRadius = 26

        lensStackView.translatesAutoresizingMaskIntoConstraints = false
        lensStackView.axis = .horizontal
        lensStackView.spacing = 10
        lensStackView.distribution = .fillEqually

        bottomStatusLabel.translatesAutoresizingMaskIntoConstraints = false
        bottomStatusLabel.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
        bottomStatusLabel.textColor = UIColor.white.withAlphaComponent(0.84)
        bottomStatusLabel.numberOfLines = 1
        bottomStatusLabel.text = "Camera + Mic capture session"

        recordButton.translatesAutoresizingMaskIntoConstraints = false
        recordButton.layer.cornerRadius = 30
        recordButton.layer.borderWidth = 5
        recordButton.layer.borderColor = UIColor.white.withAlphaComponent(0.92).cgColor
        recordButton.backgroundColor = .systemRed
        recordButton.addTarget(self, action: #selector(recordButtonTapped(_:)), for: .touchUpInside)

        leftControlsStackView.translatesAutoresizingMaskIntoConstraints = false
        leftControlsStackView.axis = .horizontal
        leftControlsStackView.spacing = 8
        leftControlsStackView.alignment = .center

        switchCameraButton.translatesAutoresizingMaskIntoConstraints = false
        styleHUDButton(switchCameraButton, title: "切換")
        switchCameraButton.addTarget(self, action: #selector(switchCameraTapped(_:)), for: .touchUpInside)

        inspectButton.translatesAutoresizingMaskIntoConstraints = false
        styleHUDButton(inspectButton, title: "資訊")
        inspectButton.addTarget(self, action: #selector(inspectTapped(_:)), for: .touchUpInside)

        audioMeterCardView.translatesAutoresizingMaskIntoConstraints = false
        audioMeterCardView.backgroundColor = UIColor.white.withAlphaComponent(0.10)
        audioMeterCardView.layer.cornerRadius = 14

        audioTitleLabel.translatesAutoresizingMaskIntoConstraints = false
        audioTitleLabel.font = .monospacedSystemFont(ofSize: 9, weight: .semibold)
        audioTitleLabel.textColor = UIColor.systemGreen
        audioTitleLabel.text = "MIC"

        audioTrackLabel.translatesAutoresizingMaskIntoConstraints = false
        audioTrackLabel.font = .monospacedSystemFont(ofSize: 9, weight: .medium)
        audioTrackLabel.textColor = .white

        audioLevelLabel.translatesAutoresizingMaskIntoConstraints = false
        audioLevelLabel.font = .monospacedDigitSystemFont(ofSize: 14, weight: .semibold)
        audioLevelLabel.textColor = .white

        audioBarsStackView.translatesAutoresizingMaskIntoConstraints = false
        audioBarsStackView.axis = .horizontal
        audioBarsStackView.alignment = .bottom
        audioBarsStackView.distribution = .fillEqually
        audioBarsStackView.spacing = 4

        for _ in 0..<4 {
            let barContainer = UIView()
            barContainer.backgroundColor = .clear

            let bar = UIView()
            bar.translatesAutoresizingMaskIntoConstraints = false
            bar.backgroundColor = UIColor.systemGreen
            bar.layer.cornerRadius = 4
            barContainer.addSubview(bar)

            let heightConstraint = bar.heightAnchor.constraint(equalToConstant: 8)
            audioBarHeightConstraints.append(heightConstraint)
            audioBarViews.append(bar)
            audioBarsStackView.addArrangedSubview(barContainer)

            NSLayoutConstraint.activate([
                bar.leadingAnchor.constraint(equalTo: barContainer.leadingAnchor),
                bar.trailingAnchor.constraint(equalTo: barContainer.trailingAnchor),
                bar.bottomAnchor.constraint(equalTo: barContainer.bottomAnchor),
                heightConstraint
            ])
        }

        leftControlsStackView.addArrangedSubview(switchCameraButton)
        leftControlsStackView.addArrangedSubview(inspectButton)
        audioMeterCardView.addSubview(audioTitleLabel)
        audioMeterCardView.addSubview(audioTrackLabel)
        audioMeterCardView.addSubview(audioLevelLabel)
        audioMeterCardView.addSubview(audioBarsStackView)

        bottomHUDView.addSubview(lensStackView)
        bottomHUDView.addSubview(bottomStatusLabel)
        bottomHUDView.addSubview(recordButton)
        bottomHUDView.addSubview(leftControlsStackView)
        bottomHUDView.addSubview(audioMeterCardView)
        view.addSubview(bottomHUDView)

        NSLayoutConstraint.activate([
            bottomHUDView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 14),
            bottomHUDView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -14),
            bottomHUDView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),

            lensStackView.leadingAnchor.constraint(equalTo: bottomHUDView.leadingAnchor, constant: 14),
            lensStackView.trailingAnchor.constraint(equalTo: bottomHUDView.trailingAnchor, constant: -14),
            lensStackView.topAnchor.constraint(equalTo: bottomHUDView.topAnchor, constant: 14),
            lensStackView.heightAnchor.constraint(equalToConstant: 42),

            bottomStatusLabel.leadingAnchor.constraint(equalTo: lensStackView.leadingAnchor),
            bottomStatusLabel.trailingAnchor.constraint(equalTo: lensStackView.trailingAnchor),
            bottomStatusLabel.topAnchor.constraint(equalTo: lensStackView.bottomAnchor, constant: 12),

            recordButton.centerXAnchor.constraint(equalTo: bottomHUDView.centerXAnchor),
            recordButton.topAnchor.constraint(equalTo: bottomStatusLabel.bottomAnchor, constant: 16),
            recordButton.widthAnchor.constraint(equalToConstant: 60),
            recordButton.heightAnchor.constraint(equalToConstant: 60),
            recordButton.bottomAnchor.constraint(equalTo: bottomHUDView.bottomAnchor, constant: -16),

            leftControlsStackView.leadingAnchor.constraint(equalTo: lensStackView.leadingAnchor),
            leftControlsStackView.centerYAnchor.constraint(equalTo: recordButton.centerYAnchor),
            leftControlsStackView.trailingAnchor.constraint(lessThanOrEqualTo: recordButton.leadingAnchor, constant: -12),

            audioMeterCardView.trailingAnchor.constraint(equalTo: lensStackView.trailingAnchor),
            audioMeterCardView.centerYAnchor.constraint(equalTo: recordButton.centerYAnchor),
            audioMeterCardView.leadingAnchor.constraint(greaterThanOrEqualTo: recordButton.trailingAnchor, constant: 12),
            audioMeterCardView.widthAnchor.constraint(equalToConstant: 108),
            audioMeterCardView.heightAnchor.constraint(equalToConstant: 84),

            audioTitleLabel.leadingAnchor.constraint(equalTo: audioMeterCardView.leadingAnchor, constant: 10),
            audioTitleLabel.topAnchor.constraint(equalTo: audioMeterCardView.topAnchor, constant: 10),
            audioTrackLabel.leadingAnchor.constraint(equalTo: audioTitleLabel.leadingAnchor),
            audioTrackLabel.topAnchor.constraint(equalTo: audioTitleLabel.bottomAnchor, constant: 3),
            audioLevelLabel.leadingAnchor.constraint(equalTo: audioTitleLabel.leadingAnchor),
            audioLevelLabel.topAnchor.constraint(equalTo: audioTrackLabel.bottomAnchor, constant: 3),
            audioBarsStackView.leadingAnchor.constraint(equalTo: audioTitleLabel.leadingAnchor),
            audioBarsStackView.trailingAnchor.constraint(equalTo: audioMeterCardView.trailingAnchor, constant: -10),
            audioBarsStackView.bottomAnchor.constraint(equalTo: audioMeterCardView.bottomAnchor, constant: -10),
            audioBarsStackView.heightAnchor.constraint(equalToConstant: 22)
        ])
    }

    private func configureGuides() {
        for line in guideLines {
            line.backgroundColor = UIColor.white.withAlphaComponent(0.18)
            view.addSubview(line)
        }
    }

    private func configureToast() {
        toastLabel.translatesAutoresizingMaskIntoConstraints = false
        toastLabel.font = .monospacedSystemFont(ofSize: 11, weight: .semibold)
        toastLabel.textColor = .white
        toastLabel.textAlignment = .center
        toastLabel.numberOfLines = 2
        toastLabel.backgroundColor = UIColor.black.withAlphaComponent(0.78)
        toastLabel.layer.cornerRadius = 14
        toastLabel.clipsToBounds = true
        toastLabel.alpha = 0

        view.addSubview(toastLabel)

        NSLayoutConstraint.activate([
            toastLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            toastLabel.bottomAnchor.constraint(equalTo: bottomHUDView.topAnchor, constant: -14),
            toastLabel.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 28),
            toastLabel.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -28)
        ])
    }

    private func updateGuideFrames() {
        let bounds = aspectFrameView.frame
        guard bounds.width > 0, bounds.height > 0 else { return }

        guideLines[0].frame = CGRect(x: bounds.minX + (bounds.width / 3), y: bounds.minY, width: 1, height: bounds.height)
        guideLines[1].frame = CGRect(x: bounds.minX + (bounds.width * 2 / 3), y: bounds.minY, width: 1, height: bounds.height)
        guideLines[2].frame = CGRect(x: bounds.minX, y: bounds.minY + (bounds.height / 3), width: bounds.width, height: 1)
        guideLines[3].frame = CGRect(x: bounds.minX, y: bounds.minY + (bounds.height * 2 / 3), width: bounds.width, height: 1)
    }

    private func configurePermissionsAndSession() {
        let group = DispatchGroup()
        var resolvedCameraAuthorized = AVCaptureDevice.authorizationStatus(for: .video) == .authorized
        var resolvedAudioAuthorized = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized

        if AVCaptureDevice.authorizationStatus(for: .video) == .notDetermined {
            group.enter()
            AVCaptureDevice.requestAccess(for: .video) { granted in
                resolvedCameraAuthorized = granted
                group.leave()
            }
        }

        if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
            group.enter()
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                resolvedAudioAuthorized = granted
                group.leave()
            }
        }

        group.notify(queue: .main) { [weak self] in
            guard let self else { return }
            self.cameraAuthorized = resolvedCameraAuthorized
            self.audioAuthorized = resolvedAudioAuthorized
            self.updateRecordButtonAppearance()
            self.configureCaptureSession()
        }
    }

    private func configureCaptureSession() {
        refreshLensOptionsIfNeeded()

        guard cameraAuthorized else {
            secondaryStatusLabel.text = "沒有相機權限"
            bottomStatusLabel.text = "請到設定開啟 CameraHuman 的相機權限。"
            return
        }

        guard let lensOption = currentLensOption else {
            secondaryStatusLabel.text = "目前方向沒有可用鏡頭"
            bottomStatusLabel.text = "找不到可用相機裝置。"
            return
        }

        let interfaceOrientation = view.window?.windowScene?.interfaceOrientation

        sessionQueue.async { [weak self] in
            guard let self else { return }

            do {
                let videoInput = try AVCaptureDeviceInput(device: lensOption.device)
                let audioDevice = self.audioAuthorized ? AVCaptureDevice.default(for: .audio) : nil
                let audioInput = try audioDevice.map { try AVCaptureDeviceInput(device: $0) }

                self.captureSession.beginConfiguration()

                let preferredPreset = self.settings.videoPreset.capturePreset
                if self.captureSession.canSetSessionPreset(preferredPreset) {
                    self.captureSession.sessionPreset = preferredPreset
                } else {
                    self.captureSession.sessionPreset = .high
                }

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

                if !self.captureSession.outputs.contains(where: { $0 === self.movieOutput }), self.captureSession.canAddOutput(self.movieOutput) {
                    self.captureSession.addOutput(self.movieOutput)
                }

                if !self.captureSession.outputs.contains(where: { $0 === self.audioDataOutput }), self.captureSession.canAddOutput(self.audioDataOutput) {
                    self.captureSession.addOutput(self.audioDataOutput)
                    self.audioDataOutput.connection(with: .audio)?.isEnabled = self.audioAuthorized
                }

                if !self.audioAuthorized {
                    self.audioDataOutput.connection(with: .audio)?.isEnabled = false
                }

                if let videoConnection = self.movieOutput.connection(with: .video),
                   videoConnection.isVideoOrientationSupported,
                   let interfaceOrientation {
                    videoConnection.videoOrientation = AVCaptureVideoOrientation(interfaceOrientation)
                }

                self.captureSession.commitConfiguration()
                self.audioMeterConnection = self.audioDataOutput.connection(with: .audio)
                self.startCameraSessionIfNeeded()

                DispatchQueue.main.async {
                    self.attachPreviewIfNeeded()
                    self.updateLensButtons()
                    self.updateHUD(for: lensOption.device, lensTitle: lensOption.title)
                    self.startAudioMeterTimerIfNeeded()
                }
            } catch {
                DispatchQueue.main.async {
                    self.secondaryStatusLabel.text = "啟用相機失敗"
                    self.bottomStatusLabel.text = error.localizedDescription
                }
            }
        }
    }

    private func startRecording() {
        guard cameraAuthorized else { return }
        guard !movieOutput.isRecording else { return }
        let interfaceOrientation = view.window?.windowScene?.interfaceOrientation

        recordingState = .starting
        updateRecordButtonAppearance()
        bottomStatusLabel.text = "準備開始錄影..."

        sessionQueue.async { [weak self] in
            guard let self else { return }

            let outputURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("CameraHuman-\(UUID().uuidString)")
                .appendingPathExtension("mov")

            if let videoConnection = self.movieOutput.connection(with: .video),
               videoConnection.isVideoOrientationSupported,
               let interfaceOrientation {
                videoConnection.videoOrientation = AVCaptureVideoOrientation(interfaceOrientation)
            }

            self.movieOutput.startRecording(to: outputURL, recordingDelegate: self)
        }
    }

    private func stopRecording() {
        guard movieOutput.isRecording else { return }
        recordingState = .stopping
        updateRecordButtonAppearance()
        bottomStatusLabel.text = "停止錄影中..."
        sessionQueue.async { [weak self] in
            self?.movieOutput.stopRecording()
        }
    }

    private func attachPreviewIfNeeded() {
        guard previewLayer == nil else { return }
        let layer = AVCaptureVideoPreviewLayer(session: captureSession)
        layer.videoGravity = .resizeAspectFill
        layer.frame = previewContainerView.bounds
        previewContainerView.layer.insertSublayer(layer, at: 0)
        previewLayer = layer
    }

    private func startCameraSessionIfNeeded() {
        guard !captureSession.isRunning else { return }
        captureSession.startRunning()
    }

    private func stopCameraSession() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            guard self.captureSession.isRunning else { return }
            self.captureSession.stopRunning()
        }
    }

    private func refreshLensOptionsIfNeeded() {
        if availableLensOptions.isEmpty {
            refreshLensOptions()
        }
    }

    private func refreshLensOptions() {
        let previouslySelectedMode = currentLensOption?.mode
        let resolvedOptions = currentPosition == .front ? frontLensOptions() : backLensOptions()

        var seenDeviceIDs = Set<String>()
        availableLensOptions = resolvedOptions.filter { option in
            seenDeviceIDs.insert(option.device.uniqueID).inserted
        }

        if let previouslySelectedMode,
           let matchingOption = availableLensOptions.first(where: { $0.mode == previouslySelectedMode }) {
            currentLensOption = matchingOption
        } else {
            currentLensOption = availableLensOptions.first
        }

        rebuildLensButtons()
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

    private func rebuildLensButtons() {
        for arrangedView in lensStackView.arrangedSubviews {
            lensStackView.removeArrangedSubview(arrangedView)
            arrangedView.removeFromSuperview()
        }

        if availableLensOptions.isEmpty {
            let label = UILabel()
            label.text = "NO CAMERA"
            label.font = .monospacedSystemFont(ofSize: 13, weight: .semibold)
            label.textAlignment = .center
            label.textColor = .white
            lensStackView.addArrangedSubview(label)
            return
        }

        for (index, option) in availableLensOptions.enumerated() {
            let button = UIButton(type: .system)
            button.tag = index
            button.setTitle(option.title, for: .normal)
            button.titleLabel?.font = .monospacedSystemFont(ofSize: 14, weight: .semibold)
            button.layer.cornerRadius = 16
            button.layer.borderWidth = 1
            button.addTarget(self, action: #selector(lensButtonTapped(_:)), for: .touchUpInside)
            lensStackView.addArrangedSubview(button)
        }

        updateLensButtons()
    }

    private func updateLensButtons() {
        for (index, arrangedView) in lensStackView.arrangedSubviews.enumerated() {
            guard let button = arrangedView as? UIButton else { continue }
            let isSelected = availableLensOptions.indices.contains(index) && availableLensOptions[index].device.uniqueID == currentLensOption?.device.uniqueID
            button.backgroundColor = isSelected ? UIColor.systemBlue : UIColor.black.withAlphaComponent(0.34)
            button.layer.borderColor = (isSelected ? UIColor.systemBlue : UIColor.white.withAlphaComponent(0.42)).cgColor
            button.setTitleColor(.white, for: .normal)
        }
    }

    private func updatePrimaryHUD(timerText: String = "00:00") {
        let quality = qualityText()
        let aspect = aspectRatioText()
        replacePrimaryStatusChips(quality: quality, aspect: aspect, timerText: timerText, isRecording: recordingState == .recording)
    }

    private func updateHUD(for device: AVCaptureDevice, lensTitle: String) {
        updatePrimaryHUD()
        replaceTechnicalChips(with: [
            "LENS \(lensTitle)",
            "FPS \(frameRateText(for: device))",
            "SHUTTER \(shutterText(for: device))",
            "IRIS \(irisText(for: device))",
            "ISO \(String(format: "%.0f", device.iso))",
            "WB \(whiteBalanceText(for: device))"
        ])

        let positionText = currentPosition == .front ? "FRONT" : "BACK"
        let audioStatusText = audioAuthorized ? "MIC ON" : "MIC OFF"
        secondaryStatusLabel.text = "\(positionText) | \(device.localizedName) | \(audioStatusText)"
        bottomStatusLabel.text = "\(qualityText()) • \(aspectRatioText()) • \(settings.aspectRatio == .ratio4x3 ? "Crop on save" : "Native frame")"
    }

    private func replaceTechnicalChips(with titles: [String]) {
        for arrangedView in technicalStatusStackView.arrangedSubviews {
            technicalStatusStackView.removeArrangedSubview(arrangedView)
            arrangedView.removeFromSuperview()
        }

        let rows = stride(from: 0, to: titles.count, by: 3).map { startIndex in
            Array(titles[startIndex..<min(startIndex + 3, titles.count)])
        }

        for rowTitles in rows {
            let rowStackView = UIStackView()
            rowStackView.axis = .horizontal
            rowStackView.spacing = 6
            rowStackView.distribution = .fillEqually

            for title in rowTitles {
                let label = UILabel()
                label.textAlignment = .center
                label.numberOfLines = 2
                label.font = .monospacedSystemFont(ofSize: 9, weight: .medium)
                label.textColor = .white
                label.backgroundColor = UIColor.white.withAlphaComponent(0.10)
                label.layer.cornerRadius = 8
                label.clipsToBounds = true
                label.attributedText = technicalChipText(for: title)
                rowStackView.addArrangedSubview(label)
            }

            while rowStackView.arrangedSubviews.count < 3 {
                let spacer = UIView()
                rowStackView.addArrangedSubview(spacer)
            }

            technicalStatusStackView.addArrangedSubview(rowStackView)
        }
    }

    private func replaceChips(in stackView: UIStackView, titles: [String], selectedIndex: Int?) {
        for arrangedView in stackView.arrangedSubviews {
            stackView.removeArrangedSubview(arrangedView)
            arrangedView.removeFromSuperview()
        }

        for (index, title) in titles.enumerated() {
            let label = UILabel()
            label.text = title
            label.textAlignment = .center
            label.font = .monospacedSystemFont(ofSize: 10, weight: .medium)
            label.textColor = .white
            label.backgroundColor = index == selectedIndex ? UIColor.systemRed : UIColor.white.withAlphaComponent(0.12)
            label.layer.cornerRadius = 8
            label.clipsToBounds = true
            stackView.addArrangedSubview(label)
        }
    }

    private func replacePrimaryStatusChips(quality: String, aspect: String, timerText: String, isRecording: Bool) {
        for arrangedView in primaryStatusStackView.arrangedSubviews {
            primaryStatusStackView.removeArrangedSubview(arrangedView)
            arrangedView.removeFromSuperview()
        }

        let qualityLabel = makePrimaryStatusLabel(
            title: "FORMAT",
            value: quality,
            accentColor: UIColor.systemBlue,
            isEmphasized: false
        )

        let aspectLabel = makePrimaryStatusLabel(
            title: "FRAME",
            value: aspect,
            accentColor: UIColor.systemBlue,
            isEmphasized: false
        )

        let normalizedTimer = timerText.replacingOccurrences(of: "REC ", with: "")
        let timerLabel = makePrimaryStatusLabel(
            title: isRecording ? "REC" : "TIME",
            value: normalizedTimer,
            accentColor: isRecording ? UIColor.systemRed : UIColor.white.withAlphaComponent(0.75),
            isEmphasized: isRecording
        )

        primaryStatusStackView.addArrangedSubview(qualityLabel)
        primaryStatusStackView.addArrangedSubview(aspectLabel)
        primaryStatusStackView.addArrangedSubview(timerLabel)
    }

    private func makePrimaryStatusLabel(title: String, value: String, accentColor: UIColor, isEmphasized: Bool) -> UILabel {
        let label = UILabel()
        label.textAlignment = .center
        label.numberOfLines = 2
        label.layer.cornerRadius = 8
        label.clipsToBounds = true
        label.backgroundColor = isEmphasized
            ? accentColor.withAlphaComponent(0.24)
            : UIColor.white.withAlphaComponent(0.10)

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center

        let attributed = NSMutableAttributedString(
            string: "\(title)\n",
            attributes: [
                .font: UIFont.monospacedSystemFont(ofSize: 8, weight: .semibold),
                .foregroundColor: accentColor,
                .paragraphStyle: paragraph
            ]
        )
        attributed.append(
            NSAttributedString(
                string: value,
                attributes: [
                    .font: UIFont.monospacedDigitSystemFont(ofSize: isEmphasized ? 12 : 11, weight: .semibold),
                    .foregroundColor: UIColor.white,
                    .paragraphStyle: paragraph
                ]
            )
        )

        label.attributedText = attributed
        return label
    }

    private func updateAudioMeter(level: Float, trackCount: Int) {
        let decibels = Int(round((level * 60) - 60))
        audioTrackLabel.text = "TRACKS \(max(trackCount, audioAuthorized ? 1 : 0))"
        audioLevelLabel.text = String(format: "%02d dB", decibels)

        let meterColor: UIColor
        switch level {
        case 0.85...:
            meterColor = .systemRed
        case 0.68...:
            meterColor = .systemYellow
        default:
            meterColor = .systemGreen
        }

        for (index, heightConstraint) in audioBarHeightConstraints.enumerated() {
            let multiplier = max(0.18, CGFloat(level) * (0.55 + (CGFloat(index) * 0.15)))
            heightConstraint.constant = 6 + (16 * multiplier)
            audioBarViews[index].backgroundColor = meterColor
        }

        audioTitleLabel.textColor = meterColor
        audioLevelLabel.textColor = meterColor

        UIView.animate(withDuration: 0.12) {
            self.audioMeterCardView.layoutIfNeeded()
        }
    }

    private func updateRecordButtonAppearance() {
        switch recordingState {
        case .idle:
            recordButton.backgroundColor = .systemRed
            recordButton.layer.cornerRadius = 30
            recordButton.isEnabled = cameraAuthorized
        case .starting, .stopping:
            recordButton.backgroundColor = UIColor.systemOrange
            recordButton.layer.cornerRadius = 16
            recordButton.isEnabled = false
        case .recording:
            recordButton.backgroundColor = .systemRed
            recordButton.layer.cornerRadius = 16
            recordButton.isEnabled = true
        }
    }

    private func startRecordingTimer() {
        stopRecordingTimer()
        recordingStartDate = Date()
        updatePrimaryHUD(timerText: "REC 00:00")
        recordingTimer = Timer.scheduledTimer(timeInterval: 1, target: self, selector: #selector(recordingTimerFired), userInfo: nil, repeats: true)
    }

    private func stopRecordingTimer() {
        recordingTimer?.invalidate()
        recordingTimer = nil
        recordingStartDate = nil
        updatePrimaryHUD()
    }

    private func startAudioMeterTimerIfNeeded() {
        guard audioMeterTimer == nil else { return }
        audioMeterTimer = Timer.scheduledTimer(timeInterval: 0.12, target: self, selector: #selector(audioMeterTimerFired), userInfo: nil, repeats: true)
    }

    private func stopAudioMeterTimer() {
        audioMeterTimer?.invalidate()
        audioMeterTimer = nil
    }

    private func qualityText() -> String {
        switch captureSession.sessionPreset {
        case .hd4K3840x2160:
            return "4K"
        case .hd1920x1080:
            return "FHD"
        case .hd1280x720:
            return "HD"
        default:
            return settings.videoPreset.displayTitle
        }
    }

    private func aspectRatioText() -> String {
        settings.aspectRatio.displayTitle
    }

    private func frameRateText(for device: AVCaptureDevice) -> String {
        let maxFrameRate = device.activeFormat.videoSupportedFrameRateRanges.map(\.maxFrameRate).max() ?? 0
        return String(format: "%.0f", maxFrameRate)
    }

    private func shutterText(for device: AVCaptureDevice) -> String {
        let duration = CMTimeGetSeconds(device.exposureDuration)
        guard duration > 0 else { return "AUTO" }
        let denominator = max(1, Int(round(1 / duration)))
        return "1/\(denominator)"
    }

    private func irisText(for device: AVCaptureDevice) -> String {
        if device.lensAperture > 0 {
            return String(format: "F%.1f", device.lensAperture)
        }
        return "FIXED"
    }

    private func whiteBalanceText(for device: AVCaptureDevice) -> String {
        switch device.whiteBalanceMode {
        case .locked:
            return "LOCK"
        case .autoWhiteBalance, .continuousAutoWhiteBalance:
            return "AUTO"
        @unknown default:
            return "--"
        }
    }

    private func buildCameraReport() -> String {
        let deviceTypes: [AVCaptureDevice.DeviceType] = [
            .builtInWideAngleCamera,
            .builtInUltraWideCamera,
            .builtInTelephotoCamera,
            .builtInTrueDepthCamera
        ]

        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: deviceTypes,
            mediaType: .video,
            position: .unspecified
        )

        let lines = discoverySession.devices.map { device in
            let position = device.position == .front ? "FRONT" : "BACK"
            return "\(position) | \(device.localizedName) | \(device.deviceType.rawValue)"
        }

        return lines.isEmpty ? "找不到可用鏡頭。" : lines.joined(separator: "\n")
    }

    private func styleHUDButton(_ button: UIButton, title: String) {
        button.setTitle(title, for: .normal)
        button.setTitleColor(.white, for: .normal)
        button.titleLabel?.font = .monospacedSystemFont(ofSize: 11, weight: .semibold)
        button.backgroundColor = UIColor.white.withAlphaComponent(0.14)
        button.layer.cornerRadius = 12
        button.contentEdgeInsets = UIEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)
    }

    private func technicalChipText(for rawText: String) -> NSAttributedString {
        let parts = rawText.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        let title = String(parts.first ?? "")
        let value = parts.count > 1 ? String(parts[1]) : "--"

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center

        let attributed = NSMutableAttributedString(
            string: "\(title)\n",
            attributes: [
                .font: UIFont.monospacedSystemFont(ofSize: 8, weight: .semibold),
                .foregroundColor: UIColor.systemBlue,
                .paragraphStyle: paragraph
            ]
        )
        attributed.append(
            NSAttributedString(
                string: value,
                attributes: [
                    .font: UIFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold),
                    .foregroundColor: UIColor.white,
                    .paragraphStyle: paragraph
                ]
            )
        )
        return attributed
    }

    private func applyGuideVisibility() {
        let shouldShowGuides = settings.showGrid
        guideLines.forEach { $0.isHidden = !shouldShowGuides }
    }

    private func updateAspectMaskLayout() {
        let bounds = previewContainerView.bounds
        guard bounds.width > 0, bounds.height > 0 else { return }

        let ratioSize = settings.aspectRatio.landscapeSize
        let targetHeight = min(bounds.height, bounds.width * (ratioSize.height / ratioSize.width))
        let maskHeight = max(0, (bounds.height - targetHeight) / 2)

        aspectMaskTopHeightConstraint?.constant = maskHeight
        aspectMaskBottomHeightConstraint?.constant = maskHeight
        aspectFrameLabel.text = settings.aspectRatio.displayTitle
        previewContainerView.layoutIfNeeded()
    }

    func fileOutput(_ output: AVCaptureFileOutput, didStartRecordingTo fileURL: URL, from connections: [AVCaptureConnection]) {
        DispatchQueue.main.async {
            self.recordingState = .recording
            self.updateRecordButtonAppearance()
            self.startRecordingTimer()
            self.bottomStatusLabel.text = "錄影中：\(fileURL.lastPathComponent)"
        }
    }

    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        DispatchQueue.main.async {
            self.stopRecordingTimer()
            self.recordingState = .idle
            self.updateRecordButtonAppearance()
            if let error {
                self.bottomStatusLabel.text = "錄影失敗：\(error.localizedDescription)"
            } else {
                self.bottomStatusLabel.text = "錄影完成，整理素材中..."
                let aspectRatio = self.settings.aspectRatio
                DispatchQueue.global(qos: .userInitiated).async {
                    do {
                        let savedRecording = try MediaLibrary.shared.storeRecording(from: outputFileURL, aspectRatio: aspectRatio)
                        DispatchQueue.main.async {
                            self.bottomStatusLabel.text = "已儲存：\(savedRecording.fileName)"
                            self.showToast(text: "已儲存\n\(savedRecording.fileName)")
                        }
                    } catch {
                        DispatchQueue.main.async {
                            self.bottomStatusLabel.text = "儲存失敗：\(error.localizedDescription)"
                            self.showToast(text: "儲存失敗")
                        }
                    }
                }
            }
        }
    }

    private func showToast(text: String) {
        toastLabel.text = text
        UIView.animate(withDuration: 0.18, animations: {
            self.toastLabel.alpha = 1
        }) { _ in
            UIView.animate(withDuration: 0.22, delay: 1.6, options: [.curveEaseInOut]) {
                self.toastLabel.alpha = 0
            }
        }
    }
}

private extension AVCaptureVideoOrientation {
    init(_ interfaceOrientation: UIInterfaceOrientation) {
        switch interfaceOrientation {
        case .portrait:
            self = .portrait
        case .portraitUpsideDown:
            self = .portraitUpsideDown
        case .landscapeLeft:
            self = .landscapeRight
        case .landscapeRight:
            self = .landscapeLeft
        @unknown default:
            self = .portrait
        }
    }
}
