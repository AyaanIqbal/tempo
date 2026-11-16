import Foundation
import TempoCore

@main struct InteractionChecks {
    @MainActor static func main() throws {
        let temporary = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let suite = "TempoChecks-" + UUID().uuidString
        let preferences = UserDefaults(suiteName: suite)!
        defer { preferences.removePersistentDomain(forName: suite) }
        let store = Store(fileURL: temporary.appending(path: "workspace.json"), preferences: preferences)
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
        store.edit(other) { $0.dueDate = Date() }
        store.openScope("today")
        precondition(store.scopedTasks.map(\.id) == [other], "Today summarizes today's due tasks")
        store.openScope("all")
        precondition(!store.showInProgress && !store.availableStatuses.contains(.inProgress), "In progress is opt-in")
        store.showInProgress = true
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
        // Status cards toggle a filter in-place and never change the label scope.
        store.openScope(parentLabel.uuidString)
        store.toggleStatusFilter(.inProgress)
        precondition(store.statusFilter == .inProgress && store.scope == parentLabel.uuidString)
        precondition(store.taskRows.map(\.id) == [smart])
        store.toggleStatusFilter(.inProgress)
        precondition(store.statusFilter == nil && Set(store.taskRows.map(\.id)) == Set([smart, direct]))
        let withProgress = Store(fileURL: temporary.appending(path: "workspace.json"), preferences: preferences)
        precondition(withProgress.showInProgress, "Enabled In progress preference must persist")
        store.showInProgress = false
        precondition(store.displayStatus(store.workspace.tasks.first { $0.id == smart }!) == .todo)
        precondition(store.summaryCount(.todo) == 2)
        precondition(store.workspace.tasks.first { $0.id == smart }?.status == .inProgress, "Disabling a status must preserve its saved value")
        store.toggleStatusFilter(.todo)
        precondition(Set(store.taskRows.map(\.id)) == Set([smart, direct]))
        store.toggleStatusFilter(.todo)
        precondition(store.statusFilter == nil)
        store.openScope("all")
        store.toggleStatusFilter(.done)
        precondition(store.taskRows.allSatisfy { $0.task.status == .done })
        store.toggleStatusFilter(.done)
        let parent = store.add("Parent created from composer")!
        store.beginInlineSubtask(of: parent)
        store.inlineSubtaskDraft = "Child one"
        let childOne = store.submitInlineSubtask()!
        store.inlineSubtaskDraft = "Child two"
        let childTwo = store.submitInlineSubtask(nest: true)!
        precondition(store.workspace.tasks.first { $0.id == childOne }?.parentID == parent)
        precondition(store.workspace.tasks.first { $0.id == childTwo }?.parentID == parent)
        precondition(store.inlineSubtaskParent == childTwo)
        store.inlineSubtaskDraft = "Grandchild"
        let grandchild = store.submitInlineSubtask()!
        precondition(store.workspace.tasks.first { $0.id == grandchild }?.parentID == childTwo)
        precondition(store.inspectorID == nil, "Inline subtask entry never needs a detail pane")
        store.edit(parent) { $0.notes = "## Heading\n- **Important** step\n- Another step" }
        store.editNotes(parent)
        precondition(store.inspectorID == parent && store.focusNotesID == parent && store.viewMode == .list)
        store.closeInspector()
        precondition(!store.workspace.sidebarScopes().contains("inbox"))
        // Right from the sidebar requests creation, regardless of existing tasks.
        store.openScope(parentLabel.uuidString)
        store.selectedID = smart
        let request = store.focusComposer
        store.requestNewTask()
        precondition(store.focusComposer != request && store.activeRegion == .editor && store.inspectorID == nil)
        store.openTask(smart)
        precondition(store.focusNotesID == smart && store.activeRegion == .editor)
        let notesRequest = store.notesFocusRequest
        store.openTask(smart)
        precondition(store.notesFocusRequest != notesRequest, "Reopening an expanded task must focus notes again")
        let savedNotes = store.workspace.tasks.first { $0.id == parent }!.notes
        store.navigateBack()
        precondition(store.inspectorID == nil && store.activeRegion == .tasks)
        store.navigateBack()
        precondition(store.activeRegion == .sidebar && store.scope == parentLabel.uuidString)
        store.navigateBack()
        precondition(store.scope == "all" && store.activeRegion == .sidebar)
        store.navigateBack()
        precondition(store.scope == "all", "Escape at home is idempotent")
        precondition(store.workspace.tasks.first { $0.id == parent }!.notes == savedNotes)
        store.beginInlineSubtask(of: parent)
        store.inlineSubtaskDraft = "Unfinished thought"
        store.navigateBack()
        store.beginInlineSubtask(of: parent)
        precondition(store.inlineSubtaskDraft == "Unfinished thought", "Escape must not discard an unfinished subtask draft")
        store.navigateBack()
        // Exercise the warmed display cache across filter and workspace mutations.
        store.openScope(parentLabel.uuidString)
        store.search = "cached child"
        precondition(store.taskRows.isEmpty)
        let cachedChild = store.add("Cached child", parent: direct)!
        precondition(store.taskRows.map(\.id) == [direct, cachedChild], "Editing the workspace invalidates cached search results and retains matching ancestors")
        store.collapsedTasks.insert(direct)
        precondition(store.taskRows.map(\.id) == [direct])
        store.collapsedTasks.remove(direct)
        store.search = ""
        let beforeCompletion = store.openTaskCount(in: parentLabel)
        store.status(cachedChild, .done)
        precondition(store.openTaskCount(in: parentLabel) == beforeCompletion - 2, "Completing a child and its parent updates cached rollups")
        precondition(store.summaryCount(.done) >= 2)
        let loaded = Store(fileURL: temporary.appending(path: "workspace.json"), preferences: preferences)
        precondition(!loaded.showInProgress, "Status preference persists independently of task data")
        precondition(loaded.workspace == store.workspace, "Selection changes must not lose saved task data")
        print("Interaction checks passed: creation, explicit open, task navigation, subtasks, completed visibility, smart entry, scoped summaries, status sorting, focus highlights, per-view properties, and persistence.")
    }
}
