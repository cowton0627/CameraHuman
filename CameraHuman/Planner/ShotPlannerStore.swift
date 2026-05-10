//
//  ShotPlannerStore.swift
//  CameraHuman
//

import Foundation

extension Notification.Name {
    static let shotPlannerDidChange = Notification.Name("shotPlannerDidChange")
}

struct ShotChecklistItem {
    let id: String
    let title: String
    var isDone: Bool
}

final class ShotPlannerStore {
    static let shared = ShotPlannerStore()

    private enum Keys {
        static let checklist = "shot_planner_checklist"
        static let notes = "shot_planner_notes"
        static let actionItems = "shot_planner_action_items"
        static let linkedRecordingName = "shot_planner_linked_recording_name"
    }

    private let defaults = UserDefaults.standard

    private(set) var checklist: [ShotChecklistItem]
    private(set) var notes: String
    private(set) var actionItems: [String]
    private(set) var linkedRecordingName: String?

    private init() {
        let defaultItems = [
            ShotChecklistItem(id: "framing", title: "確認構圖與比例", isDone: false),
            ShotChecklistItem(id: "audio", title: "確認收音與軌道", isDone: false),
            ShotChecklistItem(id: "take", title: "確認本次 take 目標", isDone: false)
        ]

        if let storedChecklist = defaults.array(forKey: Keys.checklist) as? [[String: Any]] {
            checklist = storedChecklist.compactMap { item in
                guard let id = item["id"] as? String, let title = item["title"] as? String else { return nil }
                return ShotChecklistItem(id: id, title: title, isDone: item["isDone"] as? Bool ?? false)
            }
            if checklist.isEmpty { checklist = defaultItems }
        } else {
            checklist = defaultItems
        }

        notes = defaults.string(forKey: Keys.notes) ?? ""
        actionItems = defaults.stringArray(forKey: Keys.actionItems) ?? []
        linkedRecordingName = defaults.string(forKey: Keys.linkedRecordingName)
    }

    func toggleChecklistItem(id: String) {
        guard let index = checklist.firstIndex(where: { $0.id == id }) else { return }
        checklist[index].isDone.toggle()
        persist()
    }

    func updateNotes(_ value: String) {
        notes = value
        persist()
    }

    func addActionItem(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        actionItems.insert(trimmed, at: 0)
        actionItems = Array(actionItems.prefix(6))
        persist()
    }

    func linkRecording(named fileName: String?) {
        linkedRecordingName = fileName
        persist()
    }

    private func persist() {
        defaults.set(
            checklist.map { ["id": $0.id, "title": $0.title, "isDone": $0.isDone] },
            forKey: Keys.checklist
        )
        defaults.set(notes, forKey: Keys.notes)
        defaults.set(actionItems, forKey: Keys.actionItems)
        defaults.set(linkedRecordingName, forKey: Keys.linkedRecordingName)
        NotificationCenter.default.post(name: .shotPlannerDidChange, object: nil)
    }
}
