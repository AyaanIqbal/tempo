import SwiftUI
import AppKit
import TempoCore

@main struct TempoApp: App {
    @State private var store = Store()
    @StateObject private var updates = UpdateManager()
    var body: some Scene {
        Window("Tempo", id: "main") {
            ContentView(store: store)
                .frame(minWidth: 900, minHeight: 620)
                .tint(Color.accent)
                .onAppear { NSApp.setActivationPolicy(.regular); NSApp.activate(ignoringOtherApps: true) }
        }
        .defaultSize(width: 1180, height: 800)
        .windowStyle(.hiddenTitleBar)
        .commands {
            UpdateCommands(manager: updates)
            CommandGroup(replacing: .newItem) {
                Button("New Task") { store.focusComposer = UUID() }.keyboardShortcut("n")
                Button("New Subtask") { if store.selectedID != nil { NotificationCenter.default.post(name: .newSubtask, object: nil) } }.keyboardShortcut("n", modifiers: [.command, .shift]).disabled(store.selectedID == nil)
            }
            CommandGroup(replacing: .undoRedo) { Button("Undo Last Change") { store.undo() }.keyboardShortcut("z").disabled(store.undoWorkspace == nil) }
            CommandMenu("Task") {
                Button("Complete / Reopen") { if let id = store.selectedID { store.toggle(id) } }.keyboardShortcut(.return).disabled(store.selectedID == nil)
                ForEach(TaskStatus.allCases, id: \.self) { status in Button(status.rawValue) { if let id = store.selectedID { store.status(id, status) } }.disabled(store.selectedID == nil) }
                Divider()
                ForEach(Importance.allCases, id: \.self) { priority in Button("Importance: \(priority.title)") { if let id = store.selectedID { store.edit(id) { $0.importance = priority } } }.keyboardShortcut(KeyEquivalent(Character(String(priority.rawValue))), modifiers: [.command, .option]).disabled(store.selectedID == nil) }
                Divider()
                Button("Delete Task and Subtasks") { store.deleteSelected() }.keyboardShortcut(.delete, modifiers: .command).disabled(store.selectedID == nil)
            }
            CommandMenu("Navigate") {
                Button("Command Menu…") { store.showCommands = true }.keyboardShortcut("k")
                Button("Focus Sidebar") { NotificationCenter.default.post(name: .focusSidebar, object: nil) }.keyboardShortcut("s", modifiers: [.control, .command])
                Button("Search Tasks") { NotificationCenter.default.post(name: .searchTasks, object: nil) }.keyboardShortcut("f")
                Button("Next Task") { store.selectNext(1) }.keyboardShortcut(.downArrow, modifiers: .option)
                Button("Previous Task") { store.selectNext(-1) }.keyboardShortcut(.upArrow, modifiers: .option)
                Divider()
                Button("List View") { store.board = false }.keyboardShortcut("1")
                Button("Board View") { store.board = true }.keyboardShortcut("2")
                Button("Web View") { store.viewMode = .web }.keyboardShortcut("3")
            }
            CommandGroup(after: .importExport) {
                Button("Export Backup…") { store.exportBackup() }
                Button("Restore Backup…") { store.importBackup() }
            }
            CommandGroup(replacing: .help) { Button("Tempo Keyboard Shortcuts") { store.showHelp = true }.keyboardShortcut("/", modifiers: .command) }
        }

    }
}
extension Notification.Name {
    static let newSubtask = Notification.Name("tempo.newSubtask")
    static let focusTasks = Notification.Name("tempo.focusTasks")
    static let focusSidebar = Notification.Name("tempo.focusSidebar")
    static let searchTasks = Notification.Name("tempo.search")
}
extension Color {
    static let accent = Color(red: 0.40, green: 0.43, blue: 0.82)
    static let canvas = Color(nsColor: .windowBackgroundColor)
    static let quiet = Color.secondary
}
