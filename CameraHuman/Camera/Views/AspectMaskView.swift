import AVFoundation
import UIKit

/// 預覽畫面外殼：放 AVCaptureVideoPreviewLayer，並在上方畫 vignette / aspect mask（4:3 黑邊）/ 構圖框 + 標籤 / 三分線。
/// 注意：目前實作 aspectMask 高度都設為 0（讓預覽全螢幕），保留結構以便日後恢復裁切預覽顯示。
final class AspectMaskView: UIView {
    private let vignetteView = UIView()
    private let aspectMaskTopView = UIView()
    private let aspectMaskBottomView = UIView()
    private let aspectFrameView = UIView()
    private let aspectFrameLabel = UILabel()
    private let guideLines = [UIView(), UIView(), UIView(), UIView()]
    private var aspectMaskTopHeightConstraint: NSLayoutConstraint!
    private var aspectMaskBottomHeightConstraint: NSLayoutConstraint!
    private var previewLayer: AVCaptureVideoPreviewLayer?

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = .black
        clipsToBounds = true

        configureSubviews()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func attachPreviewLayer(_ layer: AVCaptureVideoPreviewLayer) {
        guard previewLayer == nil else { return }
        layer.videoGravity = .resizeAspectFill
        layer.frame = bounds
        self.layer.insertSublayer(layer, at: 0)
        previewLayer = layer
    }

    func setAspectRatio(_ ratio: CameraSettingsStore.AspectRatio) {
        aspectFrameLabel.text = ratio.displayTitle
        aspectMaskTopHeightConstraint.constant = 0
        aspectMaskBottomHeightConstraint.constant = 0
        layoutIfNeeded()
    }

    func setGuidesVisible(_ visible: Bool) {
        guideLines.forEach { $0.isHidden = !visible }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        previewLayer?.frame = bounds
        repositionGuideLines()
    }

    private func configureSubviews() {
        vignetteView.translatesAutoresizingMaskIntoConstraints = false
        vignetteView.backgroundColor = UIColor.black.withAlphaComponent(0.18)

        aspectMaskTopView.translatesAutoresizingMaskIntoConstraints = false
        aspectMaskTopView.backgroundColor = UIColor.black.withAlphaComponent(0.46)

        aspectMaskBottomView.translatesAutoresizingMaskIntoConstraints = false
        aspectMaskBottomView.backgroundColor = UIColor.black.withAlphaComponent(0.46)

        aspectFrameView.translatesAutoresizingMaskIntoConstraints = false
        aspectFrameView.layer.borderWidth = 1
        aspectFrameView.layer.borderColor = UIColor.white.withAlphaComponent(0.42).cgColor
        aspectFrameView.isUserInteractionEnabled = false

        aspectFrameLabel.translatesAutoresizingMaskIntoConstraints = false
        aspectFrameLabel.font = .monospacedSystemFont(ofSize: 11, weight: .semibold)
        aspectFrameLabel.textColor = UIColor.white.withAlphaComponent(0.88)

        addSubview(vignetteView)
        addSubview(aspectMaskTopView)
        addSubview(aspectMaskBottomView)
        addSubview(aspectFrameView)
        aspectFrameView.addSubview(aspectFrameLabel)

        for line in guideLines {
            line.backgroundColor = UIColor.white.withAlphaComponent(0.18)
            addSubview(line)
        }

        aspectMaskTopHeightConstraint = aspectMaskTopView.heightAnchor.constraint(equalToConstant: 0)
        aspectMaskBottomHeightConstraint = aspectMaskBottomView.heightAnchor.constraint(equalToConstant: 0)

        NSLayoutConstraint.activate([
            vignetteView.leadingAnchor.constraint(equalTo: leadingAnchor),
            vignetteView.trailingAnchor.constraint(equalTo: trailingAnchor),
            vignetteView.topAnchor.constraint(equalTo: topAnchor),
            vignetteView.bottomAnchor.constraint(equalTo: bottomAnchor),

            aspectMaskTopView.leadingAnchor.constraint(equalTo: leadingAnchor),
            aspectMaskTopView.trailingAnchor.constraint(equalTo: trailingAnchor),
            aspectMaskTopView.topAnchor.constraint(equalTo: topAnchor),
            aspectMaskTopHeightConstraint,

            aspectMaskBottomView.leadingAnchor.constraint(equalTo: leadingAnchor),
            aspectMaskBottomView.trailingAnchor.constraint(equalTo: trailingAnchor),
            aspectMaskBottomView.bottomAnchor.constraint(equalTo: bottomAnchor),
            aspectMaskBottomHeightConstraint,

            aspectFrameView.leadingAnchor.constraint(equalTo: leadingAnchor),
            aspectFrameView.trailingAnchor.constraint(equalTo: trailingAnchor),
            aspectFrameView.topAnchor.constraint(equalTo: aspectMaskTopView.bottomAnchor),
            aspectFrameView.bottomAnchor.constraint(equalTo: aspectMaskBottomView.topAnchor),

            aspectFrameLabel.leadingAnchor.constraint(equalTo: aspectFrameView.leadingAnchor, constant: 10),
            aspectFrameLabel.topAnchor.constraint(equalTo: aspectFrameView.topAnchor, constant: 10)
        ])
    }

    private func repositionGuideLines() {
        let frame = aspectFrameView.frame
        guard frame.width > 0, frame.height > 0 else { return }

        guideLines[0].frame = CGRect(x: frame.minX + (frame.width / 3), y: frame.minY, width: 1, height: frame.height)
        guideLines[1].frame = CGRect(x: frame.minX + (frame.width * 2 / 3), y: frame.minY, width: 1, height: frame.height)
        guideLines[2].frame = CGRect(x: frame.minX, y: frame.minY + (frame.height / 3), width: frame.width, height: 1)
        guideLines[3].frame = CGRect(x: frame.minX, y: frame.minY + (frame.height * 2 / 3), width: frame.width, height: 1)
    }
}
