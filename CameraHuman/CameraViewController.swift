//
//  CameraViewController.swift
//  CameraHuman
//

import UIKit
import AVFoundation

final class CameraViewController: UIViewController {
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

    private let captureSession = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "com.camerahuman.camera-session")

    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var currentVideoInput: AVCaptureDeviceInput?
    private var cameraAuthorized = false
    private var currentPosition: AVCaptureDevice.Position = .back
    private var currentLensOption: LensOption?
    private var availableLensOptions: [LensOption] = []

    private let previewContainerView = UIView()
    private let vignetteView = UIView()
    private let topHUDView = UIStackView()
    private let bottomHUDView = UIView()
    private let titleLabel = UILabel()
    private let statusLabel = UILabel()
    private let lensStackView = UIStackView()
    private let technicalStackView = UIStackView()
    private let infoLabel = UILabel()
    private let switchCameraButton = UIButton(type: .system)
    private let inspectButton = UIButton(type: .system)
    private let guideLines = [UIView(), UIView(), UIView(), UIView()]

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "相機"
        view.backgroundColor = .black
        configureUI()
        refreshLensOptions()
        configureCameraPermissionAndSession()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = previewContainerView.bounds
        updateGuideFrames()
    }

    deinit {
        stopCameraSession()
    }

    @objc private func lensButtonTapped(_ sender: UIButton) {
        guard sender.tag >= 0, sender.tag < availableLensOptions.count else { return }
        currentLensOption = availableLensOptions[sender.tag]
        configureActiveCamera()
        updateLensButtons()
    }

    @objc private func switchCameraTapped(_ sender: UIButton) {
        currentPosition = currentPosition == .back ? .front : .back
        refreshLensOptions()
        configureActiveCamera()
    }

    @objc private func inspectTapped(_ sender: UIButton) {
        infoLabel.text = buildCameraReport()
    }

    private func configureUI() {
        configurePreview()
        configureTopHUD()
        configureBottomHUD()
        configureGuides()
    }

    private func configurePreview() {
        previewContainerView.translatesAutoresizingMaskIntoConstraints = false
        previewContainerView.backgroundColor = .black
        previewContainerView.clipsToBounds = true

        vignetteView.translatesAutoresizingMaskIntoConstraints = false
        vignetteView.backgroundColor = UIColor.black.withAlphaComponent(0.14)

        view.addSubview(previewContainerView)
        previewContainerView.addSubview(vignetteView)

        NSLayoutConstraint.activate([
            previewContainerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            previewContainerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            previewContainerView.topAnchor.constraint(equalTo: view.topAnchor),
            previewContainerView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            vignetteView.leadingAnchor.constraint(equalTo: previewContainerView.leadingAnchor),
            vignetteView.trailingAnchor.constraint(equalTo: previewContainerView.trailingAnchor),
            vignetteView.topAnchor.constraint(equalTo: previewContainerView.topAnchor),
            vignetteView.bottomAnchor.constraint(equalTo: previewContainerView.bottomAnchor)
        ])
    }

    private func configureTopHUD() {
        topHUDView.translatesAutoresizingMaskIntoConstraints = false
        topHUDView.axis = .vertical
        topHUDView.spacing = 10
        topHUDView.layoutMargins = UIEdgeInsets(top: 12, left: 14, bottom: 12, right: 14)
        topHUDView.isLayoutMarginsRelativeArrangement = true
        topHUDView.backgroundColor = UIColor.black.withAlphaComponent(0.58)
        topHUDView.layer.cornerRadius = 18

        titleLabel.font = .monospacedSystemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = .white
        titleLabel.text = "CAMERA HUMAN"

        statusLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        statusLabel.textColor = UIColor.white.withAlphaComponent(0.86)
        statusLabel.numberOfLines = 0
        statusLabel.text = "等待相機權限"

        technicalStackView.axis = .horizontal
        technicalStackView.spacing = 8
        technicalStackView.distribution = .fillEqually

        topHUDView.addArrangedSubview(titleLabel)
        topHUDView.addArrangedSubview(technicalStackView)
        topHUDView.addArrangedSubview(statusLabel)
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
        bottomHUDView.layer.cornerRadius = 24

        lensStackView.translatesAutoresizingMaskIntoConstraints = false
        lensStackView.axis = .horizontal
        lensStackView.spacing = 10
        lensStackView.distribution = .fillEqually

        infoLabel.translatesAutoresizingMaskIntoConstraints = false
        infoLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        infoLabel.textColor = UIColor.white.withAlphaComponent(0.86)
        infoLabel.numberOfLines = 0
        infoLabel.text = "實體鏡頭模式會依目前 iPhone 型號自動顯示。"

        switchCameraButton.translatesAutoresizingMaskIntoConstraints = false
        styleHUDButton(switchCameraButton, title: "切換鏡頭")
        switchCameraButton.addTarget(self, action: #selector(switchCameraTapped(_:)), for: .touchUpInside)

        inspectButton.translatesAutoresizingMaskIntoConstraints = false
        styleHUDButton(inspectButton, title: "鏡頭資訊")
        inspectButton.addTarget(self, action: #selector(inspectTapped(_:)), for: .touchUpInside)

        bottomHUDView.addSubview(lensStackView)
        bottomHUDView.addSubview(infoLabel)
        bottomHUDView.addSubview(switchCameraButton)
        bottomHUDView.addSubview(inspectButton)
        view.addSubview(bottomHUDView)

        NSLayoutConstraint.activate([
            bottomHUDView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 14),
            bottomHUDView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -14),
            bottomHUDView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -18),

            lensStackView.leadingAnchor.constraint(equalTo: bottomHUDView.leadingAnchor, constant: 14),
            lensStackView.trailingAnchor.constraint(equalTo: bottomHUDView.trailingAnchor, constant: -14),
            lensStackView.topAnchor.constraint(equalTo: bottomHUDView.topAnchor, constant: 14),
            lensStackView.heightAnchor.constraint(equalToConstant: 44),

            switchCameraButton.leadingAnchor.constraint(equalTo: lensStackView.leadingAnchor),
            switchCameraButton.topAnchor.constraint(equalTo: lensStackView.bottomAnchor, constant: 12),

            inspectButton.leadingAnchor.constraint(equalTo: switchCameraButton.trailingAnchor, constant: 10),
            inspectButton.topAnchor.constraint(equalTo: switchCameraButton.topAnchor),
            inspectButton.trailingAnchor.constraint(lessThanOrEqualTo: lensStackView.trailingAnchor),

            infoLabel.leadingAnchor.constraint(equalTo: lensStackView.leadingAnchor),
            infoLabel.trailingAnchor.constraint(equalTo: lensStackView.trailingAnchor),
            infoLabel.topAnchor.constraint(equalTo: switchCameraButton.bottomAnchor, constant: 12),
            infoLabel.bottomAnchor.constraint(equalTo: bottomHUDView.bottomAnchor, constant: -14)
        ])
    }

    private func configureGuides() {
        for line in guideLines {
            line.backgroundColor = UIColor.white.withAlphaComponent(0.18)
            view.addSubview(line)
        }
    }

    private func updateGuideFrames() {
        let bounds = view.bounds
        guard bounds.width > 0, bounds.height > 0 else { return }

        guideLines[0].frame = CGRect(x: bounds.width / 3, y: 0, width: 1, height: bounds.height)
        guideLines[1].frame = CGRect(x: bounds.width * 2 / 3, y: 0, width: 1, height: bounds.height)
        guideLines[2].frame = CGRect(x: 0, y: bounds.height / 3, width: bounds.width, height: 1)
        guideLines[3].frame = CGRect(x: 0, y: bounds.height * 2 / 3, width: bounds.width, height: 1)
    }

    private func configureCameraPermissionAndSession() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            cameraAuthorized = true
            configureActiveCamera()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    self.cameraAuthorized = granted
                    granted ? self.configureActiveCamera() : self.showCameraPermissionDenied()
                }
            }
        case .denied, .restricted:
            showCameraPermissionDenied()
        @unknown default:
            statusLabel.text = "相機權限狀態未知"
        }
    }

    private func showCameraPermissionDenied() {
        statusLabel.text = "沒有相機權限"
        infoLabel.text = "請到設定開啟 CameraHuman 的相機存取。"
    }

    private func configureActiveCamera() {
        guard cameraAuthorized else { return }

        if currentLensOption == nil {
            currentLensOption = availableLensOptions.first
        }

        guard let lensOption = currentLensOption else {
            statusLabel.text = "目前方向沒有可用鏡頭"
            return
        }

        let device = lensOption.device

        sessionQueue.async { [weak self] in
            guard let self = self else { return }

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
                    self.updateHUD(for: device, lensTitle: lensOption.title)
                    self.updateLensButtons()
                }
            } catch {
                DispatchQueue.main.async {
                    self.statusLabel.text = "啟用相機失敗"
                    self.infoLabel.text = error.localizedDescription
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
            guard let self = self else { return }
            guard self.captureSession.isRunning else { return }
            self.captureSession.stopRunning()
        }
    }

    private func refreshLensOptions() {
        let resolvedOptions: [LensOption]

        if currentPosition == .front {
            resolvedOptions = frontLensOptions()
        } else {
            resolvedOptions = backLensOptions()
        }

        var seenDeviceIDs = Set<String>()
        availableLensOptions = resolvedOptions.filter { (option: LensOption) -> Bool in
            seenDeviceIDs.insert(option.device.uniqueID).inserted
        }

        currentLensOption = availableLensOptions.first
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
        LensMode.allCases.compactMap { (mode: LensMode) -> LensOption? in
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
            label.textColor = .white
            label.textAlignment = .center
            label.font = .monospacedSystemFont(ofSize: 13, weight: .semibold)
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
            let isSelected = availableLensOptions[index].device.uniqueID == currentLensOption?.device.uniqueID
            button.backgroundColor = isSelected ? .systemBlue : UIColor.black.withAlphaComponent(0.38)
            button.layer.borderColor = (isSelected ? UIColor.systemBlue : UIColor.white.withAlphaComponent(0.4)).cgColor
            button.setTitleColor(.white, for: .normal)
        }
    }

    private func updateHUD(for device: AVCaptureDevice, lensTitle: String) {
        let frameRate = maxFrameRateText(for: device)
        let iso = String(format: "ISO %.0f", device.iso)
        let shutter = shutterText(for: device)
        let whiteBalance = whiteBalanceText(for: device)
        let position = currentPosition == .front ? "FRONT" : "BACK"

        replaceTechnicalChips(with: [
            lensTitle,
            frameRate,
            shutter,
            iso,
            whiteBalance
        ])

        statusLabel.text = "\(position)  |  \(device.localizedName)"
        infoLabel.text = """
        \(device.deviceType.rawValue)
        實體鏡頭選擇：\(availableLensOptions.map { $0.title }.joined(separator: " / "))
        前鏡頭若沒有實體差異，只顯示 FRONT；人像屬於拍攝效果，不列入鏡頭列。
        """
    }

    private func replaceTechnicalChips(with titles: [String]) {
        for arrangedView in technicalStackView.arrangedSubviews {
            technicalStackView.removeArrangedSubview(arrangedView)
            arrangedView.removeFromSuperview()
        }

        for title in titles {
            let label = UILabel()
            label.text = title
            label.textColor = .white
            label.textAlignment = .center
            label.font = .monospacedSystemFont(ofSize: 10, weight: .medium)
            label.backgroundColor = UIColor.white.withAlphaComponent(0.12)
            label.layer.cornerRadius = 8
            label.clipsToBounds = true
            technicalStackView.addArrangedSubview(label)
        }
    }

    private func maxFrameRateText(for device: AVCaptureDevice) -> String {
        let maxFrameRate = device.activeFormat.videoSupportedFrameRateRanges
            .map { (range: AVFrameRateRange) -> Double in range.maxFrameRate }
            .max() ?? 0
        return String(format: "%.0f FPS", maxFrameRate)
    }

    private func shutterText(for device: AVCaptureDevice) -> String {
        let duration = CMTimeGetSeconds(device.exposureDuration)
        guard duration > 0 else { return "SHUTTER AUTO" }
        return String(format: "1/%.0f", 1 / duration)
    }

    private func whiteBalanceText(for device: AVCaptureDevice) -> String {
        switch device.whiteBalanceMode {
        case .locked: return "WB LOCK"
        case .autoWhiteBalance: return "WB AUTO"
        case .continuousAutoWhiteBalance: return "WB AUTO"
        @unknown default: return "WB --"
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

        let lines = discoverySession.devices.map { (device: AVCaptureDevice) -> String in
            let position: String = device.position == .front ? "FRONT" : "BACK"
            let zoom = String(format: "%.1fx", device.activeFormat.videoMaxZoomFactor)
            return "\(position) | \(device.localizedName)\n\(device.deviceType.rawValue)\nMAX ZOOM \(zoom)"
        }

        return lines.isEmpty ? "找不到可用鏡頭。" : lines.joined(separator: "\n\n")
    }

    private func styleHUDButton(_ button: UIButton, title: String) {
        button.setTitle(title, for: .normal)
        button.setTitleColor(.white, for: .normal)
        button.titleLabel?.font = .monospacedSystemFont(ofSize: 12, weight: .semibold)
        button.backgroundColor = UIColor.white.withAlphaComponent(0.14)
        button.layer.cornerRadius = 14
        button.contentEdgeInsets = UIEdgeInsets(top: 10, left: 14, bottom: 10, right: 14)
    }
}
