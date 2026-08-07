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

    private let chatEngine: ChatEngine
    private let plannerCard = PlannerCardView()
    private let headerContainerView = UIView()

    private let headerLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let quickActionsStackView = UIStackView()
    private let tableView = UITableView(frame: .zero, style: .plain)
    private let inputContainerView = UIView()
    private let inputField = UITextField()
    private let sendButton = UIButton(type: .system)
    private var inputBottomConstraint: NSLayoutConstraint!
    private var keyboardObserver: KeyboardObserver?
    private static let inputBottomPadding: CGFloat = 12

    private var messages: [Message] = [
        Message(role: .assistant, text: "這裡是拍攝助理。你可以問目前設定、最近素材，或要我幫你整理下一個拍攝步驟。")
    ]

    init(chatEngine: ChatEngine = KeywordChatEngine()) {
        self.chatEngine = chatEngine
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        configureUI()
        installKeyboardDismissGestures()
        keyboardObserver = KeyboardObserver(ownerView: view) { [weak self] intrusion, duration, options in
            guard let self else { return }
            self.inputBottomConstraint.constant = -Self.inputBottomPadding - intrusion
            UIView.animate(
                withDuration: duration,
                delay: 0,
                options: options,
                animations: { self.view.layoutIfNeeded() }
            )
        }

        plannerCard.onNotesSaved = { [weak self] in
            self?.appendMessage(.init(role: .assistant, text: "已更新拍攝備忘。"))
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateTableHeaderSizeIfNeeded()
    }

    @objc private func quickActionTapped(_ sender: UIButton) {
        guard let title = sender.currentTitle else { return }
        inputField.text = title
        sendCurrentInput()
    }

    @objc private func sendTapped(_ sender: UIButton) {
        sendCurrentInput()
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        sendCurrentInput()
        textField.resignFirstResponder()
        return true
    }

    private func installKeyboardDismissGestures() {
        let tap = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
        tap.cancelsTouchesInView = false
        view.addGestureRecognizer(tap)
        tableView.keyboardDismissMode = .interactive
    }

    @objc private func dismissKeyboard() {
        view.endEditing(true)
    }

    private func configureUI() {
        headerLabel.translatesAutoresizingMaskIntoConstraints = false
        headerLabel.font = .monospacedSystemFont(ofSize: 22, weight: .semibold)
        headerLabel.textColor = .white
        headerLabel.text = "Assistant"
        headerLabel.accessibilityIdentifier = "assistant.title"

        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        subtitleLabel.font = .systemFont(ofSize: 13, weight: .regular)
        subtitleLabel.textColor = UIColor.white.withAlphaComponent(0.72)
        subtitleLabel.numberOfLines = 0
        subtitleLabel.text = "LOCAL · RULE-BASED\n讀取目前設定、最近素材與 Planner 狀態；ChatEngine 可替換成真正的 AI provider。"

        quickActionsStackView.translatesAutoresizingMaskIntoConstraints = false
        quickActionsStackView.axis = .horizontal
        quickActionsStackView.spacing = 8
        quickActionsStackView.distribution = .fillEqually

        let quickTitles = ["目前設定", "最近素材", "下一步建議"]
        for title in quickTitles {
            let button = UIButton(type: .system)
            button.accessibilityIdentifier = "assistant.quickAction.\(title)"
            button.setTitle(title, for: .normal)
            button.setTitleColor(.white, for: .normal)
            button.titleLabel?.font = .monospacedSystemFont(ofSize: 11, weight: .semibold)
            button.titleLabel?.adjustsFontSizeToFitWidth = true
            button.titleLabel?.minimumScaleFactor = 0.78
            button.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.22)
            button.layer.cornerRadius = 14
            button.addTarget(self, action: #selector(quickActionTapped(_:)), for: .touchUpInside)
            quickActionsStackView.addArrangedSubview(button)
        }

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
        inputField.accessibilityIdentifier = "assistant.input"
        inputField.textColor = .white
        inputField.attributedPlaceholder = NSAttributedString(
            string: "輸入拍攝問題",
            attributes: [.foregroundColor: UIColor.white.withAlphaComponent(0.45)]
        )
        inputField.delegate = self

        sendButton.translatesAutoresizingMaskIntoConstraints = false
        sendButton.accessibilityIdentifier = "assistant.send"
        sendButton.setTitle("送出", for: .normal)
        sendButton.setTitleColor(.white, for: .normal)
        sendButton.titleLabel?.font = .monospacedSystemFont(ofSize: 12, weight: .semibold)
        sendButton.backgroundColor = .systemBlue
        sendButton.layer.cornerRadius = 14
        sendButton.contentEdgeInsets = UIEdgeInsets(top: 10, left: 16, bottom: 10, right: 16)
        sendButton.addTarget(self, action: #selector(sendTapped(_:)), for: .touchUpInside)

        headerContainerView.addSubview(headerLabel)
        headerContainerView.addSubview(subtitleLabel)
        headerContainerView.addSubview(quickActionsStackView)
        headerContainerView.addSubview(plannerCard)
        view.addSubview(tableView)
        view.addSubview(inputContainerView)
        inputContainerView.addSubview(inputField)
        inputContainerView.addSubview(sendButton)

        inputBottomConstraint = inputContainerView.bottomAnchor.constraint(
            equalTo: view.safeAreaLayoutGuide.bottomAnchor,
            constant: -Self.inputBottomPadding
        )

        NSLayoutConstraint.activate([
            inputBottomConstraint,

            headerLabel.leadingAnchor.constraint(equalTo: headerContainerView.leadingAnchor, constant: 20),
            headerLabel.trailingAnchor.constraint(equalTo: headerContainerView.trailingAnchor, constant: -20),
            headerLabel.topAnchor.constraint(equalTo: headerContainerView.topAnchor, constant: 20),

            subtitleLabel.leadingAnchor.constraint(equalTo: headerLabel.leadingAnchor),
            subtitleLabel.trailingAnchor.constraint(equalTo: headerLabel.trailingAnchor),
            subtitleLabel.topAnchor.constraint(equalTo: headerLabel.bottomAnchor, constant: 8),

            quickActionsStackView.leadingAnchor.constraint(equalTo: headerLabel.leadingAnchor),
            quickActionsStackView.trailingAnchor.constraint(equalTo: subtitleLabel.trailingAnchor),
            quickActionsStackView.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 16),
            quickActionsStackView.heightAnchor.constraint(equalToConstant: 36),

            plannerCard.leadingAnchor.constraint(equalTo: headerLabel.leadingAnchor),
            plannerCard.trailingAnchor.constraint(equalTo: subtitleLabel.trailingAnchor),
            plannerCard.topAnchor.constraint(equalTo: quickActionsStackView.bottomAnchor, constant: 14),
            plannerCard.bottomAnchor.constraint(equalTo: headerContainerView.bottomAnchor, constant: -14),

            // Input 固定在主畫面的 safe area，不能跨到尚未掛進 table 的 header hierarchy。
            inputContainerView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 20),
            inputContainerView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -20),

            inputField.leadingAnchor.constraint(equalTo: inputContainerView.leadingAnchor, constant: 14),
            inputField.topAnchor.constraint(equalTo: inputContainerView.topAnchor, constant: 12),
            inputField.bottomAnchor.constraint(equalTo: inputContainerView.bottomAnchor, constant: -12),

            sendButton.leadingAnchor.constraint(equalTo: inputField.trailingAnchor, constant: 12),
            sendButton.trailingAnchor.constraint(equalTo: inputContainerView.trailingAnchor, constant: -12),
            sendButton.centerYAnchor.constraint(equalTo: inputField.centerYAnchor),
            sendButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 64),

            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.bottomAnchor.constraint(equalTo: inputContainerView.topAnchor, constant: -12)
        ])

        tableView.tableHeaderView = headerContainerView
    }

    private func updateTableHeaderSizeIfNeeded() {
        let width = tableView.bounds.width
        guard width > 0 else { return }
        headerContainerView.frame.size.width = width
        let targetSize = CGSize(width: width, height: UIView.layoutFittingCompressedSize.height)
        let height = headerContainerView.systemLayoutSizeFitting(
            targetSize,
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        ).height
        guard abs(headerContainerView.frame.height - height) > 0.5 else { return }
        headerContainerView.frame.size.height = height
        tableView.tableHeaderView = headerContainerView
    }

    private func sendCurrentInput() {
        let rawText = inputField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !rawText.isEmpty else { return }

        appendMessage(.init(role: .user, text: rawText))
        inputField.text = nil
        appendMessage(.init(role: .assistant, text: chatEngine.reply(to: rawText)))
    }

    private func appendMessage(_ message: Message) {
        messages.append(message)
        tableView.reloadData()
        let lastRow = max(0, messages.count - 1)
        tableView.scrollToRow(at: IndexPath(row: lastRow, section: 0), at: .bottom, animated: true)
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
