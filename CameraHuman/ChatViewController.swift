//
//  ChatViewController.swift
//  CameraHuman
//

import UIKit

final class ChatViewController: UIViewController, UITableViewDataSource, UITableViewDelegate, UITextFieldDelegate {
    private struct Message {
        enum Role {
            case assistant
            case user
        }

        let role: Role
        let text: String
    }

    private let settings = CameraSettingsStore.shared
    private let planner = ShotPlannerStore.shared

    private let headerLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let quickActionsStackView = UIStackView()
    private let plannerStackView = UIStackView()
    private let checklistStatusLabel = UILabel()
    private let checklistButtonsStackView = UIStackView()
    private let notesTextView = UITextView()
    private let saveNotesButton = UIButton(type: .system)
    private let linkedClipLabel = UILabel()
    private let actionItemsLabel = UILabel()
    private let tableView = UITableView(frame: .zero, style: .plain)
    private let inputContainerView = UIView()
    private let inputField = UITextField()
    private let sendButton = UIButton(type: .system)

    private var messages: [Message] = [
        Message(role: .assistant, text: "這裡是拍攝助理。你可以問目前設定、最近素材，或要我幫你整理下一個拍攝步驟。")
    ]

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        NotificationCenter.default.addObserver(self, selector: #selector(externalStateDidChange), name: .mediaLibraryDidChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(externalStateDidChange), name: .cameraSettingsDidChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(plannerDidChange), name: .shotPlannerDidChange, object: nil)
        configureUI()
        reloadPlannerUI()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func externalStateDidChange() {
        subtitleLabel.text = "目前會讀取最新設定與最近素材，幫你整理拍攝狀態。"
    }

    @objc private func plannerDidChange() {
        reloadPlannerUI()
    }

    @objc private func quickActionTapped(_ sender: UIButton) {
        guard let title = sender.currentTitle else { return }
        inputField.text = title
        sendCurrentInput()
    }

    @objc private func sendTapped(_ sender: UIButton) {
        sendCurrentInput()
    }

    @objc private func checklistButtonTapped(_ sender: UIButton) {
        guard sender.tag >= 0, sender.tag < planner.checklist.count else { return }
        planner.toggleChecklistItem(id: planner.checklist[sender.tag].id)
    }

    @objc private func saveNotesTapped(_ sender: UIButton) {
        planner.updateNotes(notesTextView.text ?? "")
        appendMessage(.init(role: .assistant, text: "已更新拍攝備忘。"))
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        sendCurrentInput()
        return true
    }

    private func configureUI() {
        headerLabel.translatesAutoresizingMaskIntoConstraints = false
        headerLabel.font = .monospacedSystemFont(ofSize: 24, weight: .semibold)
        headerLabel.textColor = .white
        headerLabel.text = "Chat"

        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        subtitleLabel.font = .systemFont(ofSize: 14, weight: .regular)
        subtitleLabel.textColor = UIColor.white.withAlphaComponent(0.72)
        subtitleLabel.numberOfLines = 0
        subtitleLabel.text = "目前會讀取最新設定與最近素材，幫你整理拍攝狀態。"

        quickActionsStackView.translatesAutoresizingMaskIntoConstraints = false
        quickActionsStackView.axis = .horizontal
        quickActionsStackView.spacing = 8
        quickActionsStackView.distribution = .fillEqually

        let quickTitles = ["目前設定", "最近素材", "下一步建議"]
        for title in quickTitles {
            let button = UIButton(type: .system)
            button.setTitle(title, for: .normal)
            button.setTitleColor(.white, for: .normal)
            button.titleLabel?.font = .monospacedSystemFont(ofSize: 12, weight: .semibold)
            button.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.22)
            button.layer.cornerRadius = 14
            button.addTarget(self, action: #selector(quickActionTapped(_:)), for: .touchUpInside)
            quickActionsStackView.addArrangedSubview(button)
        }

        plannerStackView.translatesAutoresizingMaskIntoConstraints = false
        plannerStackView.axis = .vertical
        plannerStackView.spacing = 12
        plannerStackView.layoutMargins = UIEdgeInsets(top: 14, left: 14, bottom: 14, right: 14)
        plannerStackView.isLayoutMarginsRelativeArrangement = true
        plannerStackView.backgroundColor = UIColor.white.withAlphaComponent(0.08)
        plannerStackView.layer.cornerRadius = 20

        checklistStatusLabel.translatesAutoresizingMaskIntoConstraints = false
        checklistStatusLabel.font = .monospacedSystemFont(ofSize: 12, weight: .semibold)
        checklistStatusLabel.textColor = .systemBlue

        checklistButtonsStackView.translatesAutoresizingMaskIntoConstraints = false
        checklistButtonsStackView.axis = .vertical
        checklistButtonsStackView.spacing = 8

        notesTextView.translatesAutoresizingMaskIntoConstraints = false
        notesTextView.backgroundColor = UIColor.white.withAlphaComponent(0.06)
        notesTextView.textColor = .white
        notesTextView.font = .systemFont(ofSize: 14, weight: .regular)
        notesTextView.layer.cornerRadius = 14
        notesTextView.textContainerInset = UIEdgeInsets(top: 10, left: 8, bottom: 10, right: 8)
        notesTextView.heightAnchor.constraint(equalToConstant: 88).isActive = true

        saveNotesButton.translatesAutoresizingMaskIntoConstraints = false
        saveNotesButton.setTitle("儲存備忘", for: .normal)
        saveNotesButton.setTitleColor(.white, for: .normal)
        saveNotesButton.titleLabel?.font = .monospacedSystemFont(ofSize: 12, weight: .semibold)
        saveNotesButton.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.22)
        saveNotesButton.layer.cornerRadius = 12
        saveNotesButton.contentEdgeInsets = UIEdgeInsets(top: 10, left: 14, bottom: 10, right: 14)
        saveNotesButton.addTarget(self, action: #selector(saveNotesTapped(_:)), for: .touchUpInside)

        linkedClipLabel.translatesAutoresizingMaskIntoConstraints = false
        linkedClipLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        linkedClipLabel.textColor = UIColor.white.withAlphaComponent(0.78)
        linkedClipLabel.numberOfLines = 1

        actionItemsLabel.translatesAutoresizingMaskIntoConstraints = false
        actionItemsLabel.font = .systemFont(ofSize: 14, weight: .regular)
        actionItemsLabel.textColor = UIColor.white.withAlphaComponent(0.82)
        actionItemsLabel.numberOfLines = 0

        plannerStackView.addArrangedSubview(checklistStatusLabel)
        plannerStackView.addArrangedSubview(checklistButtonsStackView)
        plannerStackView.addArrangedSubview(notesTextView)
        plannerStackView.addArrangedSubview(saveNotesButton)
        plannerStackView.addArrangedSubview(linkedClipLabel)
        plannerStackView.addArrangedSubview(actionItemsLabel)

        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.backgroundColor = .clear
        tableView.separatorStyle = .none
        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 72
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "ChatCell")

        inputContainerView.translatesAutoresizingMaskIntoConstraints = false
        inputContainerView.backgroundColor = UIColor.white.withAlphaComponent(0.08)
        inputContainerView.layer.cornerRadius = 18

        inputField.translatesAutoresizingMaskIntoConstraints = false
        inputField.textColor = .white
        inputField.attributedPlaceholder = NSAttributedString(
            string: "輸入拍攝問題",
            attributes: [.foregroundColor: UIColor.white.withAlphaComponent(0.45)]
        )
        inputField.delegate = self

        sendButton.translatesAutoresizingMaskIntoConstraints = false
        sendButton.setTitle("送出", for: .normal)
        sendButton.setTitleColor(.white, for: .normal)
        sendButton.titleLabel?.font = .monospacedSystemFont(ofSize: 12, weight: .semibold)
        sendButton.backgroundColor = .systemBlue
        sendButton.layer.cornerRadius = 14
        sendButton.contentEdgeInsets = UIEdgeInsets(top: 10, left: 16, bottom: 10, right: 16)
        sendButton.addTarget(self, action: #selector(sendTapped(_:)), for: .touchUpInside)

        view.addSubview(headerLabel)
        view.addSubview(subtitleLabel)
        view.addSubview(quickActionsStackView)
        view.addSubview(plannerStackView)
        view.addSubview(tableView)
        view.addSubview(inputContainerView)
        inputContainerView.addSubview(inputField)
        inputContainerView.addSubview(sendButton)

        NSLayoutConstraint.activate([
            headerLabel.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 20),
            headerLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),

            subtitleLabel.leadingAnchor.constraint(equalTo: headerLabel.leadingAnchor),
            subtitleLabel.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -20),
            subtitleLabel.topAnchor.constraint(equalTo: headerLabel.bottomAnchor, constant: 8),

            quickActionsStackView.leadingAnchor.constraint(equalTo: headerLabel.leadingAnchor),
            quickActionsStackView.trailingAnchor.constraint(equalTo: subtitleLabel.trailingAnchor),
            quickActionsStackView.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 16),
            quickActionsStackView.heightAnchor.constraint(equalToConstant: 42),

