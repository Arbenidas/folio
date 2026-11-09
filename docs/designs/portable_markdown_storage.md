# Portable Markdown Storage and First-Run Setup

* **Author:** Arbenidas
* **Status:** Approved
* **Date:** 2026-11-07

## Overview

Folio should give new users a clear first-run path to choose where their notebook lives, pick a theme, and learn the basic writing workflow. Notes should be ordinary Markdown files in real folders under a `Folio/` directory inside the chosen location. The app should reflect edits made in Finder or another editor while protecting any unsaved writing in Folio.

## The Problem

Folio currently stores notes as flat Markdown files with app-specific JSON front matter. Folder names are virtual and live in that metadata, so the files do not appear in Finder as the folder tree shown in Folio, and the metadata makes the notes harder to use in other Markdown editors. The current first-run screen combines folder and theme settings, and it does not guide a new user through creating folders or writing a note.

The new storage model removes metadata from note files and makes the file system the visible notebook. This also means Folio must handle external edits, file creation, moves, and deletion without losing its own unsaved changes. The project has no end users, so this version can start with a new notebook and leave the previous storage location untouched rather than migrate it.

## Goals

* On a new installation, guide the user through a welcome, destination selection, and theme selection before opening the editor. Explain that the selected directory is a parent and preview the resulting `<selected directory>/Folio/` path.
* Provide a brief, skippable, replayable tour of folder creation and writing in the editor. Keep Vim help optional and describe only commands supported by Folio.
* Store each note as a readable `.md` file under a real folder tree in `Folio/`, without app-specific JSON or front matter. Use the file basename as the title and its relative parent path as its folder and identity.
* Allow equal filenames in different folders. Resolve same-folder collisions with the next available numeric suffix, and show the resulting filename as the note title.
* While the app is open, reflect Markdown files created, edited, moved, or deleted inside the notebook. Changes moved outside the notebook disappear from Folio.
* Never silently overwrite or discard a dirty editor draft after an external edit or deletion. Preserve it as a separate recovered Markdown note and make it easy to open.
* Reconcile external events by batching notifications and checking the file tree, rather than relying on event order. Provisional performance targets are to show one stable external change within one second and settle a burst within two seconds on a typical notebook; verify these targets on supported macOS versions.
* Reuse the current macOS folder picker, security-scoped bookmark, theme persistence, and editor help where they fit. If the selected location becomes unavailable, show an actionable recovery path instead of silently opening an empty default notebook.

## Non-Goals

* Add a folder-selection wizard to the DMG installer. Setup happens in Folio on first launch after the user copies the app.
* Migrate or delete the current `Notas Folio` data or legacy JSON notebooks. Keep the old location untouched.
* Add cloud synchronization, collaboration, remote telemetry, or support for non-Markdown files as notes. The app does not guarantee operation on network-mounted or cloud-provider-managed notebook locations.
* Implement full Vim behavior, follow symbolic links outside the notebook root, or observe files moved outside `Folio/`.
* Add recursive polling, a custom native FSEvents bridge, or an indexing database before a measured need justifies the extra maintenance.

## Open Questions

* **Performance target validation**: The one-second single-change and two-second event-burst targets are provisional. Measure them on supported macOS local volumes with the stated 1,000-note, 100-folder test notebook and adjust them if the result does not support those targets.
* **Cloud-provider behavior**: Cloud-provider-managed folders are outside the support guarantee. A provider may still expose a path on a volume macOS identifies as local; communicate the support limit without claiming Folio can reliably detect every provider-managed folder.

## Critical User Journeys (CUJs)

### CUJ 1: Set up a new notebook

* **Given**: A new installation of Folio with no completed setup and a writable local folder available.
* **When**: The user opens Folio, completes the welcome, chooses a parent folder and a theme, then continues.
* **Then**: Folio prepares `<parent>/Folio/`, shows the resolved path before completion, stores bookmark access to the parent, and opens the editor. If the notebook root already exists, Folio lists its Markdown files without replacing them.

### CUJ 2: Create folders and notes

* **Given**: Folio is open to a notebook root.
* **When**: The user creates a folder, a note, or a nested folder and writes Markdown.
* **Then**: Finder shows the matching directories and `.md` files under `Folio/`; the app shows the same hierarchy, including empty folders. Same-directory filename collisions receive a unique numeric suffix.

### CUJ 3: Reflect an external edit safely

