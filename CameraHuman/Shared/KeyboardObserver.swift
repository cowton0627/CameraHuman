import UIKit

/// 觀察鍵盤升降，並把「鍵盤侵入 safeArea 的高度」回報給 owner，方便調整 layout constraint。
/// 用法：把 ownerView 跟 onUpdate 設好；在 owner 的 deinit 不需要做事，這裡會自動 remove observer。
final class KeyboardObserver {
    /// 鍵盤侵入 safeArea bottom 的高度（無侵入或鍵盤收起時為 0）。
    typealias UpdateHandler = (_ intrusion: CGFloat, _ duration: TimeInterval, _ animationOptions: UIView.AnimationOptions) -> Void

    private weak var ownerView: UIView?
    private let onUpdate: UpdateHandler

    init(ownerView: UIView, onUpdate: @escaping UpdateHandler) {
        self.ownerView = ownerView
        self.onUpdate = onUpdate

        let center = NotificationCenter.default
        center.addObserver(
            self,
            selector: #selector(keyboardWillChangeFrame(_:)),
            name: UIResponder.keyboardWillChangeFrameNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(keyboardWillHide(_:)),
            name: UIResponder.keyboardWillHideNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func keyboardWillChangeFrame(_ note: Notification) {
        guard let view = ownerView,
              let info = note.userInfo,
              let endFrame = (info[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue,
              let duration = info[UIResponder.keyboardAnimationDurationUserInfoKey] as? TimeInterval else { return }

        let keyboardTopY = view.convert(endFrame, from: nil).minY
        let safeBottomY = view.bounds.height - view.safeAreaInsets.bottom
        let intrusion = max(0, safeBottomY - keyboardTopY)

        let curveRaw = (info[UIResponder.keyboardAnimationCurveUserInfoKey] as? Int) ?? Int(UIView.AnimationCurve.easeInOut.rawValue)
        let options = UIView.AnimationOptions(rawValue: UInt(curveRaw) << 16)

        onUpdate(intrusion, duration, options)
    }

    @objc private func keyboardWillHide(_ note: Notification) {
        guard let duration = note.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? TimeInterval else { return }
        onUpdate(0, duration, [])
    }
}
