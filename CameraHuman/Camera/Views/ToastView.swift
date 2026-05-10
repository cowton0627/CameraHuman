import UIKit

/// 暫時性提示泡泡。`show(_:)` 會淡入 → 等 1.6s → 淡出。
final class ToastView: UIView {
    private let label = UILabel()
    private static let visibleDuration: TimeInterval = 1.6
    private static let fadeDuration: TimeInterval = 0.18

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = UIColor.black.withAlphaComponent(0.78)
        layer.cornerRadius = 14
        clipsToBounds = true
        alpha = 0

        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .monospacedSystemFont(ofSize: 11, weight: .semibold)
        label.textColor = .white
        label.textAlignment = .center
        label.numberOfLines = 2
        addSubview(label)

        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func show(_ text: String) {
        label.text = text
        UIView.animate(withDuration: Self.fadeDuration, animations: {
            self.alpha = 1
        }) { _ in
            UIView.animate(withDuration: 0.22, delay: Self.visibleDuration, options: [.curveEaseInOut]) {
                self.alpha = 0
            }
        }
    }
}
