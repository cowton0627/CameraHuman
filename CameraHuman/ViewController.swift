//
//  ViewController.swift
//  CameraHuman
//
//  Created by Chun-Li Cheng on 2024/3/13.
//

import UIKit
import AVFoundation

final class ViewController: UIViewController {
    private enum CameraPosition: Int {
        case back
        case front

        var avPosition: AVCaptureDevice.Position {
            switch self {
            case .back:
                return .back
            case .front:
                return .front
            }
        }

        var title: String {
            switch self {
            case .back:
                return "後鏡頭"
            case .front:
                return "前鏡頭"
            }
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
    private var currentPosition: CameraPosition = .back
    private var currentLensMode: LensMode = .portrait
    private var availableLensModes: [LensMode] = []

    private let previewContainerView = UIView()
    private let overlayView = UIView()
    private let controlPanelView = UIStackView()
    private let meterContainerView = UIView()
    private let soundLevelBar = UIView()
    private let statusLabel = UILabel()
    private let decibelLabel = UILabel()
    private let helperLabel = UILabel()
    private let thresholdLabel = UILabel()
    private let warningLabel = UILabel()
    private let thresholdSlider = UISlider()
    private let positionControl = UISegmentedControl(items: [])
    private let lensModeControl = UISegmentedControl(items: [])
    private let deviceInfoTextView = UITextView()

    private var soundLevelBarHeightConstraint: NSLayoutConstraint?
    private var activeAlertThreshold: Float = 65

    private let minimumBarHeight: CGFloat = 16
    private let maximumBarHeight: CGFloat = 220

    override func viewDidLoad() {
        super.viewDidLoad()
        configureUI()
        bindDetector()
        updateThresholdUI()
        updateWarningLabel(isTooLoud: false, decibels: nil)
        updateUI(for: .idle)
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
        deviceInfoTextView.text = buildCameraReport()
    }

    @IBAction private func captureBtnTapped(_ sender: UIButton) {
        detector.startMonitoring()
    }

    @IBAction private func stopCaptureTapped(_ sender: UIButton) {
        detector.stopMonitoring()
    }

    @objc private func thresholdSliderChanged(_ sender: UISlider) {
        activeAlertThreshold = round(sender.value)
        updateThresholdUI()
    }

    @objc private func positionChanged(_ sender: UISegmentedControl) {
        guard let selectedPosition = CameraPosition(rawValue: sender.selectedSegmentIndex) else { return }
        currentPosition = selectedPosition
        refreshLensControl()
        configureActiveCamera()
    }

    @objc private func lensModeChanged(_ sender: UISegmentedControl) {
        guard sender.selectedSegmentIndex >= 0, sender.selectedSegmentIndex < availableLensModes.count else { return }
        currentLensMode = availableLensModes[sender.selectedSegmentIndex]
        configureActiveCamera()
    }

    private func configureUI() {
        view.backgroundColor = .systemBackground
        frameView.backgroundColor = UIColor.secondarySystemBackground
        frameView.layer.cornerRadius = 24
        frameView.layer.borderWidth = 1
        frameView.layer.borderColor = UIColor.separator.cgColor
        frameView.clipsToBounds = true

        configurePreview()
        configureButtons()
        configureLabels()
        configureControls()
        configureMeter()
        configureDeviceInfoView()
    }

    private func configurePreview() {
        previewContainerView.translatesAutoresizingMaskIntoConstraints = false
        previewContainerView.backgroundColor = .black
        previewContainerView.layer.cornerRadius = 24
        previewContainerView.clipsToBounds = true

        overlayView.translatesAutoresizingMaskIntoConstraints = false
        overlayView.backgroundColor = UIColor.black.withAlphaComponent(0.18)

        frameView.insertSubview(previewContainerView, at: 0)
        previewContainerView.addSubview(overlayView)

        NSLayoutConstraint.activate([
            previewContainerView.leadingAnchor.constraint(equalTo: frameView.leadingAnchor),
            previewContainerView.trailingAnchor.constraint(equalTo: frameView.trailingAnchor),
            previewContainerView.topAnchor.constraint(equalTo: frameView.topAnchor),
            previewContainerView.bottomAnchor.constraint(equalTo: frameView.bottomAnchor),

            overlayView.leadingAnchor.constraint(equalTo: previewContainerView.leadingAnchor),
            overlayView.trailingAnchor.constraint(equalTo: previewContainerView.trailingAnchor),
            overlayView.topAnchor.constraint(equalTo: previewContainerView.topAnchor),
            overlayView.bottomAnchor.constraint(equalTo: previewContainerView.bottomAnchor)
        ])
    }

    private func configureButtons() {
        styleButton(checkButton, title: "檢查鏡頭", backgroundColor: .systemIndigo)
        styleButton(captureBtn, title: "開始監測", backgroundColor: .systemGreen)
        styleButton(stopButton, title: "停止", backgroundColor: .systemGray)
    }

    private func configureLabels() {
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.font = .preferredFont(forTextStyle: .title3)
        statusLabel.textColor = .white
        statusLabel.numberOfLines = 0

        decibelLabel.translatesAutoresizingMaskIntoConstraints = false
        decibelLabel.font = .monospacedDigitSystemFont(ofSize: 34, weight: .bold)
        decibelLabel.textColor = .white

        helperLabel.translatesAutoresizingMaskIntoConstraints = false
        helperLabel.font = .preferredFont(forTextStyle: .footnote)
        helperLabel.textColor = UIColor.white.withAlphaComponent(0.88)
        helperLabel.numberOfLines = 0

        warningLabel.translatesAutoresizingMaskIntoConstraints = false
        warningLabel.font = .preferredFont(forTextStyle: .caption1)
        warningLabel.textAlignment = .center
        warningLabel.textColor = .white
        warningLabel.backgroundColor = UIColor.systemRed.withAlphaComponent(0.88)
        warningLabel.layer.cornerRadius = 10
        warningLabel.clipsToBounds = true
        warningLabel.numberOfLines = 2

        thresholdLabel.translatesAutoresizingMaskIntoConstraints = false
        thresholdLabel.font = .preferredFont(forTextStyle: .caption1)
        thresholdLabel.textColor = UIColor.white.withAlphaComponent(0.95)

        frameView.addSubview(statusLabel)
        frameView.addSubview(decibelLabel)
        frameView.addSubview(helperLabel)
        frameView.addSubview(warningLabel)
        frameView.addSubview(thresholdLabel)

        NSLayoutConstraint.activate([
            statusLabel.leadingAnchor.constraint(equalTo: frameView.leadingAnchor, constant: 20),
            statusLabel.topAnchor.constraint(equalTo: frameView.topAnchor, constant: 20),
            statusLabel.trailingAnchor.constraint(equalTo: frameView.trailingAnchor, constant: -20),

            decibelLabel.leadingAnchor.constraint(equalTo: statusLabel.leadingAnchor),
            decibelLabel.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 8),

            helperLabel.leadingAnchor.constraint(equalTo: statusLabel.leadingAnchor),
            helperLabel.topAnchor.constraint(equalTo: decibelLabel.bottomAnchor, constant: 8),
            helperLabel.trailingAnchor.constraint(equalTo: statusLabel.trailingAnchor),

            warningLabel.leadingAnchor.constraint(equalTo: statusLabel.leadingAnchor),
            warningLabel.topAnchor.constraint(equalTo: helperLabel.bottomAnchor, constant: 10),
            warningLabel.trailingAnchor.constraint(lessThanOrEqualTo: frameView.trailingAnchor, constant: -20),

            thresholdLabel.leadingAnchor.constraint(equalTo: statusLabel.leadingAnchor),
            thresholdLabel.topAnchor.constraint(equalTo: warningLabel.bottomAnchor, constant: 12),
            thresholdLabel.trailingAnchor.constraint(equalTo: statusLabel.trailingAnchor)
        ])
    }

