//
//  MediaLibrary.swift
//  CameraHuman
//

import Foundation
import AVFoundation

extension Notification.Name {
    static let mediaLibraryDidChange = Notification.Name("mediaLibraryDidChange")
}

struct MediaRecording {
    let url: URL
    let fileName: String
    let createdAt: Date
    let fileSize: Int64
    let note: String
}

final class MediaLibrary {
    static let shared = MediaLibrary()

    private let fileManager = FileManager.default

    private struct RecordingMetadata: Codable {
        var note: String
    }

    private init() {}

    func storeRecording(from temporaryURL: URL, aspectRatio: CameraSettingsStore.AspectRatio) throws -> MediaRecording {
        let destinationDirectory = try recordingsDirectory()
        let destinationURL = destinationDirectory.appendingPathComponent(makeFileName())
        let finalizedSourceURL: URL

        if aspectRatio == .ratio4x3 {
            finalizedSourceURL = try exportCroppedRecording(from: temporaryURL, aspectRatio: aspectRatio)
        } else {
            finalizedSourceURL = temporaryURL
        }

        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }

        try fileManager.moveItem(at: finalizedSourceURL, to: destinationURL)

        if finalizedSourceURL != temporaryURL, fileManager.fileExists(atPath: temporaryURL.path) {
            try? fileManager.removeItem(at: temporaryURL)
        }

