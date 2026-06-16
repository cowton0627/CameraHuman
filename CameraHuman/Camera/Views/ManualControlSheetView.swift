//
//  ManualControlSheetView.swift
//  CameraHuman
//

import UIKit

/// 底部彈出的手動控制面板：標題 + 可選的 AUTO/MANUAL 切換 + 1~2 條滑桿。
/// 資料驅動，不知道相機細節——值的換算與套用由 VC 接 callback 後轉給 `CameraSession`。
final class ManualControlSheetView: UIView {
    struct SliderModel {
        let key: String
        let title: String
        let minValue: Float
        let maxValue: Float
        let value: Float
        /// 離散段位值。`nil` = 連續滑桿（如 EV / 色溫）；有值 = 吸附段位（如 ISO / 快門角度）。
        /// 段位模式下滑桿走的是 index（0...count-1），回傳給 callback 的是 `steps[index]` 實際值。
        let steps: [Float]?
        /// 把當前值轉成顯示文字。段位模式收到的是 `steps[index]` 實際值。
        let display: (Float) -> String

        init(key: String, title: String, minValue: Float, maxValue: Float, value: Float, steps: [Float]? = nil, display: @escaping (Float) -> String) {
            self.key = key
            self.title = title
            self.minValue = minValue
            self.maxValue = maxValue
            self.value = value
            self.steps = steps
            self.display = display
        }
    }

    /// 拖動滑桿（持續觸發）。
    var onSliderChanged: ((_ key: String, _ value: Float) -> Void)?
    /// AUTO / MANUAL 切換。
    var onModeChanged: ((_ isAuto: Bool) -> Void)?
    /// 點關閉或點面板外。
    var onClose: (() -> Void)?

    private let containerView = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterialDark))
    private let titleLabel = UILabel()
    private let closeButton = UIButton(type: .system)
    private let modeControl = UISegmentedControl(items: ["AUTO", "MANUAL"])
    private let slidersStack = UIStackView()
    private var valueLabels: [String: UILabel] = [:]

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = .clear
        buildLayout()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    private func buildLayout() {
        containerView.translatesAutoresizingMaskIntoConstraints = false
        containerView.layer.cornerRadius = 16
        containerView.clipsToBounds = true
        addSubview(containerView)

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .monospacedSystemFont(ofSize: 12, weight: .semibold)
        titleLabel.textColor = .white

        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.setImage(UIImage(systemName: "xmark.circle.fill"), for: .normal)
        closeButton.tintColor = UIColor.white.withAlphaComponent(0.7)
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)

        modeControl.translatesAutoresizingMaskIntoConstraints = false
        modeControl.selectedSegmentTintColor = .systemBlue
        modeControl.addTarget(self, action: #selector(modeChanged), for: .valueChanged)

        slidersStack.translatesAutoresizingMaskIntoConstraints = false
        slidersStack.axis = .vertical
        slidersStack.spacing = 10

        let content = containerView.contentView
        content.addSubview(titleLabel)
        content.addSubview(closeButton)
        content.addSubview(modeControl)
        content.addSubview(slidersStack)

        NSLayoutConstraint.activate([
            containerView.leadingAnchor.constraint(equalTo: leadingAnchor),
            containerView.trailingAnchor.constraint(equalTo: trailingAnchor),
            containerView.topAnchor.constraint(equalTo: topAnchor),
            containerView.bottomAnchor.constraint(equalTo: bottomAnchor),

            titleLabel.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            titleLabel.topAnchor.constraint(equalTo: content.topAnchor, constant: 12),

            closeButton.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            closeButton.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),

            modeControl.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            modeControl.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            modeControl.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 12),

            slidersStack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            slidersStack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            slidersStack.topAnchor.constraint(equalTo: modeControl.bottomAnchor, constant: 12),
            slidersStack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -16)
        ])
    }

    /// 重新配置面板內容。`showsModeToggle == false` 時隱藏 AUTO/MANUAL（例如 WB 只有單一滑桿但仍想顯示切換時自行決定）。
    func configure(title: String, showsModeToggle: Bool, isAuto: Bool, sliders: [SliderModel]) {
        titleLabel.text = title
        modeControl.isHidden = !showsModeToggle
        if showsModeToggle {
            modeControl.selectedSegmentIndex = isAuto ? 0 : 1
        }
        rebuildSliders(sliders)
    }

    private func rebuildSliders(_ models: [SliderModel]) {
        valueLabels.removeAll()
        for view in slidersStack.arrangedSubviews {
            slidersStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        for model in models {
            slidersStack.addArrangedSubview(makeSliderRow(model))
        }
    }

    private func makeSliderRow(_ model: SliderModel) -> UIView {
        let titleLabel = UILabel()
        titleLabel.font = .monospacedSystemFont(ofSize: 10, weight: .medium)
        titleLabel.textColor = UIColor.white.withAlphaComponent(0.8)
        titleLabel.text = model.title
        titleLabel.setContentHuggingPriority(.required, for: .horizontal)
        titleLabel.widthAnchor.constraint(equalToConstant: 64).isActive = true

        let valueLabel = UILabel()
        valueLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
        valueLabel.textColor = .white
        valueLabel.textAlignment = .right
        valueLabel.adjustsFontSizeToFitWidth = true
        valueLabel.minimumScaleFactor = 0.7
        valueLabel.setContentHuggingPriority(.required, for: .horizontal)
        valueLabel.widthAnchor.constraint(equalToConstant: 104).isActive = true
        valueLabels[model.key] = valueLabel

        let slider = UISlider()
        slider.minimumTrackTintColor = .systemBlue
        slider.accessibilityIdentifier = model.key
        if let steps = model.steps, !steps.isEmpty {
            // 段位模式：滑桿走 index，初始擺到 >= 當前值的第一個段位。
            slider.minimumValue = 0
            slider.maximumValue = Float(steps.count - 1)
            let index = steps.firstIndex(where: { $0 >= model.value }) ?? (steps.count - 1)
            slider.value = Float(index)
            valueLabel.text = model.display(steps[index])
        } else {
            slider.minimumValue = model.minValue
            slider.maximumValue = model.maxValue
            slider.value = model.value
            valueLabel.text = model.display(model.value)
        }
        slider.addTarget(self, action: #selector(sliderChanged(_:)), for: .valueChanged)

        let row = UIStackView(arrangedSubviews: [titleLabel, slider, valueLabel])
        row.axis = .horizontal
        row.spacing = 8
        row.alignment = .center

        // valueChanged 時要更新對應 valueLabel，用 closure 存到 slider 上不方便，改在 handler 內用 identifier + model 對照。
        sliderModelsByKey[model.key] = model
        return row
    }

    /// 給 slider handler 反查 display closure。
    private var sliderModelsByKey: [String: SliderModel] = [:]

    @objc private func sliderChanged(_ sender: UISlider) {
        guard let key = sender.accessibilityIdentifier, let model = sliderModelsByKey[key] else { return }
        let resolvedValue: Float
        if let steps = model.steps, !steps.isEmpty {
            // 吸附到最近段位：把滑桿值 round 成 index，再寫回滑桿讓拇指吸住。
            let index = max(0, min(steps.count - 1, Int(sender.value.rounded())))
            sender.value = Float(index)
            resolvedValue = steps[index]
        } else {
            resolvedValue = sender.value
        }
        valueLabels[key]?.text = model.display(resolvedValue)
        onSliderChanged?(key, resolvedValue)
    }

    @objc private func modeChanged() {
        onModeChanged?(modeControl.selectedSegmentIndex == 0)
    }

    @objc private func closeTapped() {
        onClose?()
    }
}
