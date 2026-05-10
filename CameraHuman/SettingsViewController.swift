//
//  SettingsViewController.swift
//  CameraHuman
//

import UIKit

final class SettingsViewController: UIViewController {
    private let settings = CameraSettingsStore.shared

    private let titleLabel = UILabel()
    private let descriptionLabel = UILabel()
    private let qualityControl = UISegmentedControl(items: CameraSettingsStore.VideoPreset.allCases.map(\.displayTitle))
    private let aspectControl = UISegmentedControl(items: CameraSettingsStore.AspectRatio.allCases.map(\.displayTitle))
    private let startupCameraControl = UISegmentedControl(items: CameraSettingsStore.StartupCamera.allCases.map(\.displayTitle))
    private let gridSwitch = UISwitch()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        configureUI()
        reloadCurrentSettings()
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

        descriptionLabel.translatesAutoresizingMaskIntoConstraints = false
        descriptionLabel.font = .systemFont(ofSize: 13, weight: .regular)
        descriptionLabel.textColor = UIColor.white.withAlphaComponent(0.72)
        descriptionLabel.numberOfLines = 0
        descriptionLabel.text = "把原本寫死在 Camera 頁面的拍攝偏好抽到這裡，畫質、比例、啟動鏡頭與格線都由設定控制。"

        let qualitySection = makeSection(title: "Recording Quality", control: qualityControl)
        let aspectSection = makeSection(title: "Target Aspect", control: aspectControl)
        let startupCameraSection = makeSection(title: "Startup Camera", control: startupCameraControl)
        let gridSection = makeSwitchSection(title: "Show Grid", subtitle: "開啟後會在畫面中顯示構圖格線。", toggle: gridSwitch)

        qualityControl.addTarget(self, action: #selector(qualityChanged(_:)), for: .valueChanged)
        aspectControl.addTarget(self, action: #selector(aspectChanged(_:)), for: .valueChanged)
        startupCameraControl.addTarget(self, action: #selector(startupCameraChanged(_:)), for: .valueChanged)
        gridSwitch.addTarget(self, action: #selector(gridSwitchChanged(_:)), for: .valueChanged)

        view.addSubview(scrollView)
        scrollView.addSubview(stackView)

        stackView.addArrangedSubview(titleLabel)
        stackView.addArrangedSubview(descriptionLabel)
        stackView.addArrangedSubview(qualitySection)
        stackView.addArrangedSubview(aspectSection)
        stackView.addArrangedSubview(startupCameraSection)
        stackView.addArrangedSubview(gridSection)

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
