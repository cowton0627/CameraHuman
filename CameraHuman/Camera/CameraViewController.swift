//
//  CameraViewController.swift
//  CameraHuman
//

import AVFoundation
import UIKit

final class CameraViewController: UIViewController {
    private var isUITesting: Bool { ProcessInfo.processInfo.arguments.contains("-ui-testing") }
    private let settings = CameraSettingsStore.shared
    private let session = CameraSession()
    private lazy var recorder = CameraRecorder(session: session)
    private lazy var audioMonitor = AudioLevelMonitor { [weak self] level, trackCount in
        self?.handleAudioMeter(level: level, trackCount: trackCount)
    }

    private let previewView = AspectMaskView()
    private let toastView = ToastView()
    private let audioMeterCardView = AudioMeterCardView()

    private let topHUDView = UIStackView()
    private let primaryStatusStackView = UIStackView()
    private let technicalStatusStackView = UIStackView()
    private let topTitleLabel = UILabel()
    private let secondaryStatusLabel = UILabel()

    private let bottomHUDView = UIView()
    private let lensStackView = UIStackView()
    private let leftControlsStackView = UIStackView()
    private let bottomStatusLabel = UILabel()
    private let recordButton = UIButton(type: .custom)
    private let switchCameraButton = UIButton(type: .system)
    private let inspectButton = UIButton(type: .system)
    private let deleteLastRecordingButton = UIButton(type: .system)
    private let audioSummaryLabel = UILabel()

    private var portraitLayoutConstraints: [NSLayoutConstraint] = []
    private var landscapeLayoutConstraints: [NSLayoutConstraint] = []
    private var isUsingLandscapeLayout = false

    private var lastSavedRecording: MediaRecording?

    // MARK: - Manual control state

    /// HUD chip 點下去要打開哪種控制。`nil` = 唯讀（如 LENS / IRIS）。
    private enum HUDControl { case format, frame, fps, exposure, whiteBalance }

    private let controlSheet = ManualControlSheetView()
    private var controlSheetBottomConstraint: NSLayoutConstraint?
    /// 重建 chip 時把可點 chip 對應到要開的控制。
    private var technicalChipControls: [UIView: HUDControl] = [:]
    private var primaryChipControls: [UIView: HUDControl] = [:]
    /// 曝光面板狀態：手動模式下兩條滑桿要一起送進 setManualExposure，所以兩個值都要記住。
    private var exposureIsAuto = true
    private var manualISO: Float = 100
    /// 快門以「角度」為準（電影機慣例），實際秒數依當前 fps 換算。
    private var manualShutterAngle: Double = CameraManualControls.recommendedShutterAngle
    private var manualFPS: Double = 30
    private var whiteBalanceIsAuto = true
    private var manualKelvin: Float = 5000
    /// 面板目前開的是哪種控制（AUTO/MANUAL 切換時要知道作用到誰）。
    private var activeSheetControl: HUDControl?

