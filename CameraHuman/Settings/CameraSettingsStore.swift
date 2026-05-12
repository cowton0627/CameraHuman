//
//  CameraSettingsStore.swift
//  CameraHuman
//

import Foundation
import AVFoundation
import CoreGraphics

extension Notification.Name {
    static let cameraSettingsDidChange = Notification.Name("cameraSettingsDidChange")
}

/// 拍攝設定的唯讀視圖。給不需要修改設定、只需要讀的 consumer（如 `KeywordChatEngine`）用，
/// 方便注入測試 stub 而不必持有真實的 `CameraSettingsStore` singleton。
protocol CameraSettings: AnyObject {
    var videoPreset: CameraSettingsStore.VideoPreset { get }
    var aspectRatio: CameraSettingsStore.AspectRatio { get }
    var startupCamera: CameraSettingsStore.StartupCamera { get }
    var showGrid: Bool { get }
}

final class CameraSettingsStore: CameraSettings {
    enum VideoPreset: Int, CaseIterable {
        case hd
        case fullHD

        var displayTitle: String {
            switch self {
            case .hd: return "HD"
            case .fullHD: return "FHD"
            }
        }

        var capturePreset: AVCaptureSession.Preset {
            switch self {
            case .hd: return .hd1280x720
            case .fullHD: return .hd1920x1080
            }
        }
    }

    enum AspectRatio: Int, CaseIterable {
        case ratio16x9
        case ratio4x3

        var displayTitle: String {
            switch self {
            case .ratio16x9: return "16:9"
            case .ratio4x3: return "4:3"
            }
        }

        var landscapeSize: CGSize {
            switch self {
            case .ratio16x9:
                return CGSize(width: 16, height: 9)
            case .ratio4x3:
                return CGSize(width: 4, height: 3)
            }
        }
    }

    enum StartupCamera: Int, CaseIterable {
        case back
        case front

        var displayTitle: String {
            switch self {
            case .back: return "Back"
            case .front: return "Front"
            }
        }

        var capturePosition: AVCaptureDevice.Position {
            switch self {
            case .back: return .back
            case .front: return .front
            }
        }
    }

    static let shared = CameraSettingsStore()

    private enum Keys {
        static let videoPreset = "camera_settings_video_preset"
        static let aspectRatio = "camera_settings_aspect_ratio"
        static let startupCamera = "camera_settings_startup_camera"
        static let showGrid = "camera_settings_show_grid"
    }

    private let defaults = UserDefaults.standard

    var videoPreset: VideoPreset {
        didSet { persist() }
    }

    var aspectRatio: AspectRatio {
        didSet { persist() }
    }

    var startupCamera: StartupCamera {
        didSet { persist() }
    }

    var showGrid: Bool {
        didSet { persist() }
    }

    private init() {
        videoPreset = VideoPreset(rawValue: defaults.integer(forKey: Keys.videoPreset)) ?? .fullHD
        aspectRatio = AspectRatio(rawValue: defaults.integer(forKey: Keys.aspectRatio)) ?? .ratio16x9
        startupCamera = StartupCamera(rawValue: defaults.integer(forKey: Keys.startupCamera)) ?? .back

        if defaults.object(forKey: Keys.showGrid) == nil {
            showGrid = true
        } else {
            showGrid = defaults.bool(forKey: Keys.showGrid)
        }
    }

    private func persist() {
        defaults.set(videoPreset.rawValue, forKey: Keys.videoPreset)
        defaults.set(aspectRatio.rawValue, forKey: Keys.aspectRatio)
        defaults.set(startupCamera.rawValue, forKey: Keys.startupCamera)
        defaults.set(showGrid, forKey: Keys.showGrid)
        NotificationCenter.default.post(name: .cameraSettingsDidChange, object: nil)
    }
}