* **Given**: Folio has a notebook open and a note is selected.
* **When**: Another editor changes the file, creates another `.md` file, moves a note, or deletes it.
* **Then**: Folio reconciles the disk tree and updates the sidebar and editor. If the affected note has unsaved Folio text, Folio preserves that draft in its private Recovery view before applying the external state.

### CUJ 4: Change the notebook location

* **Given**: Folio has a readable notebook and a new writable local parent folder is selected in Settings.
* **When**: The user previews and confirms the new location.
* **Then**: Folio copies the notebook tree to `<new parent>/Folio/`, resolves collisions without overwriting files, persists the new bookmark only after the copy succeeds, and retains the previous notebook as a backup.

## Technical Plan (Architecture)

## Technical Plan (Architecture)

### First-run setup and notebook access

Keep `StartupGate` as the entry point. Replace the current combined setup screen with short steps for welcome, location, and theme, then show the editor and offer a small anchored tour. The tour should point to the actual folder and editor controls, allow skipping, and be replayable from Help. Keep the Vim explanation optional and reuse the current command help.

The folder picker continues to select a parent directory and persist access through the existing macOS security-scoped bookmark. Folio derives `<parent>/Folio/` as its notebook root. The setup view previews that full path, opens the picker at the current user's home directory, and explains when an existing `Folio/` will be reused. Validate access and prepare the root before marking setup complete. Persist tour completion separately from folder setup and theme preferences, so a skipped tour does not reopen setup.

### Markdown repository and real folder tree

Make the notebook root the single boundary used by storage, the watcher, and the editor. Adapt `FileRepository` and `DocumentRepository` so the data layer can load a notebook snapshot containing both note files and folder paths, including empty directories. Represent a note's identity as its normalized path relative to `Folio/`; use the basename as its title and the parent path as its folder. Store only the note body in `.md` files, without JSON metadata or front matter.

Replace whole-notebook write-and-delete behavior with explicit note and folder operations. Creating or moving a note writes to the matching path. Renaming a title renames its file. Creating, renaming, moving, or deleting a folder changes the real directory tree. Deleting a note removes only that note. Use a unique numbered basename when a destination already contains a file with the same name. Write changed files through a temporary file and rename so other editors are less likely to observe partial content. Ignore Folio's temporary files during scans.

The sidebar should render the repository's folder paths, not infer folders only from notes. That keeps empty folders visible and makes the displayed hierarchy match Finder. The editor controller continues to own selection and unsaved text, but delegates all filesystem operations to the repository rather than saving a full stale list that could delete files it has not seen.

### External change reconciliation

After the initial notebook scan, start `Directory.watch(recursive: true)` on `<parent>/Folio/` while the security-scoped parent remains open. Treat each event as a reason to reconcile, not as a complete change record: batch bursts briefly, scan the tree, and compare the resulting snapshot with the last known disk state. Run a scan at startup, after app resume, and after watcher restart. Do not follow symbolic links. If access or the watcher fails, keep the current editor state, show an actionable status, and offer retry or folder reselection.

For a clean note, apply the disk version and update the selected editor if needed. For a dirty note whose file changed externally, first save a Markdown copy of the local draft into an app-private recovered-drafts area under Application Support, then load the disk version at its notebook path. For a dirty note deleted externally, save the draft to the same recovery area and remove the deleted path from the notebook. Show a non-blocking notice with an action to open recovered drafts; keep a persistent Recovery view available until the user resolves them. This recovery area is managed by Folio and is not part of the shareable notebook tree.

The repository and editor controller must serialize local saves and external reconciliations. Compare the last known file contents or fingerprint with the editor revision before applying a disk update; never blindly overwrite a file on an event. A move within the notebook is observed as a path removal plus path creation and results in the corresponding folder/title change. A move outside the root removes it from Folio. A new `.md` file becomes a note after a scan; unreadable or malformed files should be reported without blocking access to other notes.

### Storage-location changes in Settings

Keep the existing Settings ability to change the location. Treat the selected path as a new parent and resolve its `Folio/` child. Copy the current notebook's files and directories to the new root using the same collision rules, retain the old notebook as a backup, and persist the new bookmark only after the copy and target validation succeed. If the target root already has files, do not overwrite them; merge by choosing unique names and show the resolved destination to the user before switching.

### Data flow

