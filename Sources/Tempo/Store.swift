import SwiftUI
import AppKit
import UniformTypeIdentifiers
import TempoCore

enum NavigationRegion: Hashable { case sidebar, tasks, editor }

enum WorkspaceView: String, CaseIterable { case list = "List", board = "Board" }

@MainActor @Observable final class Store {
    var workspace = Workspace()
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
    var selected: TaskItem? { workspace.tasks.first { $0.id == selectedID } }
    var isEditingText: Bool {
        if let editor = NSApp?.keyWindow?.firstResponder as? NSTextView, editor.isEditable { return true }
        if let field = NSApp?.keyWindow?.firstResponder as? NSTextField, field.isEditable { return true }
        return activeRegion == .editor
    }
    var canUseTaskShortcuts: Bool { selectedID != nil && activeRegion == .tasks && !isEditingText }
    var inspected: TaskItem? { workspace.tasks.first { $0.id == inspectorID } }
    var taskRows: [TaskTreeRow] { workspace.taskRows(roots: roots, collapsed: collapsedTasks, showResolved: board || showResolved, byImportance: sortByImportance).filter { visibleTaskIDs.contains($0.id) } }
    var properties: ViewProperties { board ? workspace.boardProperties : workspace.listProperties }
    var scopedTasks: [TaskItem] {
        workspace.tasks.filter { task in
            scope == "all"
            || (scope == "today" && task.dueDate.map { Calendar.current.isDateInToday($0) } == true)
            || workspace.labelPath(workspace.effectiveLabel(task)).contains { $0.id.uuidString == scope }
        }
    }
    var visibleTaskIDs: Set<UUID> {
        var ids: Set<UUID> = []
        for task in scopedTasks {
            guard statusFilter == nil || displayStatus(task) == statusFilter else { continue }
            guard search.isEmpty || task.title.localizedCaseInsensitiveContains(search) || task.notes.localizedCaseInsensitiveContains(search) else { continue }
            guard showResolved || !task.status.isResolved || board else { continue }
            ids.insert(task.id)
            var parent = task.parentID
            while let id = parent { ids.insert(id); parent = workspace.tasks.first { $0.id == id }?.parentID }
        }
        return ids
    }
    var roots: [TaskItem] {
        workspace.sortedTasks(workspace.tasks.filter { $0.parentID == nil && visibleTaskIDs.contains($0.id) }, byImportance: sortByImportance)
    }
    var availableStatuses: [TaskStatus] { TaskStatus.allCases.filter { showInProgress || $0 != .inProgress } }
    var boardStatuses: [TaskStatus] { availableStatuses.filter { $0 != .canceled || scopedTasks.contains { $0.status == .canceled } } }
    func displayStatus(_ task: TaskItem) -> TaskStatus { !showInProgress && task.status == .inProgress ? .todo : task.status }
    func summaryCount(_ status: TaskStatus) -> Int { scopedTasks.filter { displayStatus($0) == status }.count }
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
        for ancestor in workspace.tasks where workspace.descendants(of: ancestor.id).contains(id) { collapsedTasks.remove(ancestor.id) }
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
        let items = viewMode == .board ? boardStatuses.flatMap { status in roots.filter { displayStatus($0) == status } } : taskRows.map(\.task)
        guard !items.isEmpty else { return }
        let index = items.firstIndex { $0.id == selectedID } ?? (offset > 0 ? -1 : items.count)
        selectedID = items[min(max(index + offset, 0), items.count - 1)].id
    }
}
