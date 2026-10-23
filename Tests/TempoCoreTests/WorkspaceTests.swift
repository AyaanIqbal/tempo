import Foundation
import TempoCore

func completionCascadesAndPreservesCanceled() throws {
    var w = Workspace(); let p = w.addTask(title: "Parent")!; let a = w.addTask(title: "A", parent: p)!; let b = w.addTask(title: "B", parent: a)!
    try w.setStatus(b, to: .canceled, reason: "No longer needed")
    precondition(w.tasks.first { $0.id == p }?.status == .done)
    try w.setStatus(p, to: .done)
    precondition(w.tasks.first { $0.id == b }?.status == .canceled)
    try w.setStatus(b, to: .todo)
    precondition(w.tasks.first { $0.id == p }?.status == .todo)
    precondition(w.tasks.first { $0.id == a }?.status == .todo)
}
func parentCompletionAndReopen() throws {
    var w = Workspace(); let p = w.addTask(title: "Parent")!; let c = w.addTask(title: "Child", parent: p)!
    try w.setStatus(p, to: .done)
    precondition(w.tasks.allSatisfy { $0.status == .done })
    try w.setStatus(p, to: .todo)
    precondition(w.tasks.first { $0.id == c }?.status == .done)
    _ = w.addTask(title: "New child", parent: p)
    precondition(w.tasks.first { $0.id == p }?.status == .todo)
}
func cancellationRequiresReasonAndCascades() throws {
    var w = Workspace(); let p = w.addTask(title: "Parent")!; let c = w.addTask(title: "Child", parent: p)!
    do { try w.setStatus(p, to: .canceled, reason: "  "); preconditionFailure("Accepted an empty cancellation reason") } catch ModelError.reasonRequired {}
    try w.setStatus(p, to: .canceled, reason: "Scope changed")
    precondition(w.tasks.first { $0.id == c }?.cancellationReason == "Scope changed")
}
func labelsAndSmartMatching() {
    var w = Workspace(); let work = TaskLabel(name: "Work"); let edge = TaskLabel(name: "Edge Security", parentID: work.id); w.labels = [work, edge]
    let p = w.addTask(title: "Parent", label: edge.id)!; let c = w.addTask(title: "Child", parent: p)!
    precondition(w.labelPath(w.effectiveLabel(w.tasks.first { $0.id == c }!)).map(\.name) == ["Work", "Edge Security"])
    precondition(w.matches(for: "Edge Security WAF harvester").first?.id == edge.id)
    precondition(w.matches(for: "Discuss Edge Security with team").isEmpty)
}
func deleteAndBackupValidation() throws {
    var w = Workspace(); let p = w.addTask(title: "Parent")!; _ = w.addTask(title: "Child", parent: p)
    let data = try JSONEncoder().encode(w); let restored = try JSONDecoder().decode(Workspace.self, from: data); precondition(restored == w)
    w.delete(p); precondition(w.tasks.isEmpty)
    var cyclic = Workspace(); let id = cyclic.addTask(title: "Cycle")!; cyclic.tasks[0].parentID = id
    do { try cyclic.validate(); preconditionFailure("Accepted a parent cycle") } catch ModelError.invalidBackup {}
}

try completionCascadesAndPreservesCanceled()
try parentCompletionAndReopen()
try cancellationRequiresReasonAndCascades()
labelsAndSmartMatching()
try deleteAndBackupValidation()
print("Passed all 5 Tempo model checks.")

func labelTreeEditing() throws {
    var w = Workspace()
    let work = try w.addLabel(name: "Work")
    let school = try w.addLabel(name: "School")
    let edge = try w.addLabel(name: "Edge Security", parent: work)
    let backend = try w.addLabel(name: "Backend", parent: edge)
    precondition(w.labelRows().map(\.id) == [work, edge, backend, school])
    precondition(w.labelRows(collapsed: [work]).map(\.id) == [work, school])
    do { try w.updateLabel(work, name: "Work", parent: backend); preconditionFailure("Allowed a label cycle") } catch LabelError.invalidParent {}
    do { _ = try w.addLabel(name: " work "); preconditionFailure("Allowed a duplicate sibling") } catch LabelError.duplicateName {}
    try w.updateLabel(edge, name: "Security", parent: school)
    precondition(w.labelPath(backend).map(\.name) == ["School", "Security", "Backend"])
    let task = w.addTask(title: "WAF", label: edge)!
    w.removeLabel(edge)
    precondition(w.tasks.first { $0.id == task }?.labelID == school)
    precondition(w.labelPath(backend).map(\.name) == ["School", "Backend"])
    try w.validate()
}
func graphRelationshipsAndCompletion() throws {
    var w = Workspace(); let work = try w.addLabel(name: "Work"); let edge = try w.addLabel(name: "Edge Security", parent: work)
    let parent = w.addTask(title: "WAF", label: edge)!; let child = w.addTask(title: "Harvester", parent: parent)!
    try w.setStatus(child, to: .done)
    let inbox = w.addTask(title: "Unlabeled task")!
    var graph = w.taskGraph()
    precondition(graph.first { $0.itemID == child }?.parent == "task-\(parent)")
    precondition(graph.first { $0.itemID == child }?.status == .done)
    precondition(graph.first { $0.itemID == parent }?.parent == "label-\(edge)")
    precondition(graph.first { $0.itemID == edge }?.parent == "label-\(work)")
    precondition(graph.first { $0.itemID == inbox }?.parent == "inbox")
    graph = w.taskGraph(scope: edge.uuidString, query: "Harvester")
    precondition(graph.contains { $0.itemID == parent })
    precondition(!graph.contains { $0.itemID == inbox })
    precondition(graph.allSatisfy { node in node.parent == nil || graph.contains { $0.id == node.parent } })
    precondition(!w.taskGraph(includeResolved: false).contains { $0.itemID == child })
}
try labelTreeEditing()
try graphRelationshipsAndCompletion()
print("Passed label editing/tree and graph relationship/completion checks (7 groups total).")