```text
First-run UI ──select parent──> macOS folder picker + security-scoped bookmark
      │                                  │
      └──theme / tour state              └──parent/Folio notebook root
                                                  │
                                      Markdown repository
                                       ├── scan notes + folders
                                       ├── explicit file operations
                                       └── recursive watcher
                                                  │
                                      reconciliation snapshot
                                                  │
                               Editor controller + conflict recovery
                                     ├── current Markdown editor
                                     ├── sidebar folder tree
                                     └── recovered-drafts view
```

### Assumptions to validate

* The first release guarantees writable notebook locations on local macOS volumes. Reject a volume macOS identifies as remote; files inside folders managed by iCloud or another sync provider are outside the support guarantee even if the provider exposes a local path.
* Validate the provisional one-second single-change and two-second burst-refresh targets against a representative notebook size on supported macOS versions.

## Alternatives Considered

### Keep flat Markdown files with JSON front matter

* **Pros**: Preserves stable IDs, ordering, and folder metadata in the existing repository. It keeps the current whole-notebook model and minimizes changes to the sidebar.
* **Cons**: Finder shows a flat list, folder structure is app-specific, and other Markdown editors encounter Folio's JSON metadata in each note.
* **Reason for Rejection**: Rejected by author for this feature because the notebook must use real folders and readable Markdown files without app-specific metadata.

### Use the selected directory itself as the notebook root

* **Pros**: Avoids one directory level and makes the selected location exactly match the stored root.
* **Cons**: Notes and folders are placed directly beside other user files in the chosen location, making it easier to mix unrelated content with Folio's notebook.
* **Reason for Rejection**: Rejected by author in favor of creating a recognizable `Folio/` folder inside the selected parent.

### Keep a separate database as the source of truth and export Markdown copies

* **Pros**: The database can retain stable IDs, order, and app state without putting metadata in note bodies.
* **Cons**: The Markdown files become copies rather than the live notebook. External edits need import rules, and database state can disagree with files.
* **Reason for Rejection**: Rejected by author because notes should be directly usable and editable in Finder and other Markdown editors without an app-only data store deciding their contents.

### Poll the whole tree or add a native FSEvents bridge

* **Pros**: Polling can recover from missed events by repeated scans. A native bridge can expose more platform-specific event details.
* **Cons**: Repeated scans add work even when nothing changes. A native bridge adds Swift/Dart channel code and another platform-specific component to maintain.
* **Reason for Rejection**: Rejected for the first version in favor of Dart's recursive `Directory.watch` plus batched snapshot reconciliation. Revisit only if measured reliability or latency misses the stated targets.

### Store conflict copies beside the original or in `Folio/Recuperadas/`

* **Pros**: A sibling copy remains close to its original folder. A `Recuperadas/` folder is visible in Finder and keeps recovery files grouped.
* **Cons**: A sibling copy can clutter user folders and collide with intentional filenames. A notebook recovery folder mixes conflict artifacts into the shareable note tree.
* **Reason for Rejection**: Rejected by author in favor of an app-private recovery area under Application Support, surfaced through a persistent Recovery view. This keeps the shared notebook clean while making recovery discoverable in Folio.

### Migrate the existing `Notas Folio` store

* **Pros**: Retains notes created in older builds and avoids an apparently empty notebook for an upgrading user.
* **Cons**: Migration must translate JSON front matter, virtual folders, and stable IDs into path-based titles and directories. It also needs collision handling and rollback rules.
* **Reason for Rejection**: Rejected by author for this release because the project has no end users and the new version can start with a fresh notebook. Leave old data untouched; revisit migration if real users depend on it.

## Non-Functional Requirements

* **Security & Privacy**: Use the macOS security-scoped bookmark for the selected parent and limit all notebook scans and writes to its `Folio/` child. Do not follow symbolic links. Keep recovered drafts in Application Support. Do not log Markdown contents or full note paths by default.
* **Performance & Reliability**: Use event notifications as hints, batch bursts, and reconcile from disk. Rescan at startup and after app resume or watcher restart. Validate the provisional latency targets against 1,000 notes and 100 nested folders on supported local macOS volumes.
* **Storage Safety**: Write one note at a time through a temporary file and atomic rename. A stale whole-notebook snapshot must never delete or overwrite an unseen file. Dirty drafts that conflict with external changes remain recoverable until the user deletes or restores them; no automatic expiration.
* **Rollout & Rollback**: Do not migrate or delete `Notas Folio` or old JSON notebooks. The new version writes to a separate `<parent>/Folio/` tree. Older builds will not read this new tree; the old data remains untouched, but notes created in the new format are not available in older builds.
* **Platform Scope**: Guarantee support for writable local macOS volumes. Reject volumes macOS identifies as remote. Cloud-provider-managed folders may be exposed as local paths but remain outside the support guarantee.

