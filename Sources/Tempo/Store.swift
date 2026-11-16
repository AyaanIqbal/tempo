import SwiftUI
import AppKit
import UniformTypeIdentifiers
import TempoCore

enum NavigationRegion: Hashable { case sidebar, tasks, editor }

enum WorkspaceView: String, CaseIterable { case list = "List", board = "Board" }

private struct TaskIndex {
    let byID: [UUID: TaskItem]
    let children: [UUID?: [TaskItem]]
    var labelPaths: [UUID: [TaskLabel]] = [:]
    var taskLabels: [UUID: UUID] = [:]
    var openCounts: [UUID: Int] = [:]

    init(_ workspace: Workspace) {
        byID = Dictionary(uniqueKeysWithValues: workspace.tasks.map { ($0.id, $0) })
        children = Dictionary(grouping: workspace.tasks, by: \.parentID)
        for label in workspace.labels { labelPaths[label.id] = workspace.labelPath(label.id) }
        var pending = children[nil] ?? []
        while let task = pending.popLast() {
            let label = task.parentID.flatMap { taskLabels[$0] } ?? (task.parentID == nil ? task.labelID : nil)
            if let label {
                taskLabels[task.id] = label
                if !task.status.isResolved {
                    for ancestor in labelPaths[label] ?? [] { openCounts[ancestor.id, default: 0] += 1 }
                }
            }
            pending.append(contentsOf: children[task.id] ?? [])
        }
    }
}

private struct TaskDisplayKey: Equatable {
    let scope: String
    let search: String
    let status: TaskStatus?
    let showResolved: Bool
    let showInProgress: Bool
    let byImportance: Bool
    let collapsed: Set<UUID>
    let today: Date?
}

private struct TaskDisplay {
    let key: TaskDisplayKey
    let scoped: [TaskItem]
    let ids: Set<UUID>
    let roots: [TaskItem]
    let rows: [TaskTreeRow]
    let counts: [TaskStatus: Int]
    let columns: [TaskStatus: [TaskItem]]
}

@MainActor @Observable final class Store {
    var workspace = Workspace() {
        didSet { cachedIndex = nil; cachedDisplay = nil }
    }
    @ObservationIgnored private var cachedIndex: TaskIndex?
    @ObservationIgnored private var cachedDisplay: TaskDisplay?
    private var taskIndex: TaskIndex {
        let current = workspace // Observe workspace changes even on cache hits.
        if let cachedIndex { return cachedIndex }
        let index = TaskIndex(current)
        cachedIndex = index
        return index
    }
    var activeRegion: NavigationRegion = .sidebar
    var selectedID: UUID?
    var inspectorID: UUID?
    var inlineSubtaskParent: UUID?
    var inlineSubtaskDraft = ""
    private var inlineDraftParent: UUID?
    var focusNotesID: UUID?
    var notesFocusRequest = UUID()
    var statusFilter: TaskStatus?
    var showInProgress: Bool {
        didSet {
            preferences.set(showInProgress, forKey: "tempo.showInProgress")
            if !showInProgress && statusFilter == .inProgress { statusFilter = nil }
        }
    }
    private let preferences: UserDefaults
    var collapsedTasks: Set<UUID> = []
    var scope = "all"
    var collapsedLabels: Set<UUID> = []
    var viewMode: WorkspaceView = .list
    var board: Bool {
        get { viewMode == .board }
        set { viewMode = newValue ? .board : .list }
    }
    var search = ""
    var showResolved = true
    var sortByImportance = false
    var showCommands = false
    var showHelp = false
    var pendingCancel: UUID?
    var focusComposer = UUID()
    var message: String?
    var undoWorkspace: Workspace?
    private var loadFailed = false
    private let fileURL: URL
    init(fileURL: URL = URL.applicationSupportDirectory.appending(path: "Tempo/workspace.json"), preferences: UserDefaults = .standard) {
        self.preferences = preferences
        self.showInProgress = preferences.bool(forKey: "tempo.showInProgress")
        self.fileURL = fileURL
        do {
            if FileManager.default.fileExists(atPath: fileURL.path) {
                let loaded = try JSONDecoder().decode(Workspace.self, from: Data(contentsOf: fileURL))
                try loaded.validate(); workspace = loaded
            }
        } catch { loadFailed = true; message = "Could not read your saved workspace. Your data has been preserved. Restore a backup or fix the data file before editing. \(error.localizedDescription)" }
    }
    var selected: TaskItem? { selectedID.flatMap { task($0) } }
    var isEditingText: Bool {
        if let editor = NSApp?.keyWindow?.firstResponder as? NSTextView, editor.isEditable { return true }
        if let field = NSApp?.keyWindow?.firstResponder as? NSTextField, field.isEditable { return true }
        return activeRegion == .editor
    }
    var canUseTaskShortcuts: Bool { selectedID != nil && activeRegion == .tasks && !isEditingText }
    var inspected: TaskItem? { inspectorID.flatMap { task($0) } }
    func task(_ id: UUID) -> TaskItem? { taskIndex.byID[id] }
    func children(of id: UUID) -> [TaskItem] { taskIndex.children[id] ?? [] }
    func openTaskCount(in label: UUID) -> Int { taskIndex.openCounts[label, default: 0] }
    func labelPath(forTask id: UUID) -> [TaskLabel] {
        let index = taskIndex
        return index.taskLabels[id].flatMap { index.labelPaths[$0] } ?? []
    }
    var taskRows: [TaskTreeRow] { taskDisplay.rows }
    var properties: ViewProperties { board ? workspace.boardProperties : workspace.listProperties }
    var scopedTasks: [TaskItem] { taskDisplay.scoped }
    var visibleTaskIDs: Set<UUID> { taskDisplay.ids }
    var roots: [TaskItem] { taskDisplay.roots }
    func boardTasks(_ status: TaskStatus) -> [TaskItem] { taskDisplay.columns[status] ?? [] }
    var availableStatuses: [TaskStatus] { TaskStatus.allCases.filter { showInProgress || $0 != .inProgress } }
    var boardStatuses: [TaskStatus] { availableStatuses.filter { $0 != .canceled || summaryCount(.canceled) > 0 } }
    func displayStatus(_ task: TaskItem) -> TaskStatus { !showInProgress && task.status == .inProgress ? .todo : task.status }
    func summaryCount(_ status: TaskStatus) -> Int { taskDisplay.counts[status, default: 0] }