        let recording = try metadata(for: destinationURL)
        NotificationCenter.default.post(name: .mediaLibraryDidChange, object: nil)
        return recording
    }

    func listRecordings() throws -> [MediaRecording] {
        let directory = try recordingsDirectory()
        let urls = try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.creationDateKey, .fileSizeKey], options: [.skipsHiddenFiles])
        return try urls
            .filter { $0.pathExtension.lowercased() == "mov" }
            .map(metadata(for:))
            .sorted { $0.createdAt > $1.createdAt }
    }

    func deleteRecording(at url: URL) throws {
        try fileManager.removeItem(at: url)
        let metadataURL = metadataURL(for: url)
        if fileManager.fileExists(atPath: metadataURL.path) {
            try? fileManager.removeItem(at: metadataURL)
        }
        NotificationCenter.default.post(name: .mediaLibraryDidChange, object: nil)
    }

    func updateNote(_ note: String, for recordingURL: URL) throws {
        let metadata = RecordingMetadata(note: note.trimmingCharacters(in: .whitespacesAndNewlines))
        let data = try JSONEncoder().encode(metadata)
        try data.write(to: metadataURL(for: recordingURL), options: .atomic)
        NotificationCenter.default.post(name: .mediaLibraryDidChange, object: nil)
    }

    private func recordingsDirectory() throws -> URL {
        let baseDirectory = try fileManager.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let directory = baseDirectory.appendingPathComponent("Recordings", isDirectory: true)
        if !fileManager.fileExists(atPath: directory.path) {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return directory
    }

    private func metadata(for url: URL) throws -> MediaRecording {
        let values = try url.resourceValues(forKeys: [.creationDateKey, .fileSizeKey])
        return MediaRecording(
            url: url,
            fileName: url.lastPathComponent,
            createdAt: values.creationDate ?? Date.distantPast,
            fileSize: Int64(values.fileSize ?? 0),
            note: loadMetadata(for: url)?.note ?? ""
        )
    }

    private func makeFileName() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return "CameraHuman-\(formatter.string(from: Date())).mov"
    }

    private func exportCroppedRecording(from sourceURL: URL, aspectRatio: CameraSettingsStore.AspectRatio) throws -> URL {
        let asset = AVAsset(url: sourceURL)
        guard let videoTrack = asset.tracks(withMediaType: .video).first else {
            throw NSError(domain: "MediaLibrary", code: 1001, userInfo: [NSLocalizedDescriptionKey: "找不到影片軌。"])
        }

        let composition = AVMutableComposition()
        guard
            let compositionVideoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
        else {
            throw NSError(domain: "MediaLibrary", code: 1002, userInfo: [NSLocalizedDescriptionKey: "無法建立影片輸出軌。"])
        }

        try compositionVideoTrack.insertTimeRange(CMTimeRange(start: .zero, duration: asset.duration), of: videoTrack, at: .zero)
        compositionVideoTrack.preferredTransform = .identity

        if let audioTrack = asset.tracks(withMediaType: .audio).first,
           let compositionAudioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
            try compositionAudioTrack.insertTimeRange(CMTimeRange(start: .zero, duration: asset.duration), of: audioTrack, at: .zero)
        }

        let renderSize = croppedRenderSize(for: videoTrack, aspectRatio: aspectRatio)
        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = renderSize
        videoComposition.frameDuration = CMTime(value: 1, timescale: max(1, Int32(round(videoTrack.nominalFrameRate == 0 ? 30 : videoTrack.nominalFrameRate))))

        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: asset.duration)

        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: compositionVideoTrack)
        layerInstruction.setTransform(transformForCropping(videoTrack: videoTrack, aspectRatio: aspectRatio, renderSize: renderSize), at: .zero)
        instruction.layerInstructions = [layerInstruction]
        videoComposition.instructions = [instruction]

        guard let exportSession = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
            throw NSError(domain: "MediaLibrary", code: 1003, userInfo: [NSLocalizedDescriptionKey: "無法建立影片輸出工作。"])
        }

        let exportURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mov")

        exportSession.outputURL = exportURL
        exportSession.outputFileType = .mov
        exportSession.shouldOptimizeForNetworkUse = true
        exportSession.videoComposition = videoComposition

        let semaphore = DispatchSemaphore(value: 0)
        exportSession.exportAsynchronously {
            semaphore.signal()
        }
        semaphore.wait()

        if let error = exportSession.error {
            throw error
        }

        guard exportSession.status == .completed else {
            throw NSError(domain: "MediaLibrary", code: 1004, userInfo: [NSLocalizedDescriptionKey: "影片裁切未完成。"])
        }

        return exportURL
    }

    private func croppedRenderSize(for videoTrack: AVAssetTrack, aspectRatio: CameraSettingsStore.AspectRatio) -> CGSize {
        let transformedSize = absoluteSize(for: videoTrack)
        let targetRatio = aspectRatio.landscapeSize.width / aspectRatio.landscapeSize.height
        let currentRatio = transformedSize.width / transformedSize.height

        if currentRatio > targetRatio {
            return CGSize(width: transformedSize.height * targetRatio, height: transformedSize.height)
        }

        return CGSize(width: transformedSize.width, height: transformedSize.width / targetRatio)
    }

    private func transformForCropping(videoTrack: AVAssetTrack, aspectRatio: CameraSettingsStore.AspectRatio, renderSize: CGSize) -> CGAffineTransform {
        let preferredTransform = videoTrack.preferredTransform
        let transformedSize = absoluteSize(for: videoTrack)
        let xOffset = max(0, (transformedSize.width - renderSize.width) / 2)
        let yOffset = max(0, (transformedSize.height - renderSize.height) / 2)
        return preferredTransform.translatedBy(x: -xOffset, y: -yOffset)
    }

    private func absoluteSize(for videoTrack: AVAssetTrack) -> CGSize {
        let naturalSize = videoTrack.naturalSize
        let transformedRect = CGRect(origin: .zero, size: naturalSize).applying(videoTrack.preferredTransform)
        return CGSize(width: abs(transformedRect.width), height: abs(transformedRect.height))
    }

    private func metadataURL(for recordingURL: URL) -> URL {
        recordingURL.deletingPathExtension().appendingPathExtension("json")
    }

    private func loadMetadata(for recordingURL: URL) -> RecordingMetadata? {
        let url = metadataURL(for: recordingURL)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(RecordingMetadata.self, from: data)
    }
}
