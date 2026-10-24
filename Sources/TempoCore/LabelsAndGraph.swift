import Foundation

public struct LabelTreeRow: Identifiable, Sendable {
    public let label: TaskLabel
    public let depth: Int
    public var id: UUID { label.id }
}
public enum LabelError: LocalizedError {
    case emptyName, duplicateName, invalidParent
    public var errorDescription: String? {
        switch self {
        case .emptyName: "Give the label a name."
        case .duplicateName: "A label with this name already exists in this branch."
        case .invalidParent: "A label cannot be moved inside itself or one of its sub-labels."
        }
    }
}
public extension Workspace {
    func labelRows(collapsed: Set<UUID> = [], parent: UUID? = nil, depth: Int = 0) -> [LabelTreeRow] {
        labels.filter { $0.parentID == parent }.flatMap { label in
            [LabelTreeRow(label: label, depth: depth)] + (collapsed.contains(label.id) ? [] : labelRows(collapsed: collapsed, parent: label.id, depth: depth + 1))
        }
    }
    func labelDescendants(of id: UUID) -> Set<UUID> {
        Set(labels.filter { $0.parentID == id }.flatMap { [$0.id] + Array(labelDescendants(of: $0.id)) })
    }
    @discardableResult mutating func addLabel(name: String, parent: UUID? = nil) throws -> UUID {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        try validateLabel(name: name, parent: parent)
        let label = TaskLabel(name: name, parentID: parent); labels.append(label); return label.id
    }
    mutating func updateLabel(_ id: UUID, name: String, parent: UUID?) throws {
        guard let index = labels.firstIndex(where: { $0.id == id }) else { return }
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        try validateLabel(name: name, parent: parent, excluding: id)
        labels[index].name = name; labels[index].parentID = parent
    }
    // Remove only the label. Its children and directly assigned tasks move up one level.
    mutating func removeLabel(_ id: UUID) {
        guard let label = labels.first(where: { $0.id == id }) else { return }
        for index in labels.indices where labels[index].parentID == id { labels[index].parentID = label.parentID }
        for index in tasks.indices where tasks[index].labelID == id { tasks[index].labelID = label.parentID }
        labels.removeAll { $0.id == id }
    }
    private func validateLabel(name: String, parent: UUID?, excluding id: UUID? = nil) throws {
        guard !name.isEmpty else { throw LabelError.emptyName }
        if let parent {
            guard labels.contains(where: { $0.id == parent }), parent != id else { throw LabelError.invalidParent }
            if let id, labelDescendants(of: id).contains(parent) { throw LabelError.invalidParent }
        }
        guard !labels.contains(where: { $0.id != id && $0.parentID == parent && $0.name.caseInsensitiveCompare(name) == .orderedSame }) else { throw LabelError.duplicateName }
    }
}

public extension Workspace {
    func viewCaption(for scope: String) -> String {
        switch scope {
        case "inbox": return "Unlabelled tasks, ready to find their place."
        case "today": return "Focus on what's due today."
        case "all": return "Make room for what matters."
        default:
            guard let label = labels.first(where: { $0.id.uuidString == scope }) else { return "Make room for what matters." }
            let custom = label.caption?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return custom.isEmpty ? "Tasks and progress for \(label.name)." : custom
        }
    }
}

public extension Workspace {
    func sidebarScopes(collapsed: Set<UUID> = []) -> [String] {
        ["all", "inbox", "today"] + labelRows(collapsed: collapsed).map { $0.id.uuidString }
    }
    func adjacentScope(to current: String, offset: Int, collapsed: Set<UUID> = []) -> String {
        let scopes = sidebarScopes(collapsed: collapsed)
        guard let index = scopes.firstIndex(of: current) else { return scopes[0] }
        return scopes[min(max(index + offset, 0), scopes.count - 1)]
    }
}

public struct TaskTreeRow: Identifiable, Sendable {
    public let task: TaskItem
    public let depth: Int
    public var id: UUID { task.id }
}
public extension Workspace {
    func taskCount(in label: UUID) -> Int {
        tasks.filter { labelPath(effectiveLabel($0)).contains { $0.id == label } }.count
    }
    func taskRows(roots: [TaskItem], collapsed: Set<UUID> = [], showResolved: Bool = true, depth: Int = 0, byImportance: Bool = false) -> [TaskTreeRow] {
        sortedTasks(roots, byImportance: byImportance).flatMap { task in
            guard showResolved || !task.status.isResolved else { return [TaskTreeRow]() }
            return [TaskTreeRow(task: task, depth: depth)] + (collapsed.contains(task.id) ? [] : taskRows(roots: children(of: task.id), collapsed: collapsed, showResolved: showResolved, depth: depth + 1, byImportance: byImportance))
        }
    }
    func smartMatches(for task: TaskItem) -> [TaskLabel] {
        guard task.parentID == nil, task.smartEntryDismissed != true else { return [] }
        return matches(for: task.title)
    }
    mutating func acceptSmartMatch(task id: UUID, label labelID: UUID) {
        guard let index = tasks.firstIndex(where: { $0.id == id }), let label = smartMatches(for: tasks[index]).first(where: { $0.id == labelID }) else { return }
        let title = String(tasks[index].title.dropFirst(label.name.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        tasks[index].title = title; tasks[index].labelID = label.id; tasks[index].smartEntryDismissed = nil
    }
}

public extension Workspace {
    func sortedTasks(_ tasks: [TaskItem], byImportance: Bool = false) -> [TaskItem] {
        func rank(_ status: TaskStatus) -> Int {
            switch status { case .inProgress: 0; case .todo: 1; case .done: 2; case .canceled: 3 }
        }
        return tasks.sorted {
            if rank($0.status) != rank($1.status) { return rank($0.status) < rank($1.status) }
            if byImportance && $0.importance != $1.importance { return $0.importance.rawValue > $1.importance.rawValue }
            return $0.createdAt > $1.createdAt
        }
    }
}