    private func configureControls() {
        thresholdSlider.translatesAutoresizingMaskIntoConstraints = false
        thresholdSlider.minimumValue = 45
        thresholdSlider.maximumValue = 90
        thresholdSlider.value = activeAlertThreshold
        thresholdSlider.minimumTrackTintColor = .systemYellow
        thresholdSlider.maximumTrackTintColor = UIColor.white.withAlphaComponent(0.25)
        thresholdSlider.addTarget(self, action: #selector(thresholdSliderChanged(_:)), for: .valueChanged)

        positionControl.translatesAutoresizingMaskIntoConstraints = false
        positionControl.insertSegment(withTitle: CameraPosition.back.title, at: 0, animated: false)
        positionControl.insertSegment(withTitle: CameraPosition.front.title, at: 1, animated: false)
        positionControl.selectedSegmentIndex = currentPosition.rawValue
        positionControl.backgroundColor = UIColor.black.withAlphaComponent(0.22)
        positionControl.selectedSegmentTintColor = UIColor.white.withAlphaComponent(0.9)
        positionControl.addTarget(self, action: #selector(positionChanged(_:)), for: .valueChanged)

        lensModeControl.translatesAutoresizingMaskIntoConstraints = false
        lensModeControl.backgroundColor = UIColor.black.withAlphaComponent(0.22)
        lensModeControl.selectedSegmentTintColor = UIColor.white.withAlphaComponent(0.9)
        lensModeControl.addTarget(self, action: #selector(lensModeChanged(_:)), for: .valueChanged)

        controlPanelView.translatesAutoresizingMaskIntoConstraints = false
        controlPanelView.axis = .vertical
        controlPanelView.spacing = 10

        frameView.addSubview(thresholdSlider)
        frameView.addSubview(positionControl)
        frameView.addSubview(lensModeControl)

        NSLayoutConstraint.activate([
            thresholdSlider.leadingAnchor.constraint(equalTo: thresholdLabel.leadingAnchor),
            thresholdSlider.trailingAnchor.constraint(equalTo: thresholdLabel.trailingAnchor),
            thresholdSlider.topAnchor.constraint(equalTo: thresholdLabel.bottomAnchor, constant: 6),

            positionControl.leadingAnchor.constraint(equalTo: thresholdSlider.leadingAnchor),
            positionControl.trailingAnchor.constraint(equalTo: thresholdSlider.trailingAnchor),
            positionControl.topAnchor.constraint(equalTo: thresholdSlider.bottomAnchor, constant: 14),

            lensModeControl.leadingAnchor.constraint(equalTo: thresholdSlider.leadingAnchor),
            lensModeControl.trailingAnchor.constraint(equalTo: thresholdSlider.trailingAnchor),
            lensModeControl.topAnchor.constraint(equalTo: positionControl.bottomAnchor, constant: 10)
        ])
    }

    private func configureMeter() {
        meterContainerView.translatesAutoresizingMaskIntoConstraints = false
        meterContainerView.backgroundColor = UIColor.white.withAlphaComponent(0.14)
        meterContainerView.layer.cornerRadius = 18

        soundLevelBar.translatesAutoresizingMaskIntoConstraints = false
        soundLevelBar.backgroundColor = .systemGreen
        soundLevelBar.layer.cornerRadius = 18

        frameView.addSubview(meterContainerView)
        meterContainerView.addSubview(soundLevelBar)

        soundLevelBarHeightConstraint = soundLevelBar.heightAnchor.constraint(equalToConstant: minimumBarHeight)
        soundLevelBarHeightConstraint?.isActive = true

        NSLayoutConstraint.activate([
            meterContainerView.leadingAnchor.constraint(equalTo: frameView.leadingAnchor, constant: 20),
            meterContainerView.bottomAnchor.constraint(equalTo: frameView.bottomAnchor, constant: -28),
            meterContainerView.widthAnchor.constraint(equalToConstant: 84),
            meterContainerView.heightAnchor.constraint(equalToConstant: maximumBarHeight),

            soundLevelBar.leadingAnchor.constraint(equalTo: meterContainerView.leadingAnchor),
            soundLevelBar.trailingAnchor.constraint(equalTo: meterContainerView.trailingAnchor),
            soundLevelBar.bottomAnchor.constraint(equalTo: meterContainerView.bottomAnchor)
        ])
    }

    private func configureDeviceInfoView() {
        deviceInfoTextView.translatesAutoresizingMaskIntoConstraints = false
        deviceInfoTextView.backgroundColor = UIColor.black.withAlphaComponent(0.22)
        deviceInfoTextView.textColor = .white
        deviceInfoTextView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        deviceInfoTextView.layer.cornerRadius = 18
        deviceInfoTextView.isEditable = false
        deviceInfoTextView.isScrollEnabled = true
        deviceInfoTextView.textContainerInset = UIEdgeInsets(top: 12, left: 10, bottom: 12, right: 10)
        deviceInfoTextView.text = """
        歡迎使用 CameraHuman。

        已新增功能：
        1. 即時相機預覽
        2. 前後鏡頭切換
        3. 人像 / 廣角 / 超廣角 / 長焦模式
        4. 聲音過大門檻提醒
        """

        frameView.addSubview(deviceInfoTextView)

        NSLayoutConstraint.activate([
            deviceInfoTextView.leadingAnchor.constraint(equalTo: meterContainerView.trailingAnchor, constant: 20),
            deviceInfoTextView.trailingAnchor.constraint(equalTo: frameView.trailingAnchor, constant: -20),
            deviceInfoTextView.topAnchor.constraint(equalTo: lensModeControl.bottomAnchor, constant: 14),
            deviceInfoTextView.bottomAnchor.constraint(equalTo: frameView.bottomAnchor, constant: -20)
        ])
    }

    private func bindDetector() {
        detector.onStateChange = { [weak self] state in
            self?.updateUI(for: state)
        }

        detector.onLevelUpdate = { [weak self] snapshot in
            self?.updateMeter(using: snapshot)
        }
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
                        self?.deviceInfoTextView.text = "沒有相機權限，請到設定開啟 CameraHuman 的相機存取。"
                    }
                }
            }
        case .denied, .restricted:
            deviceInfoTextView.text = "沒有相機權限，請到設定開啟 CameraHuman 的相機存取。"
        @unknown default:
            deviceInfoTextView.text = "相機權限狀態未知。"
        }
    }

