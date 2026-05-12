//
//  ShotPlannerStoreTests.swift
//  CameraHumanTests
//

import XCTest
@testable import CameraHuman

final class ShotPlannerStoreTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "test-planner-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    private func makeStore() -> ShotPlannerStore {
        ShotPlannerStore(defaults: defaults)
    }

    // 1. 全新 store 有 3 個預設 checklist 項目，全部 isDone = false
    func test_defaults_checklistHasThreeItemsAllUndone() {
        let store = makeStore()
        XCTAssertEqual(store.checklist.count, 3)
        XCTAssertEqual(store.checklist.map(\.id), ["framing", "audio", "take"])
        XCTAssertTrue(store.checklist.allSatisfy { !$0.isDone })
    }

    // 2. 全新 store 其他欄位空 / nil
    func test_defaults_emptyFields() {
        let store = makeStore()
        XCTAssertEqual(store.notes, "")
        XCTAssertEqual(store.actionItems, [])
        XCTAssertNil(store.linkedRecordingName)
    }

    // 3. toggleChecklistItem 對有效 id → flip
    func test_toggleChecklistItem_flipsDone() {
        let store = makeStore()
        store.toggleChecklistItem(id: "framing")
        XCTAssertTrue(store.checklist.first(where: { $0.id == "framing" })?.isDone == true)
    }

    // 4. toggleChecklistItem 對不存在 id → noop
    func test_toggleChecklistItem_unknownId_noop() {
        let store = makeStore()
        let before = store.checklist
        store.toggleChecklistItem(id: "nonexistent")
        XCTAssertEqual(before.map(\.isDone), store.checklist.map(\.isDone))
    }

    // 5. updateNotes 寫進 notes
    func test_updateNotes_setsValue() {
        let store = makeStore()
        store.updateNotes("test note")
        XCTAssertEqual(store.notes, "test note")
    }

    // 6. addActionItem 插入到最前面（newest first）
    func test_addActionItem_insertsToFront() {
        let store = makeStore()
        store.addActionItem("first")
        store.addActionItem("second")
        XCTAssertEqual(store.actionItems.first, "second")
        XCTAssertEqual(store.actionItems.last, "first")
    }

    // 7. addActionItem 自動 trim whitespace
    func test_addActionItem_trimsWhitespace() {
        let store = makeStore()
        store.addActionItem("   hello   ")
        XCTAssertEqual(store.actionItems, ["hello"])
    }

    // 8. addActionItem 空字串 → noop
    func test_addActionItem_emptyString_noop() {
        let store = makeStore()
        store.addActionItem("")
        XCTAssertEqual(store.actionItems, [])
    }

    // 9. addActionItem 全空白 → noop
    func test_addActionItem_whitespaceOnly_noop() {
        let store = makeStore()
        store.addActionItem("   \n  \t  ")
        XCTAssertEqual(store.actionItems, [])
    }

    // 10. addActionItem 最多保留 6 個（newest first）
    func test_addActionItem_capsAt6() {
        let store = makeStore()
        for i in 1...10 {
            store.addActionItem("item \(i)")
        }
        XCTAssertEqual(store.actionItems.count, 6)
        XCTAssertEqual(store.actionItems.first, "item 10")
        XCTAssertEqual(store.actionItems.last, "item 5")
    }

    // 11. linkRecording with name
    func test_linkRecording_setsName() {
        let store = makeStore()
        store.linkRecording(named: "clip.mov")
        XCTAssertEqual(store.linkedRecordingName, "clip.mov")
    }

    // 12. linkRecording with nil → 解除連結
    func test_linkRecording_nilClearsLink() {
        let store = makeStore()
        store.linkRecording(named: "clip.mov")
        store.linkRecording(named: nil)
        XCTAssertNil(store.linkedRecordingName)
    }

    // 13. Persist + 重建 store 後狀態保留
    func test_persistAndReload_preservesState() {
        let store1 = makeStore()
        store1.toggleChecklistItem(id: "framing")
        store1.updateNotes("persisted")
        store1.addActionItem("action 1")
        store1.linkRecording(named: "clip.mov")

        let store2 = ShotPlannerStore(defaults: defaults)
        XCTAssertTrue(store2.checklist.first(where: { $0.id == "framing" })?.isDone == true)
        XCTAssertEqual(store2.notes, "persisted")
        XCTAssertEqual(store2.actionItems, ["action 1"])
        XCTAssertEqual(store2.linkedRecordingName, "clip.mov")
    }

    // 14. 任何 mutation 都會 post .shotPlannerDidChange
    func test_mutation_postsNotification() {
        let store = makeStore()
        let expectation = expectation(forNotification: .shotPlannerDidChange, object: nil)
        store.updateNotes("trigger")
        wait(for: [expectation], timeout: 0.5)
    }
}