## Additional Resources

* Project storage and setup documentation: [README](../../README.md).
* Dart filesystem watching behavior: [FileSystemEntity.watch](https://api.dart.dev/dart-io/FileSystemEntity/watch.html).
* Apple filesystem event recovery guidance: [MustScanSubDirs](https://developer.apple.com/documentation/coreservices/1455361-fseventstreameventflags/kfseventstreameventflagmustscansubdirs).
* Source components reviewed: `lib/features/editor/data/file_repository.dart`, `lib/features/editor/presentation/controllers/editor_notifier.dart`, `lib/core/first_run_config.dart`, and `macos/Runner/MainFlutterWindow.swift`.

## Future Improvements

* **The idea**: Revisit migration support, cloud-provider behavior, and recovery export if the project gains users who need those workflows or if local-volume watcher measurements miss the acceptance targets.

## Detailed Implementation Plan

All paths below are relative to the app repository root.

### Target Files to Create/Modify

#### 1. `lib/main.dart` (Modify)

* **Type / Scope**: Flutter startup and application routing.
* **Proposed Changes**: Keep `StartupGate`, but pass the selected parent directory to the updated setup flow. After setup completes, resolve and validate the `Folio/` root before creating the editor provider. Distinguish unavailable storage from an empty notebook so startup never silently opens a different default store.

#### 2. `lib/core/first_run_config.dart` (Modify)

* **Type / Scope**: First-run configuration and selected parent path.
* **Proposed Changes**: Model the selected parent separately from the derived notebook root. Use the dynamic macOS home directory returned by the native runner as the first-run default, with a runtime home-directory fallback when the method channel is unavailable. Keep the selected parent and bookmark in sync; complete setup only after the `Folio/` root is accessible and prepared. Keep tour-completion state out of the storage setup-complete flag.

#### 3. `macos/Runner/MainFlutterWindow.swift` (Modify)

* **Type / Scope**: Native macOS folder picker and bookmark bridge.
* **Proposed Changes**: Include `NSHomeDirectory()` in `loadInitialSetup` as the dynamic default location. Continue bookmarking and holding access to the user-selected parent; Flutter derives and watches the `Folio/` child under that scope. Check `URLResourceValues.volumeIsLocal` after folder selection and reject remote-mounted volumes with an actionable message. Preserve the existing `chooseNotesDirectory` and `completeInitialSetup` behavior and surface bookmark failures to Flutter.

#### 4. `lib/core/onboarding_preferences.dart` (Create)

* **Type / Scope**: Private onboarding preference persistence.
* **Proposed Changes**: Store whether the interactive tour has been completed or skipped in a small app-support preference file, separately from the selected folder and theme. Expose load and save methods. Never store note contents or note paths here.

#### 5. `lib/features/onboarding/presentation/views/initial_setup_screen.dart` (Modify)

* **Type / Scope**: First-run UI.
* **Proposed Changes**: Convert the current combined form into a three-step welcome, location, and theme flow with a visible progress cue, back/continue controls, and keyboard-accessible actions. Default the parent to the current user's home directory. Show the resulting `<parent>/Folio/` path and explain that an existing root will be reused without replacing files. State that network volumes and third-party folder synchronization are outside the supported setup. Preview themes. Keep cancellation and permission errors recoverable in the current step; do not mark setup complete until local location access and root creation succeed.

#### 6. `lib/features/onboarding/presentation/widgets/first_run_tour.dart` (Create)

* **Type / Scope**: Interactive editor tour.
* **Proposed Changes**: Add a short anchored tour for creating a folder, creating a note, and writing in the editor. Include skip and back/next controls, keyboard access, and a replay entry from Help. Provide an optional Vim segment that reuses the documented supported command list. Do not block editor use if the tour is skipped.

#### 7. `lib/features/editor/domain/markdown_document.dart` (Modify)

* **Type / Scope**: Note domain model.
* **Proposed Changes**: Define `id` as the normalized path relative to the notebook root, `title` as the filename without `.md`, and `folder` as the relative parent directory. Update copy/rename/move operations so changing a title or folder updates the derived path identity. Keep note content as the raw Markdown body.

#### 8. `lib/features/editor/domain/notebook_snapshot.dart` (Create)

* **Type / Scope**: Storage snapshot model.
* **Proposed Changes**: Add an immutable snapshot containing the notes and the complete set of relative folder paths, including empty directories. This gives the sidebar a filesystem-backed tree without inventing folders from note metadata.

#### 9. `lib/features/editor/domain/document_repository.dart` (Modify)

* **Type / Scope**: Storage abstraction.
* **Proposed Changes**: Replace whole-list save semantics with explicit operations for scanning a `NotebookSnapshot`, saving or renaming a note, creating/moving/deleting notes, creating/moving/deleting folders, and reconciling the notebook after external changes. Define errors for inaccessible roots, name collisions, malformed UTF-8, and per-file read/write failures.

#### 10. `lib/features/editor/data/file_repository.dart` (Modify)

* **Type / Scope**: Markdown file storage.
* **Proposed Changes**: Resolve the repository root as the selected parent plus `Folio/`. Read only non-hidden `.md` files and real directories below that root; do not follow symbolic links. Decode note bodies as UTF-8 and do not parse or write app metadata. Sort paths deterministically by case-insensitive folder and basename. Sanitize app-entered path components by replacing control and cross-platform reserved filename characters with `-`, trim surrounding whitespace and trailing periods, fall back to `Nueva nota` for an empty title, and add numeric suffixes beginning at `2` for collisions. Preserve Unicode letters. Implement explicit filesystem operations and atomic per-file writes using an ignored temporary extension; a general editor save must never delete files absent from its previous in-memory snapshot. When deleting an app folder, keep the existing user-facing behavior: move its notes and subfolders into the parent, then remove the empty directory. During Settings copy, merge directories and resolve file conflicts with the same unique-name rule.

#### 11. `lib/features/editor/data/notebook_sync_service.dart` (Create)

* **Type / Scope**: Filesystem watcher and reconciliation scheduling.
* **Proposed Changes**: Subscribe to `Directory.watch(recursive: true)` for the notebook root. Coalesce event bursts with a short trailing debounce, ignore Folio's temporary write files, and trigger one repository scan per batch. Expose snapshots and watcher errors to the editor controller. Rescan after app resume and restart the subscription after transient errors. Keep this service independent of Flutter widgets and avoid polling.

#### 12. `lib/features/editor/data/recovered_drafts_repository.dart` (Create)

* **Type / Scope**: Private conflict-draft storage.
* **Proposed Changes**: Save unsaved Markdown to `getApplicationSupportDirectory()/Folio/Recovered drafts/` using timestamped, unique `.md` filenames. Store no app metadata in the Markdown body. List, open, and delete recovered drafts; do not expire them automatically. Keep these drafts outside the user-selected notebook root.

#### 13. `lib/features/editor/presentation/controllers/editor_notifier.dart` (Modify)

* **Type / Scope**: Editor state, save queue, and synchronization.
* **Proposed Changes**: Load a `NotebookSnapshot`, maintain explicit dirty revisions, and call repository operations rather than save the entire note list. Serialize local writes with external reconciliation. If a clean note changes on disk, update the buffer and preview. If a dirty note changes or disappears on disk, save its editor contents through the recovery repository before applying disk state. Handle path-based renames and moves without stale writes. Expose external-change and recovery status to the view.

#### 14. `lib/features/editor/presentation/widgets/notes_sidebar.dart` (Modify)

* **Type / Scope**: Notes and folder navigation.
* **Proposed Changes**: Render folders from `NotebookSnapshot.folderPaths`, including empty folders. Keep drag-and-drop, selection, collapse state, and keyboard navigation aligned with actual filesystem paths. Show a Recovery entry and count only while recovered drafts exist.

#### 15. `lib/features/editor/presentation/views/editor_screen.dart` (Modify)

* **Type / Scope**: Editor integration and high-level UX.
* **Proposed Changes**: Start and dispose `NotebookSyncService` with the editor lifecycle; trigger reconciliation when the app resumes. Connect sidebar operations to real repository actions. Show non-blocking status for external changes and errors. Add a clear action to open recovered drafts and launch or replay the first-run tour. Keep error and conflict states actionable without modal interruption during typing.

#### 16. `lib/features/editor/presentation/views/recovered_drafts_view.dart` (Create)

* **Type / Scope**: Recovered draft experience.
* **Proposed Changes**: Add a persistent view listing private recovered Markdown drafts with title and recovery time. Let users open a draft read-only, restore it as a new notebook note with a unique filename, or delete it after confirmation. Explain that restoring copies it into the selected `Folio/` notebook.

#### 17. `lib/features/editor/presentation/widgets/markdown_help.dart` (Modify)

* **Type / Scope**: Help and tour re-entry.
* **Proposed Changes**: Add an entry to replay the folder/editor tour and retain the existing Markdown and Vim reference sections. Label Vim support as optional and partial.

#### 18. `lib/features/settings/presentation/views/settings_screen.dart` (Modify)

* **Type / Scope**: Storage and appearance settings.
* **Proposed Changes**: Display the resolved `<parent>/Folio/` root while passing the parent to the native folder picker. Preview the destination before switching. Show copy progress, name-collision outcomes, permission failures, and confirmation that the prior notebook remains as a backup. Keep theme changes independent of onboarding completion.

#### 19. `pubspec.yaml` (Modify)

* **Type / Scope**: Dart dependencies.
* **Proposed Changes**: Promote the already locked `path` package (currently 1.9.1) to a direct dependency for safe path joining, normalization, and root-containment checks. Do not add a watcher package; use `dart:io`.

#### 20. `pubspec.lock` (Modify)

* **Type / Scope**: Locked Dart dependencies.
* **Proposed Changes**: Update the lockfile when `path` becomes a direct dependency; keep the resolved version at the compatible locked version unless Flutter's dependency resolution requires an update.

#### 21. `README.md` (Modify)

* **Type / Scope**: User-facing storage and onboarding documentation.
* **Proposed Changes**: Explain the first-run steps, the selected parent and resulting `Folio/` path, real nested folders, filename/title convention, supported external Markdown changes, private recovered drafts, local-volume support limits, and that the old storage format is not migrated.

#### 22. `test/widget_test.dart` (Modify)

* **Type / Scope**: Existing editor widget and controller test infrastructure.
* **Proposed Changes**: Update `MemoryRepository` to implement the revised repository contract. Retain existing editor, Vim, motion, and save-error coverage while adding assertions for real folder snapshots and external-change status.

#### 23. `test/file_repository_test.dart` (Create)

* **Type / Scope**: Markdown repository unit tests.
* **Proposed Changes**: Cover plain Markdown round-trip without front matter, nested and empty folders, deterministic ordering, path sanitization, duplicate filenames, rename/move/delete operations, existing-root adoption without overwrite, UTF-8 failures, hidden files, and symlink exclusion.

#### 24. `test/notebook_sync_service_test.dart` (Create)

* **Type / Scope**: Watcher and reconciliation tests.
* **Proposed Changes**: Cover external create/edit/rename/move/delete, atomic replacement, temporary-file suppression, burst coalescing, app-resume rescans, watcher restart, and inaccessible roots. Assert that the final snapshot matches disk state and repeated events do not duplicate notes.

#### 25. `test/recovered_drafts_repository_test.dart` (Create)

* **Type / Scope**: Private recovery store tests.
* **Proposed Changes**: Cover save/list/open/restore/delete, unique names for repeated conflicts, Markdown body preservation, and persistence without automatic expiration.

#### 26. `test/onboarding_test.dart` (Create)

* **Type / Scope**: First-run and tour widget tests.
* **Proposed Changes**: Cover dynamic home default, step order and back navigation, resolved-path preview, theme choice persistence, validation errors, setup retry, tour skip/replay, optional Vim content, and keyboard-accessible progression.

### Verification Plan

* **Compilation/Build**: `flutter analyze`; `flutter build macos --debug`.
* **Unit and Widget Tests**: `flutter test`, including the repository, watcher, recovery, onboarding, and existing editor suites.
* **Storage checks**: Verify that note bodies contain only user Markdown, folder and filename changes are reflected in Finder, and no normal save deletes an unseen file.
* **Conflict checks**: With unsaved text open, externally edit or delete the file; verify the external state remains at the original path and the local text appears in the private Recovery view.
* **Performance check**: Measure one edit and a burst against 1,000 notes in 100 nested folders on supported macOS versions. Validate the provisional one-second single-change and two-second burst targets; revise them if the baseline does not support them.
* **Packaged-app checks**: Install from a clean DMG on a fresh macOS account. Verify dynamic home-folder default, local-volume validation, security-scoped access after restart, existing `Folio/` reuse, settings location change and backup, external edits from Finder and another editor, app sleep/resume, recovery access, keyboard navigation, and VoiceOver labels for onboarding and recovery actions.