    private var taskDisplay: TaskDisplay {
        let current = workspace
        let today = scope == "today" ? Calendar.current.startOfDay(for: .now) : nil
        let key = TaskDisplayKey(scope: scope, search: search, status: statusFilter,
                                 showResolved: board || showResolved, showInProgress: showInProgress,
                                 byImportance: sortByImportance, collapsed: collapsedTasks, today: today)
        if let cachedDisplay, cachedDisplay.key == key { return cachedDisplay }

        let index = taskIndex
        let scopeID = UUID(uuidString: key.scope)
        let scoped: [TaskItem]
        if key.scope == "all" { scoped = current.tasks }
        else if let today {
            let calendar = Calendar.current
            scoped = current.tasks.filter { $0.dueDate.map { calendar.isDate($0, inSameDayAs: today) } == true }
        } else if let scopeID {
            scoped = current.tasks.filter { item in
                guard let label = index.taskLabels[item.id] else { return false }
                return index.labelPaths[label]?.contains { $0.id == scopeID } == true
            }
        } else { scoped = [] }

        func displayStatus(_ task: TaskItem) -> TaskStatus {
            !key.showInProgress && task.status == .inProgress ? .todo : task.status
        }
        var ids: Set<UUID> = []
        var counts: [TaskStatus: Int] = [:]
        for task in scoped {
            let status = displayStatus(task)
            counts[status, default: 0] += 1
            guard key.status == nil || key.status == status,
                  key.showResolved || !task.status.isResolved,
                  key.search.isEmpty || task.title.localizedCaseInsensitiveContains(key.search)
                      || task.notes.localizedCaseInsensitiveContains(key.search) else { continue }
            var candidate: UUID? = task.id
            while let id = candidate, ids.insert(id).inserted { candidate = index.byID[id]?.parentID }
        }

        let roots = current.sortedTasks((index.children[nil] ?? []).filter { ids.contains($0.id) }, byImportance: key.byImportance)
        var rows: [TaskTreeRow] = []
        func append(_ tasks: [TaskItem], at depth: Int) {
            for task in tasks where key.showResolved || !task.status.isResolved {
                rows.append(TaskTreeRow(task: task, depth: depth))
                if !key.collapsed.contains(task.id), let children = index.children[task.id] {
                    append(current.sortedTasks(children.filter { ids.contains($0.id) }, byImportance: key.byImportance), at: depth + 1)
                }
            }
        }
        append(roots, at: 0)
        let display = TaskDisplay(key: key, scoped: scoped, ids: ids, roots: roots, rows: rows,
                                  counts: counts, columns: Dictionary(grouping: roots, by: displayStatus))
        cachedDisplay = display
        return display
    }

