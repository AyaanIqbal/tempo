import SwiftUI
import TempoCore

struct TaskInspector: View {
    @Bindable var store: Store
    let taskID: UUID
    @State private var subtask = ""
    @FocusState private var subtaskFocused: Bool
    private var task: TaskItem? { store.workspace.tasks.first { $0.id == taskID } }
    private func field<T>(_ path: WritableKeyPath<TaskItem, T>, fallback: T) -> Binding<T> { Binding(get: { task?[keyPath: path] ?? fallback }, set: { value in store.edit(taskID) { $0[keyPath: path] = value } }) }
    var body: some View {
        ScrollView {
            if let task {
                VStack(alignment: .leading, spacing: 22) {
                    HStack { Text("TASK DETAILS").font(.system(size: 9, weight: .medium)).tracking(1.7).foregroundStyle(.tertiary); Spacer(); Button { store.selectedID = nil } label: { Image(systemName: "xmark") }.buttonStyle(.plain).help("Close details") }
                    TextField("Task title", text: Binding(get: { self.task?.title ?? "" }, set: { value in if !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { store.edit(taskID) { $0.title = value } } }), axis: .vertical).font(.system(size: 21, weight: .semibold)).textFieldStyle(.plain)
                    if let parent = store.workspace.tasks.first(where: { $0.id == task.parentID }) { Button { store.selectedID = parent.id } label: { Label(parent.title, systemImage: "arrow.turn.up.left") }.font(.system(size: 11)).buttonStyle(.plain).foregroundStyle(Color.accent) }
                    VStack(alignment: .leading, spacing: 16) {
                        Picker("Status", selection: Binding(get: { self.task?.status ?? .todo }, set: { store.status(taskID, $0) })) { ForEach(TaskStatus.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                        Picker("Importance", selection: field(\.importance, fallback: .none)) { ForEach(Importance.allCases, id: \.self) { Text("\($0.title) · \($0.rawValue)").tag($0) } }
                        if task.parentID == nil {
                            Picker("Label", selection: field(\.labelID, fallback: nil)) { Text("None").tag(nil as UUID?); ForEach(store.workspace.labels) { label in Text(store.workspace.labelPath(label.id).map(\.name).joined(separator: " / ")).tag(Optional(label.id)) } }
                        } else {
                            HStack { Text("Label"); Spacer(); Text(store.workspace.labelPath(store.workspace.effectiveLabel(task)).map(\.name).joined(separator: " / ")).foregroundStyle(.secondary) }.font(.system(size: 11))
                            Text("Labels are inherited from the parent task.").font(.system(size: 10)).foregroundStyle(.tertiary)
                        }
                        Toggle("Due date", isOn: Binding(get: { self.task?.dueDate != nil }, set: { enabled in store.edit(taskID) { $0.dueDate = enabled ? Date() : nil } })).font(.system(size: 12))
                        if task.dueDate != nil { DatePicker("Due", selection: Binding(get: { self.task?.dueDate ?? .now }, set: { date in store.edit(taskID) { $0.dueDate = date } }), displayedComponents: [.date]).datePickerStyle(.field).font(.system(size: 12)) }
                    }.font(.system(size: 12))
                    if task.status == .canceled { VStack(alignment: .leading, spacing: 7) { Text("Cancellation reason").font(.system(size: 10, weight: .medium)); Text(task.cancellationReason).font(.system(size: 12)) }.foregroundStyle(.secondary).padding(12).frame(maxWidth: .infinity, alignment: .leading).background(Color.orange.opacity(0.07), in: RoundedRectangle(cornerRadius: 8)) }
                    Divider()
                    VStack(alignment: .leading, spacing: 9) { Text("NOTES").font(.system(size: 9, weight: .medium)).tracking(1.4).foregroundStyle(.tertiary); TextEditor(text: field(\.notes, fallback: "")).font(.system(size: 12)).scrollContentBackground(.hidden).frame(minHeight: 100).overlay(alignment: .topLeading) { if task.notes.isEmpty { Text("Add some detail, if you need it…").font(.system(size: 12)).foregroundStyle(.tertiary).padding(.top, 2).padding(.leading, 5).allowsHitTesting(false) } } }
                    Divider()
                    VStack(alignment: .leading, spacing: 10) {
                        HStack { Text("SUBTASKS").font(.system(size: 9, weight: .medium)).tracking(1.4).foregroundStyle(.tertiary); Spacer(); let children = store.workspace.children(of: taskID); Text("\(children.filter { $0.status.isResolved }.count)/\(children.count)").font(.system(size: 10)).foregroundStyle(.tertiary) }
                        ForEach(store.workspace.children(of: taskID)) { child in
                            HStack { Button { store.toggle(child.id) } label: { Image(systemName: child.status.symbol).foregroundStyle(Color.accent.opacity(0.6)) }.buttonStyle(.plain); Button { store.selectedID = child.id } label: { Text(child.title).strikethrough(child.status.isResolved).frame(maxWidth: .infinity, alignment: .leading) }.buttonStyle(.plain) }.font(.system(size: 12)).padding(.vertical, 6)
                        }
                        HStack { Image(systemName: "plus").foregroundStyle(.tertiary); TextField("Add subtask", text: $subtask).textFieldStyle(.plain).focused($subtaskFocused).onSubmit { let title = subtask; subtask = ""; store.add(title, parent: taskID); store.selectedID = taskID; subtaskFocused = true } }.padding(9).background(Color.secondary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
                    }
                    Spacer(minLength: 20)
                    Button("Delete task and subtasks", role: .destructive) { store.deleteSelected() }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(.red.opacity(0.7))
                    Text("Changes save automatically on this Mac.").font(.system(size: 10)).foregroundStyle(.tertiary)
                }.padding(24)
            }
        }.background(.background)
        .onExitCommand {
            subtaskFocused = false
            NotificationCenter.default.post(name: .focusSidebar, object: nil)
        }
        .onReceive(NotificationCenter.default.publisher(for: .newSubtask)) { _ in subtaskFocused = true }
    }
}
