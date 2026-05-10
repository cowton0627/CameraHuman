import AVFoundation
import UIKit

/// 包裝 AVCaptureMovieFileOutput + 錄影狀態機 + 經過時間 timer。
/// VC 設好 callback 後就只要呼叫 start()/stop()，狀態變化、計時、儲存到 MediaLibrary 都由 Recorder 處理。
final class CameraRecorder: NSObject, AVCaptureFileOutputRecordingDelegate {
    enum State {
        case idle
        case starting
        case recording
        case stopping

        var label: String {
            switch self {
            case .idle: return "IDLE"
            case .starting: return "STARTING"
            case .recording: return "RECORDING"
            case .stopping: return "STOPPING"
            }
        }
    }

    // MARK: - Callbacks (main thread)
    var onStateChange: ((State) -> Void)?
    /// elapsed 秒數
    var onTimerTick: ((Int) -> Void)?
    /// 開始寫入檔案，URL 為當前錄影檔暫存位置
    var onStartedFile: ((URL) -> Void)?
    /// 錄完成功儲存到 MediaLibrary
    var onSaved: ((MediaRecording) -> Void)?
    /// 錄影／儲存失敗，message 是給 UI 顯示的字串
    var onFailed: ((String) -> Void)?

    private(set) var state: State = .idle {
        didSet {
            guard oldValue != state else { return }
            onStateChange?(state)
        }
    }

    private let session: CameraSession
    private let settings: CameraSettingsStore
    private let mediaLibrary: MediaLibrary
    private var recordingStartDate: Date?
    private var timer: Timer?

    init(
        session: CameraSession,
        settings: CameraSettingsStore = .shared,
        mediaLibrary: MediaLibrary = .shared
    ) {
        self.session = session
        self.settings = settings
        self.mediaLibrary = mediaLibrary
        super.init()
    }

    deinit {
        stopTimer()
    }

    func start(interfaceOrientation: UIInterfaceOrientation?) {
        guard session.cameraAuthorized else { return }
        guard !session.movieOutput.isRecording else { return }
        guard state == .idle else { return }

        state = .starting

        session.queue.async { [weak self] in
            guard let self else { return }

            let outputURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("CameraHuman-\(UUID().uuidString)")
                .appendingPathExtension("mov")

            if let videoConnection = self.session.movieOutput.connection(with: .video),
               videoConnection.isVideoOrientationSupported,
               let interfaceOrientation {
                videoConnection.videoOrientation = AVCaptureVideoOrientation(interfaceOrientation)
            }

            self.session.movieOutput.startRecording(to: outputURL, recordingDelegate: self)
        }
    }

    func stop() {
        guard session.movieOutput.isRecording else { return }
        guard state == .recording else { return }

        state = .stopping
        session.queue.async { [weak self] in
            self?.session.movieOutput.stopRecording()
        }
    }

    // MARK: - Timer

    private func startTimer() {
        stopTimer()
        recordingStartDate = Date()
        onTimerTick?(0)
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self, let start = self.recordingStartDate else { return }
            self.onTimerTick?(Int(Date().timeIntervalSince(start)))
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
        recordingStartDate = nil
    }

    // MARK: - AVCaptureFileOutputRecordingDelegate

    func fileOutput(_ output: AVCaptureFileOutput, didStartRecordingTo fileURL: URL, from connections: [AVCaptureConnection]) {
        DispatchQueue.main.async {
            self.state = .recording
            self.startTimer()
            self.onStartedFile?(fileURL)
        }
    }

    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        DispatchQueue.main.async {
            self.stopTimer()
            self.state = .idle

            if let error {
                self.onFailed?(error.localizedDescription)
                return
            }

            let aspectRatio = self.settings.aspectRatio
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let saved = try self.mediaLibrary.storeRecording(from: outputFileURL, aspectRatio: aspectRatio)
                    DispatchQueue.main.async {
                        self.onSaved?(saved)
                    }
                } catch {
                    DispatchQueue.main.async {
                        self.onFailed?(error.localizedDescription)
                    }
                }
            }
        }
    }
}
