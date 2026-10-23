# Privacy Notes

Privacy Notes is a secure, local-first, zero-knowledge note-taking application for Android built with Flutter, SQLCipher (AES-256-GCM hardware-backed keystore encryption), and Riverpod.

## Autosave Guarantees & Debounce Window

Privacy Notes uses a 500 ms debounce timer for autosaving note content in the editor:
- **Normal Workflow**: Edits are automatically saved to SQLite 500 ms after the user stops typing.
- **Backgrounding / Navigation**: When the app is paused, backgrounded, or when the user navigates back via button or back gesture, the pending edits are flushed immediately without waiting for the timer.
- **Abrupt Termination**: **Killing the app (e.g. `SIGKILL` or OS process termination) within the 500 ms debounce window loses only the last unsaved keystrokes** entered during that active 500 ms window. All prior revisions and previously autosaved content remain fully encrypted and persisted on disk in the SQLCipher database.
- **Partial Update Isolation**: Note autosaving executes a partial SQL `UPDATE` strictly targeting `title`, `body`, `checklist_json`, `word_count`, and `updated_at`. List-level attributes (`folder_id`, `color_label`, `is_pinned`, `is_archived`, `trashed_at`, `is_locked`) cannot be overwritten or corrupted by a delayed autosave.

---

## Design System & Tokens
- **Palette**: Centered around `AppColors.primary` (Teal 600 / 500) with accessible dark and light surfaces.
- **Spacing Scale**: Strict token system (`AppSpacing.xs` = 4, `sm` = 8, `md` = 12, `lg` = 16, `xl` = 24, `xxl` = 32) and radii (8, 12, 16).
- **Shared Widgets**: `LoadingState`, `ErrorState` (with retry), `ConfirmDialog`, `SectionHeader`.
- **Accessibility**: All 8 color labels have localized, descriptive names for TalkBack / screen readers.

---

## Manual Test Checklist

### M1 Features & Fixes
- [x] **Raw-key Database Open**: Database opens using raw 256-bit AES key via SQLCipher.
- [x] **Recovery Logic**: Graceful error handling and recovery screen if Keystore key is missing or invalid without destroying DB file.
- [x] **Search LIKE Pattern Escaping**: Searches for `%`, `_`, and `\` correctly match literal characters using `ESCAPE '\'`.
- [x] **Search Archive Exclusion**: Archived notes are excluded from search results by default unless filter includes them.
- [x] **Partial Content Updates**: Editor autosaves only content fields (`title`, `body`, `checklist_json`, `word_count`, `updated_at`), preserving list-level metadata.
- [x] **AppDatabase Single Options**: Unified `SqlCipherOpenDatabaseOptions` and transaction-based (`txn`) migrations.
- [x] **Spacing & Shared Widgets**: Replaced raw values with `AppSpacing`; replaced inline dialogs with `ConfirmDialog`, `LoadingState`, `ErrorState`, `SectionHeader`.
- [x] **Accessibility & Tooltips**: Color labels have TalkBack names; trash tooltip renamed to "Move to trash".
- [x] **Widget Test Suite**: Tests for empty, loading, error, and populated states using `FakeNotesRepository`.
- [x] **500 ms Kill Test**: Validated on-device that killing during the debounce window only loses uncommitted keystrokes within that 500 ms frame.

### M2 Features
- [x] **Folders**:
  - Create folder with name dialog.
  - Rename folder.
  - Delete folder (notes cleanly move to "No folder" via `ON DELETE SET NULL`).
  - Filter chips on home screen (All, No folder, individual folders, + New folder).
  - Move notes between folders from editor and multi-select.
- [x] **Pin & Color Labels**:
  - Toggle pinned state with pinned section at top.
  - 8 named color labels with visual indicators and TalkBack support.
- [x] **Archive Screen**:
  - Archive and unarchive notes.
  - Dedicated Archive screen accessible from navigation drawer.
  - Undo snackbar on archive and unarchive.
- [x] **Trash Screen & Retention Purge**:
  - Restore notes from trash.
  - Permanently delete notes with confirmation.
  - "Empty Trash" button with confirmation.
  - Automatic 30-day retention purge on app startup.
  - Undo snackbar on moving to trash.
- [x] **Search & Sort**:
  - Case-insensitive search across title and body.
  - Sort by Modified Date, Created Date, Title in Ascending/Descending order.
  - Pinned and Recent sections.
- [x] **List / Grid View**:
  - Smooth toggle between single-column list and 2-column grid layout.
- [x] **Multi-Select & Bulk Actions**:
  - Long-press to activate multi-select mode.
  - Bulk pin/unpin, bulk move to folder, bulk archive, bulk trash.
  - Android back button exits selection mode first before exiting screen.
- [x] **Release APK Build**: Validated on release build with full ProGuard/R8 rules.
