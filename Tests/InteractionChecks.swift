import Foundation
import TempoCore

@main struct InteractionChecks {
    @MainActor static func main() throws {
        let temporary = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let store = Store(fileURL: temporary.appending(path: "workspace.json"))
        let first = store.add("First task")!
        let second = store.add("Second task")!
        precondition(store.selectedID == second && store.inspectorID == nil, "Creation must not open task details")
        precondition(store.roots.first?.id == second, "New tasks should appear at the top")
        store.selectNext(1)
        precondition(store.selectedID == first && store.inspectorID == nil, "Arrow selection should stay in the task list")
        store.openTask(first)
        precondition(store.inspectorID == first, "Explicit open should show details")
        store.selectNext(-1)
        precondition(store.selectedID == second && store.inspectorID == nil)
        let child = store.add("Subtask", parent: second)!
        precondition(store.selectedID == child && store.inspectorID == nil)
        precondition(store.taskRows.contains { $0.id == child && $0.depth == 1 })
        store.status(first, .done)
        precondition(store.roots.contains { $0.id == first }, "Completed tasks should be visible by default")
        let label = store.addLabel("Edge Security", parent: nil)!
        let smart = store.add("Edge Security WAF")!
        store.acceptSelectedSuggestion()
        precondition(store.workspace.tasks.first { $0.id == smart }?.title == "WAF")
        precondition(store.workspace.tasks.first { $0.id == smart }?.labelID == label)
        // Summaries use the current scope, independently of hidden properties or search.
        let parentLabel = store.addLabel("Work", parent: nil)!
        store.updateLabel(label, name: "Edge Security", parent: parentLabel)
        let direct = store.add("Direct work", label: parentLabel)!
        let otherLabel = store.addLabel("School", parent: nil)!
        let other = store.add("Other project", label: otherLabel)!
        store.openScope(label.uuidString)
        precondition(store.scopedTasks.map(\.id) == [smart], "A label summary must exclude unrelated tasks")
        store.openScope(parentLabel.uuidString)
        precondition(Set(store.scopedTasks.map(\.id)) == Set([smart, direct]), "Parent summaries include child-label tasks")
        store.openScope("inbox")
        precondition(store.scopedTasks.allSatisfy { store.workspace.effectiveLabel($0) == nil })
        store.edit(other) { $0.dueDate = Date() }
        store.openScope("today")
        precondition(store.scopedTasks.map(\.id) == [other], "Today summarizes today's due tasks")
        store.openScope("all")
        store.status(smart, .inProgress)
        precondition(store.roots.first?.id == smart, "In-progress tasks precede newer To do tasks")
        precondition(store.roots.last?.id == first, "Completed tasks belong below open work")
        store.selectedID = smart
        store.activeRegion = .editor
        precondition(!store.canUseTaskShortcuts, "Typing must disable task shortcuts even with a task selected")
        store.activeRegion = .sidebar
        precondition(!store.canUseTaskShortcuts, "Sidebar navigation must not mutate a previously selected task")
        precondition(!store.highlightsTask(smart), "Returning to the sidebar clears the task highlight")
        store.activeRegion = .tasks
        precondition(store.canUseTaskShortcuts, "Task shortcuts should work after leaving text editing")
        precondition(store.highlightsTask(smart), "Entering tasks highlights only the task region")
        store.toggleProperty(\.labels)
        store.viewMode = .board
        precondition(!store.properties.labels, "Property visibility is independent per view")
        store.toggleProperty(\.importance)
        store.viewMode = .list
        precondition(store.properties.labels && !store.properties.importance)
        let loaded = Store(fileURL: temporary.appending(path: "workspace.json"))
        precondition(loaded.workspace == store.workspace, "Selection changes must not lose saved task data")
        print("Interaction checks passed: creation, explicit open, task navigation, subtasks, completed visibility, smart entry, scoped summaries, status sorting, focus highlights, per-view properties, and persistence.")
    }
}
