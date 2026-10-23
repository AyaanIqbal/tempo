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

public struct TaskGraphNode: Identifiable, Sendable {
    public enum Kind: Sendable { case workspace, label, inbox, task }
    public let id: String
    public let parent: String?
    public let title: String
    public let kind: Kind
    public let itemID: UUID?
    public let status: TaskStatus?
    public init(id: String, parent: String?, title: String, kind: Kind, itemID: UUID? = nil, status: TaskStatus? = nil) {
        self.id = id; self.parent = parent; self.title = title; self.kind = kind; self.itemID = itemID; self.status = status
    }
}
public extension Workspace {
    func taskGraph(scope: String = "all", query: String = "", includeResolved: Bool = true) -> [TaskGraphNode] {
        let scoped = tasks.filter { task in
            scope == "all" || (scope == "inbox" && effectiveLabel(task) == nil) || (scope == "today" && task.dueDate.map { Calendar.current.isDateInToday($0) } == true) || labelPath(effectiveLabel(task)).contains { $0.id.uuidString == scope }
        }
        let matching = scoped.filter { task in
            (includeResolved || !task.status.isResolved) && (query.isEmpty || task.title.localizedCaseInsensitiveContains(query) || task.notes.localizedCaseInsensitiveContains(query) || labelPath(effectiveLabel(task)).contains { $0.name.localizedCaseInsensitiveContains(query) })
        }
        // Keep ancestors so a search result never loses the structure that explains it.
        var taskIDs = Set(matching.map(\.id))
        for task in matching {
            var parent = task.parentID
            while let id = parent { taskIDs.insert(id); parent = tasks.first { $0.id == id }?.parentID }
        }
        let visibleTasks = tasks.filter { taskIDs.contains($0.id) }
        var labelIDs = Set(visibleTasks.flatMap { labelPath(effectiveLabel($0)).map(\.id) })
        if query.isEmpty && scope == "all" { labelIDs.formUnion(labels.map(\.id)) }
        if let selected = UUID(uuidString: scope), labels.contains(where: { $0.id == selected }) {
            labelIDs.formUnion(labelPath(selected).map(\.id))
            if query.isEmpty { labelIDs.formUnion(labelDescendants(of: selected)) }
        }
        var nodes = [TaskGraphNode(id: "root", parent: nil, title: "My workspace", kind: .workspace)]
        for row in labelRows() where labelIDs.contains(row.id) {
            let label = row.label
            nodes.append(TaskGraphNode(id: "label-\(label.id)", parent: label.parentID.map { "label-\($0)" } ?? "root", title: label.name, kind: .label, itemID: label.id))
        }
        if visibleTasks.contains(where: { effectiveLabel($0) == nil }) || scope == "inbox" {
            nodes.append(TaskGraphNode(id: "inbox", parent: "root", title: "Unlabeled", kind: .inbox))
        }
        for task in visibleTasks {
            let parent = task.parentID.map { "task-\($0)" } ?? effectiveLabel(task).map { "label-\($0)" } ?? "inbox"
            nodes.append(TaskGraphNode(id: "task-\(task.id)", parent: parent, title: task.title, kind: .task, itemID: task.id, status: task.status))
        }
        return nodes
    }
}
