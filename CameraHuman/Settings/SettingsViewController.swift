//
//  SettingsViewController.swift
//  CameraHuman
//

import AVFoundation
import UIKit

final class SettingsViewController: UIViewController {
    private let settings = CameraSettingsStore.shared

    private let titleLabel = UILabel()
    private let descriptionLabel = UILabel()
    private let qualityControl = UISegmentedControl(items: CameraSettingsStore.VideoPreset.allCases.map(\.displayTitle))
    private let aspectControl = UISegmentedControl(items: CameraSettingsStore.AspectRatio.allCases.map(\.displayTitle))
    private let startupCameraControl = UISegmentedControl(items: CameraSettingsStore.StartupCamera.allCases.map(\.displayTitle))
    private let gridSwitch = UISwitch()
    private let recordAudioSwitch = UISwitch()
    private let audioMeterSwitch = UISwitch()
    private let technicalHUDSwitch = UISwitch()
    private let keepScreenAwakeSwitch = UISwitch()
    private let audioInputLabel = UILabel()
    private let demoFlowLabel = UILabel()
    private let engineeringLabel = UILabel()
    private let buildLabel = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        configureUI()
        reloadCurrentSettings()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        reloadCurrentSettings()
        reloadAudioInputStatus()
    }

    @objc private func qualityChanged(_ sender: UISegmentedControl) {
        guard let preset = CameraSettingsStore.VideoPreset(rawValue: sender.selectedSegmentIndex) else { return }
        settings.videoPreset = preset
    }

    @objc private func aspectChanged(_ sender: UISegmentedControl) {
        guard let aspectRatio = CameraSettingsStore.AspectRatio(rawValue: sender.selectedSegmentIndex) else { return }
        settings.aspectRatio = aspectRatio
    }

    @objc private func startupCameraChanged(_ sender: UISegmentedControl) {
        guard let startupCamera = CameraSettingsStore.StartupCamera(rawValue: sender.selectedSegmentIndex) else { return }
        settings.startupCamera = startupCamera
    }

    @objc private func gridSwitchChanged(_ sender: UISwitch) {
        settings.showGrid = sender.isOn
    }

    @objc private func recordAudioChanged(_ sender: UISwitch) {
        settings.recordAudio = sender.isOn
        audioMeterSwitch.isEnabled = sender.isOn
        audioMeterSwitch.alpha = sender.isOn ? 1 : 0.45
    }

    @objc private func audioMeterChanged(_ sender: UISwitch) { settings.showAudioMeter = sender.isOn }
    @objc private func technicalHUDChanged(_ sender: UISwitch) { settings.showTechnicalHUD = sender.isOn }
    @objc private func keepScreenAwakeChanged(_ sender: UISwitch) { settings.keepScreenAwake = sender.isOn }

    private func configureUI() {
        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        let stackView = UIStackView()
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .vertical
        stackView.spacing = 14

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .monospacedSystemFont(ofSize: 22, weight: .semibold)
        titleLabel.textColor = .white
        titleLabel.text = "Settings"
        titleLabel.accessibilityIdentifier = "settings.title"

        descriptionLabel.translatesAutoresizingMaskIntoConstraints = false
        descriptionLabel.font = .systemFont(ofSize: 13, weight: .regular)
        descriptionLabel.textColor = UIColor.white.withAlphaComponent(0.72)
        descriptionLabel.numberOfLines = 0
        descriptionLabel.text = "設定拍攝啟動預設、取景輔助、收音與現場操作。錄影時常切換的 FORMAT / FRAME 仍可直接在 Camera 畫面調整。"

        let qualitySection = makeSection(title: "Recording Quality", control: qualityControl)
        let aspectSection = makeSection(title: "Target Aspect", control: aspectControl)
        let startupCameraSection = makeSection(title: "Startup Camera", control: startupCameraControl)
        let gridSection = makeSwitchSection(title: "Show Grid", subtitle: "開啟後會在畫面中顯示構圖格線。", toggle: gridSwitch)
        let technicalHUDSection = makeSwitchSection(title: "Technical HUD", subtitle: "顯示 FPS、快門、ISO、白平衡等即時拍攝資訊。", toggle: technicalHUDSwitch)
        let keepAwakeSection = makeSwitchSection(title: "Keep Screen Awake", subtitle: "停留在 Camera 頁時避免螢幕自動鎖定。", toggle: keepScreenAwakeSwitch)
        let recordAudioSection = makeSwitchSection(title: "Record Audio", subtitle: "把目前可用的音訊輸入寫入錄影檔。關閉後影片不含聲音。", toggle: recordAudioSwitch)
        let meterSection = makeSwitchSection(title: "Audio Meter", subtitle: "在取景畫面顯示即時 MIC dB；不影響錄音內容。", toggle: audioMeterSwitch)
        let audioInputSection = makeInfoSection(title: "Current Audio Input", label: audioInputLabel)

        qualityControl.accessibilityIdentifier = "settings.quality"
        aspectControl.accessibilityIdentifier = "settings.aspectRatio"
        startupCameraControl.accessibilityIdentifier = "settings.startupCamera"
        gridSwitch.accessibilityIdentifier = "settings.showGrid"
        recordAudioSwitch.accessibilityIdentifier = "settings.recordAudio"
        audioMeterSwitch.accessibilityIdentifier = "settings.audioMeter"
        technicalHUDSwitch.accessibilityIdentifier = "settings.technicalHUD"
        keepScreenAwakeSwitch.accessibilityIdentifier = "settings.keepScreenAwake"
        demoFlowLabel.text = "1. Camera：確認格式、構圖與 MIC，錄一段素材\n2. Media：播放、註記並 Link 到 Planner\n3. Assistant：查看狀態並產生下一步 action item"
        engineeringLabel.text = "UIKit + AVFoundation\n硬體能力驅動鏡頭與手動控制\nCapture service / recorder state machine / injectable ChatEngine\nUserDefaults + files + JSON，無第三方依賴"
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        buildLabel.text = "影人 CameraHuman · Version \(version) (\(build))\niOS 13+ · Portfolio prototype"
        let demoSection = makeInfoSection(title: "3-Minute Demo Flow", label: demoFlowLabel)
        let engineeringSection = makeInfoSection(title: "Engineering Highlights", label: engineeringLabel)
        let buildSection = makeInfoSection(title: "About This Build", label: buildLabel)

        qualityControl.addTarget(self, action: #selector(qualityChanged(_:)), for: .valueChanged)
        aspectControl.addTarget(self, action: #selector(aspectChanged(_:)), for: .valueChanged)
        startupCameraControl.addTarget(self, action: #selector(startupCameraChanged(_:)), for: .valueChanged)
        gridSwitch.addTarget(self, action: #selector(gridSwitchChanged(_:)), for: .valueChanged)
        recordAudioSwitch.addTarget(self, action: #selector(recordAudioChanged(_:)), for: .valueChanged)
        audioMeterSwitch.addTarget(self, action: #selector(audioMeterChanged(_:)), for: .valueChanged)
        technicalHUDSwitch.addTarget(self, action: #selector(technicalHUDChanged(_:)), for: .valueChanged)
        keepScreenAwakeSwitch.addTarget(self, action: #selector(keepScreenAwakeChanged(_:)), for: .valueChanged)

        view.addSubview(scrollView)
        scrollView.addSubview(stackView)

        stackView.addArrangedSubview(titleLabel)
        stackView.addArrangedSubview(descriptionLabel)
        stackView.addArrangedSubview(makeCategoryLabel("CAPTURE DEFAULTS"))
        stackView.addArrangedSubview(qualitySection)
        stackView.addArrangedSubview(aspectSection)
        stackView.addArrangedSubview(startupCameraSection)
        stackView.addArrangedSubview(makeCategoryLabel("MONITORING & OPERATION"))
        stackView.addArrangedSubview(gridSection)
        stackView.addArrangedSubview(technicalHUDSection)
        stackView.addArrangedSubview(keepAwakeSection)
        stackView.addArrangedSubview(makeCategoryLabel("AUDIO"))
        stackView.addArrangedSubview(recordAudioSection)
        stackView.addArrangedSubview(meterSection)
        stackView.addArrangedSubview(audioInputSection)
        stackView.addArrangedSubview(makeCategoryLabel("PORTFOLIO GUIDE"))
        stackView.addArrangedSubview(demoSection)
        stackView.addArrangedSubview(engineeringSection)
        stackView.addArrangedSubview(buildSection)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            stackView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 20),
            stackView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -20),
            stackView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 14),
            stackView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -24),
            stackView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -40)
        ])
    }

    private func reloadCurrentSettings() {
        qualityControl.selectedSegmentIndex = settings.videoPreset.rawValue
        aspectControl.selectedSegmentIndex = settings.aspectRatio.rawValue
        startupCameraControl.selectedSegmentIndex = settings.startupCamera.rawValue
        gridSwitch.isOn = settings.showGrid
        recordAudioSwitch.isOn = settings.recordAudio
        audioMeterSwitch.isOn = settings.showAudioMeter
        audioMeterSwitch.isEnabled = settings.recordAudio
        audioMeterSwitch.alpha = settings.recordAudio ? 1 : 0.45
        technicalHUDSwitch.isOn = settings.showTechnicalHUD
        keepScreenAwakeSwitch.isOn = settings.keepScreenAwake
    }

    private func reloadAudioInputStatus() {
        let inputs = AVAudioSession.sharedInstance().currentRoute.inputs
        guard !inputs.isEmpty else {
            audioInputLabel.text = "尚未建立音訊路由。請先開啟 Camera，或檢查麥克風權限。"
            return
        }
        audioInputLabel.text = inputs.map { input in
            let channels = input.channels?.count ?? 0
            return "\(input.portName) · \(input.portType.rawValue) · \(channels) channel\(channels == 1 ? "" : "s")"
        }.joined(separator: "\n")
    }

    private func makeCategoryLabel(_ text: String) -> UILabel {
        let label = UILabel()
        label.font = .monospacedSystemFont(ofSize: 11, weight: .bold)
        label.textColor = UIColor.white.withAlphaComponent(0.55)
        label.text = text
        return label
    }

    private func makeInfoSection(title: String, label: UILabel) -> UIView {
        let container = UIView()
        container.backgroundColor = UIColor.white.withAlphaComponent(0.08)
        container.layer.cornerRadius = 14
        let titleLabel = UILabel()
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .monospacedSystemFont(ofSize: 12, weight: .semibold)
        titleLabel.textColor = .systemBlue
        titleLabel.text = title
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 13)
        label.textColor = UIColor.white.withAlphaComponent(0.78)
        label.numberOfLines = 0
        container.addSubview(titleLabel)
        container.addSubview(label)
        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 14),
            titleLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -14),
            titleLabel.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
            label.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            label.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            label.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -12)
        ])
        return container
    }

    private func makeSection(title: String, control: UISegmentedControl) -> UIView {
        let container = UIView()
        container.backgroundColor = UIColor.white.withAlphaComponent(0.08)
        container.layer.cornerRadius = 14

        let titleLabel = UILabel()
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .monospacedSystemFont(ofSize: 12, weight: .semibold)
        titleLabel.textColor = UIColor.systemBlue
        titleLabel.text = title

        control.translatesAutoresizingMaskIntoConstraints = false
        control.selectedSegmentTintColor = .systemBlue

        container.addSubview(titleLabel)
        container.addSubview(control)

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 14),
            titleLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -14),
            titleLabel.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
            control.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 14),
            control.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -14),
            control.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 10),
            control.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -12)
        ])

        return container
    }

    private func makeSwitchSection(title: String, subtitle: String, toggle: UISwitch) -> UIView {
        let container = UIView()
        container.backgroundColor = UIColor.white.withAlphaComponent(0.08)
        container.layer.cornerRadius = 14

        let titleLabel = UILabel()
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .monospacedSystemFont(ofSize: 12, weight: .semibold)
        titleLabel.textColor = UIColor.systemBlue
        titleLabel.text = title

        let subtitleLabel = UILabel()
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        subtitleLabel.font = .systemFont(ofSize: 13, weight: .regular)
        subtitleLabel.textColor = UIColor.white.withAlphaComponent(0.72)
        subtitleLabel.numberOfLines = 0
        subtitleLabel.text = subtitle

        toggle.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(titleLabel)
        container.addSubview(subtitleLabel)
        container.addSubview(toggle)

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 14),
            titleLabel.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
            toggle.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -14),
            toggle.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            subtitleLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -14),
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            subtitleLabel.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -12)
        ])

        return container
    }
}