func captionsAndLegacyLabels() throws {
    var workspace = Workspace()
    precondition(workspace.viewCaption(for: "all") == "Make room for what matters.")
    precondition(workspace.viewCaption(for: "inbox").contains("Unlabelled"))
    precondition(workspace.viewCaption(for: "today").contains("today"))
    let school = try workspace.addLabel(name: "School")
    let work = try workspace.addLabel(name: "Work")
    workspace.labels[0].caption = "One course at a time."
    precondition(workspace.viewCaption(for: school.uuidString) == "One course at a time.")
    precondition(workspace.viewCaption(for: work.uuidString) == "Tasks and progress for Work.")
    let restored = try JSONDecoder().decode(Workspace.self, from: JSONEncoder().encode(workspace))
    precondition(restored.viewCaption(for: school.uuidString) == "One course at a time.")
    let legacyData = Data("{\"id\":\"\(UUID().uuidString)\",\"name\":\"Legacy\"}".utf8)
    let legacy = try JSONDecoder().decode(TaskLabel.self, from: legacyData)
    precondition(legacy.caption == nil)
    workspace.labels[0].caption = "  "
    precondition(workspace.viewCaption(for: school.uuidString) == "Tasks and progress for School.")
}
try captionsAndLegacyLabels()
print("Caption persistence, defaults, and legacy compatibility checks passed (8 groups total).")

func sidebarOrderAndBreadcrumbs() throws {
    var workspace = Workspace()
    let work = try workspace.addLabel(name: "Work")
    let school = try workspace.addLabel(name: "School")
    let ai = try workspace.addLabel(name: "AI Sec", parent: work)
    let nested = try workspace.addLabel(name: "Research", parent: ai)
    precondition(workspace.sidebarScopes() == ["all", "inbox", "today", work.uuidString, ai.uuidString, nested.uuidString, school.uuidString])
    precondition(workspace.adjacentScope(to: work.uuidString, offset: 1) == ai.uuidString)
    precondition(workspace.adjacentScope(to: work.uuidString, offset: 1, collapsed: [work]) == school.uuidString)
    precondition(workspace.adjacentScope(to: "all", offset: -1) == "all")
    precondition(workspace.labelPath(nested).map(\.name) == ["Work", "AI Sec", "Research"])
}
try sidebarOrderAndBreadcrumbs()
print("Sidebar navigation and breadcrumb checks passed (9 groups total).")

func rolledUpCountsAndVisibleSubtasks() throws {
    var w = Workspace(); let work = try w.addLabel(name: "Work")
    let ai = try w.addLabel(name: "AI Sec", parent: work); let edge = try w.addLabel(name: "Edge Sec", parent: work)
    let a = w.addTask(title: "AI task", label: ai)!
    let b = w.addTask(title: "Edge one", label: edge)!; _ = w.addTask(title: "Edge two", label: edge)
    precondition(w.taskCount(in: ai) == 1 && w.taskCount(in: edge) == 2 && w.taskCount(in: work) == 3)
    _ = w.addTask(title: "Work itself", label: work)
    precondition(w.taskCount(in: work) == 4)
    let child = w.addTask(title: "AI child", parent: a)!
    precondition(w.taskCount(in: ai) == 2 && w.taskCount(in: work) == 5)
    try w.setStatus(b, to: .done)
    let roots = w.tasks.filter { $0.parentID == nil }
    precondition(w.taskRows(roots: roots).contains { $0.id == b })
    precondition(w.taskRows(roots: roots).first { $0.id == child }?.depth == 1)
    precondition(!w.taskRows(roots: roots, collapsed: [a]).contains { $0.id == child })
    precondition(!w.taskRows(roots: roots, showResolved: false).contains { $0.id == b })
}
func persistentSmartEntry() throws {
    var w = Workspace(); let work = try w.addLabel(name: "Work"); let edge = try w.addLabel(name: "Edge Security", parent: work)
    let task = w.addTask(title: "Edge Security WAF harvester")!
    precondition(w.smartMatches(for: w.tasks[0]).first?.id == edge)
    let saved = try JSONDecoder().decode(Workspace.self, from: JSONEncoder().encode(w))
    precondition(saved.smartMatches(for: saved.tasks[0]).first?.id == edge)
    w.acceptSmartMatch(task: task, label: edge)
    precondition(w.tasks[0].title == "WAF harvester" && w.tasks[0].labelID == edge)
    let dismissed = w.addTask(title: "Edge Security another task")!
    let index = w.tasks.firstIndex { $0.id == dismissed }!; w.tasks[index].smartEntryDismissed = true
    let restored = try JSONDecoder().decode(Workspace.self, from: JSONEncoder().encode(w))
    precondition(restored.smartMatches(for: restored.tasks[index]).isEmpty)
    let child = w.addTask(title: "Edge Security inherited labels", parent: task)!
    precondition(w.smartMatches(for: w.tasks.first { $0.id == child }!).isEmpty)
}
try rolledUpCountsAndVisibleSubtasks()
try persistentSmartEntry()
print("Label count, nested/completed task, and persistent smart-entry checks passed (11 groups total).")
