import SwiftUI
import TempoCore

struct LabelManager: View {
    @Bindable var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var parent: UUID?
    @State private var validation = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack { Text("A place for everything").font(.system(size: 22, weight: .semibold)); Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.cancelAction) }
            Text("Add as much structure as you need. Labels can contain labels, at any depth.").font(.system(size: 12)).foregroundStyle(.secondary)
            ScrollView { VStack(alignment: .leading, spacing: 10) { if store.workspace.labels.isEmpty { Text("No labels yet. Your tasks work just fine without them.").foregroundStyle(.tertiary).padding(.vertical, 25) }; ForEach(store.workspace.labels) { label in HStack { Image(systemName: "tag").foregroundStyle(Color.accent); Text(store.workspace.labelPath(label.id).map(\.name).joined(separator: " / ")); Spacer() }.font(.system(size: 12)).padding(9).background(Color.accent.opacity(0.04), in: RoundedRectangle(cornerRadius: 6)) } } }.frame(minHeight: 100, maxHeight: 230)
            Divider()
            TextField("Label name, e.g. Edge Security", text: $name).textFieldStyle(.roundedBorder).onSubmit(add)
            Picker("Inside", selection: $parent) { Text("No parent — top-level label").tag(nil as UUID?); ForEach(store.workspace.labels) { label in Text(store.workspace.labelPath(label.id).map(\.name).joined(separator: " / ")).tag(Optional(label.id)) } }
            if !validation.isEmpty { Text(validation).foregroundStyle(.red).font(.system(size: 11)) }
            HStack { Text("Work → Edge Security → Backend").font(.system(size: 10)).foregroundStyle(.tertiary); Spacer(); Button("Add label", action: add).buttonStyle(.borderedProminent).disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
        }.padding(28).frame(width: 510)
    }
    private func add() {
        let value = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        guard !store.workspace.labels.contains(where: { $0.parentID == parent && $0.name.caseInsensitiveCompare(value) == .orderedSame }) else { validation = "A label with this name already exists here."; return }
        let before = store.workspace; store.workspace.labels.append(TaskLabel(name: value, parentID: parent)); store.save(before); name = ""; validation = ""
    }
}
struct CancelTaskView: View {
    @Bindable var store: Store
    @State private var reason = ""
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Why is this task being canceled?").font(.system(size: 20, weight: .semibold))
            Text("Unfinished subtasks will be canceled with the same reason. Completed and previously canceled work stays as it is.").font(.system(size: 12)).foregroundStyle(.secondary)
            TextField("Cancellation reason", text: $reason, axis: .vertical).lineLimit(3...6).textFieldStyle(.roundedBorder)
            HStack { Spacer(); Button("Keep task") { store.pendingCancel = nil; dismiss() }.keyboardShortcut(.cancelAction); Button("Cancel task") { if let id = store.pendingCancel { store.status(id, .canceled, reason: reason) }; store.pendingCancel = nil; dismiss() }.buttonStyle(.borderedProminent).disabled(reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
        }.padding(28).frame(width: 440)
    }
}
struct CommandMenuView: View {
    @Bindable var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @FocusState private var focused: Bool
    private var actions: [(String, String, () -> Void)] {
        var items: [(String, String, () -> Void)] = [
            ("New task", "⌘N", { store.focusComposer = UUID() }),
            ("All tasks", "", { store.scope = "all" }),
            ("Inbox", "", { store.scope = "inbox" }),
            ("Today", "", { store.scope = "today" }),
            ("List view", "⌘1", { store.board = false }),
            ("Board view", "⌘2", { store.board = true }),
            ("Manage labels", "⇧⌘L", { store.showLabels = true }),
            ("Export backup", "", { store.exportBackup() }),
            ("Restore backup", "", { store.importBackup() }),
            ("Keyboard shortcuts", "⌘/", { store.showHelp = true })
        ]
        if let id = store.selectedID {
            items += [("Complete / reopen task", "⌘↵", { store.toggle(id) }), ("Delete task", "⌘⌫", { store.deleteSelected() })]
            items += TaskStatus.allCases.map { status in ("Set status: \(status.rawValue)", "", { store.status(id, status) }) }
            items += Importance.allCases.map { priority in ("Set importance: \(priority.title)", "⌥⌘\(priority.rawValue)", { store.edit(id) { $0.importance = priority } }) }
        }
        return items.filter { query.isEmpty || $0.0.localizedCaseInsensitiveContains(query) }
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack { Image(systemName: "magnifyingglass").foregroundStyle(.secondary); TextField("What would you like to do?", text: $query).textFieldStyle(.plain).focused($focused).onSubmit { if let action = actions.first?.2 { run(action) } }; Button("Esc") { dismiss() }.font(.system(size: 10)).buttonStyle(.plain).foregroundStyle(.tertiary) }.padding(20)
            Divider()
            ScrollView { VStack(spacing: 2) { ForEach(Array(actions.enumerated()), id: \.offset) { _, item in Button { run(item.2) } label: { HStack { Text(item.0); Spacer(); Text(item.1).foregroundStyle(.tertiary) }.font(.system(size: 12)).padding(12).contentShape(Rectangle()) }.buttonStyle(.plain) }; if actions.isEmpty { Text("No matching commands").foregroundStyle(.secondary).padding(30) } }.padding(8) }.frame(height: 340)
        }.frame(width: 480).onAppear { focused = true }
    }
    private func run(_ action: @escaping () -> Void) { dismiss(); Task { @MainActor in try? await Task.sleep(for: .milliseconds(200)); action() } }
}
struct ShortcutsView: View {
    @Environment(\.dismiss) private var dismiss
    let shortcuts = [("New task", "⌘N"), ("New subtask", "⇧⌘N"), ("Command menu", "⌘K"), ("Search tasks", "⌘F"), ("Complete / reopen", "⌘↵"), ("Next / previous task", "⌥↓ / ⌥↑"), ("List / board view", "⌘1 / ⌘2"), ("Importance: None → Urgent", "⌥⌘0 … ⌥⌘4"), ("Manage labels", "⇧⌘L"), ("Delete task and subtasks", "⌘⌫"), ("Undo last change", "⌘Z")]
    var body: some View { VStack(alignment: .leading, spacing: 16) { HStack { Text("Keep your hands on the keys").font(.system(size: 20, weight: .semibold)); Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.cancelAction) }; ForEach(shortcuts, id: \.0) { name, keys in HStack { Text(name); Spacer(); Text(keys).foregroundStyle(.secondary).monospaced() }.font(.system(size: 12)); Divider() } }.padding(28).frame(width: 470) }
}
