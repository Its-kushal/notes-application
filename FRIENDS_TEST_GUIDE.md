# LeafLock Friends Test Guide

Thank you for testing LeafLock! Because LeafLock works completely offline with zero telemetry, your feedback is the only way bugs get discovered and fixed.

> **Important reminder:** **Before updating or uninstalling, make a backup and keep your paper recovery key** (in **Settings → Backup & Restore**).
>
> **Compatibility callout:** **Android 8.0 to 11 and low-RAM phones are untested** on physical hardware right now. If you are testing on an Android 8.0, 9, 10, or 11 phone, or a low-RAM device, please pay special attention to launch speed, scrolling, keyboard responsiveness, and any crashes, and let us know what works or breaks!

---

## 1. What to Try

1. **Everyday Notes & Checklists**
   - Create plain notes, checklists (toggle checklist mode in the editor), folders, colors, and pinned notes.
   - Edit a note and immediately press Back or switch apps—confirm your edits autosave.
   - Try search, Archive, Trash, and **Select All / Deselect All** in multi-select mode.
2. **Locked Notes & Paper Recovery Key**
   - Go to **Settings → Security** or tap the lock menu to set up your vault (PIN or 3x3 pattern).
   - Write down your **28-character Crockford Base32 recovery key** (`7 groups of 4`) and complete the confirmation check.
   - Lock a note, leave the app or lock the vault, then unlock it again.
3. **Offline Encrypted Backups (`.llbackup`)**
   - Go to **Settings → Backup & Restore** and save a `.llbackup` file to your Downloads or cloud drive via **Save to device** or **Share backup file**.
   - Create one more note locally, edit an existing note, and try **Restore backup** with your 28-character paper key—confirm existing notes and edits are preserved while missing notes come back cleanly.
4. **Opening `.txt` and `.md` Files**
   - In your file manager, tap a `.txt` or `.md` file and choose **LeafLock** to inspect the read-only viewer and optional **Import as note** action.

---

## 2. Screen Protection (`FLAG_SECURE`)

Screenshots and screen recordings are **blocked on locked screens by design** (`FLAG_SECURE`) while setting up, unlocking, recovering, or viewing locked notes. This prevents Android's recent-apps switcher or third-party screen recorders from capturing secrets. Please do not look for ways to bypass this protection; describe what appeared on screen in text when reporting an issue on those screens.

---

## 3. How to Report a Bug (Without Telemetry)

LeafLock never collects crash logs, analytics, or network telemetry automatically. If something misbehaves, send a message containing:

1. **Exact LeafLock App Version**: Open **Settings → About LeafLock** and note the version shown (for example `Version 0.9.0`).
2. **Phone Model & Android Version**: e.g., `Pixel 6a, Android 14` or `Moto G, Android 9 (3 GB RAM)`.
3. **Steps to Reproduce**: Exactly what you tapped before the bug occurred.
4. **Expected vs. Actual Behavior**: What you expected to happen and what happened instead (include any on-screen message text).
5. **Screenshot (non-locked screens only)**: Helpful for layout or text-size issues on unlocked screens.