    override var prefersStatusBarHidden: Bool { true }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(cameraSettingsDidChange),
            name: .cameraSettingsDidChange,
            object: nil
        )

        configureUI()
        setupControlSheet()

        if isUITesting {
            secondaryStatusLabel.text = "UI testing mode"
            bottomStatusLabel.text = "Camera hardware disabled for UI tests"
            return
        }

        wireServices()
        session.setAudioSampleBufferDelegate(audioMonitor, queue: audioMonitor.sampleQueue)

        // 把 preview layer 建好就掛上去（綁到 session）。session 之後增刪 input 它會自動跟著刷新，
        // 不必每次 onConfigured 都重建一次。
        previewView.attachPreviewLayer(AVCaptureVideoPreviewLayer(session: session.captureSession))

        session.refreshLenses()
        rebuildLensButtons()

        session.requestAuthorizations { [weak self] in
            guard let self else { return }
            self.audioMonitor.isAuthorized = self.session.audioAuthorized
            self.updateRecordButtonAppearance()
            self.session.configure(interfaceOrientation: self.view.window?.windowScene?.interfaceOrientation)
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateCameraLayoutIfNeeded()
        previewView.setAspectRatio(settings.aspectRatio)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        UIApplication.shared.isIdleTimerDisabled = settings.keepScreenAwake
        applyDisplayPreferences()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        UIApplication.shared.isIdleTimerDisabled = false
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        audioMonitor.stop()
        session.stop()
    }

    // MARK: - Service wiring

    private func wireServices() {
        session.onConfigured = { [weak self] device, lensTitle in
            guard let self else { return }
            self.updateLensButtons()
            self.updateHUD(for: device, lensTitle: lensTitle)
            self.audioMonitor.start()
        }
        session.onConfigureFailed = { [weak self] message in
            self?.secondaryStatusLabel.text = message
            self?.bottomStatusLabel.text = message
        }
        session.onLensesChanged = { [weak self] in
            self?.rebuildLensButtons()
        }

        recorder.onStateChange = { [weak self] _ in
            self?.updateRecordButtonAppearance()
            self?.refreshTechnicalHUD()
        }
        recorder.onTimerTick = { [weak self] elapsed in
            let minutes = elapsed / 60
            let seconds = elapsed % 60
            self?.updatePrimaryHUD(timerText: String(format: "REC %02d:%02d", minutes, seconds))
        }
        recorder.onStartedFile = { [weak self] url in
            self?.bottomStatusLabel.text = "錄影中：\(url.lastPathComponent)"
        }
        recorder.onSaved = { [weak self] recording in
            guard let self else { return }
            self.lastSavedRecording = recording
            self.updateDeleteLastRecordingButton()
            self.bottomStatusLabel.text = "已儲存：\(recording.fileName)"
            self.toastView.show("已儲存\n\(recording.fileName)")
            self.updatePrimaryHUD()
        }
        recorder.onFailed = { [weak self] message in
            self?.bottomStatusLabel.text = "錄影失敗：\(message)"
            self?.toastView.show("錄影失敗")
            self?.updatePrimaryHUD()
        }
    }

    // MARK: - Actions

    @objc private func lensButtonTapped(_ sender: UIButton) {
        let options = session.availableLensOptions
        guard options.indices.contains(sender.tag) else { return }
        // 點擊已選中的鏡頭 → 不必重建整個 capture session
        if options[sender.tag].device.uniqueID == session.currentLensOption?.device.uniqueID {
            return
        }
        session.selectLens(at: sender.tag)
        session.configure(interfaceOrientation: view.window?.windowScene?.interfaceOrientation)
        updateLensButtons()
    }

    @objc private func switchCameraTapped(_ sender: UIButton) {
        guard recorder.state == .idle else { return }
        session.switchPosition()
        session.configure(interfaceOrientation: view.window?.windowScene?.interfaceOrientation)
    }

    @objc private func inspectTapped(_ sender: UIButton) {
        presentCameraDiagnostics()
    }

    @objc private func deleteLastRecordingTapped(_ sender: UIButton) {
        guard let recording = lastSavedRecording else { return }
        let alert = UIAlertController(title: "刪除最近錄影？", message: recording.fileName, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "刪除", style: .destructive) { [weak self] _ in
            guard let self else { return }
            do {
                try MediaLibrary.shared.deleteRecording(at: recording.url)
                self.lastSavedRecording = nil
                self.updateDeleteLastRecordingButton()
                self.bottomStatusLabel.text = "已刪除最近錄影。"
                self.toastView.show("已刪除\n\(recording.fileName)")
            } catch {
                self.bottomStatusLabel.text = "刪除失敗：\(error.localizedDescription)"
                self.toastView.show("刪除失敗")
            }
        })
        present(alert, animated: true)
    }

    @objc private func recordButtonTapped(_ sender: UIButton) {
        switch recorder.state {
        case .idle:
            recorder.start(interfaceOrientation: view.window?.windowScene?.interfaceOrientation)
        case .recording:
            recorder.stop()
        case .starting, .stopping:
            break
        }
    }

    @objc private func cameraSettingsDidChange() {
        previewView.setGuidesVisible(settings.showGrid)
        previewView.setAspectRatio(settings.aspectRatio)
        applyDisplayPreferences()

        guard recorder.state == .idle else {
            updatePrimaryHUD()
            bottomStatusLabel.text = "部份設定會在結束目前錄影後套用。"
            return
        }

        session.resetPositionFromSettings()
        session.configure(interfaceOrientation: view.window?.windowScene?.interfaceOrientation)
    }

    private func applyDisplayPreferences() {
        technicalStatusStackView.isHidden = !settings.showTechnicalHUD
        audioSummaryLabel.isHidden = isUsingLandscapeLayout || !settings.showAudioMeter || !settings.recordAudio
        if !settings.recordAudio { audioSummaryLabel.text = "MIC OFF" }
    }

    // MARK: - Audio meter forwarding

    private func handleAudioMeter(level: Float, trackCount: Int) {
        audioMeterCardView.update(level: level, trackCount: trackCount, audioAuthorized: session.audioAuthorized)
        audioSummaryLabel.textColor = audioMeterCardView.meterColor
        let decibels = Int(round((level * 60) - 60))
        audioSummaryLabel.text = "MIC \(decibels) dB"
    }

    // MARK: - View construction

    private func configureUI() {
        configurePreview()
        configureTopHUD()
        configureBottomHUD()
        configureToast()
        previewView.setGuidesVisible(settings.showGrid)
        updatePrimaryHUD()
        replaceTechnicalChips(with: [
            (title: "LENS", value: "--", control: nil),
            (title: "FPS", value: "--", control: nil),
            (title: "SHUTTER", value: "--", control: nil),
            (title: "IRIS", value: "FIXED", control: nil),
            (title: "ISO", value: "--", control: nil),
            (title: "WB", value: "--", control: nil)
        ])
        handleAudioMeter(level: 0, trackCount: 0)
        updateRecordButtonAppearance()
        updateDeleteLastRecordingButton()
    }

    private func configurePreview() {
        view.addSubview(previewView)
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
            topHUDView.leadingAnchor.constraint(equalTo: previewView.leadingAnchor, constant: 8),
            topHUDView.trailingAnchor.constraint(equalTo: previewView.trailingAnchor, constant: -8),
            topHUDView.topAnchor.constraint(equalTo: previewView.topAnchor, constant: 8)
        ])
    }

    private func configureBottomHUD() {
        bottomHUDView.translatesAutoresizingMaskIntoConstraints = false
        bottomHUDView.backgroundColor = .clear

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
        recordButton.accessibilityIdentifier = "camera.record"
        recordButton.accessibilityLabel = "Record"
        recordButton.layer.cornerRadius = 30
        recordButton.layer.borderWidth = 5
        recordButton.layer.borderColor = UIColor.white.withAlphaComponent(0.92).cgColor
        recordButton.backgroundColor = .systemRed
        recordButton.layer.masksToBounds = true
        recordButton.layer.cornerCurve = .continuous
        recordButton.addTarget(self, action: #selector(recordButtonTapped(_:)), for: .touchUpInside)

        leftControlsStackView.translatesAutoresizingMaskIntoConstraints = false
        leftControlsStackView.axis = .horizontal
        leftControlsStackView.spacing = 8
        leftControlsStackView.alignment = .center

        switchCameraButton.translatesAutoresizingMaskIntoConstraints = false
        switchCameraButton.accessibilityIdentifier = "camera.switch"
        switchCameraButton.accessibilityLabel = "Switch Camera"
        styleHUDButton(switchCameraButton, title: "arrow.2.circlepath")
        switchCameraButton.addTarget(self, action: #selector(switchCameraTapped(_:)), for: .touchUpInside)

        inspectButton.translatesAutoresizingMaskIntoConstraints = false
        inspectButton.accessibilityIdentifier = "camera.diagnostics"
        inspectButton.accessibilityLabel = "Camera Diagnostics"
        styleHUDButton(inspectButton, title: "info.circle")
        inspectButton.addTarget(self, action: #selector(inspectTapped(_:)), for: .touchUpInside)

        deleteLastRecordingButton.translatesAutoresizingMaskIntoConstraints = false
        styleHUDButton(deleteLastRecordingButton, title: "trash")
        deleteLastRecordingButton.addTarget(self, action: #selector(deleteLastRecordingTapped(_:)), for: .touchUpInside)
        deleteLastRecordingButton.isEnabled = false
        deleteLastRecordingButton.alpha = 0.35

        leftControlsStackView.addArrangedSubview(switchCameraButton)
        leftControlsStackView.addArrangedSubview(inspectButton)
        leftControlsStackView.addArrangedSubview(deleteLastRecordingButton)

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
            deleteLastRecordingButton.heightAnchor.constraint(equalToConstant: 38)
        ]

        portraitLayoutConstraints = [
            previewView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            previewView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            previewView.topAnchor.constraint(equalTo: view.topAnchor),
            previewView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

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
            previewView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            previewView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            previewView.topAnchor.constraint(equalTo: view.topAnchor),
            previewView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

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

    private func configureToast() {
        view.addSubview(toastView)
        NSLayoutConstraint.activate([
            toastView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            toastView.bottomAnchor.constraint(equalTo: bottomHUDView.topAnchor, constant: -14),
            toastView.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 28),
            toastView.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -28)
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
        audioSummaryLabel.isHidden = shouldUseLandscapeLayout || !settings.showAudioMeter || !settings.recordAudio
        technicalStatusStackView.isHidden = !settings.showTechnicalHUD
        secondaryStatusLabel.isHidden = shouldUseLandscapeLayout
        bottomStatusLabel.textAlignment = shouldUseLandscapeLayout ? .center : .left
        view.setNeedsLayout()
    }

    // MARK: - HUD updates

    private func updatePrimaryHUD(timerText: String = "00:00") {
        let quality = qualityText()
        let aspect = settings.aspectRatio.displayTitle
        replacePrimaryStatusChips(quality: quality, aspect: aspect, timerText: timerText, isRecording: recorder.state == .recording)
    }

    private func updateHUD(for device: AVCaptureDevice, lensTitle: String) {
        updatePrimaryHUD()
        replaceTechnicalChips(with: [
            (title: "LENS", value: lensTitle, control: nil),
            (title: "FPS", value: HUDFormatters.frameRate(for: device), control: .fps),
            (title: "SHUTTER", value: HUDFormatters.shutter(for: device), control: .exposure),
            (title: "IRIS", value: HUDFormatters.iris(for: device), control: nil),
            (title: "ISO", value: String(format: "%.0f", device.iso), control: .exposure),
            (title: "WB", value: HUDFormatters.whiteBalance(for: device), control: .whiteBalance)
        ])

        let positionText = session.currentPosition == .front ? "FRONT" : "BACK"
        let audioStatusText = session.audioAuthorized ? "MIC ON" : "MIC OFF"
        secondaryStatusLabel.text = "\(positionText) | \(device.localizedName) | \(audioStatusText)"
        bottomStatusLabel.text = "\(qualityText()) • \(settings.aspectRatio.displayTitle) • \(settings.aspectRatio == .ratio4x3 ? "Crop on save" : "Native frame")"
    }

    private func replaceTechnicalChips(with chips: [(title: String, value: String, control: HUDControl?)]) {
        for arrangedView in technicalStatusStackView.arrangedSubviews {
            technicalStatusStackView.removeArrangedSubview(arrangedView)
            arrangedView.removeFromSuperview()
        }
        technicalChipControls.removeAll()

        for chip in chips {
            let label = UILabel()
            label.textAlignment = .center
            label.numberOfLines = 2
            label.adjustsFontSizeToFitWidth = true
            label.minimumScaleFactor = 0.72
            label.font = .monospacedSystemFont(ofSize: 9, weight: .medium)
            label.textColor = .white
            label.attributedText = technicalChipText(title: chip.title, value: chip.value)

            if let control = chip.control {
                // 可調的 chip 給淡底色 + 圓角當「可按」暗示，並掛 tap。
                label.backgroundColor = UIColor.white.withAlphaComponent(0.12)
                label.layer.cornerRadius = 6
                label.clipsToBounds = true
                label.isUserInteractionEnabled = true
                label.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(technicalChipTapped(_:))))
                technicalChipControls[label] = control
                if recorder.state != .idle {
                    let canAdjustISO = control == .exposure && !exposureIsAuto
                    label.alpha = canAdjustISO ? 1 : 0.55
                }
            } else {
                label.backgroundColor = .clear
            }

            technicalStatusStackView.addArrangedSubview(label)
        }
    }

    private func replacePrimaryStatusChips(quality: String, aspect: String, timerText: String, isRecording: Bool) {
        primaryChipControls.removeAll()
        for arrangedView in primaryStatusStackView.arrangedSubviews {
            primaryStatusStackView.removeArrangedSubview(arrangedView)
            arrangedView.removeFromSuperview()
        }

        let qualityLabel = makePrimaryStatusLabel(title: "FORMAT", value: quality, accentColor: UIColor.systemBlue, isEmphasized: false)
        let aspectLabel = makePrimaryStatusLabel(title: "FRAME", value: aspect, accentColor: UIColor.systemBlue, isEmphasized: false)
        makeChipInteractive(qualityLabel, control: .format, enabled: recorder.state == .idle)
        makeChipInteractive(aspectLabel, control: .frame, enabled: recorder.state == .idle)
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

    private func makeChipInteractive(_ view: UIView, control: HUDControl, enabled: Bool) {
        view.isUserInteractionEnabled = true
        view.alpha = enabled ? 1 : 0.55
        view.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(technicalChipTapped(_:))))
        primaryChipControls[view] = control
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

    private func technicalChipText(title: String, value: String) -> NSAttributedString {
        let value = value.isEmpty ? "--" : value

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

    // MARK: - Manual controls

    private func setupControlSheet() {
        controlSheet.isHidden = true
        view.addSubview(controlSheet)

        // bottom 要 pin 到 safeArea（不是 view 底）：RootTabBarController 用 additionalSafeAreaInsets
        // 把 dock 高度餵進 safeArea，pin 到 view.bottom 會讓面板下半被 dock 蓋住、滑桿被切掉。
        let bottom = controlSheet.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: 320)
        controlSheetBottomConstraint = bottom
        NSLayoutConstraint.activate([
            controlSheet.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            controlSheet.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            bottom
        ])

        controlSheet.onSliderChanged = { [weak self] key, value in
            self?.handleSliderChanged(key: key, value: value)
        }
        controlSheet.onModeChanged = { [weak self] isAuto in
            self?.handleSheetModeChanged(isAuto: isAuto)
        }
        controlSheet.onClose = { [weak self] in
            self?.hideControlSheet()
        }
    }

    @objc private func technicalChipTapped(_ gesture: UITapGestureRecognizer) {
        guard let view = gesture.view,
              let control = technicalChipControls[view] ?? primaryChipControls[view] else { return }
        switch control {
        case .format: cycleVideoPreset()
        case .frame: cycleAspectRatio()
        case .fps: cycleFrameRate()
        case .exposure: presentExposureSheet()
        case .whiteBalance: presentWhiteBalanceSheet()
        }
    }

    private func cycleFrameRate() {
        guard recorder.state == .idle else {
            toastView.show("錄影中無法更改 FPS")
            return
        }
        guard let caps = session.manualCapabilities() else {
            toastView.show("此鏡頭無法調整")
            return
        }
        guard let next = CameraManualControls.nextFrameRate(after: caps.currentFrameRate, in: caps.frameRates) else {
            toastView.show("不支援切換幀率")
            return
        }
        session.setFrameRate(next) { [weak self] success in
            guard let self else { return }
            if success {
                self.refreshTechnicalHUD()
                self.toastView.show("FPS \(Int(next))")
            } else {
                self.toastView.show("設定幀率失敗")
            }
        }
    }

    private func cycleVideoPreset() {
        guard recorder.state == .idle else {
            toastView.show("錄影中無法更改畫質")
            return
        }
        let presets = CameraSettingsStore.VideoPreset.allCases
        let nextIndex = (settings.videoPreset.rawValue + 1) % presets.count
        settings.videoPreset = presets[nextIndex]
        toastView.show("FORMAT \(settings.videoPreset.displayTitle)")
    }

    private func cycleAspectRatio() {
        guard recorder.state == .idle else {
            toastView.show("錄影中無法更改比例")
            return
        }
        let ratios = CameraSettingsStore.AspectRatio.allCases
        let nextIndex = (settings.aspectRatio.rawValue + 1) % ratios.count
        settings.aspectRatio = ratios[nextIndex]
        toastView.show("FRAME \(settings.aspectRatio.displayTitle)")
    }

    private func presentExposureSheet() {
        guard let caps = session.manualCapabilities() else {
            toastView.show("此鏡頭無法手動控制")
            return
        }
        activeSheetControl = .exposure
        manualFPS = caps.currentFrameRate > 0 ? caps.currentFrameRate : 30
        manualISO = CameraManualControls.clamp(caps.currentISO, min: caps.minISO, max: caps.maxISO)
        manualShutterAngle = CameraManualControls.nearestShutterAngle(forSeconds: caps.currentShutterSeconds, fps: manualFPS)
        if recorder.state != .idle, exposureIsAuto {
            toastView.show("錄影中僅能調整已鎖定的 ISO")
            return
        }
        configureExposureSheet(caps: caps)
        showControlSheet()
    }

    private func presentWhiteBalanceSheet() {
        guard recorder.state == .idle else {
            toastView.show("錄影中無法更改白平衡")
            return
        }
        guard let caps = session.manualCapabilities() else {
            toastView.show("此鏡頭無法手動控制")
            return
        }
        guard caps.supportsWhiteBalanceLock else {
            toastView.show("此鏡頭不支援鎖定白平衡")
            return
        }
        activeSheetControl = .whiteBalance
        manualKelvin = CameraManualControls.clamp(manualKelvin, min: caps.minKelvin, max: caps.maxKelvin)
        configureWhiteBalanceSheet(caps: caps)
        showControlSheet()
    }

    private func configureExposureSheet(caps: CameraSession.ManualCapabilities) {
        if exposureIsAuto {
            let evStops = CameraManualControls.exposureBiasStops(min: caps.minBias, max: caps.maxBias)
            let ev = ManualControlSheetView.SliderModel(
                key: "EV", title: "EV",
                minValue: caps.minBias, maxValue: caps.maxBias, value: caps.currentBias,
                steps: evStops,
                display: { String(format: "%+.1f", $0) }
            )
            controlSheet.configure(title: "曝光 EXPOSURE", showsModeToggle: true, isAuto: true, sliders: [ev])
        } else {
            let isoStops = CameraManualControls.isoStops(min: caps.minISO, max: caps.maxISO)
            let iso = ManualControlSheetView.SliderModel(
                key: "ISO", title: "ISO",
                minValue: caps.minISO, maxValue: caps.maxISO, value: manualISO,
                steps: isoStops,
                display: { String(format: "%.0f", $0) }
            )
            let fps = manualFPS
            let angleSteps = CameraManualControls.shutterAngles.map { Float($0) }
            let shutter = ManualControlSheetView.SliderModel(
                key: "SHUTTER", title: "快門",
                minValue: 0, maxValue: Float(max(0, angleSteps.count - 1)), value: Float(manualShutterAngle),
                steps: angleSteps,
                isEnabled: recorder.state == .idle,
                display: { angleValue in
                    let angle = Double(angleValue)
                    let seconds = CameraManualControls.shutterSeconds(forAngle: angle, fps: fps)
                    var text = "\(CameraManualControls.shutterText(forSeconds: seconds)) \(CameraManualControls.angleText(angle))"
                    if CameraManualControls.isFlickerSafe60Hz(seconds: seconds) { text += " ⚡" }
                    return text
                }
            )
            let sliders = recorder.state == .idle ? [iso, shutter] : [iso]
            controlSheet.configure(title: recorder.state == .idle ? "曝光 EXPOSURE" : "錄影中 · ISO", showsModeToggle: recorder.state == .idle && caps.supportsCustomExposure, isAuto: false, sliders: sliders)
        }
    }

    private func configureWhiteBalanceSheet(caps: CameraSession.ManualCapabilities) {
        if whiteBalanceIsAuto {
            controlSheet.configure(title: "白平衡 WHITE BALANCE", showsModeToggle: true, isAuto: true, sliders: [])
        } else {
            let kelvin = ManualControlSheetView.SliderModel(
                key: "WB", title: "色溫",
                minValue: caps.minKelvin, maxValue: caps.maxKelvin, value: manualKelvin,
                steps: CameraManualControls.kelvinStops(min: caps.minKelvin, max: caps.maxKelvin),
                display: { String(format: "%.0fK", $0) }
            )
            controlSheet.configure(title: "白平衡 WHITE BALANCE", showsModeToggle: true, isAuto: false, sliders: [kelvin])
        }
    }

    private func handleSliderChanged(key: String, value: Float) {
        if recorder.state != .idle, key != "ISO" {
            toastView.show("錄影中僅能調整 ISO")
            return
        }
        switch key {
        case "EV":
            session.setExposureBias(value)
        case "ISO":
            manualISO = value
            applyManualExposure()
        case "SHUTTER":
            // value 是吸附後的快門角度，依當前 fps 換算成秒套用。
            manualShutterAngle = Double(value)
            applyManualExposure()
        case "WB":
            manualKelvin = value
            session.setWhiteBalance(kelvin: value)
        default:
            break
        }
    }

    private func applyManualExposure() {
        let seconds = CameraManualControls.shutterSeconds(forAngle: manualShutterAngle, fps: manualFPS)
        session.setManualExposure(iso: manualISO, shutterSeconds: seconds)
    }

    private func handleSheetModeChanged(isAuto: Bool) {
        guard recorder.state == .idle else {
            toastView.show("錄影中無法切換模式")
            return
        }
        guard let control = activeSheetControl, let caps = session.manualCapabilities() else { return }
        switch control {
        case .exposure:
            exposureIsAuto = isAuto
            if isAuto {
                session.setAutoExposure()
            } else {
                applyManualExposure()
            }
            configureExposureSheet(caps: caps)
        case .whiteBalance:
            whiteBalanceIsAuto = isAuto
            if isAuto {
                session.setAutoWhiteBalance()
            } else {
                session.setWhiteBalance(kelvin: manualKelvin)
            }
            configureWhiteBalanceSheet(caps: caps)
        case .format, .frame, .fps:
            break
        }
    }

    private func showControlSheet() {
        view.layoutIfNeeded()
        controlSheet.isHidden = false
        controlSheetBottomConstraint?.constant = -8
        // 面板蓋住底部控制區，把錄影鍵 / 鏡頭按鈕淡出避免視覺重疊。
        UIView.animate(withDuration: 0.25) {
            self.bottomHUDView.alpha = 0
            self.view.layoutIfNeeded()
        }
    }

    private func hideControlSheet() {
        activeSheetControl = nil
        controlSheetBottomConstraint?.constant = 320
        UIView.animate(withDuration: 0.22, animations: {
            self.bottomHUDView.alpha = 1
            self.view.layoutIfNeeded()
        }, completion: { _ in
            self.controlSheet.isHidden = true
            self.refreshTechnicalHUD()
        })
    }

    private func refreshTechnicalHUD() {
        guard let device = session.activeDevice else { return }
        updateHUD(for: device, lensTitle: session.currentLensOption?.title ?? "--")
    }

    // MARK: - Lens buttons

    private func rebuildLensButtons() {
        for arrangedView in lensStackView.arrangedSubviews {
            lensStackView.removeArrangedSubview(arrangedView)
            arrangedView.removeFromSuperview()
        }

        if session.availableLensOptions.isEmpty {
            let label = UILabel()
            label.text = "NO CAMERA"
            label.font = .monospacedSystemFont(ofSize: 13, weight: .semibold)
            label.textAlignment = .center
            label.textColor = .white
            lensStackView.addArrangedSubview(label)
            return
        }

        for (index, option) in session.availableLensOptions.enumerated() {
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
            let isSelected = session.availableLensOptions.indices.contains(index)
                && session.availableLensOptions[index].device.uniqueID == session.currentLensOption?.device.uniqueID
            button.backgroundColor = isSelected ? UIColor.systemBlue : UIColor.black.withAlphaComponent(0.34)
            button.layer.borderColor = (isSelected ? UIColor.systemBlue : UIColor.white.withAlphaComponent(0.42)).cgColor
            button.setTitleColor(.white, for: .normal)
        }
    }

    // MARK: - Record / Delete button states

    private func updateRecordButtonAppearance() {
        switch recorder.state {
        case .idle:
            recordButton.backgroundColor = .systemRed
            recordButton.layer.cornerRadius = 28
            recordButton.isEnabled = session.cameraAuthorized
        case .starting, .stopping:
            recordButton.backgroundColor = UIColor.systemOrange
            recordButton.layer.cornerRadius = 16
            recordButton.isEnabled = false
        case .recording:
            recordButton.backgroundColor = .systemRed
            recordButton.layer.cornerRadius = 16
            recordButton.isEnabled = true
        }

        switch recorder.state {
        case .idle:
            bottomStatusLabel.text = bottomStatusLabel.text ?? "Camera + Mic capture session"
        case .starting:
            bottomStatusLabel.text = "準備開始錄影..."
        case .stopping:
            bottomStatusLabel.text = "停止錄影中..."
        case .recording:
            break  // 由 onStartedFile 回填檔名
        }
    }

    private func updateDeleteLastRecordingButton() {
        let hasLast = lastSavedRecording != nil
        deleteLastRecordingButton.isEnabled = hasLast
        deleteLastRecordingButton.alpha = hasLast ? 1 : 0.35
    }

    // MARK: - Helpers

    private func qualityText() -> String {
        switch session.captureSession.sessionPreset {
        case .hd4K3840x2160: return "4K"
        case .hd1920x1080: return "FHD"
        case .hd1280x720: return "HD"
        default: return settings.videoPreset.displayTitle
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

    private func presentCameraDiagnostics() {
        let report = CameraDiagnostics.report(from: CameraDiagnostics.Inputs(
            recordingState: recorder.state.label,
            quality: qualityText(),
            aspect: settings.aspectRatio.displayTitle,
            lensTitle: session.currentLensOption?.title,
            position: session.currentPosition,
            device: session.currentLensOption?.device,
            audioAuthorized: session.audioAuthorized,
            audioTrackCount: audioMonitor.latestTrackCount
        ))
        let alert = UIAlertController(title: "Camera Diagnostics", message: report, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Close", style: .cancel))
        alert.addAction(UIAlertAction(title: "Copy", style: .default) { [weak self] _ in
            UIPasteboard.general.string = report
            self?.bottomStatusLabel.text = "診斷資訊已複製。"
        })
        present(alert, animated: true)
    }
}
