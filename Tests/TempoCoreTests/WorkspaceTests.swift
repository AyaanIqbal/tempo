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
