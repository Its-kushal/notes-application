# Installing & Updating LeafLock

> **Important before you start:** **Before updating or uninstalling, make a backup and keep your paper recovery key** (in **Settings → Backup & Restore**). Android deletes an app's private encrypted database and Keystore keys permanently when an app is uninstalled.
>
> **Compatibility note:** **Android 8.0 to 11 and low-RAM phones are untested** on physical hardware right now (minimum supported version is Android 8.0 / API 26). If you run LeafLock on an Android 8.0–11 phone or a low-RAM device, please report how it behaves.

---

## 1. Verify the Download (SHA-256 Checksum)

Always check that the `.apk` file you received matches its `.sha256` checksum file before installing.

### On Windows (PowerShell)
```powershell
Get-FileHash -Algorithm SHA256 LeafLock-0.9.0-2.apk
Get-Content LeafLock-0.9.0-2.apk.sha256
```
Compare the 64-character hex string output by `Get-FileHash` (case-insensitive) against the hash inside the `.sha256` file.

### On Linux / macOS
```bash
sha256sum -c LeafLock-0.9.0-2.apk.sha256
```

### On Android
If you check on the phone directly, open your downloaded `.apk` in an open-source file manager or hash checker app that computes **SHA-256** and confirm the 64-character hash matches the contents of the `.sha256` file word-for-word. Do not install the APK if the hashes do not match.

---

## 2. Install from a File on Android

1. Copy or download `LeafLock-<version>-<code>.apk` onto your phone (for example into **Downloads**).
2. Open Android's **Files** app (or your file manager) and tap the `.apk` file.
3. **Allow "Install unknown apps"**:
   - Android blocks sideloading by default until you allow the specific app you tapped the APK from (for example **Files**).
   - Tap **Settings** on the prompt, toggle **Allow from this source** on, and press Back to continue installing.
   - After installation completes, you can safely turn **Allow from this source** back off in **Android Settings → Apps → Special app access → Install unknown apps**.

---

## 3. About the Google Play Protect Warning

When installing an APK outside the Google Play Store, Google Play Protect may display a prompt such as **"Unknown app"** or **"Play Protect doesn't recognize this app's developer"**.

- **Why this happens**: LeafLock is an offline app shared directly by an independent developer without publishing through the Google Play Store. Play Protect flags APKs signed with private developer certificates that it has not indexed via Play Store distribution.
- **How to proceed safely**: First confirm the SHA-256 checksum matches the `.sha256` file from the sender, verify in Android's install dialog that it asks for **zero permissions** (no network, no storage), and choose the standard install confirmation option presented by Android (for example **More details → Install anyway** if prompted after Play Protect's scan).
- Do not disable Google Play Protect globally or bypass Android OS security settings.

---

## 4. Updating to a Newer Version

- **Before updating or uninstalling, make a backup and keep your paper recovery key.**
- To update LeafLock, download the newer `LeafLock-<versionName>-<versionCode>.apk`, verify its SHA-256 checksum, and tap the APK file to install it directly **over** your existing LeafLock app.
- Because all official builds are signed with the same permanent LeafLock release certificate, Android keeps all your notes, locked vault, and settings in place during an update.
- **Do not uninstall the old version first** unless you intend to wipe all local data. Note also that Android will reject installing an older `versionCode` over a newer `versionCode`.

---

## 5. What Happens on Uninstall

Uninstalling LeafLock instructs Android to **permanently erase** the app's private data directory (`leaflock.db`) and its Android Hardware Keystore encryption key. Once uninstalled without a `.llbackup` file and your written 28-character paper recovery key, your notes cannot be recovered.
