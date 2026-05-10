import UIKit

/// 音量計卡片：MIC 標籤 + TRACKS 數量 + dB 數值 + 4 條動態長條。
/// 由外部餵 normalized level (0~1) + trackCount，內部處理顏色分級與長條動畫。
final class AudioMeterCardView: UIView {
    private let titleLabel = UILabel()
    private let trackLabel = UILabel()
    private let levelLabel = UILabel()
    private let barsStackView = UIStackView()
    private var barViews: [UIView] = []
    private var barHeightConstraints: [NSLayoutConstraint] = []
    private static let barCount = 4

    /// 最近一次 update 算出的色，外部（如 audioSummaryLabel）想跟著上色可以讀。
    private(set) var meterColor: UIColor = .systemGreen

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = UIColor.white.withAlphaComponent(0.10)
        layer.cornerRadius = 14

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .monospacedSystemFont(ofSize: 9, weight: .semibold)
        titleLabel.textColor = .systemGreen
        titleLabel.text = "MIC"

        trackLabel.translatesAutoresizingMaskIntoConstraints = false
        trackLabel.font = .monospacedSystemFont(ofSize: 9, weight: .medium)
        trackLabel.textColor = .white

        levelLabel.translatesAutoresizingMaskIntoConstraints = false
        levelLabel.font = .monospacedDigitSystemFont(ofSize: 14, weight: .semibold)
        levelLabel.textColor = .white

        barsStackView.translatesAutoresizingMaskIntoConstraints = false
        barsStackView.axis = .horizontal
        barsStackView.alignment = .bottom
        barsStackView.distribution = .fillEqually
        barsStackView.spacing = 4

        for _ in 0..<Self.barCount {
            let container = UIView()
            container.backgroundColor = .clear

            let bar = UIView()
            bar.translatesAutoresizingMaskIntoConstraints = false
            bar.backgroundColor = .systemGreen
            bar.layer.cornerRadius = 4
            container.addSubview(bar)

            let heightConstraint = bar.heightAnchor.constraint(equalToConstant: 8)
            barHeightConstraints.append(heightConstraint)
            barViews.append(bar)
            barsStackView.addArrangedSubview(container)

            NSLayoutConstraint.activate([
                bar.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                bar.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                bar.bottomAnchor.constraint(equalTo: container.bottomAnchor),
                heightConstraint
            ])
        }

        addSubview(titleLabel)
        addSubview(trackLabel)
        addSubview(levelLabel)
        addSubview(barsStackView)

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            trackLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            trackLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 3),
            levelLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            levelLabel.topAnchor.constraint(equalTo: trackLabel.bottomAnchor, constant: 3),
            barsStackView.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            barsStackView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            barsStackView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
            barsStackView.heightAnchor.constraint(equalToConstant: 22)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// - Parameters:
    ///   - level: 0~1 normalized 音量
    ///   - trackCount: 麥克風通道數
    ///   - audioAuthorized: 麥克風權限有沒有給
    func update(level: Float, trackCount: Int, audioAuthorized: Bool) {
        let decibels = Int(round((level * 60) - 60))
        trackLabel.text = "TRACKS \(max(trackCount, audioAuthorized ? 1 : 0))"
        levelLabel.text = String(format: "%02d dB", decibels)

        meterColor = Self.color(for: level)

        for (index, heightConstraint) in barHeightConstraints.enumerated() {
            let multiplier = max(0.18, CGFloat(level) * (0.55 + (CGFloat(index) * 0.15)))
            heightConstraint.constant = 6 + (16 * multiplier)
            barViews[index].backgroundColor = meterColor
        }

        titleLabel.textColor = meterColor
        levelLabel.textColor = meterColor

        UIView.animate(withDuration: 0.12) {
            self.layoutIfNeeded()
        }
    }

    private static func color(for level: Float) -> UIColor {
        switch level {
        case 0.85...:
            return .systemRed
        case 0.68...:
            return .systemYellow
        default:
            return .systemGreen
        }
    }
}
