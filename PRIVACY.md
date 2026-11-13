# LeafLock Privacy & Security Model

LeafLock is built on a simple principle: **your notes belong strictly on your physical device.**

---

## 1. Nothing Leaves Your Device
- **Zero network communication**: LeafLock contains no analytics, telemetry, crash-reporting SDKs, advertising libraries, or cloud sync servers.
- **No external backups**: `android:allowBackup="false"` and strict data-extraction exclusions prevent Android cloud backup or device-transfer services from copying your raw database off the phone.

## 2. Zero Dangerous Permissions
- **No `INTERNET` permission**: Even if a bug existed, the Android OS prevents LeafLock from opening a network socket or sending data anywhere.
- **No broad storage permissions**: Exporting notes, saving `.llbackup` files, and picking files to restore all use Android's Storage Access Framework (SAF) system picker so LeafLock only ever accesses the exact file you select.

## 3. Database & Locked Notes Protection
- **At-rest database encryption**: Your entire local database (`leaflock.db`) is encrypted using SQLCipher AES-256 with a 256-bit key stored in the Android Hardware Keystore.
- **What Locked Notes DO protect**:
  - Locked notes add a second, independent encryption layer using **AES-256-GCM** and **PBKDF2-HMAC-SHA256 (200,000 iterations)** derived from your PIN or pattern.
  - Protects sensitive notes if someone picks up your unlocked phone or extracts raw files from app storage while the vault is locked.
  - Sensitive vault and recovery screens enable Android's `FLAG_SECURE` window protection to block screenshots, screen recording, and recent-app thumbnail previews.
- **What Locked Notes DO NOT protect**:
  - **Rooted devices / privileged malware**: If an attacker already has root access or memory-dump capabilities on a compromised phone while your vault is unlocked, keys held in active RAM can be read.
  - **Physical compromise of your paper key**: Anyone who finds both your `.llbackup` file (or phone) and your written paper recovery key can unlock your data.

## 4. Paper Recovery Key & Encrypted Backups (`.llbackup`)
- **One root recovery key**: A single 28-character Crockford Base32 key (`7 groups of 4`) secures both vault recovery and `.llbackup` backups.
- **Never stored in plaintext**: LeafLock derives separate purpose-bound subkeys via HKDF-SHA256 (`pn-vault-recovery-v1` for the vault wrap, `pn-backup-v1` for backups). The paper key itself is never stored on disk.
- **Rotating the key**: If you generate a new paper recovery key later, previously exported `.llbackup` files continue to require the **old** paper recovery key that was active when they were created.
- **Local-only restore**: Restoring a `.llbackup` merges missing notes and folders non-destructively (never overwriting existing notes or settings) only after creating a verified pre-restore safety copy of your local database.
