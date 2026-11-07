// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Privacy Notes';

  @override
  String get cancel => 'Cancel';

  @override
  String get save => 'Save';

  @override
  String get delete => 'Delete';

  @override
  String get moveToTrash => 'Move to trash';

  @override
  String get create => 'Create';

  @override
  String get done => 'Done';

  @override
  String get close => 'Close';

  @override
  String get retry => 'Retry';

  @override
  String get getStarted => 'Get Started';

  @override
  String get skip => 'Skip';

  @override
  String get sortBy => 'Sort by';

  @override
  String get order => 'Order';

  @override
  String get ascending => 'Ascending';

  @override
  String get descending => 'Descending';

  @override
  String get sortFieldUpdated => 'Date modified';

  @override
  String get sortFieldCreated => 'Date created';

  @override
  String get sortFieldTitle => 'Title';

  @override
  String get newNote => 'New note';

  @override
  String get searchNotes => 'Search notes';

  @override
  String get clearSearch => 'Clear search';

  @override
  String get allNotes => 'All';

  @override
  String get newFolder => 'New Folder';

  @override
  String get folderName => 'Folder name';

  @override
  String get renameFolder => 'Rename Folder';

  @override
  String get deleteFolder => 'Delete folder';

  @override
  String get deleteFolderConfirmTitle => 'Delete folder?';

  @override
  String deleteFolderConfirmMessage(String folderName) {
    return 'Notes inside \"$folderName\" will not be deleted; they will stay in All notes.';
  }

  @override
  String get noFoldersYet => 'No folders created yet';

  @override
  String get moveToFolder => 'Move to folder';

  @override
  String moveNotesToFolderTitle(num count) {
    final intl.NumberFormat countNumberFormat = intl.NumberFormat.compact(
      locale: localeName,
    );
    final String countString = countNumberFormat.format(count);

    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$countString notes',
      one: '1 note',
    );
    return 'Move $_temp0 to...';
  }

  @override
  String notesCount(num count) {
    final intl.NumberFormat countNumberFormat = intl.NumberFormat.compact(
      locale: localeName,
    );
    final String countString = countNumberFormat.format(count);

    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$countString notes',
      one: '1 note',
      zero: '0 notes',
    );
    return '$_temp0';
  }

  @override
  String get pinnedSectionHeader => 'PINNED';

  @override
  String get otherNotesSectionHeader => 'NOTES';

  @override
  String get pin => 'Pin';

  @override
  String get unpin => 'Unpin';

  @override
  String get archive => 'Archive';

  @override
  String get unarchive => 'Unarchive';

  @override
  String get trash => 'Trash';

  @override
  String get restore => 'Restore';

  @override
  String get deletePermanently => 'Delete permanently';

  @override
  String get deletePermanentlyConfirmTitle => 'Delete note permanently?';

  @override
  String get deletePermanentlyConfirmMessage =>
      'This action cannot be undone. The note will be permanently erased.';

  @override
  String get emptyTrash => 'Empty Trash';

  @override
  String get emptyTrashConfirmTitle => 'Empty trash?';

  @override
  String get emptyTrashConfirmMessage =>
      'All items in the trash will be permanently deleted.';

  @override
  String trashRetentionNotice(num days) {
    final intl.NumberFormat daysNumberFormat = intl.NumberFormat.compact(
      locale: localeName,
    );
    final String daysString = daysNumberFormat.format(days);

    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: '$daysString days',
      one: '1 day',
    );
    return 'Items in trash are automatically purged after $_temp0.';
  }

  @override
  String get noNotesTitle => 'No notes yet';

  @override
  String get noNotesMessage => 'Tap + to create your first note.';

  @override
  String get noSearchResultsTitle => 'No notes found';

  @override
  String get noSearchResultsMessage => 'Try searching for different keywords.';

  @override
  String get trashEmptyTitle => 'Trash is empty';

  @override
  String get trashEmptyMessage => 'Deleted notes will appear here.';

  @override
  String get archiveEmptyTitle => 'Archive is empty';

  @override
  String get archiveEmptyMessage => 'Archived notes will appear here.';

  @override
  String selectedNotesCount(num count) {
    final intl.NumberFormat countNumberFormat = intl.NumberFormat.compact(
      locale: localeName,
    );
    final String countString = countNumberFormat.format(count);

    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$countString selected',
      one: '1 selected',
    );
    return '$_temp0';
  }

  @override
  String get selectAll => 'Select all';

  @override
  String get deselectAll => 'Deselect all';

  @override
  String get clearSelection => 'Clear selection';

  @override
  String get noteTitleHint => 'Title';

  @override
  String get noteBodyHint => 'Note';

  @override
  String get addChecklistItem => 'List item';

  @override
  String get switchToChecklist => 'Switch to checklist mode';

  @override
  String get switchToText => 'Switch to text mode';

  @override
  String wordsCount(num count) {
    final intl.NumberFormat countNumberFormat = intl.NumberFormat.compact(
      locale: localeName,
    );
    final String countString = countNumberFormat.format(count);

    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$countString words',
      one: '1 word',
      zero: '0 words',
    );
    return '$_temp0';
  }

  @override
  String charactersCount(num count) {
    final intl.NumberFormat countNumberFormat = intl.NumberFormat.compact(
      locale: localeName,
    );
    final String countString = countNumberFormat.format(count);

    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$countString characters',
      one: '1 character',
      zero: '0 characters',
    );
    return '$_temp0';
  }

  @override
  String get savedStatus => 'Saved';

  @override
  String get savingStatus => 'Saving...';

  @override
  String get colorLabel => 'Color label';

  @override
  String get colorLabelNone => 'None';

  @override
  String get colorLabelRed => 'Red';

  @override
  String get colorLabelOrange => 'Orange';

  @override
  String get colorLabelYellow => 'Yellow';

  @override
  String get colorLabelGreen => 'Green';

  @override
  String get colorLabelBlue => 'Blue';

  @override
  String get colorLabelPurple => 'Purple';

  @override
  String get lockNote => 'Lock note';

  @override
  String get lockNoteConfirmTitle => 'Lock note?';

  @override
  String get lockNoteConfirmMessage =>
      'Locking will encrypt this note with your vault key. Its folder, pin, archive status, and color label will be cleared.';

  @override
  String get unlockNote => 'Unlock note';

  @override
  String get exportNote => 'Export note';

  @override
  String get exportNoteTitle => 'Export Note';

  @override
  String get exportAsMarkdown => 'Export as Markdown (.md)';

  @override
  String get exportAsText => 'Export as Plain Text (.txt)';

  @override
  String get exportSuccess => 'Note exported successfully';

  @override
  String get exportFailed => 'Failed to export note';

  @override
  String get noteMovedToTrash => 'Note moved to trash';

  @override
  String get noteRestored => 'Note restored';

  @override
  String get undo => 'Undo';

  @override
  String get lockedNotes => 'Locked Notes';

  @override
  String get lockedNotesEmptyTitle => 'No locked notes';

  @override
  String get lockedNotesEmptyMessage =>
      'Notes you lock will be encrypted and shown here.';

  @override
  String get vaultSetupTitle => 'Set Up Vault';

  @override
  String get vaultSetupStepSecret => 'Choose Credential';

  @override
  String get vaultSetupStepRecovery => 'Paper Recovery Key';

  @override
  String get vaultSetupStepConfirm => 'Confirm Recovery Key';

  @override
  String get pinCredential => 'PIN';

  @override
  String get patternCredential => 'Pattern';

  @override
  String get enterPin => 'Enter PIN';

  @override
  String get confirmPin => 'Confirm PIN';

  @override
  String get enterPattern => 'Draw Pattern';

  @override
  String get confirmPattern => 'Confirm Pattern';

  @override
  String get pinMismatch => 'PINs do not match. Please try again.';

  @override
  String get patternMismatch => 'Patterns do not match. Please try again.';

  @override
  String get patternTooShort => 'Connect at least 4 dots.';

  @override
  String get patternAccessibilityNotice =>
      'Pattern lock is not screen-reader friendly. Use a numeric PIN for full TalkBack support.';

  @override
  String get usePinInstead => 'Use PIN instead';

  @override
  String get paperRecoveryKeyTitle => 'Write down your Paper Recovery Key';

  @override
  String get paperRecoveryKeyNotice =>
      'This 24-word key is the ONLY way to recover locked notes if you forget your secret. Write it on paper and keep it secure. Never store it digitally.';

  @override
  String get iHaveWrittenItDown => 'I have written it down';

  @override
  String get verifyRecoveryKeyPrompt =>
      'Enter the following words from your recovery key to confirm:';

  @override
  String wordNumber(int number) {
    return 'Word #$number';
  }

  @override
  String get vaultUnlockTitle => 'Unlock Vault';

  @override
  String get incorrectSecret => 'Incorrect secret. Please try again.';

  @override
  String lockoutMessage(int seconds) {
    String _temp0 = intl.Intl.pluralLogic(
      seconds,
      locale: localeName,
      other: '$seconds seconds',
      one: '1 second',
    );
    return 'Too many failed attempts. Try again in $_temp0.';
  }

  @override
  String get forgotSecret => 'Forgot Secret?';

  @override
  String get recoverVaultTitle => 'Recover vault';

  @override
  String get enterRecoveryKeyPrompt =>
      'Enter your 24-word paper recovery key separated by spaces:';

  @override
  String get invalidRecoveryKey =>
      'Invalid recovery key. Check spelling and word order.';

  @override
  String get recoverySuccess =>
      'Vault successfully recovered. Set a new credential.';

  @override
  String get welcomeTitle => 'Privacy Notes';

  @override
  String get welcomeSubtitle =>
      'A simple, private note space that stays strictly on this device.';

  @override
  String get welcomePrinciple1Title => 'On-Device Storage Only';

  @override
  String get welcomePrinciple1Desc =>
      'Your notes are stored in an encrypted database on this phone. Nothing is ever sent to any server or cloud.';

  @override
  String get welcomePrinciple2Title => 'Zero Telemetry & Zero Trackers';

  @override
  String get welcomePrinciple2Desc =>
      'No accounts, no analytics, no advertising IDs, and no internet connection permissions requested.';

  @override
  String get welcomePrinciple3Title => 'Locked Notes & Paper Key';

  @override
  String get welcomePrinciple3Desc =>
      'Protect private notes with AES-GCM encryption. A 24-word paper recovery key is created when you set up your vault.';

  @override
  String get fileViewerTitle => 'File Viewer';

  @override
  String get saveAsNoteAction => 'Save as note';

  @override
  String get toggleMonospace => 'Toggle monospace font';

  @override
  String get errorFileTooLarge =>
      'File exceeds 2 MB limit\nCannot open files larger than 2 MB.';

  @override
  String get errorFileBinary =>
      'Not a text file\nBinary or unsupported file format detected.';

  @override
  String get errorFileEmpty => 'File is empty\nThis file contains no text.';

  @override
  String get errorFileUnreadable =>
      'Unable to read file\nThe file could not be accessed or read.';

  @override
  String get settings => 'Settings';

  @override
  String get theme => 'Theme';

  @override
  String get themeSystem => 'System default';

  @override
  String get themeLight => 'Light';

  @override
  String get themeDark => 'Dark';

  @override
  String get trashRetentionTitle => 'Trash auto-delete period';

  @override
  String get trashRetention => 'Trash retention';

  @override
  String get trashRetentionPeriod => 'Trash retention period';

  @override
  String get vaultSecurityTitle => 'Vault & Security';

  @override
  String get changeSecret => 'Change Vault Secret';

  @override
  String get viewRecoveryKey => 'View Recovery Key';

  @override
  String get defaultAppsSettings => 'Default Apps Settings';

  @override
  String get defaultAppsSettingsSubtitle =>
      'Set Privacy Notes as default text and Markdown reader';

  @override
  String get about => 'About';

  @override
  String get aboutDescription =>
      'A simple, polished, privacy-first notes application.';

  @override
  String get privacyPromiseTitle => 'Our Privacy Promise';

  @override
  String get privacyPromiseBody =>
      'Privacy Notes never communicates over the network. Your notes never leave this physical device. There are zero analytics, zero trackers, and zero third-party ads.';

  @override
  String get securityBoundariesTitle => 'Security Boundaries & Threat Model';

  @override
  String get securityBoundariesBody =>
      'Locked notes are encrypted using AES-GCM with keys derived via PBKDF2 (200,000 iterations). However, if your device is rooted or compromised by malware with root privileges, encryption keys in memory could be extracted. Always safeguard your physical paper recovery key; anyone with physical access to your paper key can decrypt your locked notes.';

  @override
  String appVersion(String version) {
    return 'Version $version';
  }

  @override
  String get databaseRecoveryTitle => 'Database Recovery';

  @override
  String get databaseRecoveryMessage =>
      'The database could not be opened. Your data file is preserved. You may retry initializing or contact support.';

  @override
  String get exitSelection => 'Exit selection';

  @override
  String get switchToList => 'Switch to list';

  @override
  String get switchToGrid => 'Switch to grid';

  @override
  String get sortNotes => 'Sort notes';

  @override
  String get folderOptions => 'Folder options';

  @override
  String notesArchived(num count) {
    final intl.NumberFormat countNumberFormat = intl.NumberFormat.compact(
      locale: localeName,
    );
    final String countString = countNumberFormat.format(count);

    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$countString notes archived',
      one: '1 note archived',
    );
    return '$_temp0';
  }

  @override
  String notesMovedToTrash(num count) {
    final intl.NumberFormat countNumberFormat = intl.NumberFormat.compact(
      locale: localeName,
    );
    final String countString = countNumberFormat.format(count);

    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$countString notes moved to trash',
      one: '1 note moved to trash',
    );
    return '$_temp0';
  }

  @override
  String get noteArchived => 'Note archived';

  @override
  String get encryptedVaultSubtitle => 'Encrypted Vault (AES-256)';

  @override
  String get recentSectionHeader => 'RECENT';

  @override
  String get notesSectionHeader => 'NOTES';

  @override
  String get back => 'Back';

  @override
  String get moreOptions => 'More options';

  @override
  String get shareTextFile => 'Share text file';

  @override
  String get shareTextFileSubtitle => 'Send note via Android share sheet';

  @override
  String get saveToDevice => 'Save to device';

  @override
  String get saveToDeviceSubtitle =>
      'Choose folder via Storage Access Framework';

  @override
  String get deleteLockedNoteTitle => 'Delete locked note?';

  @override
  String get deleteLockedNoteMessage =>
      'Are you sure you want to permanently delete this locked note? This action cannot be undone.';

  @override
  String get lockVaultNow => 'Lock vault now';

  @override
  String get noteActions => 'Note actions';

  @override
  String get securingRecoveryKey => 'Securing recovery key';

  @override
  String get continueAction => 'Continue';

  @override
  String get viewKeyAgain => 'View key again';

  @override
  String get verifyAndFinish => 'Verify & Finish';

  @override
  String get securityNotice => 'Security Notice';

  @override
  String get dismiss => 'Dismiss';

  @override
  String get recoveringVault => 'Recovering vault';

  @override
  String get pinMinLength => 'PIN (min 6)';

  @override
  String get patternMinLength => 'Pattern (min 5)';

  @override
  String get confirm => 'Confirm';

  @override
  String get securingVault => 'Securing vault';

  @override
  String get confirmAndCreateVault => 'Confirm & Create Vault';

  @override
  String get unlockingVault => 'Unlocking vault';

  @override
  String get fontSizeMultiplier => 'Font size multiplier';

  @override
  String get defaultSort => 'Default sort';

  @override
  String get showTimestamps => 'Show timestamps';

  @override
  String get showTimestampsSubtitle =>
      'Display note creation and update times on cards and editor';

  @override
  String get showWordCount => 'Show word count';

  @override
  String get showWordCountSubtitle => 'Display word and checklist text counts';

  @override
  String trashRetentionSubtitle(num days) {
    final intl.NumberFormat daysNumberFormat = intl.NumberFormat.compact(
      locale: localeName,
    );
    final String daysString = daysNumberFormat.format(days);

    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: '$daysString days (auto-purge expired notes)',
      one: '1 day (auto-purge expired notes)',
    );
    return '$_temp0';
  }

  @override
  String get setUpLockedNotes => 'Set up locked notes';

  @override
  String get setUpLockedNotesSubtitle =>
      'Protect sensitive notes with a PIN or pattern';

  @override
  String get createRecoveryKey => 'Create recovery key';

  @override
  String get createRecoveryKeySubtitle =>
      'Generate a recovery key to write on paper';

  @override
  String get generateNewRecoveryKey => 'Generate a new recovery key';

  @override
  String get generateNewRecoveryKeySubtitle =>
      'Replace existing recovery key (invalidates old key)';

  @override
  String get autoLockTimeout => 'Auto-lock timeout';

  @override
  String changeSecretSubtitle(String credentialType) {
    return 'Change your current $credentialType';
  }

  @override
  String get switchCredentialType => 'Switch credential type';

  @override
  String currentCredential(String type) {
    return 'Current: $type';
  }

  @override
  String get permanentlyDeleteVault =>
      'Permanently delete vault and locked notes';

  @override
  String get permanentlyDeleteVaultSubtitle =>
      'Permanently delete all locked notes and vault';

  @override
  String get openTextMarkdownFiles => 'Open text and Markdown files';

  @override
  String get openDefaultAppsSettings => 'Open default apps settings';

  @override
  String get aboutPrivacyNotes => 'About Privacy Notes';

  @override
  String aboutSubtitle(String version) {
    return 'Version $version • Local-first & offline privacy';
  }

  @override
  String get retryAccess => 'Retry Access';

  @override
  String get debugPerformanceSeeder => 'Performance Benchmark Seeder';

  @override
  String get seed5000Notes => 'Seed 5,000 Notes';

  @override
  String get purgeSeededNotes => 'Purge Seeded Notes';

  @override
  String get seedingSuccess => 'Successfully seeded 5,000 notes.';

  @override
  String get purgingSuccess => 'Successfully purged seeded notes.';

  @override
  String get untitledNote => 'Untitled';

  @override
  String get emptyNote => 'Empty note';

  @override
  String moreItemsCount(num count) {
    final intl.NumberFormat countNumberFormat = intl.NumberFormat.compact(
      locale: localeName,
    );
    final String countString = countNumberFormat.format(count);

    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$countString more items',
      one: '1 more item',
    );
    return '+ $_temp0';
  }

  @override
  String checklistProgress(int completed, int total) {
    return '$completed/$total completed';
  }

  @override
  String get noteUnarchived => 'Note unarchived';

  @override
  String get trashEmptied => 'Trash emptied';

  @override
  String deletedAtDate(String date) {
    return 'Deleted on $date';
  }

  @override
  String editedAtDate(String date) {
    return 'Edited $date';
  }

  @override
  String get unsavedStatus => 'Unsaved';

  @override
  String get noteLocked => 'Note locked';

  @override
  String get noteUnlocked => 'Note unlocked and returned to All';

  @override
  String get noteSavedSuccessfully => 'Note saved successfully';

  @override
  String get lockedNoteDeleted => 'Locked note deleted permanently';

  @override
  String get vaultLocked => 'Vault locked';

  @override
  String get failedToShareNote => 'Failed to share note';

  @override
  String get failedToSaveNote => 'Failed to save note';

  @override
  String get decryptingNotes => 'Decrypting notes...';

  @override
  String get confirmYourPin => 'Confirm your PIN';

  @override
  String get enterNewPinPrompt => 'Enter your new PIN';

  @override
  String get drawYourPatternPrompt => 'Draw your pattern';

  @override
  String get confirmYourPattern => 'Confirm your pattern';

  @override
  String get writeDownRecoveryKey => 'Write down your recovery key';

  @override
  String get confirmRecoveryKey => 'Confirm recovery key';

  @override
  String get confirmCurrentSecretSubtitle =>
      'Confirm current secret before setting a new credential';

  @override
  String get minSixDigits => 'Minimum 6 digits';

  @override
  String get connectAtLeastFiveDots =>
      'Connect at least 5 dots without repeats';

  @override
  String enterSameSecretAgain(String secretType) {
    return 'Enter the same $secretType again';
  }

  @override
  String get keepKeySafeSubtitle =>
      'Keep this key safe. You will need to confirm it in the next step.';

  @override
  String get typeWholeKeySubtitle =>
      'Type the whole key correctly to finalize vault creation';

  @override
  String get securingVaultKey => 'Securing vault key...';

  @override
  String get changeSecretTitle => 'Change secret';

  @override
  String get setUpLockedNotesTitle => 'Set up locked notes';

  @override
  String get paperKeyWarning =>
      'Write it on paper; whoever has this key can open all your notes; it cannot be shown again.';

  @override
  String get forgotSecretNotice =>
      'If you forget your secret, your written paper recovery key is the only way to recover your notes.';

  @override
  String get recoveryKeyExplanation =>
      'This recovery key can decrypt all your notes if you forget your secret. Keep it secret and write it down now.';

  @override
  String get enterRecoveryKeyLabel => 'Enter recovery key';

  @override
  String get recoveryKeyDashesHint =>
      'Dashes and spaces are optional. Case-insensitive.';

  @override
  String get unlockNotes => 'Unlock notes';

  @override
  String get authenticatingSecret => 'Authenticating...';

  @override
  String get recoveringVaultKey => 'Recovering vault key...';

  @override
  String get currentPinPrompt => 'Enter your current PIN';

  @override
  String get currentPatternPrompt => 'Draw your current pattern';

  @override
  String get confirmSecretPrompt => 'Confirm secret before proceeding';

  @override
  String get enterSecretToAuthenticate =>
      'Enter your current secret to authenticate before creating a recovery key.';

  @override
  String get verifyingSecret => 'Verifying secret...';

  @override
  String vaultResetRequestedOn(String date) {
    return 'A vault reset was requested on $date';
  }

  @override
  String get vaultResetReadyToComplete =>
      'Vault reset ready to complete (72h passed)';

  @override
  String timeRemaining(String duration) {
    return 'Time remaining: $duration';
  }

  @override
  String get completeResetNow => 'Complete Reset Now';

  @override
  String get manageCancelResetRequest => 'Manage / Cancel Reset Request';

  @override
  String lockedOutTryAgainIn(int seconds) {
    String _temp0 = intl.Intl.pluralLogic(
      seconds,
      locale: localeName,
      other: '$seconds seconds',
      one: '1 second',
    );
    return 'Locked out. Try again in $_temp0.';
  }

  @override
  String get forgotPinOrPattern => 'Forgot PIN/pattern?';

  @override
  String get forgotSecretResetVault => 'Forgot secret? Reset locked notes';

  @override
  String get lockedNotesVaultReset => 'Locked notes and vault reset';

  @override
  String get enterYourPin => 'Enter your PIN';

  @override
  String get drawYourPattern => 'Draw your pattern';

  @override
  String get resetLockedNotes => 'Reset locked notes';

  @override
  String get appearanceSection => 'Appearance';

  @override
  String get notesAndDisplaySection => 'Notes & Display';

  @override
  String get trashAndStorageSection => 'Trash & Storage';

  @override
  String get securitySection => 'Security';

  @override
  String get fileHandlingSection => 'File Handling';

  @override
  String get informationSection => 'Information';

  @override
  String get fileHandlingExplanation =>
      'Open any .txt or .md file in your file manager, choose Privacy Notes, and tap Always/Remember my choice. If another app (such as ChatGPT) is already the default, clear it in Android Settings > Apps > that app > Open by default.\n\nNote: Android decides the default app, and some file managers may open files in their own built-in viewer.';

  @override
  String get noRecoveryKeyWarning =>
      'No recovery key created. If you forget your secret, you cannot recover locked notes.';

  @override
  String get secretChangedSuccessfully => 'Secret changed successfully';

  @override
  String get credentialUpdatedSuccessfully =>
      'Credential type updated successfully';

  @override
  String get smallFont => 'Small (85%)';

  @override
  String get defaultFont => 'Default (100%)';

  @override
  String get largeFont => 'Large (115%)';

  @override
  String get extraLargeFont => 'Extra Large (130%)';

  @override
  String get whenBackgrounded => 'When backgrounded (Default)';

  @override
  String get immediately => 'Immediately';

  @override
  String get afterOneMinute => 'After 1 minute';

  @override
  String get afterFiveMinutes => 'After 5 minutes';

  @override
  String get afterFifteenMinutes => 'After 15 minutes';

  @override
  String get sortField => 'Sort field';

  @override
  String daysRetentionCount(int days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: '$days days',
      one: '1 day',
    );
    return '$_temp0';
  }

  @override
  String daysRetentionCountDefault(int days) {
    return '$days days (Default)';
  }

  @override
  String get lastEdited => 'Last edited';

  @override
  String get dateCreated => 'Date created';

  @override
  String get insert5000BenchmarkNotes =>
      'Insert 5,000 realistic benchmark notes in batch transaction';

  @override
  String get remove5000BenchmarkNotes =>
      'Remove all 5,000 seeded benchmark notes';

  @override
  String get seedingProgress => 'Seeding 5,000 notes in background...';

  @override
  String get ourPrivacyGuarantee => 'Our Privacy Guarantee';

  @override
  String get nothingLeavesYourDeviceBody =>
      'Nothing leaves your device. All notes, folders, checklists, and cryptographic encryption keys remain strictly on your local hardware. There are no tracking scripts, no third-party telemetry, no cloud sync, and absolutely no internet permissions in this application.';

  @override
  String get hardwareBackedSqlCipher => 'Hardware-Backed SQLCipher';

  @override
  String get hardwareBackedSqlCipherDesc =>
      'Database is encrypted at rest using AES-256 with keys secured in Android Keystore.';

  @override
  String get noInternetPermission => 'No Internet Permission';

  @override
  String get noInternetPermissionDesc =>
      'The app binary requests zero network permissions (INTERNET is absent from AndroidManifest).';

  @override
  String get storageAccessFramework => 'Storage Access Framework';

  @override
  String get storageAccessFrameworkDesc =>
      'Text exports use Android SAF, keeping full storage permissions completely off your device.';

  @override
  String get lockedNotesCryptography =>
      'Locked Notes Cryptography & Threat Model';

  @override
  String get lockedNotesCryptographyDesc =>
      'Locked notes protect sensitive content with AES-256-GCM and PBKDF2 key derivation. What they protect: unauthorized access if someone picks up your unlocked phone or reads raw app storage. What they do NOT protect: rooted devices (where root malware can extract keys from RAM) or physical compromise if someone discovers your written 24-word paper recovery key.';

  @override
  String get openSourceAndTransparent => 'Open Source & Transparent';

  @override
  String get openSourceAndTransparentDesc =>
      'Licensed under the Apache 2.0 license. Fully inspectable code with no proprietary lock-in.';

  @override
  String get enterRecoveryKeyHeading => 'Enter your recovery key';

  @override
  String get enter28CharRecoveryKeyDesc =>
      'Enter the 28-character recovery key written on paper to reset your secret without losing notes.';

  @override
  String get pleaseEnterYourRecoveryKey => 'Please enter your recovery key.';

  @override
  String get checkForTypingMistakes => 'Check for typing mistakes.';

  @override
  String get noRecoveryKeyWrapExists =>
      'No recovery key wrap exists for this vault.';

  @override
  String get incorrectRecoveryKeyCheckPaper =>
      'Incorrect recovery key. Please check your paper copy.';

  @override
  String recoveryErrorWithDetails(String error) {
    return 'Recovery error: $error';
  }

  @override
  String get pinMustBeAtLeastSixDigits => 'PIN must be at least 6 digits';

  @override
  String get patternMustConnectAtLeastFiveDots =>
      'Pattern must connect at least 5 dots';

  @override
  String get patternsDoNotMatch => 'Patterns do not match. Please try again.';

  @override
  String get pinsDoNotMatch => 'PINs do not match. Please try again.';

  @override
  String get newSecretSetVaultUnlocked => 'New secret set. Vault unlocked.';

  @override
  String recoveryFailedWithDetails(String error) {
    return 'Recovery failed: $error';
  }

  @override
  String vaultResetCancelledNotice(String date) {
    return 'A vault reset was requested on $date.\n\nBecause you have successfully recovered the vault, this reset request has been automatically cancelled.';
  }

  @override
  String get securingNewSecret => 'Securing new secret...';

  @override
  String get verifyRecoveryKeyButton => 'Verify Recovery Key';

  @override
  String get currentSecretIncorrect => 'Current secret is incorrect.';

  @override
  String get regenerateRecoveryKeyTitle => 'Regenerate recovery key';

  @override
  String get createRecoveryKeyTitle => 'Create recovery key';

  @override
  String get typeDeleteToConfirm => 'Type DELETE exactly to confirm.';

  @override
  String get pleaseEnterCurrentSecret => 'Please enter your current secret.';

  @override
  String get resetWithSecretOption => 'Reset with Current Secret';

  @override
  String get resetWithRecoveryKeyOption => 'Reset with Paper Recovery Key';

  @override
  String get resetWithDelayedGraceOption => 'Emergency 72-Hour Reset';

  @override
  String get resetLockedNotesTitle => 'Reset locked notes?';

  @override
  String get vaultAccessError => 'Vault Access Error';

  @override
  String get resetWarningMessage =>
      'This action will permanently delete all locked notes. Unlocked notes will remain untouched.';

  @override
  String get deleteConfirmationPrompt =>
      'To confirm permanent deletion, type DELETE below:';

  @override
  String get requestDelayedReset => 'Request 72-Hour Delayed Reset';

  @override
  String get cancelPendingReset => 'Cancel Pending Reset';

  @override
  String get undecodedCharactersWarning =>
      'Some characters could not be decoded and were replaced with �.';

  @override
  String get variableWidthFontTooltip => 'Variable width font';

  @override
  String get monospaceFontTooltip => 'Monospace font';

  @override
  String get failedToSaveNoteRetry => 'Failed to save note. Please try again.';

  @override
  String get closeAction => 'Close';

  @override
  String get vaultSecretOption => 'Vault Secret';

  @override
  String get recoveryKeyOption => 'Recovery Key';

  @override
  String get proveCurrentSecretOrRecoveryKey =>
      'Prove current secret or recovery key to reset immediately:';

  @override
  String get recoveryKeyMismatchError =>
      'Recovery key does not match. Check for typing mistakes.';

  @override
  String get deleteEverything => 'Delete Everything';
}
