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
- Display opens a persistent property checklist: click a row to show/hide it, with separate visibility settings for list and board.
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

Click a sidebar view and use Up/Down to move through All tasks, Inbox, Today, and visible labels. Left collapses a branch or moves to its parent; Right expands it or enters its first child. Use Control-Command-S to focus the sidebar from the keyboard. Editing text keeps normal arrow-key behavior.

Command-K searches label paths and tasks as well as commands. Select a label result to open its view (collapsed ancestors expand automatically), or a task result to open its details. Breadcrumbs show the complete workspace/label/sub-label path, with clickable parents.

All tasks keeps its original caption. Inbox and Today have their own descriptions. Click the caption or pencil on any label view to customize it; Use default resets it. Captions are stored with labels, included in backups, and old data without captions still loads.
