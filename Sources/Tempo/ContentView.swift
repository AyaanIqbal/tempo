import SwiftUI
import TempoCore

struct ContentView: View {
    @Bindable var store: Store
    @State private var draft = ""
    @State private var focusBeforeCommands: Field?
    @State private var showCaptionEditor = false
    @State private var acceptedLabel: UUID?
    @State private var dismissedMatch = false
    @FocusState private var focus: Field?
    enum Field { case composer, search, sidebar, tasks }
    var body: some View {
        HSplitView {
            sidebar.frame(minWidth: 200, idealWidth: 220, maxWidth: 260)
                .focusable().focusEffectDisabled().focused($focus, equals: .sidebar)
                .onKeyPress(.downArrow) { guard focus == .sidebar else { return .ignored }; store.navigateViews(1); return .handled }
                .onKeyPress(.upArrow) { guard focus == .sidebar else { return .ignored }; store.navigateViews(-1); return .handled }
                .onKeyPress(.rightArrow) { guard focus == .sidebar else { return .ignored }; store.requestNewTask(); return .handled }
                .onKeyPress(.escape) { guard focus == .sidebar else { return .ignored }; navigateBack(); return .handled }
                .onKeyPress(.leftArrow) { guard focus == .sidebar else { return .ignored }; store.navigateLabelBranch(expand: false); return .handled }
            VStack(spacing: 0) {
                header
                ScrollViewReader { taskProxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 25) {
                        introduction
                        summary
                        toolbar
                        composer
                        if store.viewMode != .list { selectedSuggestion }
                        if store.board { board } else { taskList }
                        HStack { Spacer(); Text("A little structure. A little more headspace.").font(.system(size: 11)).foregroundStyle(.tertiary); Spacer() }.padding(.top, 10)
                    }.padding(32).frame(maxWidth: 1080).frame(maxWidth: .infinity)
                }
                .onChange(of: store.selectedID) { if let id = store.selectedID { withAnimation(.easeOut(duration: 0.1)) { taskProxy.scrollTo(id) } } }
                .onChange(of: store.inlineSubtaskParent) { if let id = store.inlineSubtaskParent { taskProxy.scrollTo(id, anchor: .center) } }
                }
            }.frame(minWidth: 490, maxWidth: .infinity).background(Color.canvas)
            .focusable().focusEffectDisabled().focused($focus, equals: .tasks)
            .onKeyPress(.downArrow) { guard focus == .tasks else { return .ignored }; store.selectNext(1); return .handled }
            .onKeyPress(.upArrow) { guard focus == .tasks else { return .ignored }; store.selectNext(-1); return .handled }
            .onKeyPress(.escape) { guard focus == .tasks else { return .ignored }; navigateBack(); return .handled }
            .onKeyPress(.leftArrow) { guard focus == .tasks else { return .ignored }; returnToSidebar(); return .handled }
            .onKeyPress(.rightArrow) { guard focus == .tasks, let id = store.selectedID else { return .ignored }; store.openTask(id); return .handled }
            .onKeyPress(keys: [.return], phases: .down) { key in
                guard focus == .tasks, !key.modifiers.contains(.command) else { return .ignored }
                if key.modifiers.contains(.shift) { beginSubtask() }
                else if let id = store.selectedID { store.openTask(id) }
                return .handled
            }

        }
        .background(SmartEntryTabHandler(enabled: canUseSmartEntryTab, shiftReturnEnabled: focus == .composer && !store.showCommands, handleShiftReturn: createParentAndSubtask,
            emptyEntryNavigation: focus == .composer && draft.isEmpty && !store.showCommands && !store.showHelp && store.pendingCancel == nil,
            handleEmptyArrow: { left in
                if left { returnToSidebar() }
                else if !store.taskRows.isEmpty { store.selectedID = nil; enterTasks() }
            }) { dismiss in
            if focus == .composer {
                if dismiss { dismissedMatch = true }
                else if let label = store.workspace.matches(for: draft, allowExact: true).first { acceptDraftSuggestion(label) }
            } else if dismiss, let task = store.selected {
                store.edit(task.id) { $0.smartEntryDismissed = true }
            } else {
                store.acceptSelectedSuggestion()
            }
        }.allowsHitTesting(false))
        .overlay {
            if store.showCommands {
                GeometryReader { geometry in
                    ZStack(alignment: .top) {
                        Color.black.opacity(0.16).ignoresSafeArea().contentShape(Rectangle())
                            .onTapGesture { dismissCommands() }
                        CommandMenuView(store: store, onDismiss: dismissCommands)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .overlay { RoundedRectangle(cornerRadius: 14).strokeBorder(Color.primary.opacity(0.08)) }
                            .shadow(color: .black.opacity(0.24), radius: 28, y: 12)
                            .padding(.top, min(geometry.size.height * 0.12, 90))
                            .frame(maxWidth: .infinity)
                    }
                }.transaction { $0.disablesAnimations = true }
            }
        }
        .onChange(of: store.showCommands) { if store.showCommands { focusBeforeCommands = focus } }
        .sheet(isPresented: $store.showHelp) { ShortcutsView() }
        .sheet(isPresented: Binding(get: { store.pendingCancel != nil }, set: { if !$0 { store.pendingCancel = nil } })) { CancelTaskView(store: store) }
        .alert("Tempo", isPresented: Binding(get: { store.message != nil }, set: { if !$0 { store.message = nil } })) { Button("OK") { store.message = nil } } message: { Text(store.message ?? "") }
        .onExitCommand { if !store.showCommands && !store.showHelp && store.pendingCancel == nil { navigateBack() } }
        .onAppear { focus = .sidebar }
        .onChange(of: focus) {
            switch focus {
            case .sidebar: store.activeRegion = .sidebar
            case .tasks: store.activeRegion = .tasks
            default: store.activeRegion = .editor
            }
        }
        .onChange(of: store.notesFocusRequest) { focus = nil; store.activeRegion = .editor }
        .onChange(of: store.scope) { store.revealCurrentLabel() }
        .onReceive(NotificationCenter.default.publisher(for: .focusSidebar)) { _ in returnToSidebar() }
        .onChange(of: store.focusComposer) { store.inlineSubtaskParent = nil; store.statusFilter = nil; store.search = ""; store.closeInspector(); store.activeRegion = .editor; focus = .composer }
        .onReceive(NotificationCenter.default.publisher(for: .focusTasks)) { _ in enterTasks() }
        .onReceive(NotificationCenter.default.publisher(for: .newSubtask)) { _ in beginSubtask() }
        .onReceive(NotificationCenter.default.publisher(for: .searchTasks)) { _ in focus = .search }
    }
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 9) { Image(systemName: "waveform.path").font(.system(size: 23, weight: .bold)).foregroundStyle(Color.accent); Text("tempo").font(.system(size: 25, weight: .bold, design: .rounded)) }.padding(.bottom, 30).padding(.top, 28).padding(.leading, 10)
            nav("All tasks", symbol: "square.stack.3d.up", scope: "all", count: store.workspace.tasks.filter { !$0.status.isResolved }.count)
            nav("Today", symbol: "sun.max", scope: "today")
            LabelExplorer(store: store, selection: Binding(get: { UUID(uuidString: store.scope) }, set: { id in if let id { store.openScope(id.uuidString); focus = .sidebar; store.activeRegion = .sidebar } })).padding(.top, 26)
            Spacer(minLength: 15)
            Divider().padding(.horizontal, 10)
            Button { store.showCommands = true } label: { HStack { Label("Command menu", systemImage: "command"); Spacer(); Text("⌘K").foregroundStyle(.tertiary) }.padding(12).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle()) }.buttonStyle(.tempo).font(.system(size: 11))
            Menu { Button("Export backup…") { store.exportBackup() }; Button("Restore backup…") { store.importBackup() }; Button("Keyboard shortcuts") { store.showHelp = true } } label: { Label("Local workspace", systemImage: "internaldrive").font(.system(size: 11)).foregroundStyle(.secondary) }.menuStyle(.borderlessButton).padding(.horizontal, 12).padding(.bottom, 20)
        }.padding(.horizontal, 12).background(Color.accent.opacity(0.035))
    }
    private func nav(_ title: String, symbol: String, scope: String, count: Int? = nil) -> some View {
        Button { store.openScope(scope); focus = .sidebar; store.activeRegion = .sidebar } label: { HStack(spacing: 11) { Image(systemName: symbol).frame(width: 16); Text(title); Spacer(); if let count { Text("\(count)").font(.system(size: 11)) } }.font(.system(size: 12, weight: store.scope == scope && store.activeRegion == .sidebar ? .semibold : .regular)).padding(11).foregroundStyle(store.scope == scope && store.activeRegion == .sidebar ? Color.accent : .secondary).frame(maxWidth: .infinity, minHeight: 36, alignment: .leading).background(store.scope == scope && store.activeRegion == .sidebar ? Color.accent.opacity(0.11) : .clear, in: RoundedRectangle(cornerRadius: 7)).contentShape(Rectangle()) }.buttonStyle(.tempo)
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
                }.buttonStyle(.tempo).font(.system(size: 11)).fixedSize(horizontal: true, vertical: false)
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
            Button { store.focusComposer = UUID() } label: { Label("New task", systemImage: "plus").font(.system(size: 12, weight: .medium)).padding(.vertical, 4) }.buttonStyle(.borderedProminent)
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
                }.buttonStyle(.tempo).help("Customize this label's caption")
                .popover(isPresented: $showCaptionEditor) { LabelCaptionEditor(store: store, labelID: label.id).id(label.id) }
            } else {
                Text(store.workspace.viewCaption(for: store.scope)).font(.system(size: 12)).foregroundStyle(.secondary)
            }
        }.onChange(of: store.scope) { showCaptionEditor = false }
    }
    private var summary: some View {
        HStack(spacing: 12) {
            statusCard(.todo, title: "To do", symbol: "circle.dotted", color: .accent)
            if store.showInProgress { statusCard(.inProgress, title: "In progress", symbol: "circle.lefthalf.filled", color: .orange) }
            statusCard(.done, title: "Completed", symbol: "checkmark.circle", color: .green)
        }
    }
    private func statusCard(_ status: TaskStatus, title: String, symbol: String, color: Color) -> some View {
        let selected = store.statusFilter == status
        return Button { store.toggleStatusFilter(status) } label: {
            HStack(spacing: 12) {
                Image(systemName: symbol).font(.system(size: 18)).foregroundStyle(color.opacity(0.8)).frame(width: 35, height: 35).background(color.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 3) { Text("\(store.summaryCount(status))").font(.system(size: 22, weight: .medium)); Text(title).font(.system(size: 10)).foregroundStyle(.secondary) }
                Spacer(minLength: 0)
                if selected { Image(systemName: "checkmark").font(.system(size: 11)).foregroundStyle(color) }
            }.padding(16).frame(maxWidth: .infinity).background(selected ? color.opacity(0.07) : Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10)).overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(selected ? color.opacity(0.5) : Color.secondary.opacity(0.12)) }.contentShape(Rectangle())
        }.buttonStyle(.tempo).help(selected ? "Show all tasks in this view" : "Show \(title.lowercased()) tasks").accessibilityValue(selected ? "Selected" : "Not selected")
    }
    private var toolbar: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 16) {
                viewSelector
                Spacer(minLength: 0)
                taskSearch.frame(width: 160)
                Spacer(minLength: 0)
                propertyControls
            }
            VStack(spacing: 12) {
                HStack(spacing: 16) { viewSelector; Spacer(minLength: 0); taskSearch.frame(maxWidth: 180) }
                HStack { Spacer(); propertyControls }
            }
        }
    }
    private var viewSelector: some View {
        Picker("View", selection: $store.viewMode) {
            Label("List", systemImage: "list.bullet").tag(WorkspaceView.list)
            Label("Board", systemImage: "rectangle.split.3x1").tag(WorkspaceView.board)
        }.pickerStyle(.segmented).labelsHidden().fixedSize(horizontal: true, vertical: false)
    }
    private var taskSearch: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundStyle(.tertiary)
            TextField("Search tasks", text: $store.search).textFieldStyle(.plain)
                .focused($focus, equals: .search).onExitCommand { returnToSidebar() }
        }.font(.system(size: 11)).padding(.horizontal, 10).frame(height: 30)
            .background(Color.secondary.opacity(0.035), in: RoundedRectangle(cornerRadius: 6))
            .overlay { RoundedRectangle(cornerRadius: 6).strokeBorder(Color.secondary.opacity(0.12)) }
    }
    private var propertyControls: some View {
        HStack(spacing: 2) {
            displayProperty("Labels", symbol: "tag", key: \.labels)
            displayProperty("Importance", symbol: "flag", key: \.importance)
            displayProperty("Due date", symbol: "calendar", key: \.dueDate)
            displayProperty("Status", symbol: "circle.lefthalf.filled", key: \.status)
        }.padding(3).background(Color.secondary.opacity(0.04), in: RoundedRectangle(cornerRadius: 7))
            .overlay { RoundedRectangle(cornerRadius: 7).strokeBorder(Color.secondary.opacity(0.1)) }
            .fixedSize(horizontal: true, vertical: false)
    }
    private func displayProperty(_ title: String, symbol: String, key: WritableKeyPath<ViewProperties, Bool>) -> some View {
        let enabled = store.properties[keyPath: key]
        return Button { store.toggleProperty(key) } label: {
            HStack(spacing: 5) { Image(systemName: symbol).font(.system(size: 10)); Text(title).fixedSize() }
                .font(.system(size: 10, weight: enabled ? .medium : .regular))
                .foregroundStyle(enabled ? Color.accent : .secondary)
                .padding(.horizontal, 8).frame(height: 26)
                .background(enabled ? Color.accent.opacity(0.09) : .clear, in: RoundedRectangle(cornerRadius: 4))
                .contentShape(Rectangle())
        }.buttonStyle(.tempo).help("\(enabled ? "Hide" : "Show") \(title.lowercased())")
            .accessibilityLabel(title).accessibilityValue(enabled ? "Visible" : "Hidden")
    }
    private var composer: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "plus").foregroundStyle(.tertiary)
                TextField("What needs to get done?", text: $draft)
                    .textFieldStyle(.plain).focused($focus, equals: .composer).onSubmit(addTask)
                    .onExitCommand { if store.selected != nil { enterTasks() } else { returnToSidebar() } }

                if let acceptedLabel { Text(store.workspace.labelPath(acceptedLabel).map(\.name).joined(separator: " > ")).font(.system(size: 10)).foregroundStyle(Color.accent); Button { self.acceptedLabel = nil } label: { Image(systemName: "xmark") }.buttonStyle(.tempo) }
                Text("↵").foregroundStyle(.tertiary)
            }
            if !dismissedMatch && acceptedLabel == nil {
                ForEach(store.workspace.matches(for: draft, allowExact: true)) { match in
                    HStack { Text("Suggested:").foregroundStyle(.secondary); Button(store.workspace.labelPath(match.id).map(\.name).joined(separator: " > ")) { acceptDraftSuggestion(match) }; Text("Tab to apply").foregroundStyle(.tertiary); Button("Dismiss · ⇧Tab") { dismissedMatch = true }.buttonStyle(.tempo).foregroundStyle(.secondary) }.font(.system(size: 11))
                }
            }
        }.padding(16).background(.background, in: RoundedRectangle(cornerRadius: 9)).overlay { RoundedRectangle(cornerRadius: 9).strokeBorder(Color.accent.opacity(0.18)) }
        .onChange(of: draft) { if draft.isEmpty { dismissedMatch = false } }
    }
    @ViewBuilder private var selectedSuggestion: some View {
        if focus != .composer, let task = store.selected { SmartSuggestionCard(store: store, taskID: task.id) }
    }
    private var canUseSmartEntryTab: Bool {
        guard !store.showCommands, !store.showHelp, store.pendingCancel == nil, !showCaptionEditor else { return false }
        if focus == .composer {
            return !dismissedMatch && acceptedLabel == nil && !store.workspace.matches(for: draft, allowExact: true).isEmpty
        }
        if focus == .tasks, let task = store.selected { return !store.workspace.smartMatches(for: task).isEmpty }
        return false
    }
    private func acceptDraftSuggestion(_ label: TaskLabel) {
        acceptedLabel = label.id
        focus = .composer
        draft = String(draft.dropFirst(label.name.count)).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private func dismissCommands() {
        store.showCommands = false
        focus = focusBeforeCommands ?? .sidebar
    }
    private func navigateBack() {
        store.navigateBack()
        focus = store.activeRegion == .tasks ? .tasks : .sidebar
    }
    private func returnToSidebar() {
        focus = .sidebar; store.activeRegion = .sidebar
    }
    private func enterTasks() {
        guard !store.taskRows.isEmpty else { store.focusComposer = UUID(); return }
        focus = nil
        if store.selectedID == nil { store.selectNext(1) }
        focus = .tasks; store.activeRegion = .tasks
    }
    private func beginSubtask() {
        guard let id = store.selectedID else { return }
        store.beginInlineSubtask(of: id)
        focus = nil
    }
    private func createParentAndSubtask() {
        let title = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        if title.isEmpty { beginSubtask(); return }
        let label = acceptedLabel ?? store.workspace.labels.first { $0.id.uuidString == store.scope }?.id
        guard let id = store.add(title, label: label, dismissSuggestion: dismissedMatch) else { return }
        draft = ""; acceptedLabel = nil; dismissedMatch = false
        store.beginInlineSubtask(of: id); focus = nil
    }
    private func addTask() {
        let label = acceptedLabel ?? store.workspace.labels.first { $0.id.uuidString == store.scope }?.id
        guard store.add(draft, label: label, dismissSuggestion: dismissedMatch) != nil else { return }
        draft = ""; acceptedLabel = nil; dismissedMatch = false; focus = .composer
    }
    private var taskList: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Text("YOUR TASKS").tracking(1.5); Spacer(); Text("\(store.taskRows.count) tasks") }.font(.system(size: 9, weight: .medium)).foregroundStyle(.tertiary)
            if store.roots.isEmpty {
                VStack(spacing: 12) { Image(systemName: store.search.isEmpty ? "sparkles" : "magnifyingglass").font(.system(size: 25)).foregroundStyle(Color.accent.opacity(0.5)); Text(store.search.isEmpty ? "A little space to get started." : "No matching tasks.").font(.system(size: 15, weight: .medium)); Text(store.search.isEmpty ? "Write your first task above. Details can wait." : "Try another search or change your filters.").font(.system(size: 12)).foregroundStyle(.secondary) }.frame(maxWidth: .infinity).padding(.vertical, 65)
            } else {
                LazyVStack(spacing: 0) { ForEach(store.taskRows) { row in TaskRow(store: store, task: row.task, depth: row.depth).id(row.id); if row.id != store.taskRows.last?.id { Divider().padding(.leading, 45) } } }.background(.background, in: RoundedRectangle(cornerRadius: 10)).overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(.quaternary.opacity(0.5)) }
            }
        }
    }
    private var board: some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: 12) {
                ForEach(store.boardStatuses, id: \.self) { status in
                    VStack(alignment: .leading, spacing: 12) {
                        HStack { Image(systemName: status.symbol); Text(status == .done ? "Completed" : status.rawValue); Spacer(); Text("\(store.roots.filter { store.displayStatus($0) == status }.count)").foregroundStyle(.tertiary) }.font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                        ForEach(store.roots.filter { store.displayStatus($0) == status }) { task in
                            VStack(alignment: .leading, spacing: 12) {
                                Button {
                                    store.openTask(task.id)
                                } label: {
                                    VStack(alignment: .leading, spacing: 12) {
                                        Text(task.title).font(.system(size: 12, weight: .medium)).fixedSize(horizontal: false, vertical: true)
                                        TaskBadges(store: store, task: task)
                                    }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                                }.buttonStyle(.tempo).draggable(task.id.uuidString)
                                if store.inspectorID == task.id { InlineTaskEditor(store: store, taskID: task.id).id(task.id) }
                            }.frame(maxWidth: .infinity, alignment: .leading).padding(14)
                                .background(.background, in: RoundedRectangle(cornerRadius: 8))
                                .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(store.highlightsTask(task.id) ? Color.accent.opacity(0.6) : Color.secondary.opacity(0.08)) }
                        }
                        if store.roots.filter({ store.displayStatus($0) == status }).isEmpty { Text("Drop a task here").font(.system(size: 11)).foregroundStyle(.tertiary).frame(maxWidth: .infinity).padding(.vertical, 30) }
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
    var depth = 0
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
        HStack(spacing: 12) {
            if !store.workspace.children(of: task.id).isEmpty {
                Button { if store.collapsedTasks.contains(task.id) { store.collapsedTasks.remove(task.id) } else { store.collapsedTasks.insert(task.id) } } label: { Image(systemName: store.collapsedTasks.contains(task.id) ? "chevron.right" : "chevron.down").font(.system(size: 9)).foregroundStyle(.secondary).frame(width: 15, height: 24).contentShape(Rectangle()) }.buttonStyle(.tempo)
            }
            Button { store.toggle(task.id) } label: { Image(systemName: store.displayStatus(task).symbol).font(.system(size: 17)).foregroundStyle(task.status.isResolved ? Color.accent.opacity(0.6) : Color.secondary.opacity(0.4)) }.buttonStyle(.tempo).help(task.status.isResolved ? "Reopen task" : "Complete task")
            VStack(alignment: .leading, spacing: 5) {
                Text(task.title).font(.system(size: 12)).strikethrough(task.status.isResolved).foregroundStyle(task.status.isResolved ? .secondary : .primary).lineLimit(2)
                let children = store.workspace.children(of: task.id)
                if !children.isEmpty { Text("\(children.filter { $0.status.isResolved }.count)/\(children.count) subtasks").font(.system(size: 9)).foregroundStyle(.tertiary) }
            }
            Spacer(minLength: 0)
            Button { store.beginInlineSubtask(of: task.id) } label: { Image(systemName: "plus").frame(width: 24, height: 24).contentShape(Rectangle()) }.buttonStyle(.tempo).foregroundStyle(.secondary).help("Add subtask · Shift-Enter")
            Button { store.editNotes(task.id) } label: { Image(systemName: task.notes.isEmpty ? "note.text.badge.plus" : "note.text").frame(width: 24, height: 24).contentShape(Rectangle()) }.buttonStyle(.tempo).foregroundStyle(.secondary).help("Edit notes · Shift-Command-M")
            TaskBadges(store: store, task: task)
        }.padding(15).padding(.leading, CGFloat(depth) * 22).background(store.highlightsTask(task.id) ? Color.accent.opacity(0.055) : .clear).contentShape(Rectangle()).hoverFeedback().onTapGesture { store.openTask(task.id) }
        .contextMenu { ForEach(store.boardStatuses, id: \.self) { status in Button(status.rawValue) { store.status(task.id, status) } }; Divider(); Button("Delete", role: .destructive) { store.selectedID = task.id; store.deleteSelected() } }
        if store.inspectorID == task.id {
            InlineTaskEditor(store: store, taskID: task.id).id(task.id).padding(.leading, 38 + CGFloat(depth) * 22).padding(.trailing, 15).padding(.bottom, 12)
        }
        if store.inlineSubtaskParent == task.id {
            InlineSubtaskEntry(store: store, parentID: task.id).id(task.id).padding(.leading, 38 + CGFloat(depth) * 22).padding(.trailing, 15).padding(.bottom, 12)
        }
        if store.highlightsTask(task.id) {
            SmartSuggestionCard(store: store, taskID: task.id).padding(.horizontal, 15 + CGFloat(depth) * 22).padding(.bottom, store.workspace.smartMatches(for: task).isEmpty ? 0 : 12)
        }
        }
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
            if store.properties.status { Text(store.displayStatus(task) == .done ? "Completed" : store.displayStatus(task).rawValue).foregroundStyle(.secondary) }
        }.font(.system(size: 9))
    }
}