            plannerStackView.leadingAnchor.constraint(equalTo: headerLabel.leadingAnchor),
            plannerStackView.trailingAnchor.constraint(equalTo: subtitleLabel.trailingAnchor),
            plannerStackView.topAnchor.constraint(equalTo: quickActionsStackView.bottomAnchor, constant: 14),

            inputContainerView.leadingAnchor.constraint(equalTo: headerLabel.leadingAnchor),
            inputContainerView.trailingAnchor.constraint(equalTo: subtitleLabel.trailingAnchor),
            inputContainerView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12),

            inputField.leadingAnchor.constraint(equalTo: inputContainerView.leadingAnchor, constant: 14),
            inputField.topAnchor.constraint(equalTo: inputContainerView.topAnchor, constant: 12),
            inputField.bottomAnchor.constraint(equalTo: inputContainerView.bottomAnchor, constant: -12),

            sendButton.leadingAnchor.constraint(equalTo: inputField.trailingAnchor, constant: 12),
            sendButton.trailingAnchor.constraint(equalTo: inputContainerView.trailingAnchor, constant: -12),
            sendButton.centerYAnchor.constraint(equalTo: inputField.centerYAnchor),
            sendButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 64),

            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.topAnchor.constraint(equalTo: plannerStackView.bottomAnchor, constant: 14),
            tableView.bottomAnchor.constraint(equalTo: inputContainerView.topAnchor, constant: -12)
        ])
    }

    private func sendCurrentInput() {
        let rawText = inputField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !rawText.isEmpty else { return }

        appendMessage(.init(role: .user, text: rawText))
        inputField.text = nil
        appendMessage(.init(role: .assistant, text: respond(to: rawText)))
    }

    private func appendMessage(_ message: Message) {
        messages.append(message)
        tableView.reloadData()
        let lastRow = max(0, messages.count - 1)
        tableView.scrollToRow(at: IndexPath(row: lastRow, section: 0), at: .bottom, animated: true)
    }

    private func respond(to input: String) -> String {
        let normalized = input.lowercased()

        if normalized.contains("設定") || normalized.contains("config") {
            return currentSettingsSummary()
        }

        if normalized.contains("素材") || normalized.contains("media") || normalized.contains("錄影") {
            return latestMediaSummary()
        }

        if normalized.contains("建議") || normalized.contains("下一步") || normalized.contains("next") {
            let suggestion = nextStepSuggestion()
            planner.addActionItem(suggestion)
            return "\(suggestion)\n\n已加入 action items。"
        }

        return [
            currentSettingsSummary(),
            latestMediaSummary(),
            nextStepSuggestion()
        ].joined(separator: "\n\n")
    }

    private func currentSettingsSummary() -> String {
        "目前設定：\(settings.videoPreset.displayTitle)、\(settings.aspectRatio.displayTitle)、啟動鏡頭 \(settings.startupCamera.displayTitle)、格線 \(settings.showGrid ? "開啟" : "關閉")。"
    }

    private func latestMediaSummary() -> String {
        let recordings = (try? MediaLibrary.shared.listRecordings()) ?? []
        guard let latest = recordings.first else {
            return "目前還沒有素材。先到 Camera 錄一段，Media 頁就會出現可播放的檔案。"
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd HH:mm"
        let timeString = formatter.string(from: latest.createdAt)
        let sizeFormatter = ByteCountFormatter()
        sizeFormatter.countStyle = .file
        let sizeText = sizeFormatter.string(fromByteCount: latest.fileSize)
        return "最近素材：\(latest.fileName)\n建立時間 \(timeString)\n檔案大小 \(sizeText)"
    }

    private func nextStepSuggestion() -> String {
        let recordings = (try? MediaLibrary.shared.listRecordings()) ?? []

        if recordings.isEmpty {
            return "下一步建議：先在 Camera 頁用 \(settings.videoPreset.displayTitle) / \(settings.aspectRatio.displayTitle) 錄一段測試，確認構圖框、鏡頭切換與聲音監看都正常。"
        }

        if settings.aspectRatio == .ratio4x3 {
            return "下一步建議：你現在走 4:3 流程，錄完後去 Media 確認輸出比例是否正確，再決定是否要補更完整的裁切安全區。"
        }

        return "下一步建議：Media 已經有素材，現在應該開始補 Chat 與 Media 的素材註記、分類或專案管理，不要再把流程卡在單純錄影。"
    }

    private func reloadPlannerUI() {
        let completedCount = planner.checklist.filter(\.isDone).count
        checklistStatusLabel.text = "SHOT CHECKLIST  \(completedCount)/\(planner.checklist.count)"
        notesTextView.text = planner.notes.isEmpty ? "在這裡記錄這次拍攝的目標、場景、台詞或失敗原因。" : planner.notes
        linkedClipLabel.text = "Linked Clip  \(planner.linkedRecordingName ?? "none")"

        for view in checklistButtonsStackView.arrangedSubviews {
            checklistButtonsStackView.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        for (index, item) in planner.checklist.enumerated() {
            let button = UIButton(type: .system)
            button.tag = index
            button.contentHorizontalAlignment = .left
            button.setTitle("\(item.isDone ? "✓" : "○")  \(item.title)", for: .normal)
            button.setTitleColor(.white, for: .normal)
            button.titleLabel?.font = .systemFont(ofSize: 14, weight: .medium)
            button.backgroundColor = item.isDone ? UIColor.systemBlue.withAlphaComponent(0.18) : UIColor.white.withAlphaComponent(0.06)
            button.layer.cornerRadius = 12
            button.contentEdgeInsets = UIEdgeInsets(top: 10, left: 12, bottom: 10, right: 12)
            button.addTarget(self, action: #selector(checklistButtonTapped(_:)), for: .touchUpInside)
            checklistButtonsStackView.addArrangedSubview(button)
        }

        if planner.actionItems.isEmpty {
            actionItemsLabel.text = "Action Items\n尚未建立。先點「下一步建議」或直接詢問拍攝建議。"
        } else {
            let items = planner.actionItems.prefix(3).enumerated().map { index, value in
                "\(index + 1). \(value)"
            }.joined(separator: "\n")
            actionItemsLabel.text = "Action Items\n\(items)"
        }
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        messages.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let message = messages[indexPath.row]
        let cell: UITableViewCell

        if #available(iOS 14.0, *) {
            cell = tableView.dequeueReusableCell(withIdentifier: "ChatCell", for: indexPath)
            var content = cell.defaultContentConfiguration()
            content.text = message.role == .assistant ? "Assistant" : "You"
            content.secondaryText = message.text
            content.textProperties.font = .monospacedSystemFont(ofSize: 12, weight: .semibold)
            content.secondaryTextProperties.font = .systemFont(ofSize: 15, weight: .regular)
            content.textProperties.color = message.role == .assistant ? .systemBlue : .white
            content.secondaryTextProperties.color = .white
            content.secondaryTextProperties.numberOfLines = 0
            cell.contentConfiguration = content
        } else {
            cell = tableView.dequeueReusableCell(withIdentifier: "ChatLegacyCell") ??
                UITableViewCell(style: .subtitle, reuseIdentifier: "ChatLegacyCell")
            cell.textLabel?.text = message.role == .assistant ? "Assistant" : "You"
            cell.textLabel?.font = .monospacedSystemFont(ofSize: 12, weight: .semibold)
            cell.textLabel?.textColor = message.role == .assistant ? .systemBlue : .white
            cell.detailTextLabel?.text = message.text
            cell.detailTextLabel?.numberOfLines = 0
            cell.detailTextLabel?.font = .systemFont(ofSize: 15, weight: .regular)
            cell.detailTextLabel?.textColor = .white
        }

        cell.backgroundColor = message.role == .assistant
            ? UIColor.systemBlue.withAlphaComponent(0.08)
            : UIColor.white.withAlphaComponent(0.06)
        cell.selectionStyle = .none
        return cell
    }
}
