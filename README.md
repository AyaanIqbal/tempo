# Tempo

A native, local-first Mac task app. SwiftUI, no browser or task-data server. Sparkle handles app updates. Requires macOS 14+ and Swift 6 command line tools; full Xcode is optional for local development.

## Download

[Download Tempo for Mac (.dmg)](https://github.com/AyaanIqbal/tempo/releases/latest/download/Tempo.dmg). Open the disk image and drag Tempo to Applications. Supports Apple Silicon and Intel. Public releases may lag the latest source; early builds are not yet notarized by Apple.

## Run and build

```sh
swift run Tempo
./scripts/build-app.sh
open build/Tempo.app
```

## Tasks, notes, and subtasks in one place

Start with a plain task list. Optional labels, dates, priorities, and status columns stay out of the way until you enable them. Click a task or press Enter to expand its notes and properties directly in the list and immediately type in its Markdown notes. There is no right-hand detail pane. Board cards also expand in place.

- **Enter while composing:** save the task.
- **Shift-Enter while composing:** save the parent and start its first subtask directly underneath.
- **Shift-Enter on a selected task** or **Command-Shift-N:** add a subtask beneath it without opening its notes.
- **Enter in the inline subtask field:** add a sibling and keep entering subtasks under the same parent.
- **Shift-Enter in that field:** save the child and start a nested subtask beneath it.
- **Escape:** finish inline entry or notes and return to task navigation. Repeated Escape moves to the sidebar and then All tasks, where it stays. Unfinished drafts and saved notes are preserved.
- Use the row's **+** button for subtasks or its **notes** button for notes; **Command-Shift-M** also opens notes.

Notes save automatically as Markdown text. Bullets, nested bullets, numbered lists, and task checkboxes continue automatically on Enter; Enter on an empty list item exits the list. Command-B and Command-I insert bold/italic Markdown. The toolbar adds bold, italic, headings, and bullet lists; Preview renders them. Existing notes remain unchanged. Properties expand separately below notes.

Completing a parent completes unfinished descendants. Resolving all children completes the parent. Reopening a child reopens resolved ancestors. Cancellation requires a reason and propagates only to unfinished descendants; canceled children count as resolved.

## Views and statuses

All tasks includes unlabeled tasks; Today shows work due today. Labels can nest to any depth and use paths such as `Work > Edge Security > Backend`. A task has one label path; subtasks inherit it. The sidebar counts only open tasks (To do and In progress), including descendants within a label branch.

**To do and Completed are the default main statuses.** Enable In progress in **Tempo → Settings** (Command-comma). Disabling it leaves saved statuses intact: existing in-progress work appears under To do until re-enabled. Canceled remains available as an explicit task action, and gets a board column when canceled work exists.

Click a status summary card to filter the current view. Click the selected card again to restore that view's default list. Counts stay scoped to the label branch, Today, or All tasks. Completed tasks remain visible by default and sort after open work.

List and Board have separate property visibility settings. Property controls are on the right of the toolbar, search is in the middle, and the view selector is on the left. Importance labels have numeric weights: None 0, Low 1, Medium 2, High 3, Urgent 4.

## Keyboard navigation and smart entry

Use Up/Down in the sidebar to choose All tasks, Today, or a label. Right always focuses new-task entry, whether or not the current view has tasks. While that field is empty, Left returns to the sidebar and Down selects the first visible task (or stays in entry if there are none). With text present, arrows retain their normal editing behavior. Up/Down navigates visible tasks and subtasks; Left returns to the sidebar. Click branch chevrons to collapse or expand them. Control-Command-S focuses the sidebar.

Command-K opens an immediate floating command/search popup. Search label paths or tasks, navigate with arrows, and press Enter. Escape, outside-click, or Command-K dismisses it. Breadcrumb parents are clickable.

Type `work`, press Tab to apply the Work label, then type the task title. Tab applies smart-entry suggestions; Shift-Tab dismisses them. Suggestions on saved tasks remain available until explicitly dismissed. Dismissals persist per task. Normal Tab navigation is preserved when no suggestion is available.

Text editing takes precedence over task shortcuts. Shift-Command-Delete deletes a selected task outside text editing; Command-Delete retains native text deletion. Command-Z uses native text undo. Option-Command-Z undoes the last workspace change outside text editing. Help → Tempo Keyboard Shortcuts lists the other shortcuts.

## Local data, appearance, and releases

Data lives in `~/Library/Application Support/Tempo/workspace.json`, independently of the repo. File → Export Backup creates a portable JSON copy. Restore confirms replacement and supports session undo. Invalid data is preserved rather than overwritten. Keep regular backups. There is no task sync, account, or analytics.

Choose System, Light, or Dark from Appearance or Settings. Your appearance and optional In progress preference are saved on this Mac. Label captions are editable in their views and are included in backups.

The app icon is in `Assets/Tempo.icns`, with PNG preview and editable SVG beside it. `./scripts/generate-icon.sh` regenerates the icon sizes. See [Releasing Tempo](docs/RELEASING.md) for GitHub draft releases, signed updates, DMG packaging, and optional Apple notarization. Build scripts do not commit or push.

## Checks

```sh
swift run TempoChecks
./scripts/check-interactions.sh
python3 Tests/release_checks.py
```

These run model and interaction checks using temporary workspaces, including nested subtasks, active counts, status filters, optional status persistence, saved notes, label safety, and shortcuts. They do not edit your real tasks. Hands-on UI review is still needed for visual layout and keyboard focus behavior.

Clickable controls have hover and pressed feedback, and task rows highlight on hover. Markdown notes have native text editing and literal punctuation: smart quotes and dash substitution are disabled so Markdown markers stay intact.
