import Foundation

public enum TaskStatus: String, Codable, CaseIterable, Sendable {
    case todo = "To do", inProgress = "In progress", done = "Done", canceled = "Canceled"
    public var isResolved: Bool { self == .done || self == .canceled }
    public var symbol: String { switch self { case .todo: "circle"; case .inProgress: "circle.lefthalf.filled"; case .done: "checkmark.circle.fill"; case .canceled: "xmark.circle" } }
}
public enum Importance: Int, Codable, CaseIterable, Sendable {
    case none = 0, low, medium, high, urgent
    public var title: String { ["None", "Low", "Medium", "High", "Urgent"][rawValue] }
}
public struct TaskItem: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID()
    public var title: String
    public var notes = ""
    public var status: TaskStatus = .todo
    public var importance: Importance = .none
    public var dueDate: Date?
    public var labelID: UUID?
    public var parentID: UUID?
    public var smartEntryDismissed: Bool?
    public var cancellationReason = ""
    public var createdAt = Date()
    public init(title: String, parentID: UUID? = nil, labelID: UUID? = nil) { self.title = title; self.parentID = parentID; self.labelID = labelID }
}
public struct TaskLabel: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID()
    public var name: String
    public var caption: String?
    public var parentID: UUID?
    public init(name: String, parentID: UUID? = nil) { self.name = name; self.parentID = parentID }
}
public struct ViewProperties: Codable, Equatable, Sendable {
    public var labels = false
    public var importance = false
    public var dueDate = false
    public var status = false
    public init() {}
}
public struct Workspace: Codable, Equatable, Sendable {
    public var tasks: [TaskItem] = []
    public var labels: [TaskLabel] = []
    public var listProperties = ViewProperties()
    public var boardProperties = ViewProperties()
    public init() {}
    public func children(of id: UUID) -> [TaskItem] { tasks.filter { $0.parentID == id } }
    public func descendants(of id: UUID) -> [UUID] { children(of: id).flatMap { [$0.id] + descendants(of: $0.id) } }
    public func labelPath(_ id: UUID?) -> [TaskLabel] {
        guard let id, let label = labels.first(where: { $0.id == id }) else { return [] }
        return labelPath(label.parentID) + [label]
    }
    public func effectiveLabel(_ task: TaskItem) -> UUID? {
        if let parent = tasks.first(where: { $0.id == task.parentID }) { return effectiveLabel(parent) }
        return task.labelID
    }
    public func matches(for title: String) -> [TaskLabel] {
        labels.filter { title.lowercased().hasPrefix($0.name.lowercased() + " ") }.sorted { $0.name.count > $1.name.count }
    }
    public mutating func setStatus(_ id: UUID, to status: TaskStatus, reason: String = "") throws {
        let reason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard status != .canceled || !reason.isEmpty else { throw ModelError.reasonRequired }
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[index].status = status
        tasks[index].cancellationReason = status == .canceled ? reason : ""
        if status.isResolved {
            let ids = Set(descendants(of: id))
            for i in tasks.indices where ids.contains(tasks[i].id) && !tasks[i].status.isResolved {
                tasks[i].status = status
                tasks[i].cancellationReason = status == .canceled ? reason : ""
            }
        }
        reconcileParent(of: id)
    }
    public mutating func reconcileParent(of id: UUID) {
        guard let parent = tasks.first(where: { $0.id == id })?.parentID, let index = tasks.firstIndex(where: { $0.id == parent }) else { return }
        let allResolved = children(of: parent).allSatisfy { $0.status.isResolved }
        if allResolved && tasks[index].status != .canceled { tasks[index].status = .done }
        else if !allResolved && tasks[index].status.isResolved { tasks[index].status = .todo; tasks[index].cancellationReason = "" }
        reconcileParent(of: parent)
    }
    public mutating func addTask(title: String, parent: UUID? = nil, label: UUID? = nil) -> UUID? {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return nil }
        let task = TaskItem(title: title, parentID: parent, labelID: parent == nil ? label : nil)
        tasks.append(task)
        reconcileParent(of: task.id)
        return task.id
    }
    public mutating func delete(_ id: UUID) {
        let parent = tasks.first(where: { $0.id == id })?.parentID
        let ids = Set([id] + descendants(of: id))
        tasks.removeAll { ids.contains($0.id) }
        if let parent, let child = children(of: parent).first { reconcileParent(of: child.id) }
    }
    public func validate() throws {
        guard Set(tasks.map(\.id)).count == tasks.count, Set(labels.map(\.id)).count == labels.count else { throw ModelError.invalidBackup }
        for task in tasks {
            guard !task.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  task.labelID == nil || labels.contains(where: { $0.id == task.labelID }),
                  task.status != .canceled || !task.cancellationReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ModelError.invalidBackup }
            var seen: Set<UUID> = [task.id]; var current = task.parentID
            while let id = current {
                guard seen.insert(id).inserted, let parent = tasks.first(where: { $0.id == id }) else { throw ModelError.invalidBackup }
                current = parent.parentID
            }
        }
        for label in labels {
            guard !label.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ModelError.invalidBackup }
            var seen: Set<UUID> = [label.id]; var current = label.parentID
            while let id = current {
                guard seen.insert(id).inserted, let parent = labels.first(where: { $0.id == id }) else { throw ModelError.invalidBackup }
                current = parent.parentID
            }
        }
    }
}
public enum ModelError: LocalizedError {
    case reasonRequired, invalidBackup
    public var errorDescription: String? { switch self { case .reasonRequired: "Enter a reason before canceling this task."; case .invalidBackup: "This backup contains invalid tasks or label relationships." } }
}
