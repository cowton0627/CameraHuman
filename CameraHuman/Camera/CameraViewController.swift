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
    private var currentAudioTrackCount: Int = 0

    private var cameraAuthorized = false
    private var audioAuthorized = false
    private var currentPosition: AVCaptureDevice.Position = CameraSettingsStore.shared.startupCamera.capturePosition
    private var currentLensOption: LensOption?
    private var availableLensOptions: [LensOption] = []
    private var recordingState: RecordingState = .idle
    private var recordingStartDate: Date?
    private var lastSavedRecording: MediaRecording?
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
    private let deleteLastRecordingButton = UIButton(type: .system)
    private let audioMeterCardView = UIView()
    private let audioTitleLabel = UILabel()
    private let audioTrackLabel = UILabel()
    private let audioLevelLabel = UILabel()
    private let audioSummaryLabel = UILabel()
    private let audioBarsStackView = UIStackView()
    private let toastLabel = UILabel()
    private var audioBarViews: [UIView] = []
    private var audioBarHeightConstraints: [NSLayoutConstraint] = []
    private var portraitLayoutConstraints: [NSLayoutConstraint] = []
    private var landscapeLayoutConstraints: [NSLayoutConstraint] = []
    private var isUsingLandscapeLayout = false

    private let guideLines = [UIView(), UIView(), UIView(), UIView()]

    override var prefersStatusBarHidden: Bool {
        true
    }

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
        updateCameraLayoutIfNeeded()
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
        presentCameraDiagnostics()
    }

    @objc private func deleteLastRecordingTapped(_ sender: UIButton) {
        guard let recording = lastSavedRecording else { return }
        let alertController = UIAlertController(title: "刪除最近錄影？", message: recording.fileName, preferredStyle: .alert)
        alertController.addAction(UIAlertAction(title: "取消", style: .cancel))
        alertController.addAction(UIAlertAction(title: "刪除", style: .destructive) { [weak self] _ in
            guard let self else { return }
            do {
                try MediaLibrary.shared.deleteRecording(at: recording.url)
                self.lastSavedRecording = nil
                self.updateDeleteLastRecordingButton()
                self.bottomStatusLabel.text = "已刪除最近錄影。"
                self.showToast(text: "已刪除\n\(recording.fileName)")
            } catch {
                self.bottomStatusLabel.text = "刪除失敗：\(error.localizedDescription)"
                self.showToast(text: "刪除失敗")
            }
        })
        present(alertController, animated: true)
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
        currentAudioTrackCount = trackCount
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
        updateDeleteLastRecordingButton()
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
        topHUDView.spacing = 6
        topHUDView.layoutMargins = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        topHUDView.isLayoutMarginsRelativeArrangement = true
        topHUDView.backgroundColor = UIColor.black.withAlphaComponent(0.18)
        topHUDView.layer.cornerRadius = 12

        topTitleLabel.font = .monospacedSystemFont(ofSize: 12, weight: .semibold)
        topTitleLabel.textColor = .white
        topTitleLabel.text = "CAMERA"
        topTitleLabel.isHidden = true

        primaryStatusStackView.axis = .horizontal
        primaryStatusStackView.spacing = 8
        primaryStatusStackView.distribution = .fillEqually

        technicalStatusStackView.axis = .horizontal
        technicalStatusStackView.spacing = 10
        technicalStatusStackView.distribution = .fillEqually

        secondaryStatusLabel.font = .monospacedSystemFont(ofSize: 9, weight: .regular)
        secondaryStatusLabel.textColor = UIColor.white.withAlphaComponent(0.84)
        secondaryStatusLabel.numberOfLines = 1
        secondaryStatusLabel.adjustsFontSizeToFitWidth = true
        secondaryStatusLabel.minimumScaleFactor = 0.7
        secondaryStatusLabel.text = "等待相機與麥克風權限"

        topHUDView.addArrangedSubview(topTitleLabel)
        topHUDView.addArrangedSubview(primaryStatusStackView)
        topHUDView.addArrangedSubview(technicalStatusStackView)
        topHUDView.addArrangedSubview(secondaryStatusLabel)
        view.addSubview(topHUDView)

        NSLayoutConstraint.activate([
            topHUDView.leadingAnchor.constraint(equalTo: previewContainerView.leadingAnchor, constant: 8),
            topHUDView.trailingAnchor.constraint(equalTo: previewContainerView.trailingAnchor, constant: -8),
            topHUDView.topAnchor.constraint(equalTo: previewContainerView.topAnchor, constant: 8)
        ])
    }

    private func configureBottomHUD() {
        bottomHUDView.translatesAutoresizingMaskIntoConstraints = false
        bottomHUDView.backgroundColor = .clear
        bottomHUDView.layer.cornerRadius = 0

        lensStackView.translatesAutoresizingMaskIntoConstraints = false
        lensStackView.axis = .horizontal
        lensStackView.spacing = 8
        lensStackView.distribution = .fillEqually

        bottomStatusLabel.translatesAutoresizingMaskIntoConstraints = false
        bottomStatusLabel.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
        bottomStatusLabel.textColor = UIColor.white.withAlphaComponent(0.84)
        bottomStatusLabel.numberOfLines = 1
        bottomStatusLabel.text = "Camera + Mic capture session"

        audioSummaryLabel.translatesAutoresizingMaskIntoConstraints = false
        audioSummaryLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
        audioSummaryLabel.textColor = UIColor.systemGreen
        audioSummaryLabel.textAlignment = .right
        audioSummaryLabel.adjustsFontSizeToFitWidth = true
        audioSummaryLabel.minimumScaleFactor = 0.75
        audioSummaryLabel.text = "MIC -- dB"

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
        styleHUDButton(switchCameraButton, title: "arrow.2.circlepath")
        switchCameraButton.addTarget(self, action: #selector(switchCameraTapped(_:)), for: .touchUpInside)

        inspectButton.translatesAutoresizingMaskIntoConstraints = false
        styleHUDButton(inspectButton, title: "info.circle")
        inspectButton.addTarget(self, action: #selector(inspectTapped(_:)), for: .touchUpInside)

        deleteLastRecordingButton.translatesAutoresizingMaskIntoConstraints = false
        styleHUDButton(deleteLastRecordingButton, title: "trash")
        deleteLastRecordingButton.addTarget(self, action: #selector(deleteLastRecordingTapped(_:)), for: .touchUpInside)
        deleteLastRecordingButton.isEnabled = false
        deleteLastRecordingButton.alpha = 0.35

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
        leftControlsStackView.addArrangedSubview(deleteLastRecordingButton)
        audioMeterCardView.addSubview(audioTitleLabel)
        audioMeterCardView.addSubview(audioTrackLabel)
        audioMeterCardView.addSubview(audioLevelLabel)
        audioMeterCardView.addSubview(audioBarsStackView)

        bottomHUDView.addSubview(lensStackView)
        bottomHUDView.addSubview(bottomStatusLabel)
        bottomHUDView.addSubview(recordButton)
        bottomHUDView.addSubview(leftControlsStackView)
        bottomHUDView.addSubview(audioSummaryLabel)
        bottomHUDView.addSubview(audioMeterCardView)
        view.addSubview(bottomHUDView)

        let sharedConstraints = [
            bottomStatusLabel.heightAnchor.constraint(equalToConstant: 14),
            recordButton.widthAnchor.constraint(equalToConstant: 56),
            recordButton.heightAnchor.constraint(equalToConstant: 56),
            audioMeterCardView.widthAnchor.constraint(equalToConstant: 118),
            audioMeterCardView.heightAnchor.constraint(equalToConstant: 74),
            switchCameraButton.widthAnchor.constraint(equalToConstant: 38),
            switchCameraButton.heightAnchor.constraint(equalToConstant: 38),
            inspectButton.widthAnchor.constraint(equalToConstant: 38),
            inspectButton.heightAnchor.constraint(equalToConstant: 38),
            deleteLastRecordingButton.widthAnchor.constraint(equalToConstant: 38),
            deleteLastRecordingButton.heightAnchor.constraint(equalToConstant: 38),

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
        ]

        portraitLayoutConstraints = [
            previewContainerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            previewContainerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            previewContainerView.topAnchor.constraint(equalTo: view.topAnchor),
            previewContainerView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            bottomHUDView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bottomHUDView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bottomHUDView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            bottomHUDView.heightAnchor.constraint(equalToConstant: 82),

            lensStackView.leadingAnchor.constraint(equalTo: bottomHUDView.leadingAnchor, constant: 12),
            lensStackView.trailingAnchor.constraint(lessThanOrEqualTo: leftControlsStackView.leadingAnchor, constant: -12),
            lensStackView.centerYAnchor.constraint(equalTo: recordButton.centerYAnchor),
            lensStackView.heightAnchor.constraint(equalToConstant: 38),

            recordButton.centerXAnchor.constraint(equalTo: bottomHUDView.centerXAnchor),
            recordButton.centerYAnchor.constraint(equalTo: bottomHUDView.centerYAnchor, constant: -6),

            leftControlsStackView.leadingAnchor.constraint(greaterThanOrEqualTo: recordButton.trailingAnchor, constant: 8),
            leftControlsStackView.trailingAnchor.constraint(equalTo: bottomHUDView.trailingAnchor, constant: -12),
            leftControlsStackView.centerYAnchor.constraint(equalTo: recordButton.centerYAnchor),

            bottomStatusLabel.leadingAnchor.constraint(equalTo: bottomHUDView.leadingAnchor, constant: 16),
            bottomStatusLabel.trailingAnchor.constraint(lessThanOrEqualTo: audioSummaryLabel.leadingAnchor, constant: -12),
            bottomStatusLabel.topAnchor.constraint(equalTo: recordButton.bottomAnchor, constant: 6),

            audioSummaryLabel.trailingAnchor.constraint(equalTo: bottomHUDView.trailingAnchor, constant: -16),
            audioSummaryLabel.centerYAnchor.constraint(equalTo: bottomStatusLabel.centerYAnchor),
            audioSummaryLabel.widthAnchor.constraint(equalToConstant: 112),

            audioMeterCardView.trailingAnchor.constraint(equalTo: bottomHUDView.trailingAnchor, constant: -12),
            audioMeterCardView.bottomAnchor.constraint(equalTo: bottomHUDView.bottomAnchor, constant: -8)
        ]

        landscapeLayoutConstraints = [
            previewContainerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            previewContainerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            previewContainerView.topAnchor.constraint(equalTo: view.topAnchor),
            previewContainerView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            bottomHUDView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            bottomHUDView.topAnchor.constraint(equalTo: view.topAnchor),
            bottomHUDView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            bottomHUDView.widthAnchor.constraint(equalToConstant: 72),

            recordButton.centerXAnchor.constraint(equalTo: bottomHUDView.centerXAnchor),
            recordButton.centerYAnchor.constraint(equalTo: bottomHUDView.centerYAnchor),

            leftControlsStackView.centerXAnchor.constraint(equalTo: bottomHUDView.centerXAnchor),
            leftControlsStackView.bottomAnchor.constraint(equalTo: recordButton.topAnchor, constant: -22),

            lensStackView.centerXAnchor.constraint(equalTo: bottomHUDView.centerXAnchor),
            lensStackView.topAnchor.constraint(equalTo: recordButton.bottomAnchor, constant: 22),
            lensStackView.widthAnchor.constraint(equalToConstant: 72),

            audioMeterCardView.centerXAnchor.constraint(equalTo: bottomHUDView.centerXAnchor),
            audioMeterCardView.bottomAnchor.constraint(equalTo: bottomHUDView.bottomAnchor, constant: -12),

            bottomStatusLabel.leadingAnchor.constraint(equalTo: bottomHUDView.leadingAnchor, constant: 8),
            bottomStatusLabel.trailingAnchor.constraint(equalTo: bottomHUDView.trailingAnchor, constant: -8),
            bottomStatusLabel.topAnchor.constraint(equalTo: bottomHUDView.topAnchor, constant: 8)
        ]

        NSLayoutConstraint.activate(sharedConstraints)
        updateCameraLayoutIfNeeded(force: true)
    }

    private func configureGuides() {
        for line in guideLines {
            line.backgroundColor = UIColor.white.withAlphaComponent(0.18)
            previewContainerView.addSubview(line)
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

    private func updateCameraLayoutIfNeeded(force: Bool = false) {
        let shouldUseLandscapeLayout = view.bounds.width > view.bounds.height
        guard force || shouldUseLandscapeLayout != isUsingLandscapeLayout else { return }

        NSLayoutConstraint.deactivate(isUsingLandscapeLayout ? landscapeLayoutConstraints : portraitLayoutConstraints)
        NSLayoutConstraint.activate(shouldUseLandscapeLayout ? landscapeLayoutConstraints : portraitLayoutConstraints)
        isUsingLandscapeLayout = shouldUseLandscapeLayout

        leftControlsStackView.axis = shouldUseLandscapeLayout ? .vertical : .horizontal
        lensStackView.axis = shouldUseLandscapeLayout ? .vertical : .horizontal
        lensStackView.isHidden = shouldUseLandscapeLayout
        audioMeterCardView.isHidden = true
        audioSummaryLabel.isHidden = shouldUseLandscapeLayout
        technicalStatusStackView.isHidden = false
        secondaryStatusLabel.isHidden = shouldUseLandscapeLayout
        bottomStatusLabel.textAlignment = shouldUseLandscapeLayout ? .center : .left
        view.setNeedsLayout()
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
            button.titleLabel?.font = .monospacedSystemFont(ofSize: 12, weight: .semibold)
            button.layer.cornerRadius = 14
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
            "FPS \(HUDFormatters.frameRate(for: device))",
            "SHUTTER \(HUDFormatters.shutter(for: device))",
            "IRIS \(HUDFormatters.iris(for: device))",
            "ISO \(String(format: "%.0f", device.iso))",
            "WB \(HUDFormatters.whiteBalance(for: device))"
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

        for title in titles {
            let label = UILabel()
            label.textAlignment = .center
            label.numberOfLines = 2
            label.adjustsFontSizeToFitWidth = true
            label.minimumScaleFactor = 0.72
            label.font = .monospacedSystemFont(ofSize: 9, weight: .medium)
            label.textColor = .white
            label.backgroundColor = .clear
            label.attributedText = technicalChipText(for: title)
            technicalStatusStackView.addArrangedSubview(label)
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
        label.layer.cornerRadius = 6
        label.clipsToBounds = true
        label.backgroundColor = isEmphasized
            ? accentColor.withAlphaComponent(0.24)
            : UIColor.black.withAlphaComponent(0.34)

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
        audioSummaryLabel.textColor = meterColor
        audioSummaryLabel.text = "MIC \(decibels) dB"

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

    private func updateDeleteLastRecordingButton() {
        let hasLastRecording = lastSavedRecording != nil
        deleteLastRecordingButton.isEnabled = hasLastRecording
        deleteLastRecordingButton.alpha = hasLastRecording ? 1 : 0.35
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

    private func presentCameraDiagnostics() {
        let report = CameraDiagnostics.report(from: CameraDiagnostics.Inputs(
            recordingState: recordingStateLabel(),
            quality: qualityText(),
            aspect: aspectRatioText(),
            lensTitle: currentLensOption?.title,
            position: currentPosition,
            device: currentLensOption?.device,
            audioAuthorized: audioAuthorized,
            audioTrackCount: currentAudioTrackCount
        ))
        let alertController = UIAlertController(title: "Camera Diagnostics", message: report, preferredStyle: .alert)
        alertController.addAction(UIAlertAction(title: "Close", style: .cancel))
        alertController.addAction(UIAlertAction(title: "Copy", style: .default) { _ in
            UIPasteboard.general.string = report
            self.bottomStatusLabel.text = "診斷資訊已複製。"
        })
        present(alertController, animated: true)
    }

    private func recordingStateLabel() -> String {
        switch recordingState {
        case .idle:
            return "IDLE"
        case .starting:
            return "STARTING"
        case .recording:
            return "RECORDING"
        case .stopping:
            return "STOPPING"
        }
    }

    private func styleHUDButton(_ button: UIButton, title: String) {
        if let image = UIImage(systemName: title) {
            button.setImage(image, for: .normal)
            button.setTitle(nil, for: .normal)
            button.tintColor = .white
            button.imageView?.contentMode = .scaleAspectFit
        } else {
            button.setTitle(title, for: .normal)
            button.setTitleColor(.white, for: .normal)
            button.titleLabel?.font = .monospacedSystemFont(ofSize: 11, weight: .semibold)
        }
        button.backgroundColor = UIColor.white.withAlphaComponent(0.14)
        button.layer.cornerRadius = 14
        button.contentEdgeInsets = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
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

        aspectMaskTopHeightConstraint?.constant = 0
        aspectMaskBottomHeightConstraint?.constant = 0
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
                            self.lastSavedRecording = savedRecording
                            self.updateDeleteLastRecordingButton()
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
        case .unknown:
            self = .portrait
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