    func toggleStatusFilter(_ status: TaskStatus) {
        statusFilter = statusFilter == status ? nil : status
        selectedID = nil; inspectorID = nil; inlineSubtaskParent = nil
    }
    func beginInlineSubtask(of id: UUID) {
        guard workspace.tasks.contains(where: { $0.id == id }) else { return }
        viewMode = .list; search = ""; statusFilter = nil
        if inlineDraftParent != id { inlineSubtaskDraft = "" }
        inlineDraftParent = id
        inlineSubtaskParent = id; collapsedTasks.remove(id); selectedID = id; activeRegion = .editor
    }
    @discardableResult func submitInlineSubtask(nest: Bool = false) -> UUID? {
        guard let parent = inlineSubtaskParent, let id = add(inlineSubtaskDraft, parent: parent) else { return nil }
        inlineSubtaskDraft = ""
        if nest { beginInlineSubtask(of: id) }
        return id
    }
    func editNotes(_ id: UUID) {
        openTask(id); viewMode = .list; focusNotesID = id
    }
    func highlightsTask(_ id: UUID) -> Bool { activeRegion == .tasks && selectedID == id }
    var title: String { switch scope { case "all": "All tasks"; case "today": "Today"; default: workspace.labels.first { $0.id.uuidString == scope }?.name ?? "All tasks" } }
    func save(_ before: Workspace? = nil) {
        guard !loadFailed else { if let before { workspace = before }; message = "Saving is disabled because the existing data file could not be read. Restore a valid backup first."; return }
        do {
            try workspace.validate()
            let data = try JSONEncoder().encode(workspace)
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: fileURL, options: .atomic)
            if let before { undoWorkspace = before }
        } catch { if let before { workspace = before }; message = "Could not save changes: \(error.localizedDescription)" }
    }
    @discardableResult func add(_ title: String, parent: UUID? = nil, label: UUID? = nil, dismissSuggestion: Bool = false) -> UUID? {
        let before = workspace
        guard let id = workspace.addTask(title: title, parent: parent, label: label) else { return nil }
        if dismissSuggestion, let index = workspace.tasks.firstIndex(where: { $0.id == id }) { workspace.tasks[index].smartEntryDismissed = true }
        if let parent { collapsedTasks.remove(parent) }
        selectedID = id; save(before)
        return workspace.tasks.contains(where: { $0.id == id }) ? id : nil
    }
    func openTask(_ id: UUID) {
        var parent = task(id)?.parentID
        while let ancestor = parent { collapsedTasks.remove(ancestor); parent = task(ancestor)?.parentID }
        selectedID = id; inspectorID = id; focusNotesID = id; notesFocusRequest = UUID(); activeRegion = .editor }
    func navigateBack() {
        if inspectorID != nil || inlineSubtaskParent != nil {
            inspectorID = nil; inlineSubtaskParent = nil; activeRegion = .tasks
        } else if activeRegion == .editor {
            activeRegion = selectedID == nil ? .sidebar : .tasks
        } else if activeRegion == .tasks {
            activeRegion = .sidebar
        } else {
            openScope("all"); activeRegion = .sidebar
        }
    }
    func requestNewTask() {
        inspectorID = nil; inlineSubtaskParent = nil; statusFilter = nil; search = ""
        activeRegion = .editor; focusComposer = UUID()
    }
    func closeInspector() { inspectorID = nil }
    func acceptSelectedSuggestion() {
        guard let task = selected, let label = workspace.smartMatches(for: task).first else { return }
        let before = workspace; workspace.acceptSmartMatch(task: task.id, label: label.id); save(before)
    }
    func acceptSuggestion(task: UUID, label: UUID) {
        let before = workspace; workspace.acceptSmartMatch(task: task, label: label); save(before)
    }
    func edit(_ id: UUID, _ change: (inout TaskItem) -> Void) {
        guard let index = workspace.tasks.firstIndex(where: { $0.id == id }) else { return }
        let before = workspace; change(&workspace.tasks[index]); save(before)
    }
    func status(_ id: UUID, _ status: TaskStatus, reason: String = "") {
        if status == .canceled && reason.isEmpty { pendingCancel = id; return }
        let before = workspace
        do { try workspace.setStatus(id, to: status, reason: reason); save(before) } catch { message = error.localizedDescription }
    }
    func toggle(_ id: UUID) {
        guard let task = workspace.tasks.first(where: { $0.id == id }) else { return }
        status(id, task.status.isResolved ? .todo : .done)
    }
    func deleteSelected() {
        guard let id = selectedID else { return }; let before = workspace
        let removed = Set([id] + workspace.descendants(of: id)); workspace.delete(id); selectedID = nil; if let parent = inlineSubtaskParent, removed.contains(parent) { inlineSubtaskParent = nil; inlineSubtaskDraft = "" }; if let inspectorID, removed.contains(inspectorID) { self.inspectorID = nil }; save(before)
    }
    func undo() { guard let previous = undoWorkspace else { return }; let current = workspace; workspace = previous; save(current) }
    func toggleProperty(_ key: WritableKeyPath<ViewProperties, Bool>) {
        let before = workspace
        if board { workspace.boardProperties[keyPath: key].toggle() } else { workspace.listProperties[keyPath: key].toggle() }
        save(before)
    }
    @discardableResult func addLabel(_ name: String, parent: UUID?) -> UUID? {
        let before = workspace
        do { let id = try workspace.addLabel(name: name, parent: parent); save(before); return workspace.labels.contains(where: { $0.id == id }) ? id : nil }
        catch { message = error.localizedDescription; return nil }
    }
    func updateLabel(_ id: UUID, name: String, parent: UUID?) {
        let before = workspace
        do { try workspace.updateLabel(id, name: name, parent: parent); save(before) }
        catch { message = error.localizedDescription }
    }
    func setLabelCaption(_ id: UUID, caption: String) {
        guard let index = workspace.labels.firstIndex(where: { $0.id == id }) else { return }
        let before = workspace
        let caption = caption.trimmingCharacters(in: .whitespacesAndNewlines)
        workspace.labels[index].caption = caption.isEmpty ? nil : caption
        save(before)
    }
    func removeLabel(_ id: UUID) {
        let before = workspace; workspace.removeLabel(id); if scope == id.uuidString { scope = "all" }; save(before)
    }
    func exportBackup() {
        let panel = NSSavePanel(); panel.allowedContentTypes = [.json]; panel.nameFieldStringValue = "Tempo-backup.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; try encoder.encode(workspace).write(to: url, options: .atomic) } catch { message = error.localizedDescription }
    }
    func importBackup() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let imported = try JSONDecoder().decode(Workspace.self, from: Data(contentsOf: url)); try imported.validate()
            let alert = NSAlert(); alert.messageText = "Restore this backup?"; alert.informativeText = "This replaces your current tasks and labels. You can undo the restore during this session."; alert.addButton(withTitle: "Restore"); alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
            if loadFailed, FileManager.default.fileExists(atPath: fileURL.path) {
                let recoveryURL = fileURL.deletingLastPathComponent().appending(path: "workspace-unreadable-\(UUID().uuidString).json")
                try FileManager.default.copyItem(at: fileURL, to: recoveryURL)
            }
            loadFailed = false; let before = workspace; workspace = imported; selectedID = nil; inspectorID = nil; save(before)
        } catch { message = "Could not restore backup: \(error.localizedDescription)" }
    }
    func openScope(_ scope: String) {
        activeRegion = .sidebar
        self.scope = scope; statusFilter = nil; inlineSubtaskParent = nil; selectedID = nil; inspectorID = nil; search = ""
        revealCurrentLabel()
    }
    func revealCurrentLabel() {
        guard let id = UUID(uuidString: scope) else { return }
        for label in workspace.labelPath(id).dropLast() { collapsedLabels.remove(label.id) }
    }
    func navigateViews(_ offset: Int) {
        openScope(workspace.adjacentScope(to: scope, offset: offset, collapsed: collapsedLabels))
    }
    func navigateLabelBranch(expand: Bool) {
        guard let id = UUID(uuidString: scope), let label = workspace.labels.first(where: { $0.id == id }) else { return }
        let child = workspace.labels.first { $0.parentID == id }
        if expand {
            if collapsedLabels.contains(id) { collapsedLabels.remove(id) }
            else if let child { openScope(child.id.uuidString) }
        } else if child != nil && !collapsedLabels.contains(id) { collapsedLabels.insert(id) }
        else if let parent = label.parentID { openScope(parent.uuidString) }
    }
    func selectNext(_ offset: Int) {
        activeRegion = .tasks
        inspectorID = nil
        let items = viewMode == .board ? boardStatuses.flatMap { boardTasks($0) } : taskRows.map(\.task)
        guard !items.isEmpty else { return }
        let index = items.firstIndex { $0.id == selectedID } ?? (offset > 0 ? -1 : items.count)
        selectedID = items[min(max(index + offset, 0), items.count - 1)].id
    }
}
