import SwiftUI
import AppKit
import TempoCore

/// Notes and optional properties expand directly beneath the task row.
struct InlineTaskEditor: View {
    @Bindable var store: Store
    let taskID: UUID
    @State private var preview = false
    @FocusState private var notesFocused: Bool
    private var task: TaskItem? { store.task(taskID) }
    private func field<T>(_ path: WritableKeyPath<TaskItem, T>, fallback: T) -> Binding<T> {
        Binding(get: { task?[keyPath: path] ?? fallback }, set: { value in store.edit(taskID) { $0[keyPath: path] = value } })
    }
    var body: some View {
        if let task {
            VStack(alignment: .leading, spacing: 15) {
                HStack {
                    TextField("Task title", text: Binding(get: { self.task?.title ?? "" }, set: { title in
                        if !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { store.edit(taskID) { $0.title = title } }
                    })).textFieldStyle(.plain).font(.system(size: 16, weight: .medium))
                    Button { close() } label: { Image(systemName: "xmark").frame(width: 26, height: 26).contentShape(Rectangle()) }.buttonStyle(.tempo).help("Close expanded task")
                }
                HStack(spacing: 12) {
                    Text("MARKDOWN NOTES").font(.system(size: 9, weight: .semibold)).tracking(1.2).foregroundStyle(.secondary)
                    Button { format("**", "**", "bold text") } label: { Image(systemName: "bold") }.help("Bold")
                    Button { format("_", "_", "italic text") } label: { Image(systemName: "italic") }.help("Italic")
                    Button { format("\n- ", "", "List item") } label: { Image(systemName: "list.bullet") }.help("Bullet list")
                    Button { format("\n## ", "", "Heading") } label: { Image(systemName: "textformat.size") }.help("Heading")
                    Spacer()
                    Button { preview.toggle() } label: { Label(preview ? "Edit" : "Preview", systemImage: preview ? "pencil" : "eye") }
                }.buttonStyle(.tempo).font(.system(size: 11))
                if preview {
                    VStack(alignment: .leading, spacing: 8) {
                        if task.notes.isEmpty { Text("No notes yet.").foregroundStyle(.tertiary) }
                        ForEach(Array(task.notes.components(separatedBy: "\n").enumerated()), id: \.offset) { _, line in
                            if line.hasPrefix("# ") { Text(.init(String(line.dropFirst(2)))).font(.title3.bold()) }
                            else if line.hasPrefix("## ") { Text(.init(String(line.dropFirst(3)))).font(.headline) }
                            else if line.hasPrefix("- ") || line.hasPrefix("* ") { HStack(alignment: .top) { Text("•"); Text(.init(String(line.dropFirst(2)))) } }
                            else { Text(.init(line.isEmpty ? " " : line)).textSelection(.enabled) }
                        }
                    }.font(.system(size: 12)).frame(maxWidth: .infinity, minHeight: 80, alignment: .topLeading).padding(10)
                } else {
                    MarkdownNotesEditor(text: field(\.notes, fallback: ""), focused: Binding(get: { notesFocused }, set: { notesFocused = $0 }), onEscape: close)
                        .frame(height: 140).padding(8)
                        .background(Color.secondary.opacity(0.035), in: RoundedRectangle(cornerRadius: 7))
                        .overlay(alignment: .topLeading) {
                            if task.notes.isEmpty { Text("Write Markdown notes… Use - for jot notes; Enter continues the list.").font(.system(size: 11)).foregroundStyle(.tertiary).padding(13).allowsHitTesting(false) }
                        }
                }
                HStack {
                    Button { store.beginInlineSubtask(of: taskID) } label: { Label("Add subtask", systemImage: "plus") }.buttonStyle(.bordered)
                    Text("Shift-Enter from the task list").font(.system(size: 10)).foregroundStyle(.tertiary)
                    Spacer()
                    Text("Saved on this Mac").font(.system(size: 10)).foregroundStyle(.tertiary)
                }
                DisclosureGroup("Properties") {
                    VStack(alignment: .leading, spacing: 12) {
                        Picker("Status", selection: Binding(get: { self.task.map { store.displayStatus($0) } ?? .todo }, set: { store.status(taskID, $0) })) { ForEach(store.availableStatuses, id: \.self) { Text($0 == .done ? "Completed" : $0.rawValue).tag($0) } }
                        Picker("Importance", selection: field(\.importance, fallback: .none)) { ForEach(Importance.allCases, id: \.self) { Text($0.title).tag($0) } }
                        if task.parentID == nil { LabelChooser(store: store, selection: field(\.labelID, fallback: nil)) }
                        else { Text("Label: " + store.workspace.labelPath(store.workspace.effectiveLabel(task)).map(\.name).joined(separator: " > ")).foregroundStyle(.secondary) }
                        Toggle("Due date", isOn: Binding(get: { self.task?.dueDate != nil }, set: { enabled in store.edit(taskID) { $0.dueDate = enabled ? .now : nil } }))
                        if task.dueDate != nil { DatePicker("Due", selection: Binding(get: { self.task?.dueDate ?? .now }, set: { date in store.edit(taskID) { $0.dueDate = date } }), displayedComponents: .date) }
                        if task.status == .canceled { Text("Canceled: " + task.cancellationReason).foregroundStyle(.secondary) }
                    }.font(.system(size: 12)).padding(.top, 10)
                }.font(.system(size: 11)).foregroundStyle(.secondary)
            }.padding(18).background(Color.accent.opacity(0.025), in: RoundedRectangle(cornerRadius: 8))
            .onAppear { notesFocused = true; store.activeRegion = .editor }
            .onChange(of: store.notesFocusRequest) { if store.focusNotesID == taskID { preview = false; notesFocused = true } }
            .onChange(of: notesFocused) { if notesFocused { store.activeRegion = .editor } }
            .onExitCommand { close() }
        }
    }
    private func close() { notesFocused = false; store.closeInspector(); NotificationCenter.default.post(name: .focusTasks, object: nil) }
    private func format(_ prefix: String, _ suffix: String, _ placeholder: String) {
        preview = false
        if notesFocused, let editor = NSApp.keyWindow?.firstResponder as? NSTextView {
            let range = editor.selectedRange()
            let selected = (editor.string as NSString).substring(with: range)
            editor.insertText(prefix + (selected.isEmpty ? placeholder : selected) + suffix, replacementRange: range)
        } else {
            store.edit(taskID) { $0.notes += ($0.notes.isEmpty ? "" : "\n") + prefix + placeholder + suffix }
        }
        notesFocused = true
    }
}

struct InlineSubtaskEntry: View {
    @Bindable var store: Store
    let parentID: UUID
    @FocusState private var focused: Bool
    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "arrow.turn.down.right").foregroundStyle(Color.accent)
            TextField("Add a subtask…", text: $store.inlineSubtaskDraft).textFieldStyle(.plain).focused($focused)
                .onSubmit { _ = store.submitInlineSubtask() }
                .onExitCommand { store.inlineSubtaskParent = nil; NotificationCenter.default.post(name: .focusTasks, object: nil) }
            Text("↵ add · ⇧↵ nest · esc done").font(.system(size: 9)).foregroundStyle(.tertiary)
        }.font(.system(size: 12)).padding(13).background(Color.accent.opacity(0.05), in: RoundedRectangle(cornerRadius: 7))
            .onAppear { focused = true; store.activeRegion = .editor }
            .background(SmartEntryTabHandler(enabled: false, shiftReturnEnabled: focused, handleShiftReturn: { _ = store.submitInlineSubtask(nest: true) }, handle: { _ in }).allowsHitTesting(false))
    }
}
