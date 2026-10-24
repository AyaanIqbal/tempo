import SwiftUI
import TempoCore

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
    @State private var selectedIndex = 0
    @FocusState private var focused: Bool
    private var actions: [(String, String, () -> Void)] {
        var items: [(String, String, () -> Void)] = [
            ("New task", "⌘N", { store.focusComposer = UUID() }),
            ("All tasks", "", { store.openScope("all") }),
            ("Inbox", "", { store.openScope("inbox") }),
            ("Today", "", { store.openScope("today") }),
            ("List view", "⌘1", { store.viewMode = .list }),
            ("Board view", "⌘2", { store.viewMode = .board }),
            ("Web view", "⌘3", { store.viewMode = .web }),
            ("Export backup", "", { store.exportBackup() }),
            ("Restore backup", "", { store.importBackup() }),
            ("Keyboard shortcuts", "⌘/", { store.showHelp = true })
        ]
        items += store.workspace.labelRows().map { row in
            let path = store.workspace.labelPath(row.id).map(\.name).joined(separator: " / ")
            return ("Open label: \(path)", "", { store.openScope(row.id.uuidString); NotificationCenter.default.post(name: .focusSidebar, object: nil) })
        }
        if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let terms = query.split(whereSeparator: \.isWhitespace).map(String.init)
            let matches = store.workspace.tasks.filter { task in
                let path = store.workspace.labelPath(store.workspace.effectiveLabel(task)).map(\.name).joined(separator: " / ")
                return terms.allSatisfy { "\(path) \(task.title)".localizedCaseInsensitiveContains($0) }
            }.prefix(20)
            items += matches.map { task in
                let path = store.workspace.labelPath(store.workspace.effectiveLabel(task)).map(\.name).joined(separator: " / ")
                let title = path.isEmpty ? "Task: \(task.title)" : "Task: \(path) / \(task.title)"
                return (title, "", { store.openScope(store.workspace.effectiveLabel(task)?.uuidString ?? "inbox"); store.openTask(task.id) })
            }
        }
        if let id = store.selectedID {
            items += [("Complete / reopen task", "⌘↵", { store.toggle(id) }), ("Delete task", "⇧⌘⌫", { store.deleteSelected() })]
            items += TaskStatus.allCases.map { status in ("Set status: \(status.rawValue)", "", { store.status(id, status) }) }
            items += Importance.allCases.map { priority in ("Set importance: \(priority.title)", "⌥⌘\(priority.rawValue)", { store.edit(id) { $0.importance = priority } }) }
        }
        let terms = query.split(whereSeparator: \.isWhitespace).map(String.init)
        return items.filter { item in terms.allSatisfy { item.0.localizedCaseInsensitiveContains($0) } }
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("What would you like to do?", text: $query)
                    .textFieldStyle(.plain).focused($focused)
                    .onSubmit { activateSelected() }
                    .onKeyPress(.downArrow) { move(1); return .handled }
                    .onKeyPress(.upArrow) { move(-1); return .handled }
                    .onKeyPress(.escape) { dismiss(); return .handled }
                Button("Esc") { dismiss() }.font(.system(size: 10)).buttonStyle(.plain).foregroundStyle(.tertiary)
            }.padding(20)
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(Array(actions.enumerated()), id: \.offset) { index, item in
                            Button { run(item.2) } label: {
                                HStack { Text(item.0); Spacer(); if selectedIndex == index { Image(systemName: "return").font(.system(size: 10)).foregroundStyle(Color.accent) }; Text(item.1).foregroundStyle(.tertiary) }
                                    .font(.system(size: 12)).padding(12)
                                    .frame(maxWidth: .infinity, minHeight: 39, alignment: .leading)
                                    .background(selectedIndex == index ? Color.accent.opacity(0.10) : .clear, in: RoundedRectangle(cornerRadius: 6))
                                    .contentShape(Rectangle())
                            }.buttonStyle(.plain).id(index)
                            .accessibilityAddTraits(selectedIndex == index ? .isSelected : [])
                        }
                        if actions.isEmpty { Text("No matching commands").foregroundStyle(.secondary).padding(30) }
                    }.padding(8)
                }.frame(height: 340)
                .onChange(of: selectedIndex) { withAnimation(.easeOut(duration: 0.1)) { proxy.scrollTo(selectedIndex, anchor: .center) } }
                .onChange(of: query) { selectedIndex = 0; proxy.scrollTo(0, anchor: .top) }
            }
            Divider()
            HStack { Text("↑ ↓ to navigate"); Spacer(); Text("↵ to select · esc to close") }.font(.system(size: 10)).foregroundStyle(.tertiary).padding(.horizontal, 20).padding(.vertical, 10)
        }.frame(width: 480).onAppear { focused = true }
    }
    private func move(_ offset: Int) {
        guard !actions.isEmpty else { selectedIndex = 0; return }
        selectedIndex = (selectedIndex + offset + actions.count) % actions.count
    }
    private func activateSelected() {
        guard actions.indices.contains(selectedIndex) else { return }; run(actions[selectedIndex].2)
    }
    private func run(_ action: @escaping () -> Void) { dismiss(); Task { @MainActor in try? await Task.sleep(for: .milliseconds(200)); action() } }
}
struct ShortcutsView: View {
    let shortcuts = [("New task", "⌘N"), ("New subtask", "⇧⌘N"), ("Command menu", "⌘K"), ("Search tasks", "⌘F"), ("Complete / reopen", "⌘↵"), ("Next / previous task", "⌥↓ / ⌥↑"), ("List / board / web view", "⌘1 / ⌘2 / ⌘3"), ("Navigate command menu", "↑ / ↓ / ↵"), ("Focus sidebar", "⌃⌘S"), ("Sidebar views", "↑ / ↓"), ("Sidebar → tasks / tasks → sidebar", "→ / ←"), ("Task selection / open details", "↑ ↓ / ↵"), ("Subtask of selected task", "⇧↵"), ("Apply / dismiss smart entry", "Tab / ⇧Tab"), ("Importance: None → Urgent", "⌥⌘0 … ⌥⌘4"), ("Delete task and subtasks", "⇧⌘⌫"), ("Undo last task change", "⌥⌘Z")]

    @Environment(\.dismiss) private var dismiss
    var body: some View { VStack(alignment: .leading, spacing: 16) { HStack { Text("Keep your hands on the keys").font(.system(size: 20, weight: .semibold)); Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.cancelAction) }; ForEach(shortcuts, id: \.0) { name, keys in HStack { Text(name); Spacer(); Text(keys).foregroundStyle(.secondary).monospaced() }.font(.system(size: 12)); Divider() } }.padding(28).frame(width: 470) }
}
