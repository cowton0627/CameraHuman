//
//  ViewController.swift
//  CameraHuman
//
//  Created by Chun-Li Cheng on 2024/3/13.
//

import UIKit
import AVFoundation

final class ViewController: UIViewController {
    private enum Page: Int {
        case camera
        case sound
    }

    private enum CameraPosition: Int {
        case back
        case front

        var avPosition: AVCaptureDevice.Position {
            self == .back ? .back : .front
        }

        var title: String {
            self == .back ? "相機頁" : "聲音頁"
        }
    }

    private enum LensMode: CaseIterable {
        case portrait
        case wide
        case ultraWide
        case telephoto

        var title: String {
            switch self {
            case .portrait:
                return "人像"
            case .wide:
                return "廣角"
            case .ultraWide:
                return "超廣角"
            case .telephoto:
                return "長焦"
            }
        }
    }

    @IBOutlet private weak var checkButton: UIButton!
    @IBOutlet private weak var captureBtn: UIButton!
    @IBOutlet private weak var stopButton: UIButton!
    @IBOutlet private weak var frameView: UIView!

    private let detector = SoundDetector()

    private let captureSession = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "com.camerahuman.camera-session")
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var currentVideoInput: AVCaptureDeviceInput?
    private var cameraAuthorized = false
    private var currentPosition: AVCaptureDevice.Position = .back
    private var currentLensMode: LensMode = .portrait
    private var availableLensModes: [LensMode] = []
    private var currentPage: Page = .camera
    private var activeAlertThreshold: Float = 65
    private var soundLevelBarHeightConstraint: NSLayoutConstraint?

    private let minimumBarHeight: CGFloat = 16
    private let maximumBarHeight: CGFloat = 240

    private let cameraPageView = UIView()
    private let soundPageView = UIView()

    private let previewContainerView = UIView()
    private let cameraOverlayView = UIView()
    private let cameraStatusLabel = UILabel()
    private let cameraPositionControl = UISegmentedControl(items: ["後鏡頭", "前鏡頭"])
    private let lensModeControl = UISegmentedControl(items: [])
    private let cameraInfoTextView = UITextView()
    private let refreshCameraButton = UIButton(type: .system)

    private let soundHeaderLabel = UILabel()
    private let soundDecibelLabel = UILabel()
    private let soundHelperLabel = UILabel()
    private let thresholdLabel = UILabel()
    private let warningLabel = UILabel()
    private let thresholdSlider = UISlider()
    private let meterContainerView = UIView()
    private let soundLevelBar = UIView()
    private let startMonitoringButton = UIButton(type: .system)
    private let stopMonitoringButton = UIButton(type: .system)

    override func viewDidLoad() {
        super.viewDidLoad()
        configureRootUI()
        configurePages()
        bindDetector()
        updateThresholdUI()
        updateSoundUI(for: .idle)
        switchToPage(.camera)
        refreshLensControl()
        configureCameraPermissionAndSession()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = previewContainerView.bounds
    }

    deinit {
        detector.stopMonitoring()
        stopCameraSession()
    }

    @IBAction private func checkButtonTapped(_ sender: UIButton) {
        switchToPage(.camera)
    }

    @IBAction private func captureBtnTapped(_ sender: UIButton) {
        switchToPage(.sound)
    }

    @IBAction private func stopCaptureTapped(_ sender: UIButton) {
        switchToPage(.camera)
    }

    @objc private func refreshCameraTapped(_ sender: UIButton) {
        cameraInfoTextView.text = buildCameraReport()
    }

    @objc private func startMonitoringTapped(_ sender: UIButton) {
        detector.startMonitoring()
    }

    @objc private func stopMonitoringTapped(_ sender: UIButton) {
        detector.stopMonitoring()
    }

    @objc private func thresholdSliderChanged(_ sender: UISlider) {
        activeAlertThreshold = round(sender.value)
        updateThresholdUI()
    }

    @objc private func cameraPositionChanged(_ sender: UISegmentedControl) {
        currentPosition = sender.selectedSegmentIndex == 0 ? .back : .front
        refreshLensControl()
        configureActiveCamera()
    }

    @objc private func lensModeChanged(_ sender: UISegmentedControl) {
        guard sender.selectedSegmentIndex >= 0, sender.selectedSegmentIndex < availableLensModes.count else { return }
        currentLensMode = availableLensModes[sender.selectedSegmentIndex]
        configureActiveCamera()
    }

    private func configureRootUI() {
        view.backgroundColor = .systemBackground
        frameView.backgroundColor = UIColor.secondarySystemBackground
        frameView.layer.cornerRadius = 24
        frameView.layer.borderWidth = 1
        frameView.layer.borderColor = UIColor.separator.cgColor
        frameView.clipsToBounds = true

        styleTabButton(checkButton, title: "相機頁", isActive: true)
        styleTabButton(captureBtn, title: "聲音頁", isActive: false)
        stopButton.isHidden = true
    }

    private func configurePages() {
        cameraPageView.translatesAutoresizingMaskIntoConstraints = false
        soundPageView.translatesAutoresizingMaskIntoConstraints = false

        frameView.addSubview(cameraPageView)
        frameView.addSubview(soundPageView)

        NSLayoutConstraint.activate([
            cameraPageView.leadingAnchor.constraint(equalTo: frameView.leadingAnchor),
            cameraPageView.trailingAnchor.constraint(equalTo: frameView.trailingAnchor),
            cameraPageView.topAnchor.constraint(equalTo: frameView.topAnchor),
            cameraPageView.bottomAnchor.constraint(equalTo: frameView.bottomAnchor),

            soundPageView.leadingAnchor.constraint(equalTo: frameView.leadingAnchor),
            soundPageView.trailingAnchor.constraint(equalTo: frameView.trailingAnchor),
            soundPageView.topAnchor.constraint(equalTo: frameView.topAnchor),
            soundPageView.bottomAnchor.constraint(equalTo: frameView.bottomAnchor)
        ])

        configureCameraPage()
        configureSoundPage()
    }

    private func configureCameraPage() {
        previewContainerView.translatesAutoresizingMaskIntoConstraints = false
        previewContainerView.backgroundColor = .black
        previewContainerView.layer.cornerRadius = 24
        previewContainerView.clipsToBounds = true

        cameraOverlayView.translatesAutoresizingMaskIntoConstraints = false
        cameraOverlayView.backgroundColor = UIColor.black.withAlphaComponent(0.18)

        cameraStatusLabel.translatesAutoresizingMaskIntoConstraints = false
        cameraStatusLabel.font = .preferredFont(forTextStyle: .title3)
        cameraStatusLabel.textColor = .white
        cameraStatusLabel.numberOfLines = 0
        cameraStatusLabel.text = "相機頁"

        cameraPositionControl.translatesAutoresizingMaskIntoConstraints = false
        cameraPositionControl.selectedSegmentIndex = 0
        cameraPositionControl.backgroundColor = UIColor.black.withAlphaComponent(0.22)
        cameraPositionControl.selectedSegmentTintColor = UIColor.white.withAlphaComponent(0.92)
        cameraPositionControl.addTarget(self, action: #selector(cameraPositionChanged(_:)), for: .valueChanged)

        lensModeControl.translatesAutoresizingMaskIntoConstraints = false
        lensModeControl.backgroundColor = UIColor.black.withAlphaComponent(0.22)
        lensModeControl.selectedSegmentTintColor = UIColor.white.withAlphaComponent(0.92)
        lensModeControl.addTarget(self, action: #selector(lensModeChanged(_:)), for: .valueChanged)

        refreshCameraButton.translatesAutoresizingMaskIntoConstraints = false
        styleActionButton(refreshCameraButton, title: "檢查鏡頭資訊", backgroundColor: .systemIndigo)
        refreshCameraButton.addTarget(self, action: #selector(refreshCameraTapped(_:)), for: .touchUpInside)

        cameraInfoTextView.translatesAutoresizingMaskIntoConstraints = false
        cameraInfoTextView.backgroundColor = UIColor.black.withAlphaComponent(0.22)
        cameraInfoTextView.textColor = .white
        cameraInfoTextView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        cameraInfoTextView.layer.cornerRadius = 18
        cameraInfoTextView.isEditable = false
        cameraInfoTextView.textContainerInset = UIEdgeInsets(top: 12, left: 10, bottom: 12, right: 10)
        cameraInfoTextView.text = """
        這裡是相機頁。

        功能：
        1. 即時相機預覽
        2. 前後鏡頭切換
        3. 人像 / 廣角 / 超廣角 / 長焦模式
        """

        cameraPageView.addSubview(previewContainerView)
        previewContainerView.addSubview(cameraOverlayView)
        cameraPageView.addSubview(cameraStatusLabel)
        cameraPageView.addSubview(cameraPositionControl)
        cameraPageView.addSubview(lensModeControl)
        cameraPageView.addSubview(refreshCameraButton)
        cameraPageView.addSubview(cameraInfoTextView)

        NSLayoutConstraint.activate([
            previewContainerView.leadingAnchor.constraint(equalTo: cameraPageView.leadingAnchor),
            previewContainerView.trailingAnchor.constraint(equalTo: cameraPageView.trailingAnchor),
            previewContainerView.topAnchor.constraint(equalTo: cameraPageView.topAnchor),
            previewContainerView.bottomAnchor.constraint(equalTo: cameraPageView.bottomAnchor),

            cameraOverlayView.leadingAnchor.constraint(equalTo: previewContainerView.leadingAnchor),
            cameraOverlayView.trailingAnchor.constraint(equalTo: previewContainerView.trailingAnchor),
            cameraOverlayView.topAnchor.constraint(equalTo: previewContainerView.topAnchor),
            cameraOverlayView.bottomAnchor.constraint(equalTo: previewContainerView.bottomAnchor),

            cameraStatusLabel.leadingAnchor.constraint(equalTo: cameraPageView.leadingAnchor, constant: 20),
            cameraStatusLabel.topAnchor.constraint(equalTo: cameraPageView.topAnchor, constant: 20),
            cameraStatusLabel.trailingAnchor.constraint(equalTo: cameraPageView.trailingAnchor, constant: -20),

            cameraPositionControl.leadingAnchor.constraint(equalTo: cameraStatusLabel.leadingAnchor),
            cameraPositionControl.trailingAnchor.constraint(equalTo: cameraStatusLabel.trailingAnchor),
            cameraPositionControl.topAnchor.constraint(equalTo: cameraStatusLabel.bottomAnchor, constant: 12),

            lensModeControl.leadingAnchor.constraint(equalTo: cameraStatusLabel.leadingAnchor),
            lensModeControl.trailingAnchor.constraint(equalTo: cameraStatusLabel.trailingAnchor),
            lensModeControl.topAnchor.constraint(equalTo: cameraPositionControl.bottomAnchor, constant: 10),

            refreshCameraButton.leadingAnchor.constraint(equalTo: cameraStatusLabel.leadingAnchor),
            refreshCameraButton.topAnchor.constraint(equalTo: lensModeControl.bottomAnchor, constant: 12),

            cameraInfoTextView.leadingAnchor.constraint(equalTo: cameraStatusLabel.leadingAnchor),
            cameraInfoTextView.trailingAnchor.constraint(equalTo: cameraStatusLabel.trailingAnchor),
            cameraInfoTextView.topAnchor.constraint(equalTo: refreshCameraButton.bottomAnchor, constant: 14),
            cameraInfoTextView.bottomAnchor.constraint(equalTo: cameraPageView.bottomAnchor, constant: -20)
        ])
    }

    private func configureSoundPage() {
        soundPageView.backgroundColor = UIColor.systemBackground

        soundHeaderLabel.translatesAutoresizingMaskIntoConstraints = false
        soundHeaderLabel.font = .preferredFont(forTextStyle: .title2)
        soundHeaderLabel.textColor = .label
        soundHeaderLabel.text = "聲音頁"

        soundDecibelLabel.translatesAutoresizingMaskIntoConstraints = false
        soundDecibelLabel.font = .monospacedDigitSystemFont(ofSize: 38, weight: .bold)
        soundDecibelLabel.textColor = .label
        soundDecibelLabel.text = "--.- dB"

        soundHelperLabel.translatesAutoresizingMaskIntoConstraints = false
        soundHelperLabel.font = .preferredFont(forTextStyle: .footnote)
        soundHelperLabel.textColor = .secondaryLabel
        soundHelperLabel.numberOfLines = 0

        thresholdLabel.translatesAutoresizingMaskIntoConstraints = false
        thresholdLabel.font = .preferredFont(forTextStyle: .caption1)
        thresholdLabel.textColor = .secondaryLabel

        warningLabel.translatesAutoresizingMaskIntoConstraints = false
        warningLabel.font = .preferredFont(forTextStyle: .caption1)
        warningLabel.textColor = .white
        warningLabel.backgroundColor = .systemRed
        warningLabel.layer.cornerRadius = 10
        warningLabel.clipsToBounds = true
        warningLabel.numberOfLines = 2
        warningLabel.textAlignment = .center

        thresholdSlider.translatesAutoresizingMaskIntoConstraints = false
        thresholdSlider.minimumValue = 45
        thresholdSlider.maximumValue = 90
        thresholdSlider.value = activeAlertThreshold
        thresholdSlider.addTarget(self, action: #selector(thresholdSliderChanged(_:)), for: .valueChanged)

        meterContainerView.translatesAutoresizingMaskIntoConstraints = false
        meterContainerView.backgroundColor = UIColor.systemGray5
        meterContainerView.layer.cornerRadius = 20

        soundLevelBar.translatesAutoresizingMaskIntoConstraints = false
        soundLevelBar.backgroundColor = .systemGreen
        soundLevelBar.layer.cornerRadius = 20

        startMonitoringButton.translatesAutoresizingMaskIntoConstraints = false
        styleActionButton(startMonitoringButton, title: "開始監測", backgroundColor: .systemGreen)
        startMonitoringButton.addTarget(self, action: #selector(startMonitoringTapped(_:)), for: .touchUpInside)

        stopMonitoringButton.translatesAutoresizingMaskIntoConstraints = false
        styleActionButton(stopMonitoringButton, title: "停止監測", backgroundColor: .systemGray)
        stopMonitoringButton.addTarget(self, action: #selector(stopMonitoringTapped(_:)), for: .touchUpInside)

        soundPageView.addSubview(soundHeaderLabel)
        soundPageView.addSubview(soundDecibelLabel)
        soundPageView.addSubview(soundHelperLabel)
        soundPageView.addSubview(warningLabel)
        soundPageView.addSubview(thresholdLabel)
        soundPageView.addSubview(thresholdSlider)
        soundPageView.addSubview(meterContainerView)
        meterContainerView.addSubview(soundLevelBar)
        soundPageView.addSubview(startMonitoringButton)
        soundPageView.addSubview(stopMonitoringButton)

        soundLevelBarHeightConstraint = soundLevelBar.heightAnchor.constraint(equalToConstant: minimumBarHeight)
        soundLevelBarHeightConstraint?.isActive = true

        NSLayoutConstraint.activate([
            soundHeaderLabel.leadingAnchor.constraint(equalTo: soundPageView.leadingAnchor, constant: 20),
            soundHeaderLabel.topAnchor.constraint(equalTo: soundPageView.topAnchor, constant: 24),
            soundHeaderLabel.trailingAnchor.constraint(equalTo: soundPageView.trailingAnchor, constant: -20),

            soundDecibelLabel.leadingAnchor.constraint(equalTo: soundHeaderLabel.leadingAnchor),
            soundDecibelLabel.topAnchor.constraint(equalTo: soundHeaderLabel.bottomAnchor, constant: 12),

            soundHelperLabel.leadingAnchor.constraint(equalTo: soundHeaderLabel.leadingAnchor),
            soundHelperLabel.trailingAnchor.constraint(equalTo: soundHeaderLabel.trailingAnchor),
            soundHelperLabel.topAnchor.constraint(equalTo: soundDecibelLabel.bottomAnchor, constant: 10),

            warningLabel.leadingAnchor.constraint(equalTo: soundHeaderLabel.leadingAnchor),
            warningLabel.topAnchor.constraint(equalTo: soundHelperLabel.bottomAnchor, constant: 10),
            warningLabel.trailingAnchor.constraint(lessThanOrEqualTo: soundHeaderLabel.trailingAnchor),

            thresholdLabel.leadingAnchor.constraint(equalTo: soundHeaderLabel.leadingAnchor),
            thresholdLabel.trailingAnchor.constraint(equalTo: soundHeaderLabel.trailingAnchor),
            thresholdLabel.topAnchor.constraint(equalTo: warningLabel.bottomAnchor, constant: 14),

            thresholdSlider.leadingAnchor.constraint(equalTo: soundHeaderLabel.leadingAnchor),
            thresholdSlider.trailingAnchor.constraint(equalTo: soundHeaderLabel.trailingAnchor),
            thresholdSlider.topAnchor.constraint(equalTo: thresholdLabel.bottomAnchor, constant: 8),

            meterContainerView.leadingAnchor.constraint(equalTo: soundHeaderLabel.leadingAnchor),
            meterContainerView.topAnchor.constraint(equalTo: thresholdSlider.bottomAnchor, constant: 26),
            meterContainerView.widthAnchor.constraint(equalToConstant: 96),
            meterContainerView.heightAnchor.constraint(equalToConstant: maximumBarHeight),

            soundLevelBar.leadingAnchor.constraint(equalTo: meterContainerView.leadingAnchor),
            soundLevelBar.trailingAnchor.constraint(equalTo: meterContainerView.trailingAnchor),
            soundLevelBar.bottomAnchor.constraint(equalTo: meterContainerView.bottomAnchor),

            startMonitoringButton.leadingAnchor.constraint(equalTo: meterContainerView.trailingAnchor, constant: 20),
            startMonitoringButton.topAnchor.constraint(equalTo: meterContainerView.topAnchor),

            stopMonitoringButton.leadingAnchor.constraint(equalTo: startMonitoringButton.leadingAnchor),
            stopMonitoringButton.topAnchor.constraint(equalTo: startMonitoringButton.bottomAnchor, constant: 12),
            stopMonitoringButton.trailingAnchor.constraint(lessThanOrEqualTo: soundHeaderLabel.trailingAnchor)
        ])
    }

    private func bindDetector() {
        detector.onStateChange = { [weak self] state in
            self?.updateSoundUI(for: state)
        }

        detector.onLevelUpdate = { [weak self] snapshot in
            self?.updateMeter(using: snapshot)
        }
    }

    private func switchToPage(_ page: Page) {
        currentPage = page
        cameraPageView.isHidden = page != .camera
        soundPageView.isHidden = page != .sound
        styleTabButton(checkButton, title: "相機頁", isActive: page == .camera)
        styleTabButton(captureBtn, title: "聲音頁", isActive: page == .sound)
    }

    private func configureCameraPermissionAndSession() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            cameraAuthorized = true
            configureActiveCamera()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    self?.cameraAuthorized = granted
                    if granted {
                        self?.configureActiveCamera()
                    } else {
                        self?.cameraInfoTextView.text = "沒有相機權限，請到設定開啟 CameraHuman 的相機存取。"
                    }
                }
            }
        case .denied, .restricted:
            cameraInfoTextView.text = "沒有相機權限，請到設定開啟 CameraHuman 的相機存取。"
        @unknown default:
            cameraInfoTextView.text = "相機權限狀態未知。"
        }
    }

    private func configureActiveCamera() {
        guard cameraAuthorized else { return }
        guard let device = preferredDevice(for: currentPosition, mode: currentLensMode) else {
            cameraInfoTextView.text = "目前裝置沒有 \(currentLensMode.title) 可用鏡頭。"
            return
        }

        sessionQueue.async { [weak self] in
            guard let self else { return }

            do {
                let newInput = try AVCaptureDeviceInput(device: device)
                self.captureSession.beginConfiguration()
                self.captureSession.sessionPreset = .high

                if let currentInput = self.currentVideoInput {
                    self.captureSession.removeInput(currentInput)
                }

                if self.captureSession.canAddInput(newInput) {
                    self.captureSession.addInput(newInput)
                    self.currentVideoInput = newInput
                }

                self.captureSession.commitConfiguration()
                self.startCameraSessionIfNeeded()

                DispatchQueue.main.async {
                    self.attachPreviewIfNeeded()
                    self.cameraInfoTextView.text = self.cameraSummary(for: device)
                }
            } catch {
                DispatchQueue.main.async {
                    self.cameraInfoTextView.text = "啟用相機失敗：\(error.localizedDescription)"
                }
            }
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

    private func refreshLensControl() {
        availableLensModes = LensMode.allCases.filter { preferredDevice(for: currentPosition, mode: $0) != nil }
        if availableLensModes.isEmpty {
            availableLensModes = [.wide]
        }

        if !availableLensModes.contains(currentLensMode) {
            currentLensMode = availableLensModes[0]
        }

        lensModeControl.removeAllSegments()
        for (index, mode) in availableLensModes.enumerated() {
            lensModeControl.insertSegment(withTitle: mode.title, at: index, animated: false)
        }
        lensModeControl.selectedSegmentIndex = availableLensModes.firstIndex(of: currentLensMode) ?? 0
    }

    private func preferredDevice(for position: AVCaptureDevice.Position, mode: LensMode) -> AVCaptureDevice? {
        let prioritizedTypes: [AVCaptureDevice.DeviceType]

        switch (position, mode) {
        case (.front, .portrait):
            prioritizedTypes = [.builtInTrueDepthCamera, .builtInWideAngleCamera]
        case (.front, _):
            prioritizedTypes = [.builtInTrueDepthCamera, .builtInWideAngleCamera]
        case (.back, .portrait):
            prioritizedTypes = [.builtInDualCamera, .builtInTripleCamera, .builtInDualWideCamera, .builtInTelephotoCamera, .builtInWideAngleCamera]
        case (.back, .wide):
            prioritizedTypes = [.builtInWideAngleCamera, .builtInDualWideCamera, .builtInTripleCamera]
        case (.back, .ultraWide):
            prioritizedTypes = [.builtInUltraWideCamera, .builtInTripleCamera, .builtInDualWideCamera]
        case (.back, .telephoto):
            prioritizedTypes = [.builtInTelephotoCamera, .builtInDualCamera, .builtInTripleCamera]
        default:
            prioritizedTypes = [.builtInWideAngleCamera]
        }

        for type in prioritizedTypes {
            if let device = AVCaptureDevice.default(type, for: .video, position: position) {
                return device
            }
        }

        return AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position)
    }

    private func cameraSummary(for device: AVCaptureDevice) -> String {
        let aperture = device.lensAperture > 0 ? String(format: "f/%.1f", device.lensAperture) : "未知"
        let zoom = String(format: "%.1fx", device.activeFormat.videoMaxZoomFactor)
        let positionText = currentPosition == .front ? "前置" : "後置"

        return """
        目前相機已啟用

        鏡頭位置：\(positionText)
        模式：\(currentLensMode.title)
        裝置：\(device.localizedName)
        類型：\(device.deviceType.rawValue)
        光圈：\(aperture)
        最大變焦：\(zoom)
        """
    }

    private func updateSoundUI(for state: SoundDetector.State) {
        switch state {
        case .idle:
            soundHelperLabel.text = "這裡是聲音頁。按下開始後會監測環境音量並依門檻提醒。"
            soundDecibelLabel.text = "--.- dB"
            startMonitoringButton.isEnabled = true
            stopMonitoringButton.isEnabled = false
            updateMeterAppearance(color: .systemGreen)
            updateMeterHeight(minimumBarHeight)
            updateWarningLabel(isTooLoud: false, decibels: nil)
        case .requestingPermission:
            soundHelperLabel.text = "要求麥克風權限中，請在系統提示中允許存取。"
            startMonitoringButton.isEnabled = false
            stopMonitoringButton.isEnabled = false
            updateMeterAppearance(color: .systemOrange)
        case .running:
            soundHelperLabel.text = "超過 \(Int(activeAlertThreshold)) dB 會顯示過大提醒。"
            startMonitoringButton.isEnabled = false
            stopMonitoringButton.isEnabled = true
        case .permissionDenied:
            soundHelperLabel.text = "沒有麥克風權限，請到設定開啟 CameraHuman 的麥克風存取。"
            soundDecibelLabel.text = "--.- dB"
            startMonitoringButton.isEnabled = true
            stopMonitoringButton.isEnabled = false
            updateMeterAppearance(color: .systemRed)
            updateMeterHeight(minimumBarHeight)
            updateWarningLabel(isTooLoud: false, decibels: nil)
        case .failed(let message):
            soundHelperLabel.text = "啟動失敗：\(message)"
            startMonitoringButton.isEnabled = true
            stopMonitoringButton.isEnabled = false
            updateMeterAppearance(color: .systemRed)
            updateWarningLabel(isTooLoud: false, decibels: nil)
        }

        startMonitoringButton.alpha = startMonitoringButton.isEnabled ? 1 : 0.6
        stopMonitoringButton.alpha = stopMonitoringButton.isEnabled ? 1 : 0.6
    }

    private func updateMeter(using snapshot: SoundDetector.LevelSnapshot) {
        soundDecibelLabel.text = String(format: "%.1f dB", snapshot.decibels)

        let newHeight = minimumBarHeight + (maximumBarHeight - minimumBarHeight) * CGFloat(snapshot.normalizedLevel)
        updateMeterHeight(newHeight)

        let isTooLoud = snapshot.decibels >= activeAlertThreshold
        updateWarningLabel(isTooLoud: isTooLoud, decibels: snapshot.decibels)

        if isTooLoud {
            updateMeterAppearance(color: .systemRed)
        } else if snapshot.normalizedLevel > 0.45 {
            updateMeterAppearance(color: .systemOrange)
        } else {
            updateMeterAppearance(color: .systemGreen)
        }
    }

    private func updateThresholdUI() {
        thresholdLabel.text = "過大提醒門檻：\(Int(activeAlertThreshold)) dB"
    }

    private func updateWarningLabel(isTooLoud: Bool, decibels: Float?) {
        if isTooLoud, let decibels {
            warningLabel.text = String(format: "聲音過大 %.1f dB\n請留意目前環境音量", decibels)
            warningLabel.isHidden = false
        } else {
            warningLabel.isHidden = true
        }
    }

    private func updateMeterHeight(_ height: CGFloat) {
        soundLevelBarHeightConstraint?.constant = max(minimumBarHeight, min(maximumBarHeight, height))
        UIView.animate(withDuration: 0.12) {
            self.soundPageView.layoutIfNeeded()
        }
    }

    private func updateMeterAppearance(color: UIColor) {
        soundLevelBar.backgroundColor = color
    }

    private func buildCameraReport() -> String {
        let deviceTypes: [AVCaptureDevice.DeviceType] = [
            .builtInWideAngleCamera,
            .builtInUltraWideCamera,
            .builtInTelephotoCamera,
            .builtInDualCamera,
            .builtInDualWideCamera,
            .builtInTripleCamera,
            .builtInTrueDepthCamera
        ]

        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: deviceTypes,
            mediaType: .video,
            position: .unspecified
        )

        let devices = discoverySession.devices
        guard !devices.isEmpty else {
            return "找不到可用鏡頭。"
        }

        let frontCount = devices.filter { $0.position == .front }.count
        let backCount = devices.filter { $0.position == .back }.count

        var lines = [
            "鏡頭檢查結果",
            "前鏡頭: \(frontCount) 顆",
            "後鏡頭: \(backCount) 顆",
            ""
        ]

        for (index, device) in devices.enumerated() {
            let position: String
            switch device.position {
            case .front:
                position = "前置"
            case .back:
                position = "後置"
            case .unspecified:
                position = "未指定"
            @unknown default:
                position = "未知"
            }

            let aperture = device.lensAperture > 0 ? String(format: "f/%.1f", device.lensAperture) : "未知"
            let zoom = String(format: "%.1fx", device.activeFormat.videoMaxZoomFactor)

            lines.append("""
            \(index + 1). \(position) | \(device.localizedName)
               類型: \(device.deviceType.rawValue)
               光圈: \(aperture)
               最大變焦: \(zoom)
            """)
        }

        return lines.joined(separator: "\n")
    }

    private func styleTabButton(_ button: UIButton, title: String, isActive: Bool) {
        button.setTitle(title, for: .normal)
        button.setTitleColor(isActive ? .white : .label, for: .normal)
        button.backgroundColor = isActive ? .systemBlue : UIColor.systemGray5
        button.layer.cornerRadius = 14
        button.contentEdgeInsets = UIEdgeInsets(top: 12, left: 18, bottom: 12, right: 18)
    }

    private func styleActionButton(_ button: UIButton, title: String, backgroundColor: UIColor) {
        button.setTitle(title, for: .normal)
        button.setTitleColor(.white, for: .normal)
        button.backgroundColor = backgroundColor
        button.layer.cornerRadius = 14
        button.contentEdgeInsets = UIEdgeInsets(top: 12, left: 18, bottom: 12, right: 18)
    }
}
