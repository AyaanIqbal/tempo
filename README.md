# Tempo

A native, local-first Mac task app. SwiftUI, no browser or task-data server. Sparkle handles app updates. Requires macOS 14+ and Swift 6 command line tools (full Xcode is optional).

## Run

```sh
swift run Tempo
```

Build a standalone app, then open it:

```sh
./scripts/build-app.sh
open build/Tempo.app
```

The app is ad-hoc signed for local development. Distribution and notarization are not configured.

## Test

```sh
swift run TempoChecks
```

## Features

- Start with an empty task list. No mandatory labels, dates, or priorities.
- Nested subtasks: completing a parent resolves unfinished descendants; resolving every child completes the parent. Reopening a child reopens resolved ancestors. Reopening a parent preserves its children's states.
- Cancellation requires a reason and propagates to unfinished descendants. Existing completed/canceled tasks are preserved. Canceled children count as resolved.
- Arbitrarily nested labels, one label path per task. Subtasks inherit their parent's path.
- Expandable IDE-style label explorer: + at the top creates a root label; + on a row creates a sub-label; right-click for siblings. Return saves an inline label, Escape cancels.
- Prefix matching suggests existing labels; accepting the suggestion removes the prefix. Matches never silently change a task. Ambiguous names show separate path suggestions.
- Importance: None (0), Low (1), Medium (2), High (3), Urgent (4). Optional sort by weight. None means unassigned. Parent importance is independent.
- Optional due dates and notes; independent dates on subtasks.
- List and status board, with drag and drop. Display properties saved separately for list and board.
- Mac menu shortcuts and searchable command menu with Up/Down selection, Return to execute, and automatic scrolling. See Help → Tempo Keyboard Shortcuts.
- Full-width sidebar navigation targets, including the padding around labels.
- Labels use simple dot markers. Right-click a label to rename, move, or remove it directly in the sidebar.
- Property controls sit on the right of the toolbar, with search in the middle and the view selector on the left. Click Labels, Importance, Due date, or Status directly to show/hide them. Settings stay independent for list and board. Completed tasks stay visible; status ordering puts in-progress work first and completed work last.
- Web view (⌘3): a native, zoomable map connecting labels, tasks, and subtasks. Status icons and colors distinguish open, in-progress, done, and canceled work; resolved tasks are included by default. Search and sidebar filters apply to the map. Click tasks to inspect them or their status icons to complete/reopen them.
- Automatic local JSON saving, atomic writes, export/restore, and session undo for deletions and edits.

## Data

Data lives in `~/Library/Application Support/Tempo/workspace.json`, independently of the repository location. File → Export Backup creates a portable JSON copy. Restore replaces the workspace after confirmation and supports session undo. Invalid data is preserved instead of overwritten; restore a valid backup to recover.

There is no task sync, account, or analytics. Release builds contact the public GitHub update feed through Sparkle. Keep regular backups. Undo stores the last workspace change; workspace undo includes edits to text fields. UI behavior still needs hands-on review. Removing a label moves its directly assigned tasks and child labels to its parent (or the top level/Inbox), and supports session undo.

No commits or pushes are made by the build scripts.

The checks use a standalone executable so they also run with Apple Command Line Tools installations that do not include the XCTest/Testing modules.

## Downloads and updates

See [Releasing Tempo](docs/RELEASING.md) for versioning, signed update packaging, GitHub Actions releases, and optional Apple notarization. The release workflow creates a draft for review; publishing it makes the stable download and update feed point to that release. Initial setup and a real two-version update test are required before calling distribution complete.

## Navigating your workspace

Click a sidebar view and use Up/Down to move through All tasks, Inbox, Today, and visible labels. Left collapses a branch or moves to its parent. Right enters the task list. Click a branch chevron to expand it. Use Control-Command-S to focus the sidebar from the keyboard. Editing text keeps normal arrow-key behavior. Press Escape from task entry to highlight the selected/newly created task, without clearing unfinished text. Search and task details/notes return to the sidebar on Escape.

Command-K searches label paths and tasks as well as commands. Select a label result to open its view (collapsed ancestors expand automatically), or a task result to open its details. Breadcrumbs show the complete workspace/label/sub-label path, with clickable parents.

All tasks keeps its original caption. Inbox and Today have their own descriptions. Click the caption or pencil on any label view to customize it; Use default resets it. Captions are stored with labels, included in backups, and old data without captions still loads.

## Task selection and quick entry

Creating a task highlights it without opening the detail pane. New tasks appear first. Escape leaves quick entry at that selected task; Up/Down moves through visible tasks and subtasks. Left returns to the sidebar, and Right from the sidebar enters tasks. Enter, Right from a selected task, or clicking an existing task opens details. Shift-Enter (or Command-Shift-N) starts a subtask of the selected task in the composer.

Completed tasks are visible by default; completed work stays visible below open tasks. Subtasks appear as nested rows and can be collapsed. Label counts include all tasks and inherited subtasks within the entire label branch, including completed/canceled tasks.

Smart-entry matches can be accepted with Tab while typing or while a task is selected. Unaccepted suggestions appear next to a selected task, including after selecting it again later; Dismiss is stored per task. Accepting a suggestion assigns its label and removes its prefix from the title. Subtasks inherit labels, so their titles are not parsed into independent label paths.

The label property opens a searchable, indented hierarchy instead of a flat menu. Search by label name or any parent in the path; Up/Down and Enter work in the chooser.

Run `./scripts/check-interactions.sh` to verify selection versus explicit opening, new-task order, subtask navigation, completed visibility, smart matching, and persisted workspace data using a temporary workspace (not your real tasks).

Summary cards count only the current view: all work in All tasks, unlabeled work in Inbox, due-today work in Today, and the full current label branch in label views. Task order is In progress, To do, Done, then Canceled; optional priority sorting applies within each status. Nested tasks follow the same ordering within their parent. Moving between sidebar and task list transfers the highlight to the active region while remembering the selected task.
