import SwiftUI

struct LabelCaptionEditor: View {
    @Bindable var store: Store
    let labelID: UUID
    @Environment(\.dismiss) private var dismiss
    @State private var draft = ""
    @FocusState private var focused: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Customize caption").font(.system(size: 15, weight: .semibold))
            Text("Give this label view a little context of its own.").font(.system(size: 11)).foregroundStyle(.secondary)
            TextField("Add a caption…", text: $draft, axis: .vertical).lineLimit(2...4).textFieldStyle(.roundedBorder).focused($focused)
            HStack {
                Button("Use default") { store.setLabelCaption(labelID, caption: ""); dismiss() }.buttonStyle(.plain).foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") { store.setLabelCaption(labelID, caption: draft); dismiss() }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            }.font(.system(size: 11))
        }.padding(20).frame(width: 350)
        .onAppear { draft = store.workspace.labels.first { $0.id == labelID }?.caption ?? ""; focused = true }
    }
}
