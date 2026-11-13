# Agent & Contributor Guardrails for LeafLock

Follow these standing project rules in every session:

1. **Connected Physical Device Only (No Emulators)**:
   - A physical Android test device is used for device verification.
   - **Never install, create, configure, or start an Android emulator** (`emulator`, `avdmanager`, `sdkmanager --install "system-images..."`).
   - Do not modify AVDs or emulator binaries.

2. **Protect Existing Device App & User Data**:
   - Never uninstall or clear data on an existing `com.privacynotes.app` or `com.leaflock.app` install unless explicitly instructed.
   - Install updates only with `adb install -r` targeting the matching `applicationId`. Never restore or overwrite the user's personal backups during automated testing.

3. **Keystore & Signing Privacy**:
   - **Never ask for, read, inspect, log, or print** `android/key.properties`, `.jks` / `.keystore` files, or any keystore/key passwords.
   - Keep `android/key.properties`, `*.jks`, and `*.keystore` git-ignored at all times.

4. **Repository & Git Hygiene**:
   - Never run `git add` or `git commit`; append sequential, ready-to-run staging and commit commands to `to_commits.txt`.
   - Never touch anything under `legacy/` and never rewrite git history.
   - Never add new third-party dependencies in `pubspec.yaml` without explicit user approval.

5. **Verification Honesty**:
   - `UNVERIFIED` is not `PASS`. Never claim the user confirmed, tapped, or tested something; report only directly observed tool output.
