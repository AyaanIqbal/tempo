import SwiftUI
import AppKit
import TempoCore

@main struct TempoApp: App {
    @AppStorage("tempo.appearance") private var appearance: AppAppearance = .system
    @State private var store = Store()
    @StateObject private var updates = UpdateManager()
    var body: some Scene {
        Window("Tempo", id: "main") {
            ContentView(store: store)
                .frame(minWidth: 900, minHeight: 620)
                .tint(Color.accent)
                .preferredColorScheme(appearance.colorScheme)
                .onChange(of: appearance) { NSApp.appearance = appearance.nativeAppearance }
                .onAppear { NSApp.appearance = appearance.nativeAppearance; NSApp.setActivationPolicy(.regular); NSApp.activate(ignoringOtherApps: true) }
        }
        .defaultSize(width: 1180, height: 800)
        .windowStyle(.hiddenTitleBar)
        .commands {
            UpdateCommands(manager: updates)
            CommandGroup(replacing: .newItem) {
                Button("New Task") { store.focusComposer = UUID() }.keyboardShortcut("n")
                Button("New Subtask") { if store.canUseTaskShortcuts { NotificationCenter.default.post(name: .newSubtask, object: nil) } }.keyboardShortcut("n", modifiers: [.command, .shift]).disabled(!store.canUseTaskShortcuts)
            }
            CommandGroup(after: .undoRedo) { Button("Undo Last Task Change") { if !store.isEditingText { store.undo() } }.keyboardShortcut("z", modifiers: [.command, .option]).disabled(store.undoWorkspace == nil || store.isEditingText) }
            CommandMenu("Task") {
                Button("Complete / Reopen") { if store.canUseTaskShortcuts, let id = store.selectedID { store.toggle(id) } }.keyboardShortcut(.return).disabled(!store.canUseTaskShortcuts)
                ForEach(TaskStatus.allCases, id: \.self) { status in Button(status.rawValue) { if store.canUseTaskShortcuts, let id = store.selectedID { store.status(id, status) } }.disabled(!store.canUseTaskShortcuts) }
                Divider()
                ForEach(Importance.allCases, id: \.self) { priority in Button("Importance: \(priority.title)") { if store.canUseTaskShortcuts, let id = store.selectedID { store.edit(id) { $0.importance = priority } } }.keyboardShortcut(KeyEquivalent(Character(String(priority.rawValue))), modifiers: [.command, .option]).disabled(!store.canUseTaskShortcuts) }
                Divider()
                Button("Delete Task and Subtasks") { if store.canUseTaskShortcuts { store.deleteSelected() } }.keyboardShortcut(.delete, modifiers: [.command, .shift]).disabled(!store.canUseTaskShortcuts)
            }
            CommandMenu("Navigate") {
                Button("Command Menu…") { store.showCommands = true }.keyboardShortcut("k")
                Button("Focus Sidebar") { NotificationCenter.default.post(name: .focusSidebar, object: nil) }.keyboardShortcut("s", modifiers: [.control, .command])
                Button("Search Tasks") { NotificationCenter.default.post(name: .searchTasks, object: nil) }.keyboardShortcut("f")
                Button("Next Task") { if store.canUseTaskShortcuts { store.selectNext(1) } }.keyboardShortcut(.downArrow, modifiers: .option).disabled(!store.canUseTaskShortcuts)
                Button("Previous Task") { if store.canUseTaskShortcuts { store.selectNext(-1) } }.keyboardShortcut(.upArrow, modifiers: .option).disabled(!store.canUseTaskShortcuts)
                Divider()
                Button("List View") { store.board = false }.keyboardShortcut("1")
                Button("Board View") { store.board = true }.keyboardShortcut("2")
                Button("Web View") { store.viewMode = .web }.keyboardShortcut("3")
            }
            CommandMenu("Appearance") {
                Picker("Appearance", selection: $appearance) {
                    ForEach(AppAppearance.allCases) { value in Text(value.title).tag(value) }
                }
            }
            CommandGroup(after: .importExport) {
                Button("Export Backup…") { store.exportBackup() }
                Button("Restore Backup…") { store.importBackup() }
            }
            CommandGroup(replacing: .help) { Button("Tempo Keyboard Shortcuts") { store.showHelp = true }.keyboardShortcut("/", modifiers: .command) }
        }
        Settings { AppearanceSettings().tint(Color.accent) }
    }
}
extension Notification.Name {
    static let newSubtask = Notification.Name("tempo.newSubtask")
    static let focusTasks = Notification.Name("tempo.focusTasks")
    static let focusSidebar = Notification.Name("tempo.focusSidebar")
    static let searchTasks = Notification.Name("tempo.search")
}
extension Color {
    static let accent = Color(nsColor: NSColor(name: NSColor.Name("TempoAccent"), dynamicProvider: { appearance in
        if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
            return NSColor(srgbRed: 0.65, green: 0.67, blue: 1.0, alpha: 1)
        }
        return NSColor(srgbRed: 0.40, green: 0.43, blue: 0.82, alpha: 1)
    }))
    static let canvas = Color(nsColor: .windowBackgroundColor)
    static let quiet = Color.secondary
}
