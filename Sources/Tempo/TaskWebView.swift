import SwiftUI
import TempoCore

private struct WebLayout {
    let nodes: [TaskGraphNode]
    var positions: [String: CGPoint] = [:]
    var size = CGSize(width: 500, height: 300)
    init(nodes: [TaskGraphNode]) {
        self.nodes = nodes
        let children = Dictionary(grouping: nodes.filter { $0.parent != nil }, by: { $0.parent! })
        var leaf = 0
        var deepest = 0
        func place(_ node: TaskGraphNode, depth: Int) -> CGFloat {
            deepest = max(deepest, depth)
            let branches = children[node.id] ?? []
            let y: CGFloat
            if branches.isEmpty { y = 60 + CGFloat(leaf) * 92; leaf += 1 }
            else { let values = branches.map { place($0, depth: depth + 1) }; y = (values.first! + values.last!) / 2 }
            positions[node.id] = CGPoint(x: 130 + CGFloat(depth) * 265, y: y)
            return y
        }
        if let root = nodes.first { _ = place(root, depth: 0) }
        size = CGSize(width: max(500, CGFloat(deepest) * 265 + 260), height: max(300, CGFloat(leaf) * 92 + 35))
    }
}

struct TaskWebView: View {
    @Bindable var store: Store
    @State private var includeResolved = true
    @State private var zoom = 0.85
    private var nodes: [TaskGraphNode] { store.workspace.taskGraph(scope: store.scope, query: store.search, includeResolved: includeResolved) }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 5) { Text("YOUR WORK, CONNECTED").font(.system(size: 9, weight: .medium)).tracking(1.5).foregroundStyle(.tertiary); Text("Labels branch into projects, tasks, and subtasks.").font(.system(size: 11)).foregroundStyle(.secondary) }
                Spacer()
                Toggle("Include resolved", isOn: $includeResolved).toggleStyle(.checkbox).font(.system(size: 10))
            }
            HStack(spacing: 14) {
                legend(.todo, color: .secondary); legend(.inProgress, color: .orange); legend(.done, color: .green); legend(.canceled, color: .secondary)
                Spacer(minLength: 0)
                Button { zoom = max(0.35, zoom - 0.15) } label: { Image(systemName: "minus").frame(width: 22, height: 24).contentShape(Rectangle()) }.help("Zoom out")
                Button("\(Int(zoom * 100))%") { zoom = 0.85 }.font(.system(size: 10)).help("Reset zoom")
                Button { zoom = min(1.6, zoom + 0.15) } label: { Image(systemName: "plus").frame(width: 22, height: 24).contentShape(Rectangle()) }.help("Zoom in")
            }.buttonStyle(.plain)
            if nodes.count <= 1 {
                VStack(spacing: 12) { Image(systemName: "point.3.connected.trianglepath.dotted").font(.system(size: 32)).foregroundStyle(Color.accent.opacity(0.5)); Text(store.search.isEmpty ? "Your map starts here." : "No matching tasks.").font(.system(size: 15, weight: .medium)); Text("Add labels and tasks to see how everything connects.").font(.system(size: 12)).foregroundStyle(.secondary) }.frame(maxWidth: .infinity).frame(height: 300)
            } else {
                let layout = WebLayout(nodes: nodes)
                ScrollView([.horizontal, .vertical]) {
                    ZStack(alignment: .topLeading) {
                        Canvas { context, _ in
                            for node in nodes {
                                guard let parent = node.parent, let start = layout.positions[parent], let end = layout.positions[node.id] else { continue }
                                var path = Path(); let a = CGPoint(x: start.x + 103, y: start.y); let b = CGPoint(x: end.x - 103, y: end.y)
                                path.move(to: a); path.addCurve(to: b, control1: CGPoint(x: a.x + 38, y: a.y), control2: CGPoint(x: b.x - 38, y: b.y))
                                context.stroke(path, with: .color(node.status == .done ? .green.opacity(0.3) : Color.accent.opacity(0.22)), style: StrokeStyle(lineWidth: 1.4, dash: node.status == .canceled ? [4, 4] : []))
                            }
                        }.frame(width: layout.size.width, height: layout.size.height).allowsHitTesting(false)
                        ForEach(nodes) { node in
                            webNode(node).frame(width: 206, height: 64).position(layout.positions[node.id] ?? .zero)
                        }
                    }.frame(width: layout.size.width, height: layout.size.height).scaleEffect(zoom, anchor: .topLeading).frame(width: layout.size.width * zoom, height: layout.size.height * zoom, alignment: .topLeading)
                }.frame(height: 420).background(Color.accent.opacity(0.025), in: RoundedRectangle(cornerRadius: 10)).overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(.quaternary.opacity(0.5)) }
            }
            Text("Scroll to explore · Click a label to focus its branch · Click a task to see details").font(.system(size: 10)).foregroundStyle(.tertiary)
        }
    }
    private func webNode(_ node: TaskGraphNode) -> some View {
        let color = node.status == .done ? Color.green : node.status == .inProgress ? .orange : node.status == .canceled ? .secondary : .accent
        return HStack(spacing: 10) {
            if let status = node.status, let id = node.itemID {
                Button { store.toggle(id) } label: { Image(systemName: status.symbol).font(.system(size: 18)).foregroundStyle(color).frame(width: 28, height: 42).contentShape(Rectangle()) }.buttonStyle(.plain).help(status.isResolved ? "Reopen task" : "Complete task")
            } else {
                Image(systemName: node.kind == .workspace ? "waveform.path" : node.kind == .inbox ? "tray" : "tag").font(.system(size: 17)).foregroundStyle(Color.accent.opacity(0.75)).frame(width: 27)
            }
            Button { open(node) } label: {
                VStack(alignment: .leading, spacing: 5) {
                    Text(node.title).font(.system(size: 11, weight: node.kind == .task ? .medium : .semibold)).lineLimit(2).strikethrough(node.status == .done)
                    Text(node.status?.rawValue ?? branchSummary(node)).font(.system(size: 9)).foregroundStyle(node.status == .done ? .green : .secondary)
                }.frame(maxWidth: .infinity, minHeight: 48, alignment: .leading).contentShape(Rectangle())
            }.buttonStyle(.plain)
        }.padding(.horizontal, 11).frame(maxWidth: .infinity, maxHeight: .infinity).background(.background, in: RoundedRectangle(cornerRadius: 9)).overlay { RoundedRectangle(cornerRadius: 9).strokeBorder(store.selectedID == node.itemID && node.kind == .task ? Color.accent : color.opacity(0.2), lineWidth: 1) }
        .contextMenu { if node.kind == .task, let id = node.itemID { ForEach(TaskStatus.allCases, id: \.self) { status in Button(status.rawValue) { store.status(id, status) } } } }
        .accessibilityElement(children: .contain).accessibilityLabel("\(node.title), \(node.status?.rawValue ?? branchSummary(node))")
    }
    private func open(_ node: TaskGraphNode) {
        switch node.kind {
        case .task: store.selectedID = node.itemID
        case .label: if let id = node.itemID { store.scope = id.uuidString }
        case .inbox: store.scope = "inbox"
        case .workspace: store.scope = "all"
        }
    }
    private func branchSummary(_ node: TaskGraphNode) -> String {
        let tasks = store.workspace.tasks.filter { task in
            if node.kind == .workspace { return true }
            if node.kind == .inbox { return store.workspace.effectiveLabel(task) == nil }
            return store.workspace.labelPath(store.workspace.effectiveLabel(task)).contains { $0.id == node.itemID }
        }
        return "\(tasks.filter { $0.status == .done }.count) done · \(tasks.filter { !$0.status.isResolved }.count) open · \(tasks.filter { $0.status == .canceled }.count) canceled"
    }
    private func legend(_ status: TaskStatus, color: Color) -> some View { Label(status.rawValue, systemImage: status.symbol).font(.system(size: 9)).foregroundStyle(color) }
}
