import SwiftUI
import TempoCore

/// Searchable hierarchy replaces an ever-growing flat label menu.
struct LabelChooser: View {
    let store: Store
    @Binding var selection: UUID?
    @State private var presented = false
    @State private var query = ""
    @State private var highlighted = 0
    @FocusState private var searching: Bool
    private var rows: [LabelTreeRow] {
        let terms = query.split(whereSeparator: \.isWhitespace).map(String.init)
        return store.workspace.labelRows().filter { row in
            let path = store.workspace.labelPath(row.id).map(\.name).joined(separator: " / ")
            return terms.allSatisfy { path.localizedCaseInsensitiveContains($0) }
        }
    }
    var body: some View {
        HStack {
            Text("Label")
            Spacer()
            Button { query = ""; highlighted = 0; presented = true } label: {
                HStack(spacing: 7) { Text(store.workspace.labelPath(selection).last?.name ?? "None").lineLimit(1); Image(systemName: "chevron.up.chevron.down").font(.system(size: 8)) }.padding(.horizontal, 9).padding(.vertical, 6).background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 5)).contentShape(Rectangle())
            }.buttonStyle(.plain).help(store.workspace.labelPath(selection).map(\.name).joined(separator: " / "))
            .popover(isPresented: $presented) {
                VStack(alignment: .leading, spacing: 9) {
                    HStack { Image(systemName: "magnifyingglass").foregroundStyle(.secondary); TextField("Find a label…", text: $query).textFieldStyle(.plain).focused($searching)
                            .onKeyPress(.downArrow) { move(1); return .handled }
                            .onKeyPress(.upArrow) { move(-1); return .handled }
                            .onSubmit { choose(highlighted) }
                            .onExitCommand { presented = false }
                    }.padding(8)
                    Divider()
                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(spacing: 2) {
                                option(index: 0, id: nil, title: "None", path: "", depth: 0)
                                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                                    option(index: index + 1, id: row.id, title: row.label.name, path: query.isEmpty ? "" : store.workspace.labelPath(row.id).dropLast().map(\.name).joined(separator: " / "), depth: query.isEmpty ? row.depth : 0)
                                }
                            }
                        }.frame(maxHeight: 270)
                        .onChange(of: highlighted) { proxy.scrollTo(highlighted) }
                    }
                    Text("↑ ↓ to navigate · ↵ to assign").font(.system(size: 9)).foregroundStyle(.tertiary).padding(.horizontal, 8)
                }.padding(10).frame(width: 300).onAppear { searching = true }.onChange(of: query) { highlighted = 0 }
            }
        }
    }
    private func option(index: Int, id: UUID?, title: String, path: String, depth: Int) -> some View {
        Button { choose(index) } label: {
            HStack(spacing: 8) {
                Circle().fill(Color.accent.opacity(id == nil ? 0.15 : 0.65)).frame(width: 6, height: 6)
                VStack(alignment: .leading, spacing: 3) { Text(title); if !path.isEmpty { Text(path).font(.system(size: 9)).foregroundStyle(.secondary) } }
                Spacer(); if selection == id { Image(systemName: "checkmark").foregroundStyle(Color.accent) }
            }.font(.system(size: 12)).padding(.vertical, 9).padding(.leading, 10 + CGFloat(depth) * 13).padding(.trailing, 10).frame(maxWidth: .infinity, alignment: .leading).background(highlighted == index ? Color.accent.opacity(0.09) : .clear, in: RoundedRectangle(cornerRadius: 5)).contentShape(Rectangle())
        }.buttonStyle(.plain).id(index)
    }
    private func move(_ offset: Int) { highlighted = min(max(highlighted + offset, 0), rows.count) }
    private func choose(_ index: Int) { guard index == 0 || rows.indices.contains(index - 1) else { return }; selection = index == 0 ? nil : rows[index - 1].id; presented = false }
}
