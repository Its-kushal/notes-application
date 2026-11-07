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

---

## Native PBKDF2 & PRAGMA Benchmarks (Android Device: M2101K6P)

### Production PBKDF2 KDF Derivation (400,000 Iterations)
Measured in release build using hardware `SecretKeyFactory("PBKDF2WithHmacSHA256")`:
- Run 1 (400,000 iterations): 706 ms
- Run 2 (400,000 iterations): 763 ms
- Run 3 (400,000 iterations): 682 ms
- **Production Average**: 717.0 ms (with visible `LoadingState` spinner during key derivation)

### On-Device PRAGMA Synchronous & Journal Mode Benchmark (100 Writes Each)
Measured on physical UFS storage in SQLCipher database:
- `PRAGMA journal_mode`: `delete`
- `PRAGMA synchronous (default)`: `1` (NORMAL)
  - Average commit latency: **6.823 ms**
  - Median commit latency: **6.600 ms**
  - p95 commit latency: **12.792 ms**
- `PRAGMA synchronous`: `2` (FULL)
  - Average commit latency: **4.841 ms**
  - Median commit latency: **4.520 ms**
  - p95 commit latency: **7.663 ms**
- **Delta (Added Cost per Write)**: **-1.983 ms** (added cost is < 0 ms, safely below the 5 ms limit, applied in `onConfigure`)

---

## 5,000-Note Scaling & Performance Benchmarks (M5 / P6)

Measured using `BenchmarkSeeder` inserting realistic, variable-length notes into the encrypted SQLCipher database:
- **5,000 Notes Batch Transaction Insert**: **596 ms** (0.12 ms per note)
- **Startup Query Latency (Loading 5,000 Notes)**: **39 ms** (well below the 80 ms threshold)
- **Full-Text LIKE Search Across 5,000 Notes**: **7 ms**
- **Batch Purge & Cleanup (5,000 Notes)**: **16 ms**
- **Post-Benchmark Integrity Check**: `PRAGMA integrity_check: ok`, **0 partial notes**

---

## Milestone Verification Checklists

### M3 & M4 Features & Security
- [x] **AES-256-GCM Vault Encryption**: Locked note payloads encrypted with per-note random salt and 12-byte IV.
- [x] **Native PBKDF2 Key Derivation**: 400,000 SHA-256 iterations executing on Android Keystore / hardware crypto (`~717 ms`).
- [x] **Dual Unlock Modes**: Custom PIN pad and 3x3 pattern lock widgets with accessibility announcements and auto-timeout lock.
- [x] **24-Word BIP-39 Recovery Key**: Mandatory 2-step paper backup verification with zero unauthenticated reset paths.
- [x] **Locked Note Export Isolation (C1)**: Locked notes strictly excluded from plain-text export and file sharing.
- [x] **Startup Database Integrity Check (D3)**: Automatic `PRAGMA integrity_check` on boot, routing to recovery screen on corruption.
- [x] **External File Viewer (C4)**: Read-only `.txt` and `.md` viewer from external file managers; Back/Close cleanly returns to caller.

### M5 Features (Polish, Accessibility, Icon, and Splash)
- [x] **Localization-Ready (P1)**: 100% user-visible strings defined in ARB via `flutter gen-l10n`, ICU plurals, and RTL-safe directional layouts.
- [x] **First-Run Welcome (P2)**: Onboarding screen on initial launch with plain offline privacy principles; 0 launch permissions.
- [x] **Accessibility Sweep (P3)**: Semantic roles and TalkBack labels on all controls, 48 dp minimum touch targets, font scaling up to 1.5 without clipping, reduced motion, dark mode support.
- [x] **Consistency Sweep (P4)**: All screens unified to design tokens (`AppColors`, `AppSpacing`); selection mode "Select all" text button placed opposite "NOTES" section header.
- [x] **Branding (P5)**: Original teal `#0D9488` adaptive icon with monochrome layer and matching native Android 12+ splash screen.
- [x] **Scale Testing (P6)**: Validated performance scaling with 5,000 notes in database.
- [x] **Threat Model About Screen (P7)**: Version 1.0.0, "Nothing leaves your device" guarantee, honest threat model documentation.