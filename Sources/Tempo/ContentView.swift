import SwiftUI
import TempoCore

struct ContentView: View {
    @Bindable var store: Store
    @State private var draft = ""
    @State private var showDisplay = false
    @State private var showCaptionEditor = false
    @State private var acceptedLabel: UUID?
    @State private var dismissedMatch = false
    @FocusState private var focus: Field?
    @FocusState private var sidebarFocused: Bool
    enum Field { case composer, search }
    var body: some View {
        HSplitView {
            sidebar.frame(minWidth: 200, idealWidth: 220, maxWidth: 260)
                .focusable().focusEffectDisabled().focused($sidebarFocused)
                .onKeyPress(.downArrow) { guard sidebarFocused else { return .ignored }; store.navigateViews(1); return .handled }
                .onKeyPress(.upArrow) { guard sidebarFocused else { return .ignored }; store.navigateViews(-1); return .handled }
                .onKeyPress(.rightArrow) { guard sidebarFocused else { return .ignored }; store.navigateLabelBranch(expand: true); return .handled }
                .onKeyPress(.leftArrow) { guard sidebarFocused else { return .ignored }; store.navigateLabelBranch(expand: false); return .handled }
            VStack(spacing: 0) {
                header
                ScrollView {
                    VStack(alignment: .leading, spacing: 25) {
                        introduction
                        summary
                        toolbar
                        composer
                        if store.viewMode == .web { TaskWebView(store: store) } else if store.board { board } else { taskList }
                        HStack { Spacer(); Text("A little structure. A little more headspace.").font(.system(size: 11)).foregroundStyle(.tertiary); Spacer() }.padding(.top, 10)
                    }.padding(32).frame(maxWidth: 1080).frame(maxWidth: .infinity)
                }
            }.frame(minWidth: 490, maxWidth: .infinity).background(Color.canvas)
            if let task = store.selected {
                TaskInspector(store: store, taskID: task.id).id(task.id).frame(minWidth: 300, idealWidth: 330, maxWidth: 400)
            }
        }
        .sheet(isPresented: $store.showCommands) { CommandMenuView(store: store) }
        .sheet(isPresented: $store.showHelp) { ShortcutsView() }
        .sheet(isPresented: Binding(get: { store.pendingCancel != nil }, set: { if !$0 { store.pendingCancel = nil } })) { CancelTaskView(store: store) }
        .alert("Tempo", isPresented: Binding(get: { store.message != nil }, set: { if !$0 { store.message = nil } })) { Button("OK") { store.message = nil } } message: { Text(store.message ?? "") }
        .onChange(of: store.scope) { store.revealCurrentLabel() }
        .onReceive(NotificationCenter.default.publisher(for: .focusSidebar)) { _ in sidebarFocused = true }
        .onChange(of: store.focusComposer) { focus = .composer }
        .onReceive(NotificationCenter.default.publisher(for: .searchTasks)) { _ in focus = .search }
    }
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 9) { Image(systemName: "waveform.path").font(.system(size: 23, weight: .bold)).foregroundStyle(Color.accent); Text("tempo").font(.system(size: 25, weight: .bold, design: .rounded)) }.padding(.bottom, 30).padding(.top, 28).padding(.leading, 10)
            nav("All tasks", symbol: "square.stack.3d.up", scope: "all", count: store.workspace.tasks.filter { $0.parentID == nil && !$0.status.isResolved }.count)
            nav("Inbox", symbol: "tray", scope: "inbox")
            nav("Today", symbol: "sun.max", scope: "today")
            LabelExplorer(store: store, selection: Binding(get: { UUID(uuidString: store.scope) }, set: { id in if let id { store.openScope(id.uuidString); sidebarFocused = true } })).padding(.top, 26)
            Spacer(minLength: 15)
            Divider().padding(.horizontal, 10)
            Button { store.showCommands = true } label: { HStack { Label("Command menu", systemImage: "command"); Spacer(); Text("⌘K").foregroundStyle(.tertiary) }.padding(12).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle()) }.buttonStyle(.plain).font(.system(size: 11))
            Menu { Button("Export backup…") { store.exportBackup() }; Button("Restore backup…") { store.importBackup() }; Button("Keyboard shortcuts") { store.showHelp = true } } label: { Label("Local workspace", systemImage: "internaldrive").font(.system(size: 11)).foregroundStyle(.secondary) }.menuStyle(.borderlessButton).padding(.horizontal, 12).padding(.bottom, 20)
        }.padding(.horizontal, 12).background(Color.accent.opacity(0.035))
    }
    private func nav(_ title: String, symbol: String, scope: String, count: Int? = nil) -> some View {
        Button { store.openScope(scope); sidebarFocused = true } label: { HStack(spacing: 11) { Image(systemName: symbol).frame(width: 16); Text(title); Spacer(); if let count { Text("\(count)").font(.system(size: 11)) } }.font(.system(size: 12, weight: store.scope == scope ? .semibold : .regular)).padding(11).foregroundStyle(store.scope == scope ? Color.accent : .secondary).frame(maxWidth: .infinity, minHeight: 36, alignment: .leading).background(store.scope == scope ? Color.accent.opacity(0.11) : .clear, in: RoundedRectangle(cornerRadius: 7)).contentShape(Rectangle()) }.buttonStyle(.plain)
    }
    private var header: some View {
        HStack(spacing: 12) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    Button("My workspace") { store.openScope("all") }.foregroundStyle(.tertiary)
                    let path = store.workspace.labelPath(UUID(uuidString: store.scope))
                    if path.isEmpty {
                        Image(systemName: "chevron.right").font(.system(size: 8)).foregroundStyle(.tertiary)
                        Text(store.title).foregroundStyle(.secondary)
                    } else {
                        ForEach(path) { label in
                            Image(systemName: "chevron.right").font(.system(size: 8)).foregroundStyle(.tertiary)
                            Button(label.name) { store.openScope(label.id.uuidString) }.foregroundStyle(label.id.uuidString == store.scope ? Color.primary : .secondary)
                        }
                    }
                }.buttonStyle(.plain).font(.system(size: 11)).fixedSize(horizontal: true, vertical: false)
            }
            Spacer(minLength: 0)
            Image(systemName: "checkmark.icloud").foregroundStyle(Color.accent.opacity(0.6))
            Text("On this Mac").foregroundStyle(.tertiary).fixedSize()
        }.font(.system(size: 11)).padding(.horizontal, 32).frame(height: 57).overlay(alignment: .bottom) { Divider().opacity(0.5) }
    }
    private var introduction: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 8) { Text(Date.now.formatted(.dateTime.weekday(.wide).month(.wide).day()).uppercased()).font(.system(size: 9, weight: .medium)).tracking(1.8).foregroundStyle(.tertiary); Text(store.title).font(.system(size: 30, weight: .semibold)); caption }
            Spacer()
            Button { focus = .composer } label: { Label("New task", systemImage: "plus").font(.system(size: 12, weight: .medium)).padding(.vertical, 4) }.buttonStyle(.borderedProminent).keyboardShortcut("n")
        }
    }
    private var caption: some View {
        Group {
            if let label = store.workspace.labels.first(where: { $0.id.uuidString == store.scope }) {
                Button { showCaptionEditor = true } label: {
                    HStack(spacing: 6) {
                        Text(store.workspace.viewCaption(for: store.scope)).fixedSize(horizontal: false, vertical: true)
                        Image(systemName: "pencil").font(.system(size: 9)).foregroundStyle(.tertiary)
                    }.font(.system(size: 12)).foregroundStyle(.secondary).padding(.vertical, 3).contentShape(Rectangle())
                }.buttonStyle(.plain).help("Customize this label's caption")
                .popover(isPresented: $showCaptionEditor) { LabelCaptionEditor(store: store, labelID: label.id).id(label.id) }
            } else {
                Text(store.workspace.viewCaption(for: store.scope)).font(.system(size: 12)).foregroundStyle(.secondary)
            }
        }.onChange(of: store.scope) { showCaptionEditor = false }
    }
    private var summary: some View {
        HStack(spacing: 12) {
            stat("To do", count: store.workspace.tasks.filter { $0.parentID == nil && $0.status == .todo }.count, symbol: "circle.dotted", color: .accent)
            stat("In progress", count: store.workspace.tasks.filter { $0.parentID == nil && $0.status == .inProgress }.count, symbol: "circle.lefthalf.filled", color: .orange)
            stat("Completed", count: store.workspace.tasks.filter { $0.parentID == nil && $0.status == .done }.count, symbol: "checkmark.circle", color: .green)
        }
    }
    private func stat(_ title: String, count: Int, symbol: String, color: Color) -> some View {
        HStack(spacing: 12) { Image(systemName: symbol).font(.system(size: 18)).foregroundStyle(color.opacity(0.75)).frame(width: 35, height: 35).background(color.opacity(0.07), in: RoundedRectangle(cornerRadius: 10)); VStack(alignment: .leading, spacing: 3) { Text("\(count)").font(.system(size: 22, weight: .medium)); Text(title).font(.system(size: 10)).foregroundStyle(.secondary) }; Spacer(minLength: 0) }.padding(16).frame(maxWidth: .infinity).background(.background, in: RoundedRectangle(cornerRadius: 10)).overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(.quaternary.opacity(0.5)) }
    }
    private var toolbar: some View {
        HStack(spacing: 10) {
            Picker("View", selection: $store.viewMode) { Label("List", systemImage: "list.bullet").tag(WorkspaceView.list); Label("Board", systemImage: "rectangle.split.3x1").tag(WorkspaceView.board); Label("Web", systemImage: "point.3.connected.trianglepath.dotted").tag(WorkspaceView.web) }.pickerStyle(.segmented).labelsHidden().frame(width: 225)
            Spacer(minLength: 0)
            TextField("Search", text: $store.search).textFieldStyle(.roundedBorder).frame(maxWidth: 150).focused($focus, equals: .search)
            Button { showDisplay.toggle() } label: { Label("Display", systemImage: "slider.horizontal.3").font(.system(size: 12)).padding(.vertical, 5).contentShape(Rectangle()) }
                .buttonStyle(.plain).disabled(store.viewMode == .web)
                .popover(isPresented: $showDisplay, arrowEdge: .bottom) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("VISIBLE PROPERTIES").font(.system(size: 9, weight: .semibold)).tracking(1.2).foregroundStyle(.secondary).padding(.horizontal, 10).padding(.vertical, 8)
                        displayProperty("Labels", key: \.labels)
                        displayProperty("Importance", key: \.importance)
                        displayProperty("Due date", key: \.dueDate)
                        displayProperty("Status", key: \.status)
                        Divider().padding(.vertical, 7)
                        Toggle("Show resolved tasks", isOn: $store.showResolved).toggleStyle(.checkbox).font(.system(size: 11)).padding(8)
                        Toggle("Sort by importance", isOn: $store.sortByImportance).toggleStyle(.checkbox).font(.system(size: 11)).padding(8)
                    }.padding(10).frame(width: 230)
                }

        }
    }
    private func displayProperty(_ title: String, key: WritableKeyPath<ViewProperties, Bool>) -> some View {
        let visible = store.properties[keyPath: key]
        return Button { store.toggleProperty(key) } label: {
            HStack {
                Text(title)
                Spacer()
                Image(systemName: visible ? "checkmark.square.fill" : "square").foregroundStyle(visible ? Color.accent : .secondary)
            }.font(.system(size: 12)).padding(10).frame(maxWidth: .infinity)
                .background(visible ? Color.accent.opacity(0.07) : .clear, in: RoundedRectangle(cornerRadius: 6)).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityLabel(title).accessibilityValue(visible ? "Visible" : "Hidden")
    }
    private var composer: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "plus").foregroundStyle(.tertiary)
                TextField("What needs to get done?", text: $draft).textFieldStyle(.plain).focused($focus, equals: .composer).onSubmit(addTask)
                if let acceptedLabel { Text(store.workspace.labelPath(acceptedLabel).map(\.name).joined(separator: " / ")).font(.system(size: 10)).foregroundStyle(Color.accent); Button { self.acceptedLabel = nil } label: { Image(systemName: "xmark") }.buttonStyle(.plain) }
                Text("↵").foregroundStyle(.tertiary)
            }
            if !dismissedMatch && acceptedLabel == nil {
                ForEach(store.workspace.matches(for: draft)) { match in
                    HStack { Text("Suggested:").foregroundStyle(.secondary); Button(store.workspace.labelPath(match.id).map(\.name).joined(separator: " / ")) { acceptedLabel = match.id; draft = String(draft.dropFirst(match.name.count)).trimmingCharacters(in: .whitespaces) }; Button("Dismiss") { dismissedMatch = true }.buttonStyle(.plain).foregroundStyle(.secondary) }.font(.system(size: 11))
                }
            }
        }.padding(16).background(.background, in: RoundedRectangle(cornerRadius: 9)).overlay { RoundedRectangle(cornerRadius: 9).strokeBorder(Color.accent.opacity(0.18)) }.onChange(of: draft) { if draft.isEmpty { dismissedMatch = false; acceptedLabel = nil } }
    }
    private func addTask() {
        let label = acceptedLabel ?? store.workspace.labels.first { $0.id.uuidString == store.scope }?.id
        store.add(draft, label: label); draft = ""; acceptedLabel = nil; dismissedMatch = false; focus = .composer
    }
    private var taskList: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Text("YOUR TASKS").tracking(1.5); Spacer(); Text("\(store.roots.count) tasks") }.font(.system(size: 9, weight: .medium)).foregroundStyle(.tertiary)
            if store.roots.isEmpty {
                VStack(spacing: 12) { Image(systemName: store.search.isEmpty ? "sparkles" : "magnifyingglass").font(.system(size: 25)).foregroundStyle(Color.accent.opacity(0.5)); Text(store.search.isEmpty ? "A little space to get started." : "No matching tasks.").font(.system(size: 15, weight: .medium)); Text(store.search.isEmpty ? "Write your first task above. Details can wait." : "Try another search or change your filters.").font(.system(size: 12)).foregroundStyle(.secondary) }.frame(maxWidth: .infinity).padding(.vertical, 65)
            } else {
                LazyVStack(spacing: 0) { ForEach(store.roots) { task in TaskRow(store: store, task: task); if task.id != store.roots.last?.id { Divider().padding(.leading, 45) } } }.background(.background, in: RoundedRectangle(cornerRadius: 10)).overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(.quaternary.opacity(0.5)) }
            }
        }
    }
    private var board: some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: 12) {
                ForEach(TaskStatus.allCases, id: \.self) { status in
                    VStack(alignment: .leading, spacing: 12) {
                        HStack { Image(systemName: status.symbol); Text(status.rawValue); Spacer(); Text("\(store.roots.filter { $0.status == status }.count)").foregroundStyle(.tertiary) }.font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                        ForEach(store.roots.filter { $0.status == status }) { task in
                            VStack(alignment: .leading, spacing: 12) { Text(task.title).font(.system(size: 12, weight: .medium)).fixedSize(horizontal: false, vertical: true); TaskBadges(store: store, task: task) }.frame(maxWidth: .infinity, alignment: .leading).padding(14).background(.background, in: RoundedRectangle(cornerRadius: 8)).overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(store.selectedID == task.id ? Color.accent.opacity(0.6) : Color.secondary.opacity(0.08)) }.onTapGesture { store.selectedID = task.id }.draggable(task.id.uuidString)
                        }
                        if store.roots.filter({ $0.status == status }).isEmpty { Text("Drop a task here").font(.system(size: 11)).foregroundStyle(.tertiary).frame(maxWidth: .infinity).padding(.vertical, 30) }
                        Spacer(minLength: 0)
                    }.padding(12).frame(width: 210).frame(minHeight: 320).background(Color.accent.opacity(0.035), in: RoundedRectangle(cornerRadius: 9)).dropDestination(for: String.self) { ids, _ in guard let raw = ids.first, let id = UUID(uuidString: raw), store.workspace.tasks.contains(where: { $0.id == id }) else { return false }; store.status(id, status); return true }
                }
            }
        }
    }
}
struct TaskRow: View {
    @Bindable var store: Store
    let task: TaskItem
    var body: some View {
        HStack(spacing: 12) {
            Button { store.toggle(task.id) } label: { Image(systemName: task.status.symbol).font(.system(size: 17)).foregroundStyle(task.status.isResolved ? Color.accent.opacity(0.6) : Color.secondary.opacity(0.4)) }.buttonStyle(.plain).help(task.status.isResolved ? "Reopen task" : "Complete task")
            VStack(alignment: .leading, spacing: 5) {
                Text(task.title).font(.system(size: 12)).strikethrough(task.status.isResolved).foregroundStyle(task.status.isResolved ? .secondary : .primary).lineLimit(2)
                let children = store.workspace.children(of: task.id)
                if !children.isEmpty { Text("\(children.filter { $0.status.isResolved }.count)/\(children.count) subtasks").font(.system(size: 9)).foregroundStyle(.tertiary) }
            }
            Spacer(minLength: 0)
            TaskBadges(store: store, task: task)
        }.padding(15).background(store.selectedID == task.id ? Color.accent.opacity(0.055) : .clear).contentShape(Rectangle()).onTapGesture { store.selectedID = task.id }
        .contextMenu { ForEach(TaskStatus.allCases, id: \.self) { status in Button(status.rawValue) { store.status(task.id, status) } }; Divider(); Button("Delete", role: .destructive) { store.selectedID = task.id; store.deleteSelected() } }
    }
}
struct TaskBadges: View {
    let store: Store
    let task: TaskItem
    var body: some View {
        HStack(spacing: 8) {
            if store.properties.importance && task.importance != .none { Text(task.importance.title).foregroundStyle(task.importance == .urgent ? .red : .orange) }
            if store.properties.labels, let name = store.workspace.labelPath(store.workspace.effectiveLabel(task)).last?.name { Text(name).foregroundStyle(Color.accent).padding(.horizontal, 7).padding(.vertical, 4).background(Color.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 4)) }
            if store.properties.dueDate, let date = task.dueDate { Text(date.formatted(.dateTime.month(.abbreviated).day())).foregroundStyle(date < Calendar.current.startOfDay(for: .now) && !task.status.isResolved ? .red : .secondary) }
            if store.properties.status { Text(task.status.rawValue).foregroundStyle(.secondary) }
        }.font(.system(size: 9))
    }
}
