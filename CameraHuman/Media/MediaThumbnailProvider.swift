//
//  MediaThumbnailProvider.swift
//  CameraHuman
//

import UIKit
import AVFoundation

/// 產生素材縮圖與片長，結果以 NSCache 快取。
/// `AVAssetImageGenerator` 抓幀較慢，一律丟背景 queue，完成後回 main thread。
final class MediaThumbnailProvider {
    static let shared = MediaThumbnailProvider()

    /// 列表 cell 顯示的縮圖尺寸（pt）。VC 排版與這裡共用，避免兩處不同步。
    static let displaySize = CGSize(width: 96, height: 54)
    private static let renderScale: CGFloat = 2

    struct Preview {
        let thumbnail: UIImage?
        let duration: TimeInterval
    }

    private final class CachedPreview {
        let preview: Preview
        init(_ preview: Preview) { self.preview = preview }
    }

    private let cache = NSCache<NSURL, CachedPreview>()
    private let queue = DispatchQueue(label: "com.camerahuman.media.thumbnail", qos: .userInitiated)

    private init() {}

    /// 已快取的結果，沒有就回 nil（不觸發產生）。
    func cachedPreview(for url: URL) -> Preview? {
        cache.object(forKey: url as NSURL)?.preview
    }

    /// 背景產生縮圖 + 片長，完成後在 main thread 回呼。已快取則同步回呼。
    func loadPreview(for url: URL, completion: @escaping (Preview) -> Void) {
        if let cached = cachedPreview(for: url) {
            completion(cached)
            return
        }

        queue.async { [weak self] in
            let asset = AVAsset(url: url)
            let durationSeconds = CMTimeGetSeconds(asset.duration)

            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(
                width: Self.displaySize.width * Self.renderScale,
                height: Self.displaySize.height * Self.renderScale
            )

            let captureTime = CMTime(seconds: 0.1, preferredTimescale: 600)
            let cgImage = try? generator.copyCGImage(at: captureTime, actualTime: nil)
            let thumbnail = cgImage.map { UIImage(cgImage: $0, scale: Self.renderScale, orientation: .up) }

            let preview = Preview(
                thumbnail: thumbnail,
                duration: durationSeconds.isFinite ? durationSeconds : 0
            )
            self?.cache.setObject(CachedPreview(preview), forKey: url as NSURL)
            DispatchQueue.main.async {
                completion(preview)
            }
        }
    }

    /// 素材刪除後清掉對應快取。
    func removePreview(for url: URL) {
        cache.removeObject(forKey: url as NSURL)
    }
}
