//
//  MediaViewController.swift
//  CameraHuman
//

import UIKit
import AVKit
import Photos

final class MediaViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    private let planner = ShotPlannerStore.shared

    private let headerLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let tableView = UITableView(frame: .zero, style: .plain)
    private let emptyLabel = UILabel()
    private let toastView = ToastView()

    private var recordings: [MediaRecording] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        NotificationCenter.default.addObserver(self, selector: #selector(reloadRecordings), name: .mediaLibraryDidChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(plannerDidChange), name: .shotPlannerDidChange, object: nil)
        configureUI()
        reloadRecordings()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        reloadRecordings()
    }

    @objc private func reloadRecordings() {
        do {
            recordings = try MediaLibrary.shared.listRecordings()
            if let linkedName = planner.linkedRecordingName,
               !recordings.contains(where: { $0.fileName == linkedName }) {
                planner.linkRecording(named: nil)
            }
            subtitleLabel.text = linkedRecordingText()
            tableView.reloadData()
            emptyLabel.isHidden = !recordings.isEmpty
        } catch {
            recordings = []
            subtitleLabel.text = linkedRecordingText()
            tableView.reloadData()
            emptyLabel.isHidden = false
            emptyLabel.text = "讀取素材失敗\n\(error.localizedDescription)"
        }
    }

    @objc private func plannerDidChange() {
        subtitleLabel.text = linkedRecordingText()
    }

    private func configureUI() {
        headerLabel.translatesAutoresizingMaskIntoConstraints = false
        headerLabel.font = .monospacedSystemFont(ofSize: 24, weight: .semibold)
        headerLabel.textColor = .white
        headerLabel.text = "Media"

        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        subtitleLabel.font = .systemFont(ofSize: 13, weight: .regular)
        subtitleLabel.textColor = UIColor.white.withAlphaComponent(0.72)
        subtitleLabel.numberOfLines = 1
        subtitleLabel.text = linkedRecordingText()

        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.backgroundColor = .clear
        tableView.separatorColor = UIColor.white.withAlphaComponent(0.12)
        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = 84
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "MediaCell")

        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        emptyLabel.font = .systemFont(ofSize: 15, weight: .regular)
        emptyLabel.textColor = UIColor.white.withAlphaComponent(0.72)
        emptyLabel.textAlignment = .center
        emptyLabel.numberOfLines = 0
        emptyLabel.text = "目前還沒有錄影素材。"

        view.addSubview(headerLabel)
        view.addSubview(subtitleLabel)
        view.addSubview(tableView)
        view.addSubview(emptyLabel)
        view.addSubview(toastView)

        NSLayoutConstraint.activate([
            headerLabel.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 20),
            headerLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            subtitleLabel.leadingAnchor.constraint(equalTo: headerLabel.leadingAnchor),
            subtitleLabel.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -20),
            subtitleLabel.topAnchor.constraint(equalTo: headerLabel.bottomAnchor, constant: 6),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 14),
            tableView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            emptyLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            emptyLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 28),
            emptyLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -28),
            toastView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            toastView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
            toastView.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 28),
            toastView.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -28)
        ])
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        recordings.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let recording = recordings[indexPath.row]
        let preview = MediaThumbnailProvider.shared.cachedPreview(for: recording.url)

        var details = [formattedDate(recording.createdAt), formattedSize(recording.fileSize)]
        if let preview {
            details.insert(formattedDuration(preview.duration), at: 1)
        }
        let detailText = details.joined(separator: " · ")
        let noteText = recording.note.isEmpty ? detailText : "\(detailText)\n\(recording.note)"
        let thumbnail = preview?.thumbnail ?? UIImage(systemName: "film")
        let cell: UITableViewCell

        if #available(iOS 14.0, *) {
            cell = tableView.dequeueReusableCell(withIdentifier: "MediaCell", for: indexPath)
        } else {
            cell = tableView.dequeueReusableCell(withIdentifier: "MediaLegacyCell") ??
                UITableViewCell(style: .subtitle, reuseIdentifier: "MediaLegacyCell")
        }

        if #available(iOS 14.0, *) {
            var content = cell.defaultContentConfiguration()
            content.text = recording.fileName
            content.secondaryText = noteText
            content.textProperties.color = .white
            content.textProperties.numberOfLines = 1
            content.textProperties.lineBreakMode = .byTruncatingMiddle
            content.secondaryTextProperties.color = UIColor.white.withAlphaComponent(0.68)
            content.secondaryTextProperties.font = .systemFont(ofSize: 12, weight: .regular)
            content.secondaryTextProperties.numberOfLines = 2
            content.image = thumbnail
            content.imageProperties.maximumSize = MediaThumbnailProvider.displaySize
            content.imageProperties.reservedLayoutSize = MediaThumbnailProvider.displaySize
            content.imageProperties.cornerRadius = 6
            content.imageProperties.tintColor = UIColor.white.withAlphaComponent(0.4)
            cell.contentConfiguration = content
        } else {
            cell.textLabel?.text = recording.fileName
            cell.textLabel?.textColor = .white
            cell.textLabel?.font = .systemFont(ofSize: 16, weight: .medium)
            cell.detailTextLabel?.text = noteText
            cell.detailTextLabel?.numberOfLines = 2
            cell.detailTextLabel?.textColor = UIColor.white.withAlphaComponent(0.68)
            cell.detailTextLabel?.font = .systemFont(ofSize: 12, weight: .regular)
            cell.imageView?.image = thumbnail
            cell.imageView?.tintColor = UIColor.white.withAlphaComponent(0.4)
            cell.imageView?.layer.cornerRadius = 6
            cell.imageView?.layer.masksToBounds = true
        }

        cell.backgroundColor = .clear
        cell.accessoryType = .disclosureIndicator

        if preview == nil {
            let url = recording.url
            MediaThumbnailProvider.shared.loadPreview(for: url) { [weak self] _ in
                guard let self, let row = self.recordings.firstIndex(where: { $0.url == url }) else { return }
                self.tableView.reloadRows(at: [IndexPath(row: row, section: 0)], with: .none)
            }
        }
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let recording = recordings[indexPath.row]
        let playerViewController = AVPlayerViewController()
        playerViewController.player = AVPlayer(url: recording.url)
        present(playerViewController, animated: true) {
            playerViewController.player?.play()
        }
    }

    func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        let deleteAction = UIContextualAction(style: .destructive, title: "Delete") { [weak self] _, _, completion in
            guard let self else {
                completion(false)
                return
            }
            completion(self.deleteRecording(at: indexPath.row))
        }
        let noteAction = UIContextualAction(style: .normal, title: "Note") { [weak self] _, _, completion in
            self?.presentNoteEditor(for: indexPath.row)
            completion(true)
        }
        noteAction.backgroundColor = .systemBlue

        let linkAction = UIContextualAction(style: .normal, title: "Link") { [weak self] _, _, completion in
            guard let self else {
                completion(false)
                return
            }
            self.linkRecording(at: indexPath.row)
            completion(true)
        }
        linkAction.backgroundColor = .systemGreen

        return UISwipeActionsConfiguration(actions: [deleteAction, noteAction, linkAction])
    }

    func tableView(_ tableView: UITableView, contextMenuConfigurationForRowAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
        let recording = recordings[indexPath.row]
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
            guard let self else { return nil }

            // menu action 觸發時列表可能已變動，用 url 重新找 row，不能信任當下的 indexPath
            let noteAction = UIAction(title: "Note", image: UIImage(systemName: "square.and.pencil")) { _ in
                guard let row = self.row(for: recording) else { return }
                self.presentNoteEditor(for: row)
            }
            let linkAction = UIAction(title: "Link", image: UIImage(systemName: "link")) { _ in
                guard let row = self.row(for: recording) else { return }
                self.linkRecording(at: row)
            }
            let shareAction = UIAction(title: "Share", image: UIImage(systemName: "square.and.arrow.up")) { _ in
                self.presentShareSheet(for: recording, sourceView: tableView.cellForRow(at: indexPath))
            }
            let saveAction = UIAction(title: "Save to Photos", image: UIImage(systemName: "photo.on.rectangle")) { _ in
                self.saveToPhotos(recording)
            }
            let deleteAction = UIAction(title: "Delete", image: UIImage(systemName: "trash"), attributes: .destructive) { _ in
                guard let row = self.row(for: recording) else { return }
                _ = self.deleteRecording(at: row)
            }

            return UIMenu(children: [
                noteAction,
                linkAction,
                shareAction,
                saveAction,
                UIMenu(options: .displayInline, children: [deleteAction])
            ])
        }
    }

    private func row(for recording: MediaRecording) -> Int? {
        recordings.firstIndex(where: { $0.url == recording.url })
    }

    private func linkRecording(at row: Int) {
        let recording = recordings[row]
        planner.linkRecording(named: recording.fileName)
        subtitleLabel.text = linkedRecordingText()
    }

    @discardableResult
    private func deleteRecording(at row: Int) -> Bool {
        let recording = recordings[row]
        do {
            try MediaLibrary.shared.deleteRecording(at: recording.url)
            MediaThumbnailProvider.shared.removePreview(for: recording.url)
            if planner.linkedRecordingName == recording.fileName {
                planner.linkRecording(named: nil)
            }
            recordings.remove(at: row)
            tableView.deleteRows(at: [IndexPath(row: row, section: 0)], with: .automatic)
            emptyLabel.isHidden = !recordings.isEmpty
            return true
        } catch {
            return false
        }
    }

    private func presentShareSheet(for recording: MediaRecording, sourceView: UIView?) {
        let activityViewController = UIActivityViewController(activityItems: [recording.url], applicationActivities: nil)
        if let popover = activityViewController.popoverPresentationController {
            let anchor = sourceView ?? view!
            popover.sourceView = anchor
            popover.sourceRect = anchor.bounds
        }
        present(activityViewController, animated: true)
    }

    private func saveToPhotos(_ recording: MediaRecording) {
        let performSave = { [weak self] in
            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: recording.url)
            }) { success, error in
                DispatchQueue.main.async {
                    if success {
                        self?.toastView.show("已儲存到照片")
                    } else {
                        self?.toastView.show("儲存失敗：\(error?.localizedDescription ?? "未知錯誤")")
                    }
                }
            }
        }

        let handleStatus: (Bool) -> Void = { [weak self] granted in
            DispatchQueue.main.async {
                if granted {
                    performSave()
                } else {
                    self?.toastView.show("沒有照片權限，請到設定開啟")
                }
            }
        }

        if #available(iOS 14.0, *) {
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
                handleStatus(status == .authorized || status == .limited)
            }
        } else {
            PHPhotoLibrary.requestAuthorization { status in
                handleStatus(status == .authorized)
            }
        }
    }

    private func formattedDuration(_ duration: TimeInterval) -> String {
        let totalSeconds = Int(duration.rounded())
        return String(format: "%d:%02d", totalSeconds / 60, totalSeconds % 60)
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy/MM/dd HH:mm"
        return formatter.string(from: date)
    }

    private func formattedSize(_ size: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: size)
    }

    private func linkedRecordingText() -> String {
        if let fileName = planner.linkedRecordingName {
            return "Current planner clip: \(fileName)"
        }
        return "Current planner clip: none"
    }

    private func presentNoteEditor(for index: Int) {
        let recording = recordings[index]
        let alertController = UIAlertController(title: "素材註記", message: recording.fileName, preferredStyle: .alert)
        alertController.addTextField { textField in
            textField.placeholder = "輸入備註"
            textField.text = recording.note
        }
        alertController.addAction(UIAlertAction(title: "取消", style: .cancel))
        alertController.addAction(UIAlertAction(title: "儲存", style: .default) { [weak self] _ in
            guard let self, let note = alertController.textFields?.first?.text else { return }
            do {
                try MediaLibrary.shared.updateNote(note, for: recording.url)
                self.reloadRecordings()
            } catch {
                self.emptyLabel.isHidden = false
                self.emptyLabel.text = "儲存註記失敗\n\(error.localizedDescription)"
            }
        })
        present(alertController, animated: true)
    }
}
