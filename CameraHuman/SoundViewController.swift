//
//  SoundViewController.swift
//  CameraHuman
//

import UIKit

final class SoundViewController: UIViewController {
    private let detector = SoundDetector()

    private let headerLabel = UILabel()
    private let decibelLabel = UILabel()
    private let helperLabel = UILabel()
    private let thresholdLabel = UILabel()
    private let warningLabel = UILabel()
    private let thresholdSlider = UISlider()
    private let meterContainerView = UIView()
    private let soundLevelBar = UIView()
    private let startButton = UIButton(type: .system)
    private let stopButton = UIButton(type: .system)

    private var soundLevelBarHeightConstraint: NSLayoutConstraint?
    private var activeAlertThreshold: Float = 65

    private let minimumBarHeight: CGFloat = 16
    private let maximumBarHeight: CGFloat = 260

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "聲音"
        view.backgroundColor = .systemBackground
        configureUI()
        bindDetector()
        updateThresholdUI()
        updateUI(for: .idle)
    }

    deinit {
        detector.stopMonitoring()
    }

    @objc private func startTapped(_ sender: UIButton) {
        detector.startMonitoring()
    }

    @objc private func stopTapped(_ sender: UIButton) {
        detector.stopMonitoring()
    }

    @objc private func thresholdSliderChanged(_ sender: UISlider) {
        activeAlertThreshold = round(sender.value)
        updateThresholdUI()
    }

    private func configureUI() {
        headerLabel.translatesAutoresizingMaskIntoConstraints = false
        headerLabel.font = .preferredFont(forTextStyle: .title2)
        headerLabel.text = "聲音頁"

        decibelLabel.translatesAutoresizingMaskIntoConstraints = false
        decibelLabel.font = .monospacedDigitSystemFont(ofSize: 38, weight: .bold)
        decibelLabel.text = "--.- dB"

        helperLabel.translatesAutoresizingMaskIntoConstraints = false
        helperLabel.font = .preferredFont(forTextStyle: .footnote)
        helperLabel.textColor = .secondaryLabel
        helperLabel.numberOfLines = 0

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

        startButton.translatesAutoresizingMaskIntoConstraints = false
        styleButton(startButton, title: "開始監測", backgroundColor: .systemGreen)
        startButton.addTarget(self, action: #selector(startTapped(_:)), for: .touchUpInside)

        stopButton.translatesAutoresizingMaskIntoConstraints = false
        styleButton(stopButton, title: "停止監測", backgroundColor: .systemGray)
        stopButton.addTarget(self, action: #selector(stopTapped(_:)), for: .touchUpInside)

        view.addSubview(headerLabel)
        view.addSubview(decibelLabel)
        view.addSubview(helperLabel)
        view.addSubview(warningLabel)
        view.addSubview(thresholdLabel)
        view.addSubview(thresholdSlider)
        view.addSubview(meterContainerView)
        meterContainerView.addSubview(soundLevelBar)
        view.addSubview(startButton)
        view.addSubview(stopButton)

        soundLevelBarHeightConstraint = soundLevelBar.heightAnchor.constraint(equalToConstant: minimumBarHeight)
        soundLevelBarHeightConstraint?.isActive = true

        NSLayoutConstraint.activate([
            headerLabel.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 20),
            headerLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 24),
            headerLabel.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -20),

            decibelLabel.leadingAnchor.constraint(equalTo: headerLabel.leadingAnchor),
            decibelLabel.topAnchor.constraint(equalTo: headerLabel.bottomAnchor, constant: 12),

            helperLabel.leadingAnchor.constraint(equalTo: headerLabel.leadingAnchor),
            helperLabel.trailingAnchor.constraint(equalTo: headerLabel.trailingAnchor),
            helperLabel.topAnchor.constraint(equalTo: decibelLabel.bottomAnchor, constant: 10),

            warningLabel.leadingAnchor.constraint(equalTo: headerLabel.leadingAnchor),
            warningLabel.topAnchor.constraint(equalTo: helperLabel.bottomAnchor, constant: 10),
            warningLabel.trailingAnchor.constraint(lessThanOrEqualTo: headerLabel.trailingAnchor),

            thresholdLabel.leadingAnchor.constraint(equalTo: headerLabel.leadingAnchor),
            thresholdLabel.trailingAnchor.constraint(equalTo: headerLabel.trailingAnchor),
            thresholdLabel.topAnchor.constraint(equalTo: warningLabel.bottomAnchor, constant: 14),

            thresholdSlider.leadingAnchor.constraint(equalTo: headerLabel.leadingAnchor),
            thresholdSlider.trailingAnchor.constraint(equalTo: headerLabel.trailingAnchor),
            thresholdSlider.topAnchor.constraint(equalTo: thresholdLabel.bottomAnchor, constant: 8),

            meterContainerView.leadingAnchor.constraint(equalTo: headerLabel.leadingAnchor),
            meterContainerView.topAnchor.constraint(equalTo: thresholdSlider.bottomAnchor, constant: 26),
            meterContainerView.widthAnchor.constraint(equalToConstant: 96),
            meterContainerView.heightAnchor.constraint(equalToConstant: maximumBarHeight),

            soundLevelBar.leadingAnchor.constraint(equalTo: meterContainerView.leadingAnchor),
            soundLevelBar.trailingAnchor.constraint(equalTo: meterContainerView.trailingAnchor),
            soundLevelBar.bottomAnchor.constraint(equalTo: meterContainerView.bottomAnchor),

            startButton.leadingAnchor.constraint(equalTo: meterContainerView.trailingAnchor, constant: 20),
            startButton.topAnchor.constraint(equalTo: meterContainerView.topAnchor),

            stopButton.leadingAnchor.constraint(equalTo: startButton.leadingAnchor),
            stopButton.topAnchor.constraint(equalTo: startButton.bottomAnchor, constant: 12),
            stopButton.trailingAnchor.constraint(lessThanOrEqualTo: headerLabel.trailingAnchor)
        ])
    }

    private func bindDetector() {
        detector.onStateChange = { [weak self] state in
            guard let self = self else { return }
            self.updateUI(for: state)
        }

        detector.onLevelUpdate = { [weak self] snapshot in
            guard let self = self else { return }
            self.updateMeter(using: snapshot)
        }
    }

    private func updateUI(for state: SoundDetector.State) {
        switch state {
        case .idle:
            helperLabel.text = "按下開始後會監測環境音量並依門檻提醒。"
            decibelLabel.text = "--.- dB"
            startButton.isEnabled = true
            stopButton.isEnabled = false
            updateMeterAppearance(color: .systemGreen)
            updateMeterHeight(minimumBarHeight)
            updateWarningLabel(isTooLoud: false, decibels: nil)
        case .requestingPermission:
            helperLabel.text = "要求麥克風權限中，請在系統提示中允許存取。"
            startButton.isEnabled = false
            stopButton.isEnabled = false
            updateMeterAppearance(color: .systemOrange)
        case .running:
            helperLabel.text = "超過 \(Int(activeAlertThreshold)) dB 會顯示過大提醒。"
            startButton.isEnabled = false
            stopButton.isEnabled = true
        case .permissionDenied:
            helperLabel.text = "沒有麥克風權限，請到設定開啟 CameraHuman 的麥克風存取。"
            decibelLabel.text = "--.- dB"
            startButton.isEnabled = true
            stopButton.isEnabled = false
            updateMeterAppearance(color: .systemRed)
            updateMeterHeight(minimumBarHeight)
            updateWarningLabel(isTooLoud: false, decibels: nil)
        case .failed(let message):
            helperLabel.text = "啟動失敗：\(message)"
            startButton.isEnabled = true
            stopButton.isEnabled = false
            updateMeterAppearance(color: .systemRed)
            updateWarningLabel(isTooLoud: false, decibels: nil)
        }

        startButton.alpha = startButton.isEnabled ? 1 : 0.6
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
        } else {
            warningLabel.isHidden = true
        }
    }

    private func updateMeterHeight(_ height: CGFloat) {
        soundLevelBarHeightConstraint?.constant = max(minimumBarHeight, min(maximumBarHeight, height))
        UIView.animate(withDuration: 0.12) {
            self.view.layoutIfNeeded()
        }
    }

    private func updateMeterAppearance(color: UIColor) {
        soundLevelBar.backgroundColor = color
    }

    private func styleButton(_ button: UIButton, title: String, backgroundColor: UIColor) {
        button.setTitle(title, for: .normal)
        button.setTitleColor(.white, for: .normal)
        button.backgroundColor = backgroundColor
        button.layer.cornerRadius = 14
        button.contentEdgeInsets = UIEdgeInsets(top: 12, left: 18, bottom: 12, right: 18)
    }
}