    private func configureActiveCamera() {
        guard cameraAuthorized else { return }
        guard let device = preferredDevice(for: currentPosition, mode: currentLensMode) else {
            deviceInfoTextView.text = "目前裝置沒有 \(currentLensMode.title) 可用鏡頭。"
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
                    self.deviceInfoTextView.text = self.cameraSummary(for: device)
                }
            } catch {
                DispatchQueue.main.async {
                    self.deviceInfoTextView.text = "啟用相機失敗：\(error.localizedDescription)"
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

    private func preferredDevice(for position: CameraPosition, mode: LensMode) -> AVCaptureDevice? {
        let prioritizedTypes: [AVCaptureDevice.DeviceType]

        switch (position, mode) {
        case (.front, .portrait):
            prioritizedTypes = [.builtInTrueDepthCamera, .builtInWideAngleCamera]
        case (.front, .wide), (.front, .ultraWide), (.front, .telephoto):
            prioritizedTypes = [.builtInTrueDepthCamera, .builtInWideAngleCamera]
        case (.back, .portrait):
            prioritizedTypes = [.builtInDualCamera, .builtInTripleCamera, .builtInDualWideCamera, .builtInTelephotoCamera, .builtInWideAngleCamera]
        case (.back, .wide):
            prioritizedTypes = [.builtInWideAngleCamera, .builtInDualWideCamera, .builtInTripleCamera]
        case (.back, .ultraWide):
            prioritizedTypes = [.builtInUltraWideCamera, .builtInTripleCamera, .builtInDualWideCamera]
        case (.back, .telephoto):
            prioritizedTypes = [.builtInTelephotoCamera, .builtInDualCamera, .builtInTripleCamera]
        }

        for type in prioritizedTypes {
            if let device = AVCaptureDevice.default(type, for: .video, position: position.avPosition) {
                return device
            }
        }

        return AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position.avPosition)
    }

    private func cameraSummary(for device: AVCaptureDevice) -> String {
        let aperture = device.lensAperture > 0 ? String(format: "f/%.1f", device.lensAperture) : "未知"
        let zoom = String(format: "%.1fx", device.activeFormat.videoMaxZoomFactor)

        return """
        目前相機已啟用

        鏡頭位置：\(currentPosition.title)
        模式：\(currentLensMode.title)
        裝置：\(device.localizedName)
        類型：\(device.deviceType.rawValue)
        光圈：\(aperture)
        最大變焦：\(zoom)

        人像模式會優先挑選 TrueDepth / 雙鏡頭 / 三鏡頭等較適合拍攝人物的裝置；若裝置不支援，會自動退回可用鏡頭。
        """
    }

    private func updateUI(for state: SoundDetector.State) {
        switch state {
        case .idle:
            statusLabel.text = "待機中"
            helperLabel.text = "相機預覽已啟用。按下「開始監測」後，會顯示即時音量並依門檻提醒。"
            captureBtn.isEnabled = true
            stopButton.isEnabled = false
            decibelLabel.text = "--.- dB"
            updateMeterAppearance(color: .systemGreen)
            updateMeterHeight(minimumBarHeight)
            updateWarningLabel(isTooLoud: false, decibels: nil)
        case .requestingPermission:
            statusLabel.text = "要求麥克風權限中"
            helperLabel.text = "請在系統提示中允許麥克風存取。"
            captureBtn.isEnabled = false
            stopButton.isEnabled = false
            updateMeterAppearance(color: .systemOrange)
            updateWarningLabel(isTooLoud: false, decibels: nil)
        case .running:
            statusLabel.text = "正在監測環境聲音"
            helperLabel.text = "超過 \(Int(activeAlertThreshold)) dB 會出現過大提醒，鏡頭模式可隨時切換。"
            captureBtn.isEnabled = false
            stopButton.isEnabled = true
        case .permissionDenied:
            statusLabel.text = "沒有麥克風權限"
            helperLabel.text = "請到 iPhone 的「設定 > CameraHuman > 麥克風」開啟權限後再試。"
            captureBtn.isEnabled = true
            stopButton.isEnabled = false
            decibelLabel.text = "--.- dB"
            updateMeterAppearance(color: .systemRed)
            updateMeterHeight(minimumBarHeight)
            updateWarningLabel(isTooLoud: false, decibels: nil)
        case .failed(let message):
            statusLabel.text = "啟動失敗"
            helperLabel.text = message
            captureBtn.isEnabled = true
            stopButton.isEnabled = false
            updateMeterAppearance(color: .systemRed)
            updateWarningLabel(isTooLoud: false, decibels: nil)
        }

        captureBtn.alpha = captureBtn.isEnabled ? 1 : 0.6
        stopButton.alpha = stopButton.isEnabled ? 1 : 0.6
    }

    private func updateMeter(using snapshot: SoundDetector.LevelSnapshot) {
        decibelLabel.text = String(format: "%.1f dB", snapshot.decibels)

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
            frameView.layer.borderColor = UIColor.systemRed.cgColor
            overlayView.backgroundColor = UIColor.systemRed.withAlphaComponent(0.16)
        } else {
            warningLabel.text = "音量正常"
            warningLabel.isHidden = true
            frameView.layer.borderColor = UIColor.separator.cgColor
            overlayView.backgroundColor = UIColor.black.withAlphaComponent(0.18)
        }
    }

    private func updateMeterHeight(_ height: CGFloat) {
        soundLevelBarHeightConstraint?.constant = max(minimumBarHeight, min(maximumBarHeight, height))

        UIView.animate(withDuration: 0.12) {
            self.frameView.layoutIfNeeded()
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

    private func styleButton(_ button: UIButton, title: String, backgroundColor: UIColor) {
        button.setTitle(title, for: .normal)
        button.setTitleColor(.white, for: .normal)
        button.backgroundColor = backgroundColor
        button.layer.cornerRadius = 14
        button.contentEdgeInsets = UIEdgeInsets(top: 12, left: 18, bottom: 12, right: 18)
    }
}
