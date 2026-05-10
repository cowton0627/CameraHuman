//
//  MediaViewController.swift
//  CameraHuman
//

import UIKit
import AVKit

final class MediaViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    private let planner = ShotPlannerStore.shared

    private let headerLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let tableView = UITableView(frame: .zero, style: .plain)
    private let emptyLabel = UILabel()

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
        tableView.rowHeight = 76
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
            emptyLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -28)
        ])
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        recordings.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let recording = recordings[indexPath.row]
        let detailText = "\(formattedDate(recording.createdAt))  •  \(formattedSize(recording.fileSize))"
        let noteText = recording.note.isEmpty ? detailText : "\(detailText)\n\(recording.note)"
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
            content.secondaryTextProperties.color = UIColor.white.withAlphaComponent(0.68)
            content.secondaryTextProperties.numberOfLines = 2
            cell.contentConfiguration = content
        } else {
            cell.textLabel?.text = recording.fileName
            cell.textLabel?.textColor = .white
            cell.textLabel?.font = .systemFont(ofSize: 16, weight: .medium)
            cell.detailTextLabel?.text = noteText
            cell.detailTextLabel?.numberOfLines = 2
            cell.detailTextLabel?.textColor = UIColor.white.withAlphaComponent(0.68)
            cell.detailTextLabel?.font = .systemFont(ofSize: 12, weight: .regular)
        }

        cell.backgroundColor = .clear
        cell.accessoryType = .disclosureIndicator
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

            do {
                let recording = self.recordings[indexPath.row]
                try MediaLibrary.shared.deleteRecording(at: recording.url)
                if self.planner.linkedRecordingName == recording.fileName {
                    self.planner.linkRecording(named: nil)
                }
                self.recordings.remove(at: indexPath.row)
                tableView.deleteRows(at: [indexPath], with: .automatic)
                self.emptyLabel.isHidden = !self.recordings.isEmpty
                completion(true)
            } catch {
                completion(false)
            }
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
            let recording = self.recordings[indexPath.row]
            self.planner.linkRecording(named: recording.fileName)
            self.subtitleLabel.text = self.linkedRecordingText()
            completion(true)
        }
        linkAction.backgroundColor = .systemGreen

        return UISwipeActionsConfiguration(actions: [deleteAction, noteAction, linkAction])
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
