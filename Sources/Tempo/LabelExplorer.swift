import SwiftUI
import TempoCore

/// Nested labels with inline creation and editing.
struct LabelExplorer: View {
    @Bindable var store: Store
    @Binding var selection: UUID?
    @State private var collapsed: Set<UUID> = []
    @State private var adding = false
    @State private var renaming: UUID?
    @State private var removing: UUID?
    @State private var draftParent: UUID?
    @State private var draft = ""
    @FocusState private var editing: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 2) {
                Text("LABELS").font(.system(size: 10, weight: .semibold)).tracking(1.7).foregroundStyle(.tertiary)
                Spacer()
                Button { beginAdding(parent: nil) } label: { Image(systemName: "plus").frame(width: 26, height: 26).contentShape(Rectangle()) }.help("New top-level label")
            }.buttonStyle(.plain).foregroundStyle(.secondary).padding(.leading, 12).padding(.trailing, 3)
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    if adding && draftParent == nil { editor(depth: 0) }
                    if store.workspace.labels.isEmpty && !adding { Text("No labels yet.\nUse + to create your first one.").font(.system(size: 11)).foregroundStyle(.tertiary).lineSpacing(5).padding(12) }
                    ForEach(store.workspace.labelRows(collapsed: collapsed)) { row in
                        if renaming == row.id { editor(depth: row.depth) } else { labelRow(row) }
                        if adding && draftParent == row.id { editor(depth: row.depth + 1) }
                    }
                }.padding(.vertical, 4)
            }
        }
        .confirmationDialog("Remove label?", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }), titleVisibility: .visible) {
            Button("Remove label", role: .destructive) { if let id = removing { store.removeLabel(id) }; removing = nil }
        } message: { Text("Tasks are kept. Sub-labels and directly assigned tasks move up one level. You can undo with ⌘Z.") }
    }
    private func labelRow(_ row: LabelTreeRow) -> some View {
        let hasChildren = store.workspace.labels.contains { $0.parentID == row.id }
        return HStack(spacing: 0) {
            Button {
                if collapsed.contains(row.id) { collapsed.remove(row.id) } else { collapsed.insert(row.id) }
            } label: { Image(systemName: collapsed.contains(row.id) ? "chevron.right" : "chevron.down").font(.system(size: 8, weight: .semibold)).foregroundStyle(.tertiary).frame(width: 20, height: 32).contentShape(Rectangle()) }.buttonStyle(.plain).disabled(!hasChildren).opacity(hasChildren ? 1 : 0)
            Button { selection = row.id } label: {
                HStack(spacing: 8) { Circle().fill(Color.accent.opacity(0.65)).frame(width: 6, height: 6); Text(row.label.name).lineLimit(1); Spacer(minLength: 0) }.font(.system(size: 12)).frame(maxWidth: .infinity, minHeight: 34, alignment: .leading).contentShape(Rectangle())
            }.buttonStyle(.plain)
            Button { beginAdding(parent: row.id) } label: { Image(systemName: "plus").font(.system(size: 10)).foregroundStyle(.secondary).frame(width: 27, height: 34).contentShape(Rectangle()) }.buttonStyle(.plain).help("New sub-label inside \(row.label.name)")
        }
        .padding(.leading, CGFloat(row.depth) * 14)
        .background(selection == row.id ? Color.accent.opacity(0.11) : .clear, in: RoundedRectangle(cornerRadius: 6))
        .contextMenu {
            Button("New sub-label") { beginAdding(parent: row.id) }
            Button("New sibling label") { beginAdding(parent: row.label.parentID) }
            Button("New top-level label") { beginAdding(parent: nil) }
            Divider()
            Button("Rename…") { adding = false; renaming = row.id; draft = row.label.name; editing = true }
            Menu("Move to") {
                Button("Top level") { store.updateLabel(row.id, name: row.label.name, parent: nil) }
                ForEach(store.workspace.labelRows().filter { $0.id != row.id && !store.workspace.labelDescendants(of: row.id).contains($0.id) }) { destination in
                    Button(store.workspace.labelPath(destination.id).map(\.name).joined(separator: " / ")) { store.updateLabel(row.id, name: row.label.name, parent: destination.id) }
                }
            }
            Button("Remove label…", role: .destructive) { removing = row.id }
        }
        .help(store.workspace.labelPath(row.id).map(\.name).joined(separator: " / "))
    }
    private func editor(depth: Int) -> some View {
        HStack(spacing: 6) {
            Circle().fill(Color.accent.opacity(0.65)).frame(width: 6, height: 6)
            TextField("Label name", text: $draft).textFieldStyle(.roundedBorder).focused($editing).onSubmit(create)
                .onKeyPress(.escape) { adding = false; renaming = nil; draft = ""; return .handled }
            Button(action: create) { Image(systemName: "return").frame(width: 20, height: 28).contentShape(Rectangle()) }.buttonStyle(.plain).disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }.font(.system(size: 11)).padding(.leading, 20 + CGFloat(depth) * 14).padding(.vertical, 4)
    }
    private func beginAdding(parent: UUID?) {
        renaming = nil; draftParent = parent; draft = ""; adding = true
        if let parent { collapsed.remove(parent) }
        editing = true
    }
    private func create() {
        if let id = renaming, let label = store.workspace.labels.first(where: { $0.id == id }) {
            store.updateLabel(id, name: draft, parent: label.parentID)
            if store.workspace.labels.first(where: { $0.id == id })?.name == draft.trimmingCharacters(in: .whitespacesAndNewlines) { renaming = nil; draft = "" }
            return
        }
        guard let id = store.addLabel(draft, parent: draftParent) else { return }
        selection = id; adding = false; draft = ""
    }
}
