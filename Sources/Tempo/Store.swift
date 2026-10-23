import SwiftUI
import AppKit
import UniformTypeIdentifiers
import TempoCore

enum WorkspaceView: String, CaseIterable { case list = "List", board = "Board", web = "Web" }

@MainActor @Observable final class Store {
    var workspace = Workspace()
    var selectedID: UUID?
    var scope = "all"
    var collapsedLabels: Set<UUID> = []
    var viewMode: WorkspaceView = .list
    var board: Bool {
        get { viewMode == .board }
        set { viewMode = newValue ? .board : .list }
    }
    var search = ""
    var showResolved = false
    var sortByImportance = false
    var showCommands = false
    var showHelp = false
    var pendingCancel: UUID?
    var focusComposer = UUID()
    var message: String?
    var undoWorkspace: Workspace?
    private var loadFailed = false
    private let fileURL: URL
    init() {
        fileURL = URL.applicationSupportDirectory.appending(path: "Tempo/workspace.json")
        do {
            if FileManager.default.fileExists(atPath: fileURL.path) {
                let loaded = try JSONDecoder().decode(Workspace.self, from: Data(contentsOf: fileURL))
                try loaded.validate(); workspace = loaded
            }
        } catch { loadFailed = true; message = "Could not read your saved workspace. Your data has been preserved. Restore a backup or fix the data file before editing. \(error.localizedDescription)" }
    }
    var selected: TaskItem? { workspace.tasks.first { $0.id == selectedID } }
    var properties: ViewProperties { board ? workspace.boardProperties : workspace.listProperties }
    var roots: [TaskItem] {
        workspace.tasks.filter { task in
            guard task.parentID == nil else { return false }
            let labelMatches = scope == "all" || (scope == "inbox" && workspace.effectiveLabel(task) == nil) || (scope == "today" && task.dueDate.map { Calendar.current.isDateInToday($0) } == true) || workspace.labelPath(workspace.effectiveLabel(task)).contains { $0.id.uuidString == scope }
            let matches = task.title.localizedCaseInsensitiveContains(search) || task.notes.localizedCaseInsensitiveContains(search) || workspace.descendants(of: task.id).contains { id in workspace.tasks.first { $0.id == id }?.title.localizedCaseInsensitiveContains(search) == true }
            return labelMatches && (search.isEmpty || matches) && (board || showResolved || !task.status.isResolved)
        }.sorted { sortByImportance && $0.importance != $1.importance ? $0.importance.rawValue > $1.importance.rawValue : $0.createdAt < $1.createdAt }
    }
    var title: String { switch scope { case "all": "All tasks"; case "inbox": "Inbox"; case "today": "Today"; default: workspace.labels.first { $0.id.uuidString == scope }?.name ?? "All tasks" } }
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
    func add(_ title: String, parent: UUID? = nil, label: UUID? = nil) {
        let before = workspace
        if let id = workspace.addTask(title: title, parent: parent, label: label) { selectedID = id; save(before) }
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
        workspace.delete(id); selectedID = nil; save(before)
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
            loadFailed = false; let before = workspace; workspace = imported; selectedID = nil; save(before)
        } catch { message = "Could not restore backup: \(error.localizedDescription)" }
    }
    func openScope(_ scope: String) {
        self.scope = scope; selectedID = nil; search = ""
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
        let items = roots
        guard !items.isEmpty else { return }
        let index = items.firstIndex { $0.id == selectedID } ?? (offset > 0 ? -1 : items.count)
        selectedID = items[min(max(index + offset, 0), items.count - 1)].id
    }
}
