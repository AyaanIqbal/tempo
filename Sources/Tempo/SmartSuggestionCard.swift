import SwiftUI
import TempoCore

struct SmartSuggestionCard: View {
    @Bindable var store: Store
    let taskID: UUID
    var body: some View {
        if let task = store.workspace.tasks.first(where: { $0.id == taskID }), !store.workspace.smartMatches(for: task).isEmpty {
            VStack(alignment: .leading, spacing: 9) {
                Text("Suggested label").font(.system(size: 10)).foregroundStyle(.secondary)
                ForEach(store.workspace.smartMatches(for: task)) { label in
                    HStack {
                        Button(store.workspace.labelPath(label.id).map(\.name).joined(separator: " / ")) {
                            store.acceptSuggestion(task: task.id, label: label.id)
                            NotificationCenter.default.post(name: .focusTasks, object: nil)
                        }.buttonStyle(.bordered)
                        Text("Tab to accept").foregroundStyle(.tertiary)
                        Spacer(minLength: 0)
                    }.font(.system(size: 11))
                }
                Button("Dismiss for this task") {
                    store.edit(task.id) { $0.smartEntryDismissed = true }
                    NotificationCenter.default.post(name: .focusTasks, object: nil)
                }.buttonStyle(.plain).font(.system(size: 10)).foregroundStyle(.secondary)
            }.padding(12).frame(maxWidth: .infinity, alignment: .leading).background(Color.accent.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
        }
    }
}
