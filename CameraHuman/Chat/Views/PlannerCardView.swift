import UIKit

/// 拍攝助理首頁的 Planner 卡片：checklist + notes + linked clip + action items。
/// 自己訂閱 `.shotPlannerDidChange` 自動 reload；外部只需要透過 `onNotesSaved` 取得「使用者按下儲存備忘」的事件。
final class PlannerCardView: UIView {
    var onNotesSaved: (() -> Void)?

    private let planner: ShotPlannerStore
    private let stackView = UIStackView()
    private let checklistStatusLabel = UILabel()
    private let checklistButtonsStackView = UIStackView()
    private let notesTextView = UITextView()
    private let saveNotesButton = UIButton(type: .system)
    private let linkedClipLabel = UILabel()
    private let actionItemsLabel = UILabel()

    init(planner: ShotPlannerStore = .shared) {
        self.planner = planner
        super.init(frame: .zero)
        configure()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(plannerDidChange),
            name: .shotPlannerDidChange,
            object: nil
        )
        reload()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func reload() {
        let completed = planner.checklist.filter(\.isDone).count
        checklistStatusLabel.text = "SHOT CHECKLIST  \(completed)/\(planner.checklist.count)"
        notesTextView.text = planner.notes.isEmpty
            ? "在這裡記錄這次拍攝的目標、場景、台詞或失敗原因。"
            : planner.notes
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
            button.titleLabel?.numberOfLines = 1
            button.titleLabel?.adjustsFontSizeToFitWidth = true
            button.titleLabel?.minimumScaleFactor = 0.75
            button.backgroundColor = item.isDone
                ? UIColor.systemBlue.withAlphaComponent(0.18)
                : UIColor.white.withAlphaComponent(0.06)
            button.layer.cornerRadius = 10
            button.contentEdgeInsets = UIEdgeInsets(top: 10, left: 12, bottom: 10, right: 12)
            button.heightAnchor.constraint(equalToConstant: 44).isActive = true
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

    private func configure() {
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = UIColor.white.withAlphaComponent(0.08)
        layer.cornerRadius = 14

        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .vertical
        stackView.spacing = 8

        checklistStatusLabel.font = .monospacedSystemFont(ofSize: 12, weight: .semibold)
        checklistStatusLabel.textColor = .systemBlue

        checklistButtonsStackView.axis = .vertical
        checklistButtonsStackView.spacing = 8

        notesTextView.backgroundColor = UIColor.white.withAlphaComponent(0.06)
        notesTextView.textColor = .white
        notesTextView.font = .systemFont(ofSize: 13, weight: .regular)
        notesTextView.layer.cornerRadius = 10
        notesTextView.textContainerInset = UIEdgeInsets(top: 10, left: 8, bottom: 10, right: 8)
        notesTextView.heightAnchor.constraint(equalToConstant: 72).isActive = true

        saveNotesButton.setTitle("儲存備忘", for: .normal)
        saveNotesButton.setTitleColor(.white, for: .normal)
        saveNotesButton.titleLabel?.font = .monospacedSystemFont(ofSize: 11, weight: .semibold)
        saveNotesButton.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.22)
        saveNotesButton.layer.cornerRadius = 12
        saveNotesButton.contentEdgeInsets = UIEdgeInsets(top: 10, left: 14, bottom: 10, right: 14)
        saveNotesButton.addTarget(self, action: #selector(saveNotesTapped), for: .touchUpInside)

        linkedClipLabel.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
        linkedClipLabel.textColor = UIColor.white.withAlphaComponent(0.78)
        linkedClipLabel.numberOfLines = 1

        actionItemsLabel.font = .systemFont(ofSize: 12, weight: .regular)
        actionItemsLabel.textColor = UIColor.white.withAlphaComponent(0.82)
        actionItemsLabel.numberOfLines = 0

        stackView.addArrangedSubview(checklistStatusLabel)
        stackView.addArrangedSubview(checklistButtonsStackView)
        stackView.addArrangedSubview(notesTextView)
        stackView.addArrangedSubview(saveNotesButton)
        stackView.addArrangedSubview(linkedClipLabel)
        stackView.addArrangedSubview(actionItemsLabel)

        addSubview(stackView)
        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12)
        ])
    }

    @objc private func checklistButtonTapped(_ sender: UIButton) {
        guard sender.tag >= 0, sender.tag < planner.checklist.count else { return }
        planner.toggleChecklistItem(id: planner.checklist[sender.tag].id)
    }

    @objc private func saveNotesTapped() {
        planner.updateNotes(notesTextView.text ?? "")
        onNotesSaved?()
    }

    @objc private func plannerDidChange() {
        reload()
    }
}
