import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[Locale('en')];

  /// The name of the application
  ///
  /// In en, this message translates to:
  /// **'LeafLock'**
  String get appTitle;

  /// Standard cancel action
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// Standard save action
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// Standard delete action
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// Action to move a note to trash
  ///
  /// In en, this message translates to:
  /// **'Move to trash'**
  String get moveToTrash;

  /// Standard create action
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get create;

  /// Standard done action
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get done;

  /// Standard close action
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// Standard retry action
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retry;

  /// Button to dismiss the welcome screen and start using the app
  ///
  /// In en, this message translates to:
  /// **'Get Started'**
  String get getStarted;

  /// Button to skip an introductory flow
  ///
  /// In en, this message translates to:
  /// **'Skip'**
  String get skip;

  /// Title for sort dialog
  ///
  /// In en, this message translates to:
  /// **'Sort by'**
  String get sortBy;

  /// Section header for sort order
  ///
  /// In en, this message translates to:
  /// **'Order'**
  String get order;

  /// Sort order ascending
  ///
  /// In en, this message translates to:
  /// **'Ascending'**
  String get ascending;

  /// Sort order descending
  ///
  /// In en, this message translates to:
  /// **'Descending'**
  String get descending;

  /// Sort by last modified date
  ///
  /// In en, this message translates to:
  /// **'Date modified'**
  String get sortFieldUpdated;

  /// Sort by creation date
  ///
  /// In en, this message translates to:
  /// **'Date created'**
  String get sortFieldCreated;

  /// Sort by note title
  ///
  /// In en, this message translates to:
  /// **'Title'**
  String get sortFieldTitle;

  /// Action and accessibility label to create a new note
  ///
  /// In en, this message translates to:
  /// **'New note'**
  String get newNote;

  /// Search field hint text
  ///
  /// In en, this message translates to:
  /// **'Search notes'**
  String get searchNotes;

  /// Tooltip and semantics label to clear search query
  ///
  /// In en, this message translates to:
  /// **'Clear search'**
  String get clearSearch;

  /// Filter tab for all notes
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get allNotes;

  /// Button and dialog title to create a new folder
  ///
  /// In en, this message translates to:
  /// **'New Folder'**
  String get newFolder;

  /// Hint text for folder name text field
  ///
  /// In en, this message translates to:
  /// **'Folder name'**
  String get folderName;

  /// Dialog title and action to rename folder
  ///
  /// In en, this message translates to:
  /// **'Rename Folder'**
  String get renameFolder;

  /// Action to delete a folder
  ///
  /// In en, this message translates to:
  /// **'Delete folder'**
  String get deleteFolder;

  /// Confirmation title for deleting a folder
  ///
  /// In en, this message translates to:
  /// **'Delete folder?'**
  String get deleteFolderConfirmTitle;

  /// Confirmation message explaining notes remain safe when deleting a folder
  ///
  /// In en, this message translates to:
  /// **'Notes inside \"{folderName}\" will not be deleted; they will stay in All notes.'**
  String deleteFolderConfirmMessage(String folderName);

  /// Empty state text in folder picker
  ///
  /// In en, this message translates to:
  /// **'No folders created yet'**
  String get noFoldersYet;

  /// Action and title to move note(s) to a folder
  ///
  /// In en, this message translates to:
  /// **'Move to folder'**
  String get moveToFolder;

  /// Header for moving selected notes to folder
  ///
  /// In en, this message translates to:
  /// **'Move {count, plural, =1{1 note} other{{count} notes}} to...'**
  String moveNotesToFolderTitle(num count);

  /// Pluralized note count
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{0 notes} =1{1 note} other{{count} notes}}'**
  String notesCount(num count);

  /// Section header for pinned notes
  ///
  /// In en, this message translates to:
  /// **'PINNED'**
  String get pinnedSectionHeader;

  /// Section header for unpinned notes
  ///
  /// In en, this message translates to:
  /// **'NOTES'**
  String get otherNotesSectionHeader;

  /// Action to pin a note
  ///
  /// In en, this message translates to:
  /// **'Pin'**
  String get pin;

  /// Action to unpin a note
  ///
  /// In en, this message translates to:
  /// **'Unpin'**
  String get unpin;

  /// Action and navigation title for Archive
  ///
  /// In en, this message translates to:
  /// **'Archive'**
  String get archive;

  /// Action to unarchive a note
  ///
  /// In en, this message translates to:
  /// **'Unarchive'**
  String get unarchive;

  /// Action and navigation title for Trash
  ///
  /// In en, this message translates to:
  /// **'Trash'**
  String get trash;

  /// Action to restore a note from trash
  ///
  /// In en, this message translates to:
  /// **'Restore'**
  String get restore;

  /// Action to permanently delete a note
  ///
  /// In en, this message translates to:
  /// **'Delete permanently'**
  String get deletePermanently;

  /// Dialog title for permanent note deletion
  ///
  /// In en, this message translates to:
  /// **'Delete note permanently?'**
  String get deletePermanentlyConfirmTitle;

  /// Dialog message for permanent note deletion
  ///
  /// In en, this message translates to:
  /// **'This action cannot be undone. The note will be permanently erased.'**
  String get deletePermanentlyConfirmMessage;

  /// Action to empty all notes from trash
  ///
  /// In en, this message translates to:
  /// **'Empty Trash'**
  String get emptyTrash;

  /// Dialog title for emptying trash
  ///
  /// In en, this message translates to:
  /// **'Empty trash?'**
  String get emptyTrashConfirmTitle;

  /// Dialog message for emptying trash
  ///
  /// In en, this message translates to:
  /// **'All items in the trash will be permanently deleted.'**
  String get emptyTrashConfirmMessage;

  /// Notice showing how long items stay in trash before automatic deletion
  ///
  /// In en, this message translates to:
  /// **'Items in trash are automatically purged after {days, plural, =1{1 day} other{{days} days}}.'**
  String trashRetentionNotice(num days);

  /// Empty state title when there are no notes
  ///
  /// In en, this message translates to:
  /// **'No notes yet'**
  String get noNotesTitle;

  /// Empty state subtitle when there are no notes
  ///
  /// In en, this message translates to:
  /// **'Tap + to create your first note.'**
  String get noNotesMessage;

  /// Empty state title when search returns no matches
  ///
  /// In en, this message translates to:
  /// **'No notes found'**
  String get noSearchResultsTitle;

  /// Empty state subtitle when search returns no matches
  ///
  /// In en, this message translates to:
  /// **'Try searching for different keywords.'**
  String get noSearchResultsMessage;

  /// Empty state title for trash screen
  ///
  /// In en, this message translates to:
  /// **'Trash is empty'**
  String get trashEmptyTitle;

  /// Empty state subtitle for trash screen
  ///
  /// In en, this message translates to:
  /// **'Deleted notes will appear here.'**
  String get trashEmptyMessage;

  /// Empty state title for archive screen
  ///
  /// In en, this message translates to:
  /// **'Archive is empty'**
  String get archiveEmptyTitle;

  /// Empty state subtitle for archive screen
  ///
  /// In en, this message translates to:
  /// **'Archived notes will appear here.'**
  String get archiveEmptyMessage;

  /// Bulk selection counter
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 selected} other{{count} selected}}'**
  String selectedNotesCount(num count);

  /// Action to select all notes in bulk mode
  ///
  /// In en, this message translates to:
  /// **'Select all'**
  String get selectAll;

  /// Action to deselect all notes in bulk mode
  ///
  /// In en, this message translates to:
  /// **'Deselect all'**
  String get deselectAll;

  /// Action to clear bulk selection
  ///
  /// In en, this message translates to:
  /// **'Clear selection'**
  String get clearSelection;

  /// Hint text for note title in editor
  ///
  /// In en, this message translates to:
  /// **'Title'**
  String get noteTitleHint;

  /// Hint text for note body in editor
  ///
  /// In en, this message translates to:
  /// **'Note'**
  String get noteBodyHint;

  /// Hint text for a new checklist item row
  ///
  /// In en, this message translates to:
  /// **'List item'**
  String get addChecklistItem;

  /// Action to convert note to checklist
  ///
  /// In en, this message translates to:
  /// **'Switch to checklist mode'**
  String get switchToChecklist;

  /// Action to convert checklist back to plain text
  ///
  /// In en, this message translates to:
  /// **'Switch to text mode'**
  String get switchToText;

  /// Word count label in note editor and cards
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{0 words} =1{1 word} other{{count} words}}'**
  String wordsCount(num count);

  /// Character count display
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{0 characters} =1{1 character} other{{count} characters}}'**
  String charactersCount(num count);

  /// Autosave status indicator when saved
  ///
  /// In en, this message translates to:
  /// **'Saved'**
  String get savedStatus;

  /// Autosave status indicator while saving
  ///
  /// In en, this message translates to:
  /// **'Saving...'**
  String get savingStatus;

  /// Action to pick a color label for a note
  ///
  /// In en, this message translates to:
  /// **'Color label'**
  String get colorLabel;

  /// Label for default uncolored note
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get colorLabelNone;

  /// Color label Red
  ///
  /// In en, this message translates to:
  /// **'Red'**
  String get colorLabelRed;

  /// Color label Orange
  ///
  /// In en, this message translates to:
  /// **'Orange'**
  String get colorLabelOrange;

  /// Color label Yellow
  ///
  /// In en, this message translates to:
  /// **'Yellow'**
  String get colorLabelYellow;

  /// Color label Green
  ///
  /// In en, this message translates to:
  /// **'Green'**
  String get colorLabelGreen;

  /// Color label Blue
  ///
  /// In en, this message translates to:
  /// **'Blue'**
  String get colorLabelBlue;

  /// Color label Purple
  ///
  /// In en, this message translates to:
  /// **'Purple'**
  String get colorLabelPurple;

  /// Action to lock a note in the vault
  ///
  /// In en, this message translates to:
  /// **'Lock note'**
  String get lockNote;

  /// Confirmation title when locking a note
  ///
  /// In en, this message translates to:
  /// **'Lock note?'**
  String get lockNoteConfirmTitle;

  /// Confirmation message when locking a note
  ///
  /// In en, this message translates to:
  /// **'Locking will encrypt this note with your vault key. Its folder, pin, archive status, and color label will be cleared.'**
  String get lockNoteConfirmMessage;

  /// Action to unlock a note from the vault
  ///
  /// In en, this message translates to:
  /// **'Unlock note'**
  String get unlockNote;

  /// Action to export note as markdown or text file
  ///
  /// In en, this message translates to:
  /// **'Export note'**
  String get exportNote;

  /// Title of the export note modal bottom sheet
  ///
  /// In en, this message translates to:
  /// **'Export Note'**
  String get exportNoteTitle;

  /// Option to export note in Markdown format
  ///
  /// In en, this message translates to:
  /// **'Export as Markdown (.md)'**
  String get exportAsMarkdown;

  /// Option to export note in plain text format
  ///
  /// In en, this message translates to:
  /// **'Export as Plain Text (.txt)'**
  String get exportAsText;

  /// Snackbar message when export succeeds
  ///
  /// In en, this message translates to:
  /// **'Note exported successfully'**
  String get exportSuccess;

  /// Snackbar message when export fails
  ///
  /// In en, this message translates to:
  /// **'Failed to export note'**
  String get exportFailed;

  /// Snackbar message when a note is moved to trash
  ///
  /// In en, this message translates to:
  /// **'Note moved to trash'**
  String get noteMovedToTrash;

  /// Snackbar message when a note is restored from trash
  ///
  /// In en, this message translates to:
  /// **'Note restored'**
  String get noteRestored;

  /// Undo action button in snackbars
  ///
  /// In en, this message translates to:
  /// **'Undo'**
  String get undo;

  /// Title and navigation entry for Locked Notes vault
  ///
  /// In en, this message translates to:
  /// **'Locked Notes'**
  String get lockedNotes;

  /// Empty state title in locked notes vault
  ///
  /// In en, this message translates to:
  /// **'No locked notes'**
  String get lockedNotesEmptyTitle;

  /// Empty state message in locked notes vault
  ///
  /// In en, this message translates to:
  /// **'Notes you lock will be encrypted and shown here.'**
  String get lockedNotesEmptyMessage;

  /// Title for vault setup screen
  ///
  /// In en, this message translates to:
  /// **'Set Up Vault'**
  String get vaultSetupTitle;

  /// Step title for credential selection in vault setup
  ///
  /// In en, this message translates to:
  /// **'Choose Credential'**
  String get vaultSetupStepSecret;

  /// Step title for paper recovery key in vault setup
  ///
  /// In en, this message translates to:
  /// **'Paper Recovery Key'**
  String get vaultSetupStepRecovery;

  /// Step title for confirming recovery key in vault setup
  ///
  /// In en, this message translates to:
  /// **'Confirm Recovery Key'**
  String get vaultSetupStepConfirm;

  /// Credential type PIN
  ///
  /// In en, this message translates to:
  /// **'PIN'**
  String get pinCredential;

  /// Credential type Pattern
  ///
  /// In en, this message translates to:
  /// **'Pattern'**
  String get patternCredential;

  /// Prompt to enter PIN
  ///
  /// In en, this message translates to:
  /// **'Enter PIN'**
  String get enterPin;

  /// Prompt to re-enter PIN for confirmation
  ///
  /// In en, this message translates to:
  /// **'Confirm PIN'**
  String get confirmPin;

  /// Prompt to draw pattern
  ///
  /// In en, this message translates to:
  /// **'Draw Pattern'**
  String get enterPattern;

  /// Prompt to re-draw pattern for confirmation
  ///
  /// In en, this message translates to:
  /// **'Confirm Pattern'**
  String get confirmPattern;

  /// Error message when entered PIN does not match confirmation
  ///
  /// In en, this message translates to:
  /// **'PINs do not match. Please try again.'**
  String get pinMismatch;

  /// Error message when entered pattern does not match confirmation
  ///
  /// In en, this message translates to:
  /// **'Patterns do not match. Please try again.'**
  String get patternMismatch;

  /// Error message when pattern has fewer than 4 points
  ///
  /// In en, this message translates to:
  /// **'Connect at least 4 dots.'**
  String get patternTooShort;

  /// Accessibility warning banner displayed on pattern setup screen
  ///
  /// In en, this message translates to:
  /// **'Pattern lock is not screen-reader friendly. Use a numeric PIN for full TalkBack support.'**
  String get patternAccessibilityNotice;

  /// Button to switch from pattern lock to numeric PIN
  ///
  /// In en, this message translates to:
  /// **'Use PIN instead'**
  String get usePinInstead;

  /// Instruction to write down paper recovery key
  ///
  /// In en, this message translates to:
  /// **'Write down your Paper Recovery Key'**
  String get paperRecoveryKeyTitle;

  /// Warning and explanation for the paper recovery key
  ///
  /// In en, this message translates to:
  /// **'This 28-character key is the ONLY way to recover locked notes if you forget your secret. Write it on paper and keep it secure. Never store it digitally.'**
  String get paperRecoveryKeyNotice;

  /// Checkbox or confirmation button indicating recovery key has been copied
  ///
  /// In en, this message translates to:
  /// **'I have written it down'**
  String get iHaveWrittenItDown;

  /// Verification prompt testing user's written copy of recovery key
  ///
  /// In en, this message translates to:
  /// **'Enter your 28-character recovery key to confirm:'**
  String get verifyRecoveryKeyPrompt;

  /// Label for specific group in recovery key verification
  ///
  /// In en, this message translates to:
  /// **'Group #{number}'**
  String wordNumber(int number);

  /// Title for vault unlock screen
  ///
  /// In en, this message translates to:
  /// **'Unlock Vault'**
  String get vaultUnlockTitle;

  /// Error message when entering an incorrect vault secret
  ///
  /// In en, this message translates to:
  /// **'Incorrect secret. Please try again.'**
  String get incorrectSecret;

  /// Lockout message indicating cooldown period
  ///
  /// In en, this message translates to:
  /// **'Too many failed attempts. Try again in {seconds, plural, =1{1 second} other{{seconds} seconds}}.'**
  String lockoutMessage(int seconds);

  /// Button to navigate to recovery flow
  ///
  /// In en, this message translates to:
  /// **'Forgot Secret?'**
  String get forgotSecret;

  /// Screen title for recovering vault
  ///
  /// In en, this message translates to:
  /// **'Recover vault'**
  String get recoverVaultTitle;

  /// Instruction on vault recovery screen
  ///
  /// In en, this message translates to:
  /// **'Enter your 28-character recovery key:'**
  String get enterRecoveryKeyPrompt;

  /// Error message for invalid recovery key input
  ///
  /// In en, this message translates to:
  /// **'Invalid recovery key. Check for typing mistakes.'**
  String get invalidRecoveryKey;

  /// Message upon successful recovery key verification
  ///
  /// In en, this message translates to:
  /// **'Vault successfully recovered. Set a new credential.'**
  String get recoverySuccess;

  /// Header title on first-run welcome screen
  ///
  /// In en, this message translates to:
  /// **'LeafLock'**
  String get welcomeTitle;

  /// Header subtitle on first-run welcome screen
  ///
  /// In en, this message translates to:
  /// **'A simple, private note space that stays strictly on this device.'**
  String get welcomeSubtitle;

  /// Title for principle 1
  ///
  /// In en, this message translates to:
  /// **'On-Device Storage Only'**
  String get welcomePrinciple1Title;

  /// Description for principle 1
  ///
  /// In en, this message translates to:
  /// **'Your notes are stored in an encrypted database on this phone. Nothing is ever sent to any server or cloud.'**
  String get welcomePrinciple1Desc;

  /// Title for principle 2
  ///
  /// In en, this message translates to:
  /// **'Zero Telemetry & Zero Trackers'**
  String get welcomePrinciple2Title;

  /// Description for principle 2
  ///
  /// In en, this message translates to:
  /// **'No accounts, no analytics, no advertising IDs, and no internet connection permissions requested.'**
  String get welcomePrinciple2Desc;

  /// Title for principle 3
  ///
  /// In en, this message translates to:
  /// **'Locked Notes & Backups'**
  String get welcomePrinciple3Title;

  /// Description for principle 3
  ///
  /// In en, this message translates to:
  /// **'Protect private notes with AES-GCM encryption. A single 28-character paper recovery key secures both your vault and encrypted backups.'**
  String get welcomePrinciple3Desc;

  /// Title for external file viewer screen
  ///
  /// In en, this message translates to:
  /// **'File Viewer'**
  String get fileViewerTitle;

  /// Action in file viewer to save external file as an app note
  ///
  /// In en, this message translates to:
  /// **'Save as note'**
  String get saveAsNoteAction;

  /// Action and tooltip to toggle monospace font in file viewer
  ///
  /// In en, this message translates to:
  /// **'Toggle monospace font'**
  String get toggleMonospace;

  /// Error state message when opened external file exceeds 2 MB
  ///
  /// In en, this message translates to:
  /// **'File exceeds 2 MB limit\nCannot open files larger than 2 MB.'**
  String get errorFileTooLarge;

  /// Error state message when opened file contains NUL bytes
  ///
  /// In en, this message translates to:
  /// **'Not a text file\nBinary or unsupported file format detected.'**
  String get errorFileBinary;

  /// Error state message when opened file has 0 bytes
  ///
  /// In en, this message translates to:
  /// **'File is empty\nThis file contains no text.'**
  String get errorFileEmpty;

  /// Error state message when file stream read fails
  ///
  /// In en, this message translates to:
  /// **'Unable to read file\nThe file could not be accessed or read.'**
  String get errorFileUnreadable;

  /// Settings navigation and screen title
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings;

  /// Settings section for theme
  ///
  /// In en, this message translates to:
  /// **'Theme'**
  String get theme;

  /// System default theme option
  ///
  /// In en, this message translates to:
  /// **'System default'**
  String get themeSystem;

  /// Light theme option
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get themeLight;

  /// Dark theme option
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get themeDark;

  /// Settings item for trash auto-delete period
  ///
  /// In en, this message translates to:
  /// **'Trash auto-delete period'**
  String get trashRetentionTitle;

  /// Settings tile title for trash retention
  ///
  /// In en, this message translates to:
  /// **'Trash retention'**
  String get trashRetention;

  /// Dialog title for trash retention period selection
  ///
  /// In en, this message translates to:
  /// **'Trash retention period'**
  String get trashRetentionPeriod;

  /// Settings section header for vault
  ///
  /// In en, this message translates to:
  /// **'Vault & Security'**
  String get vaultSecurityTitle;

  /// Settings item to change PIN or Pattern
  ///
  /// In en, this message translates to:
  /// **'Change Vault Secret'**
  String get changeSecret;

  /// Settings item to view or re-record paper recovery key
  ///
  /// In en, this message translates to:
  /// **'View Recovery Key'**
  String get viewRecoveryKey;

  /// Settings item to open system default apps screen
  ///
  /// In en, this message translates to:
  /// **'Default Apps Settings'**
  String get defaultAppsSettings;

  /// Subtitle explaining default apps settings
  ///
  /// In en, this message translates to:
  /// **'Set LeafLock as default text and Markdown reader'**
  String get defaultAppsSettingsSubtitle;

  /// About navigation and screen title
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get about;

  /// App description shown on about screen
  ///
  /// In en, this message translates to:
  /// **'A simple, polished, privacy-first notes application.'**
  String get aboutDescription;

  /// Section title on about screen
  ///
  /// In en, this message translates to:
  /// **'Our Privacy Promise'**
  String get privacyPromiseTitle;

  /// Privacy promise text on about screen
  ///
  /// In en, this message translates to:
  /// **'LeafLock never communicates over the network. Your notes never leave this physical device. There are zero analytics, zero trackers, and zero third-party ads.'**
  String get privacyPromiseBody;

  /// Section title for security boundaries
  ///
  /// In en, this message translates to:
  /// **'Security Boundaries & Threat Model'**
  String get securityBoundariesTitle;

  /// Honest security explanation on about screen
  ///
  /// In en, this message translates to:
  /// **'Locked notes are encrypted using AES-GCM with keys derived via PBKDF2 (200,000 iterations). However, if your device is rooted or compromised by malware with root privileges, encryption keys in memory could be extracted. Always safeguard your physical paper recovery key; anyone with physical access to your paper key can decrypt your locked notes.'**
  String get securityBoundariesBody;

  /// App version display
  ///
  /// In en, this message translates to:
  /// **'Version {version}'**
  String appVersion(String version);

  /// Title for database recovery screen
  ///
  /// In en, this message translates to:
  /// **'Database Recovery'**
  String get databaseRecoveryTitle;

  /// Message shown when database fails integrity check on startup
  ///
  /// In en, this message translates to:
  /// **'The database could not be opened. Your data file is preserved. You may retry initializing or contact support.'**
  String get databaseRecoveryMessage;

  /// Tooltip to exit multi-select mode
  ///
  /// In en, this message translates to:
  /// **'Exit selection'**
  String get exitSelection;

  /// Tooltip to switch notes layout to single column list
  ///
  /// In en, this message translates to:
  /// **'Switch to list'**
  String get switchToList;

  /// Tooltip to switch notes layout to two column grid
  ///
  /// In en, this message translates to:
  /// **'Switch to grid'**
  String get switchToGrid;

  /// Tooltip to open sort modal
  ///
  /// In en, this message translates to:
  /// **'Sort notes'**
  String get sortNotes;

  /// Tooltip for folder chip options menu
  ///
  /// In en, this message translates to:
  /// **'Folder options'**
  String get folderOptions;

  /// Snackbar message when notes are bulk archived
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 note archived} other{{count} notes archived}}'**
  String notesArchived(num count);

  /// Snackbar message when notes are bulk moved to trash
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 note moved to trash} other{{count} notes moved to trash}}'**
  String notesMovedToTrash(num count);

  /// Snackbar message when a single note is archived
  ///
  /// In en, this message translates to:
  /// **'Note archived'**
  String get noteArchived;

  /// Subtitle in navigation drawer
  ///
  /// In en, this message translates to:
  /// **'Encrypted Vault (AES-256)'**
  String get encryptedVaultSubtitle;

  /// Section header for unpinned recent notes when pinned notes exist
  ///
  /// In en, this message translates to:
  /// **'RECENT'**
  String get recentSectionHeader;

  /// Section header for notes list
  ///
  /// In en, this message translates to:
  /// **'NOTES'**
  String get notesSectionHeader;

  /// Standard back navigation button tooltip or label
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get back;

  /// Tooltip for overflow popup menu button
  ///
  /// In en, this message translates to:
  /// **'More options'**
  String get moreOptions;

  /// Export action title to share note file
  ///
  /// In en, this message translates to:
  /// **'Share text file'**
  String get shareTextFile;

  /// Export action subtitle for share sheet
  ///
  /// In en, this message translates to:
  /// **'Send note via Android share sheet'**
  String get shareTextFileSubtitle;

  /// Export action title to save file via storage framework
  ///
  /// In en, this message translates to:
  /// **'Save to device'**
  String get saveToDevice;

  /// Export action subtitle for storage framework
  ///
  /// In en, this message translates to:
  /// **'Choose folder via Storage Access Framework'**
  String get saveToDeviceSubtitle;

  /// Confirmation title when permanently deleting a locked note
  ///
  /// In en, this message translates to:
  /// **'Delete locked note?'**
  String get deleteLockedNoteTitle;

  /// Confirmation message when deleting a locked note
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to permanently delete this locked note? This action cannot be undone.'**
  String get deleteLockedNoteMessage;

  /// Tooltip for button to immediately lock the vault
  ///
  /// In en, this message translates to:
  /// **'Lock vault now'**
  String get lockVaultNow;

  /// Tooltip for note options menu in locked notes list
  ///
  /// In en, this message translates to:
  /// **'Note actions'**
  String get noteActions;

  /// Header title while displaying paper recovery key
  ///
  /// In en, this message translates to:
  /// **'Securing recovery key'**
  String get securingRecoveryKey;

  /// Standard continue button label
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get continueAction;

  /// Button to navigate back to recovery key display
  ///
  /// In en, this message translates to:
  /// **'View key again'**
  String get viewKeyAgain;

  /// Button to confirm and complete recovery key verification
  ///
  /// In en, this message translates to:
  /// **'Verify & Finish'**
  String get verifyAndFinish;

  /// Heading for security advisory banners
  ///
  /// In en, this message translates to:
  /// **'Security Notice'**
  String get securityNotice;

  /// Action to dismiss notice banner
  ///
  /// In en, this message translates to:
  /// **'Dismiss'**
  String get dismiss;

  /// App bar title during vault recovery
  ///
  /// In en, this message translates to:
  /// **'Recovering vault'**
  String get recoveringVault;

  /// Label for PIN option specifying minimum 6 digits
  ///
  /// In en, this message translates to:
  /// **'PIN (min 6)'**
  String get pinMinLength;

  /// Label for Pattern option specifying minimum 5 dots
  ///
  /// In en, this message translates to:
  /// **'Pattern (min 5)'**
  String get patternMinLength;

  /// Action button label to confirm input
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get confirm;

  /// App bar title during vault setup
  ///
  /// In en, this message translates to:
  /// **'Securing vault'**
  String get securingVault;

  /// Action button to finalize vault creation
  ///
  /// In en, this message translates to:
  /// **'Confirm & Create Vault'**
  String get confirmAndCreateVault;

  /// App bar title during vault unlock
  ///
  /// In en, this message translates to:
  /// **'Unlocking vault'**
  String get unlockingVault;

  /// Settings title for font size slider
  ///
  /// In en, this message translates to:
  /// **'Font size multiplier'**
  String get fontSizeMultiplier;

  /// Settings title for default sort order
  ///
  /// In en, this message translates to:
  /// **'Default sort'**
  String get defaultSort;

  /// Settings title for toggling timestamp display
  ///
  /// In en, this message translates to:
  /// **'Show timestamps'**
  String get showTimestamps;

  /// Settings subtitle for timestamps
  ///
  /// In en, this message translates to:
  /// **'Display note creation and update times on cards and editor'**
  String get showTimestampsSubtitle;

  /// Settings title for toggling word counts
  ///
  /// In en, this message translates to:
  /// **'Show word count'**
  String get showWordCount;

  /// Settings subtitle for word counts
  ///
  /// In en, this message translates to:
  /// **'Display word and checklist text counts'**
  String get showWordCountSubtitle;

  /// Subtitle showing active trash retention period
  ///
  /// In en, this message translates to:
  /// **'{days, plural, =1{1 day (auto-purge expired notes)} other{{days} days (auto-purge expired notes)}}'**
  String trashRetentionSubtitle(num days);

  /// Settings title to create initial vault
  ///
  /// In en, this message translates to:
  /// **'Set up locked notes'**
  String get setUpLockedNotes;

  /// Settings subtitle for initial vault setup
  ///
  /// In en, this message translates to:
  /// **'Protect sensitive notes with a PIN or pattern'**
  String get setUpLockedNotesSubtitle;

  /// Settings title to generate first recovery key
  ///
  /// In en, this message translates to:
  /// **'Create recovery key'**
  String get createRecoveryKey;

  /// Settings subtitle to generate first recovery key
  ///
  /// In en, this message translates to:
  /// **'Generate a recovery key to write on paper'**
  String get createRecoveryKeySubtitle;

  /// Settings title to regenerate paper recovery key
  ///
  /// In en, this message translates to:
  /// **'Generate a new recovery key'**
  String get generateNewRecoveryKey;

  /// Settings subtitle for regenerating recovery key
  ///
  /// In en, this message translates to:
  /// **'Replace existing recovery key (invalidates old key)'**
  String get generateNewRecoveryKeySubtitle;

  /// Settings title for auto-lock timeout duration
  ///
  /// In en, this message translates to:
  /// **'Auto-lock timeout'**
  String get autoLockTimeout;

  /// Settings subtitle for changing secret
  ///
  /// In en, this message translates to:
  /// **'Change your current {credentialType}'**
  String changeSecretSubtitle(String credentialType);

  /// Settings title to switch between PIN and pattern
  ///
  /// In en, this message translates to:
  /// **'Switch credential type'**
  String get switchCredentialType;

  /// Settings subtitle indicating active credential type
  ///
  /// In en, this message translates to:
  /// **'Current: {type}'**
  String currentCredential(String type);

  /// Settings title for nuclear vault reset
  ///
  /// In en, this message translates to:
  /// **'Permanently delete vault and locked notes'**
  String get permanentlyDeleteVault;

  /// Settings subtitle for nuclear vault reset
  ///
  /// In en, this message translates to:
  /// **'Permanently delete all locked notes and vault'**
  String get permanentlyDeleteVaultSubtitle;

  /// Settings section header for external file intent handling
  ///
  /// In en, this message translates to:
  /// **'Open text and Markdown files'**
  String get openTextMarkdownFiles;

  /// Button label in settings to open Android default apps
  ///
  /// In en, this message translates to:
  /// **'Open default apps settings'**
  String get openDefaultAppsSettings;

  /// Settings entry title navigating to about screen
  ///
  /// In en, this message translates to:
  /// **'About LeafLock'**
  String get aboutPrivacyNotes;

  /// Subtitle on settings about entry
  ///
  /// In en, this message translates to:
  /// **'Version {version} • Local-first & offline privacy'**
  String aboutSubtitle(String version);

  /// Button to retry opening the database on recovery screen
  ///
  /// In en, this message translates to:
  /// **'Retry Access'**
  String get retryAccess;

  /// Settings section title for debug-only benchmark tools
  ///
  /// In en, this message translates to:
  /// **'Performance Benchmark Seeder'**
  String get debugPerformanceSeeder;

  /// Button to populate database with 5,000 test notes
  ///
  /// In en, this message translates to:
  /// **'Seed 5,000 Notes'**
  String get seed5000Notes;

  /// Button to delete all 5,000 seeded notes
  ///
  /// In en, this message translates to:
  /// **'Purge Seeded Notes'**
  String get purgeSeededNotes;

  /// Snackbar message when 5,000 notes are generated
  ///
  /// In en, this message translates to:
  /// **'Successfully seeded 5,000 notes.'**
  String get seedingSuccess;

  /// Snackbar message when seeded notes are purged
  ///
  /// In en, this message translates to:
  /// **'Successfully purged seeded notes.'**
  String get purgingSuccess;

  /// Fallback title when note has no title
  ///
  /// In en, this message translates to:
  /// **'Untitled'**
  String get untitledNote;

  /// Fallback text when note has neither title nor body
  ///
  /// In en, this message translates to:
  /// **'Empty note'**
  String get emptyNote;

  /// Count of remaining checklist items in collapsed preview
  ///
  /// In en, this message translates to:
  /// **'+ {count, plural, =1{1 more item} other{{count} more items}}'**
  String moreItemsCount(num count);

  /// Progress of completed checklist items
  ///
  /// In en, this message translates to:
  /// **'{completed}/{total} completed'**
  String checklistProgress(int completed, int total);

  /// Snackbar message when note is unarchived
  ///
  /// In en, this message translates to:
  /// **'Note unarchived'**
  String get noteUnarchived;

  /// Snackbar message when trash is emptied
  ///
  /// In en, this message translates to:
  /// **'Trash emptied'**
  String get trashEmptied;

  /// Timestamp indicating when note was moved to trash
  ///
  /// In en, this message translates to:
  /// **'Deleted on {date}'**
  String deletedAtDate(String date);

  /// Timestamp showing when note was last edited
  ///
  /// In en, this message translates to:
  /// **'Edited {date}'**
  String editedAtDate(String date);

  /// Autosave status when dirty edits exist
  ///
  /// In en, this message translates to:
  /// **'Unsaved'**
  String get unsavedStatus;

  /// Snackbar message when a note is locked into the vault
  ///
  /// In en, this message translates to:
  /// **'Note locked'**
  String get noteLocked;

  /// Snackbar message when a note is unlocked from the vault
  ///
  /// In en, this message translates to:
  /// **'Note unlocked and returned to All'**
  String get noteUnlocked;

  /// Snackbar message when note is saved to device storage
  ///
  /// In en, this message translates to:
  /// **'Note saved successfully'**
  String get noteSavedSuccessfully;

  /// Snackbar message when a locked note is deleted
  ///
  /// In en, this message translates to:
  /// **'Locked note deleted permanently'**
  String get lockedNoteDeleted;

  /// Loading message when vault is locked
  ///
  /// In en, this message translates to:
  /// **'Vault locked'**
  String get vaultLocked;

  /// Snackbar error message when sharing note fails
  ///
  /// In en, this message translates to:
  /// **'Failed to share note'**
  String get failedToShareNote;

  /// Snackbar error message when saving note fails
  ///
  /// In en, this message translates to:
  /// **'Failed to save note'**
  String get failedToSaveNote;

  /// Loading message when decrypting notes
  ///
  /// In en, this message translates to:
  /// **'Decrypting notes...'**
  String get decryptingNotes;

  /// Title for confirming PIN in setup
  ///
  /// In en, this message translates to:
  /// **'Confirm your PIN'**
  String get confirmYourPin;

  /// Step 1 title when entering new PIN
  ///
  /// In en, this message translates to:
  /// **'Enter your new PIN'**
  String get enterNewPinPrompt;

  /// Step 1 title when entering pattern
  ///
  /// In en, this message translates to:
  /// **'Draw your pattern'**
  String get drawYourPatternPrompt;

  /// Title for confirming pattern in setup
  ///
  /// In en, this message translates to:
  /// **'Confirm your pattern'**
  String get confirmYourPattern;

  /// Title for writing down recovery key step
  ///
  /// In en, this message translates to:
  /// **'Write down your recovery key'**
  String get writeDownRecoveryKey;

  /// Title for confirming recovery key step
  ///
  /// In en, this message translates to:
  /// **'Confirm recovery key'**
  String get confirmRecoveryKey;

  /// Subtitle when changing existing secret
  ///
  /// In en, this message translates to:
  /// **'Confirm current secret before setting a new credential'**
  String get confirmCurrentSecretSubtitle;

  /// PIN constraint subtitle
  ///
  /// In en, this message translates to:
  /// **'Minimum 6 digits'**
  String get minSixDigits;

  /// Pattern constraint subtitle
  ///
  /// In en, this message translates to:
  /// **'Connect at least 5 dots without repeats'**
  String get connectAtLeastFiveDots;

  /// Confirmation subtitle for secret entry
  ///
  /// In en, this message translates to:
  /// **'Enter the same {secretType} again'**
  String enterSameSecretAgain(String secretType);

  /// Subtitle instructing user to write down recovery key
  ///
  /// In en, this message translates to:
  /// **'Keep this key safe. You will need to confirm it in the next step.'**
  String get keepKeySafeSubtitle;

  /// Subtitle for recovery key verification step
  ///
  /// In en, this message translates to:
  /// **'Type the whole key correctly to finalize vault creation'**
  String get typeWholeKeySubtitle;

  /// Loading message during KDF derivation
  ///
  /// In en, this message translates to:
  /// **'Securing vault key...'**
  String get securingVaultKey;

  /// Title on change secret screen
  ///
  /// In en, this message translates to:
  /// **'Change secret'**
  String get changeSecretTitle;

  /// Title on initial vault setup screen
  ///
  /// In en, this message translates to:
  /// **'Set up locked notes'**
  String get setUpLockedNotesTitle;

  /// Warning banner text for paper recovery key
  ///
  /// In en, this message translates to:
  /// **'Write it on paper; whoever has this key can open all your notes; it cannot be shown again.'**
  String get paperKeyWarning;

  /// Warning banner text for credential setup
  ///
  /// In en, this message translates to:
  /// **'If you forget your secret, your written paper recovery key is the only way to recover your notes.'**
  String get forgotSecretNotice;

  /// Detailed explanation of paper recovery key purpose
  ///
  /// In en, this message translates to:
  /// **'This recovery key can decrypt all your notes if you forget your secret. Keep it secret and write it down now.'**
  String get recoveryKeyExplanation;

  /// Input field label for recovery key confirmation
  ///
  /// In en, this message translates to:
  /// **'Enter recovery key'**
  String get enterRecoveryKeyLabel;

  /// Hint beneath recovery key input
  ///
  /// In en, this message translates to:
  /// **'Dashes and spaces are optional. Case-insensitive.'**
  String get recoveryKeyDashesHint;

  /// Title on unlock screen
  ///
  /// In en, this message translates to:
  /// **'Unlock notes'**
  String get unlockNotes;

  /// Loading message during unlock authentication
  ///
  /// In en, this message translates to:
  /// **'Authenticating...'**
  String get authenticatingSecret;

  /// Loading message during vault recovery
  ///
  /// In en, this message translates to:
  /// **'Recovering vault key...'**
  String get recoveringVaultKey;

  /// Header prompt for current PIN verification
  ///
  /// In en, this message translates to:
  /// **'Enter your current PIN'**
  String get currentPinPrompt;

  /// Header prompt for current pattern verification
  ///
  /// In en, this message translates to:
  /// **'Draw your current pattern'**
  String get currentPatternPrompt;

  /// Subtitle prompt before proceeding
  ///
  /// In en, this message translates to:
  /// **'Confirm secret before proceeding'**
  String get confirmSecretPrompt;

  /// Notice banner in recovery key setup
  ///
  /// In en, this message translates to:
  /// **'Enter your current secret to authenticate before creating a recovery key.'**
  String get enterSecretToAuthenticate;

  /// Loading message when verifying secret
  ///
  /// In en, this message translates to:
  /// **'Verifying secret...'**
  String get verifyingSecret;

  /// Notice banner showing when delayed reset was requested
  ///
  /// In en, this message translates to:
  /// **'A vault reset was requested on {date}'**
  String vaultResetRequestedOn(String date);

  /// Notice banner when 72h delayed reset period has passed
  ///
  /// In en, this message translates to:
  /// **'Vault reset ready to complete (72h passed)'**
  String get vaultResetReadyToComplete;

  /// Countdown display for delayed vault reset
  ///
  /// In en, this message translates to:
  /// **'Time remaining: {duration}'**
  String timeRemaining(String duration);

  /// Button to finalize completed 72h reset
  ///
  /// In en, this message translates to:
  /// **'Complete Reset Now'**
  String get completeResetNow;

  /// Button to cancel delayed reset
  ///
  /// In en, this message translates to:
  /// **'Manage / Cancel Reset Request'**
  String get manageCancelResetRequest;

  /// Lockout banner text
  ///
  /// In en, this message translates to:
  /// **'Locked out. Try again in {seconds, plural, =1{1 second} other{{seconds} seconds}}.'**
  String lockedOutTryAgainIn(int seconds);

  /// Button to recover vault using paper recovery key
  ///
  /// In en, this message translates to:
  /// **'Forgot PIN/pattern?'**
  String get forgotPinOrPattern;

  /// Button to initiate emergency vault reset
  ///
  /// In en, this message translates to:
  /// **'Forgot secret? Reset locked notes'**
  String get forgotSecretResetVault;

  /// Snackbar message when vault reset completes
  ///
  /// In en, this message translates to:
  /// **'Locked notes and vault reset'**
  String get lockedNotesVaultReset;

  /// Title prompt to enter PIN
  ///
  /// In en, this message translates to:
  /// **'Enter your PIN'**
  String get enterYourPin;

  /// Title prompt to draw pattern
  ///
  /// In en, this message translates to:
  /// **'Draw your pattern'**
  String get drawYourPattern;

  /// Settings item to reset locked notes and vault
  ///
  /// In en, this message translates to:
  /// **'Reset locked notes'**
  String get resetLockedNotes;

  /// Section header in settings for appearance
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get appearanceSection;

  /// Section header in settings for notes and display
  ///
  /// In en, this message translates to:
  /// **'Notes & Display'**
  String get notesAndDisplaySection;

  /// Section header in settings for trash and storage
  ///
  /// In en, this message translates to:
  /// **'Trash & Storage'**
  String get trashAndStorageSection;

  /// Section header in settings for security
  ///
  /// In en, this message translates to:
  /// **'Security'**
  String get securitySection;

  /// Section header in settings for file handling
  ///
  /// In en, this message translates to:
  /// **'File Handling'**
  String get fileHandlingSection;

  /// Section header in settings for information
  ///
  /// In en, this message translates to:
  /// **'Information'**
  String get informationSection;

  /// Help text explaining how to set LeafLock as default file handler
  ///
  /// In en, this message translates to:
  /// **'Open any .txt or .md file in your file manager, choose LeafLock, and tap Always/Remember my choice. If another app (such as ChatGPT) is already the default, clear it in Android Settings > Apps > that app > Open by default.\n\nNote: Android decides the default app, and some file managers may open files in their own built-in viewer.'**
  String get fileHandlingExplanation;

  /// Warning banner in settings when vault has no recovery key
  ///
  /// In en, this message translates to:
  /// **'No recovery key created. If you forget your secret, you cannot recover locked notes.'**
  String get noRecoveryKeyWarning;

  /// Snackbar message when vault secret is changed
  ///
  /// In en, this message translates to:
  /// **'Secret changed successfully'**
  String get secretChangedSuccessfully;

  /// Snackbar message when vault credential type is switched
  ///
  /// In en, this message translates to:
  /// **'Credential type updated successfully'**
  String get credentialUpdatedSuccessfully;

  /// Font size option 85%
  ///
  /// In en, this message translates to:
  /// **'Small (85%)'**
  String get smallFont;

  /// Font size option 100%
  ///
  /// In en, this message translates to:
  /// **'Default (100%)'**
  String get defaultFont;

  /// Font size option 115%
  ///
  /// In en, this message translates to:
  /// **'Large (115%)'**
  String get largeFont;

  /// Font size option 130%
  ///
  /// In en, this message translates to:
  /// **'Extra Large (130%)'**
  String get extraLargeFont;

  /// Auto-lock timeout option for background
  ///
  /// In en, this message translates to:
  /// **'When backgrounded (Default)'**
  String get whenBackgrounded;

  /// Auto-lock timeout option immediately
  ///
  /// In en, this message translates to:
  /// **'Immediately'**
  String get immediately;

  /// Auto-lock timeout option 1 minute
  ///
  /// In en, this message translates to:
  /// **'After 1 minute'**
  String get afterOneMinute;

  /// Auto-lock timeout option 5 minutes
  ///
  /// In en, this message translates to:
  /// **'After 5 minutes'**
  String get afterFiveMinutes;

  /// Auto-lock timeout option 15 minutes
  ///
  /// In en, this message translates to:
  /// **'After 15 minutes'**
  String get afterFifteenMinutes;

  /// Section title in sort dialog
  ///
  /// In en, this message translates to:
  /// **'Sort field'**
  String get sortField;

  /// Selection item for trash retention days
  ///
  /// In en, this message translates to:
  /// **'{days, plural, =1{1 day} other{{days} days}}'**
  String daysRetentionCount(int days);

  /// Default selection item for trash retention days
  ///
  /// In en, this message translates to:
  /// **'{days} days (Default)'**
  String daysRetentionCountDefault(int days);

  /// Sort option label for last modified
  ///
  /// In en, this message translates to:
  /// **'Last edited'**
  String get lastEdited;

  /// Sort option label for date created
  ///
  /// In en, this message translates to:
  /// **'Date created'**
  String get dateCreated;

  /// Subtitle for seeding benchmark notes
  ///
  /// In en, this message translates to:
  /// **'Insert 5,000 realistic benchmark notes in batch transaction'**
  String get insert5000BenchmarkNotes;

  /// Subtitle for purging benchmark notes
  ///
  /// In en, this message translates to:
  /// **'Remove all 5,000 seeded benchmark notes'**
  String get remove5000BenchmarkNotes;

  /// Snackbar message while seeding notes
  ///
  /// In en, this message translates to:
  /// **'Seeding 5,000 notes in background...'**
  String get seedingProgress;

  /// Header for privacy guarantee card
  ///
  /// In en, this message translates to:
  /// **'Our Privacy Guarantee'**
  String get ourPrivacyGuarantee;

  /// Full privacy commitment text
  ///
  /// In en, this message translates to:
  /// **'Nothing leaves your device. All notes, folders, checklists, and cryptographic encryption keys remain strictly on your local hardware. There are no tracking scripts, no third-party telemetry, no cloud sync, and absolutely no internet permissions in this application.'**
  String get nothingLeavesYourDeviceBody;

  /// Architecture card title
  ///
  /// In en, this message translates to:
  /// **'Hardware-Backed SQLCipher'**
  String get hardwareBackedSqlCipher;

  /// Architecture card description
  ///
  /// In en, this message translates to:
  /// **'Database is encrypted at rest using AES-256 with keys secured in Android Keystore.'**
  String get hardwareBackedSqlCipherDesc;

  /// Architecture card title
  ///
  /// In en, this message translates to:
  /// **'No Internet Permission'**
  String get noInternetPermission;

  /// Architecture card description
  ///
  /// In en, this message translates to:
  /// **'The app binary requests zero network permissions (INTERNET is absent from AndroidManifest).'**
  String get noInternetPermissionDesc;

  /// Architecture card title
  ///
  /// In en, this message translates to:
  /// **'Storage Access Framework'**
  String get storageAccessFramework;

  /// Architecture card description
  ///
  /// In en, this message translates to:
  /// **'Text exports use Android SAF, keeping full storage permissions completely off your device.'**
  String get storageAccessFrameworkDesc;

  /// Architecture card title
  ///
  /// In en, this message translates to:
  /// **'Locked Notes Cryptography & Threat Model'**
  String get lockedNotesCryptography;

  /// Architecture card description
  ///
  /// In en, this message translates to:
  /// **'Locked notes protect sensitive content with AES-256-GCM and PBKDF2 key derivation. What they protect: unauthorized access if someone picks up your unlocked phone or reads raw app storage. What they do NOT protect: rooted devices (where root malware can extract keys from RAM) or physical compromise if someone discovers your written 28-character paper recovery key.'**
  String get lockedNotesCryptographyDesc;

  /// Architecture card title
  ///
  /// In en, this message translates to:
  /// **'Open Source & Transparent'**
  String get openSourceAndTransparent;

  /// Architecture card description
  ///
  /// In en, this message translates to:
  /// **'Licensed under the Apache 2.0 license. Fully inspectable code with no proprietary lock-in.'**
  String get openSourceAndTransparentDesc;

  /// Heading on vault recovery step 0
  ///
  /// In en, this message translates to:
  /// **'Enter your recovery key'**
  String get enterRecoveryKeyHeading;

  /// Description on vault recovery step 0
  ///
  /// In en, this message translates to:
  /// **'Enter the 28-character recovery key written on paper to reset your secret without losing notes.'**
  String get enter28CharRecoveryKeyDesc;

  /// Validation message when recovery key field is empty
  ///
  /// In en, this message translates to:
  /// **'Please enter your recovery key.'**
  String get pleaseEnterYourRecoveryKey;

  /// Validation error when checksum or format fails on recovery key
  ///
  /// In en, this message translates to:
  /// **'Check for typing mistakes.'**
  String get checkForTypingMistakes;

  /// Error when vault metadata lacks recovery key wrap
  ///
  /// In en, this message translates to:
  /// **'No recovery key wrap exists for this vault.'**
  String get noRecoveryKeyWrapExists;

  /// Error when recovery key fails authentication
  ///
  /// In en, this message translates to:
  /// **'Incorrect recovery key. Please check your paper copy.'**
  String get incorrectRecoveryKeyCheckPaper;

  /// Generic recovery error message
  ///
  /// In en, this message translates to:
  /// **'An error occurred during recovery. Please try again.'**
  String get recoveryErrorWithDetails;

  /// Generic recovery error message
  ///
  /// In en, this message translates to:
  /// **'An error occurred during recovery. Please try again.'**
  String get recoveryError;

  /// Validation error for short PIN
  ///
  /// In en, this message translates to:
  /// **'PIN must be at least 6 digits'**
  String get pinMustBeAtLeastSixDigits;

  /// Validation error for short pattern
  ///
  /// In en, this message translates to:
  /// **'Pattern must connect at least 5 dots'**
  String get patternMustConnectAtLeastFiveDots;

  /// Validation error when confirmation pattern differs
  ///
  /// In en, this message translates to:
  /// **'Patterns do not match. Please try again.'**
  String get patternsDoNotMatch;

  /// Validation error when confirmation PIN differs
  ///
  /// In en, this message translates to:
  /// **'PINs do not match. Please try again.'**
  String get pinsDoNotMatch;

  /// Success snackbar after recovering vault
  ///
  /// In en, this message translates to:
  /// **'New secret set. Vault unlocked.'**
  String get newSecretSetVaultUnlocked;

  /// Error message when vault recovery fails during execution
  ///
  /// In en, this message translates to:
  /// **'Vault recovery failed. Please verify your recovery key and try again.'**
  String get recoveryFailedWithDetails;

  /// Error message when vault recovery fails during execution
  ///
  /// In en, this message translates to:
  /// **'Vault recovery failed. Please verify your recovery key and try again.'**
  String get recoveryFailed;

  /// Dialog notice when pending reset is cancelled by recovery
  ///
  /// In en, this message translates to:
  /// **'A vault reset was requested on {date}.\n\nBecause you have successfully recovered the vault, this reset request has been automatically cancelled.'**
  String vaultResetCancelledNotice(String date);

  /// Loading message when saving new secret during recovery
  ///
  /// In en, this message translates to:
  /// **'Securing new secret...'**
  String get securingNewSecret;

  /// Button to verify entered recovery key
  ///
  /// In en, this message translates to:
  /// **'Verify Recovery Key'**
  String get verifyRecoveryKeyButton;

  /// Error message when entering wrong current secret
  ///
  /// In en, this message translates to:
  /// **'Current secret is incorrect.'**
  String get currentSecretIncorrect;

  /// Title when re-generating recovery key
  ///
  /// In en, this message translates to:
  /// **'Regenerate recovery key'**
  String get regenerateRecoveryKeyTitle;

  /// Title when creating initial recovery key
  ///
  /// In en, this message translates to:
  /// **'Create recovery key'**
  String get createRecoveryKeyTitle;

  /// Error message when user does not type DELETE in nuclear reset
  ///
  /// In en, this message translates to:
  /// **'Type DELETE exactly to confirm.'**
  String get typeDeleteToConfirm;

  /// Validation error when current secret is empty in reset dialog
  ///
  /// In en, this message translates to:
  /// **'Please enter your current secret.'**
  String get pleaseEnterCurrentSecret;

  /// Option in reset dialog
  ///
  /// In en, this message translates to:
  /// **'Reset with Current Secret'**
  String get resetWithSecretOption;

  /// Option in reset dialog
  ///
  /// In en, this message translates to:
  /// **'Reset with Paper Recovery Key'**
  String get resetWithRecoveryKeyOption;

  /// Option in reset dialog
  ///
  /// In en, this message translates to:
  /// **'Emergency 72-Hour Reset'**
  String get resetWithDelayedGraceOption;

  /// Dialog title for resetting locked notes
  ///
  /// In en, this message translates to:
  /// **'Reset locked notes?'**
  String get resetLockedNotesTitle;

  /// Heading on database recovery screen
  ///
  /// In en, this message translates to:
  /// **'Vault Access Error'**
  String get vaultAccessError;

  /// Warning message in reset dialog
  ///
  /// In en, this message translates to:
  /// **'This action will permanently delete all locked notes. Unlocked notes will remain untouched.'**
  String get resetWarningMessage;

  /// Prompt in reset dialog
  ///
  /// In en, this message translates to:
  /// **'To confirm permanent deletion, type DELETE below:'**
  String get deleteConfirmationPrompt;

  /// Button to request delayed reset
  ///
  /// In en, this message translates to:
  /// **'Request 72-Hour Delayed Reset'**
  String get requestDelayedReset;

  /// Button to cancel pending reset
  ///
  /// In en, this message translates to:
  /// **'Cancel Pending Reset'**
  String get cancelPendingReset;

  /// Banner warning in file viewer when invalid UTF-8 bytes were replaced
  ///
  /// In en, this message translates to:
  /// **'Some characters could not be decoded and were replaced with �.'**
  String get undecodedCharactersWarning;

  /// Tooltip in file viewer
  ///
  /// In en, this message translates to:
  /// **'Variable width font'**
  String get variableWidthFontTooltip;

  /// Tooltip in file viewer
  ///
  /// In en, this message translates to:
  /// **'Monospace font'**
  String get monospaceFontTooltip;

  /// Snackbar message when saving external file as note fails
  ///
  /// In en, this message translates to:
  /// **'Failed to save note. Please try again.'**
  String get failedToSaveNoteRetry;

  /// Generic close action button or tooltip
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get closeAction;

  /// Segment option in reset dialog
  ///
  /// In en, this message translates to:
  /// **'Vault Secret'**
  String get vaultSecretOption;

  /// Segment option in reset dialog
  ///
  /// In en, this message translates to:
  /// **'Recovery Key'**
  String get recoveryKeyOption;

  /// Instruction heading in reset dialog
  ///
  /// In en, this message translates to:
  /// **'Prove current secret or recovery key to reset immediately:'**
  String get proveCurrentSecretOrRecoveryKey;

  /// Error in recovery key entry when retype does not match
  ///
  /// In en, this message translates to:
  /// **'Recovery key does not match. Check for typing mistakes.'**
  String get recoveryKeyMismatchError;

  /// Action button in reset vault dialog to permanently delete vault
  ///
  /// In en, this message translates to:
  /// **'Delete Everything'**
  String get deleteEverything;

  /// Navigation title and screen header for backup and restore
  ///
  /// In en, this message translates to:
  /// **'Backup & Restore'**
  String get backupAndRestore;

  /// Settings subtitle for backup and restore tile
  ///
  /// In en, this message translates to:
  /// **'Encrypted offline backups saved to device storage'**
  String get backupAndRestoreSubtitle;

  /// Section header for backup operations
  ///
  /// In en, this message translates to:
  /// **'Backup'**
  String get backupSectionHeader;

  /// Section header for restore operations
  ///
  /// In en, this message translates to:
  /// **'Restore'**
  String get restoreSectionHeader;

  /// Button to create an encrypted backup now
  ///
  /// In en, this message translates to:
  /// **'Back up now'**
  String get backupNow;

  /// Subtitle describing the backup now action
  ///
  /// In en, this message translates to:
  /// **'Create an encrypted backup of all notes, folders, and settings'**
  String get backupNowSubtitle;

  /// Button to restore notes from an encrypted backup file
  ///
  /// In en, this message translates to:
  /// **'Restore backup'**
  String get restoreBackup;

  /// Subtitle describing the restore backup action
  ///
  /// In en, this message translates to:
  /// **'Import missing notes and folders from a .llbackup file'**
  String get restoreBackupSubtitle;

  /// Label showing the date and time of the last successful backup
  ///
  /// In en, this message translates to:
  /// **'Last backup: {date}'**
  String lastBackupLabel(String date);

  /// Label when no backup has been completed yet
  ///
  /// In en, this message translates to:
  /// **'Last backup: Never'**
  String get lastBackupNever;

  /// Title for the 30-day backup reminder setting
  ///
  /// In en, this message translates to:
  /// **'Backup reminder'**
  String get backupReminderTitle;

  /// Subtitle for the backup reminder setting
  ///
  /// In en, this message translates to:
  /// **'Remind me on the home screen after 30 days without a backup'**
  String get backupReminderSubtitle;

  /// Title for the 30-day backup reminder banner on the notes list
  ///
  /// In en, this message translates to:
  /// **'Back up your notes'**
  String get backupReminderBannerTitle;

  /// Message for the 30-day backup reminder banner
  ///
  /// In en, this message translates to:
  /// **'It\'s been over 30 days since your last backup. Back up your notes now to keep them safe.'**
  String get backupReminderBannerMessage;

  /// Action button to snooze the backup reminder banner for 3 days
  ///
  /// In en, this message translates to:
  /// **'Remind in 3 days'**
  String get remindInThreeDays;

  /// Progress message while backup is being encrypted and created
  ///
  /// In en, this message translates to:
  /// **'Creating encrypted backup...'**
  String get backupCreating;

  /// Snackbar message when a backup file is successfully saved
  ///
  /// In en, this message translates to:
  /// **'Backup saved successfully'**
  String get backupSuccess;

  /// Dialog title asking user if share sheet resulted in a safe save
  ///
  /// In en, this message translates to:
  /// **'Confirm Backup Save'**
  String get backupSharePromptTitle;

  /// Dialog message after closing share sheet to confirm saving
  ///
  /// In en, this message translates to:
  /// **'Did you save the backup file somewhere safe?'**
  String get backupSharePromptMessage;

  /// Affirmative button confirming backup was safely saved
  ///
  /// In en, this message translates to:
  /// **'Yes, saved'**
  String get saveConfirmed;

  /// Negative button indicating backup was not saved
  ///
  /// In en, this message translates to:
  /// **'No'**
  String get saveNotConfirmed;

  /// Subject or title when sharing a backup file
  ///
  /// In en, this message translates to:
  /// **'LeafLock Backup'**
  String get backupShareTitle;

  /// Title when prompting for existing paper key to derive backup subkey
  ///
  /// In en, this message translates to:
  /// **'Enter Paper Recovery Key'**
  String get enterPaperKeyToBackupTitle;

  /// Prompt explaining why paper key is needed to derive backup subkey
  ///
  /// In en, this message translates to:
  /// **'Enter your 28-character paper recovery key to enable backup encryption. You will only need to enter this once.'**
  String get enterPaperKeyToBackupPrompt;

  /// Title when creating a paper key for the first time during backup
  ///
  /// In en, this message translates to:
  /// **'Create Paper Recovery Key'**
  String get setupPaperKeyForBackupTitle;

  /// Prompt when generating the root recovery key during backup setup
  ///
  /// In en, this message translates to:
  /// **'LeafLock uses a single 28-character paper recovery key for vault recovery and encrypted backups. Write down this key on paper and keep it safe.'**
  String get setupPaperKeyForBackupPrompt;

  /// Title when prompting user for existing paper key during vault setup
  ///
  /// In en, this message translates to:
  /// **'Enter Paper Recovery Key'**
  String get enterExistingPaperKeyForVaultTitle;

  /// Prompt explaining why existing paper key is needed for vault setup
  ///
  /// In en, this message translates to:
  /// **'Enter the 28-character paper recovery key you created during backup setup to link your locked notes vault.'**
  String get enterExistingPaperKeyForVaultPrompt;

  /// Dialog title warning about recovery key regeneration
  ///
  /// In en, this message translates to:
  /// **'Regenerating Recovery Key'**
  String get regenerateKeyWarningTitle;

  /// Warning message before or after regenerating recovery key
  ///
  /// In en, this message translates to:
  /// **'Important: Backups created before this change will always require your previous paper key to restore. Keep your old paper key if you still need those backups.'**
  String get regenerateKeyWarningMessage;

  /// Dialog title offering a new backup after recovery key rotation
  ///
  /// In en, this message translates to:
  /// **'Create New Backup?'**
  String get regenerateKeyOfferBackupTitle;

  /// Dialog message offering immediate backup creation after key rotation
  ///
  /// In en, this message translates to:
  /// **'Your recovery key has been updated. Backups made with your old key cannot be restored with the new key. Would you like to create a fresh backup now?'**
  String get regenerateKeyOfferBackupMessage;

  /// Generic button to initiate backup
  ///
  /// In en, this message translates to:
  /// **'Back up now'**
  String get backupNowButton;

  /// Dismiss button for offers and reminders
  ///
  /// In en, this message translates to:
  /// **'Not now'**
  String get notNowButton;

  /// Title of dialog summarizing restore results
  ///
  /// In en, this message translates to:
  /// **'Restore Complete'**
  String get restoreSummaryTitle;

  /// Summary item showing count of newly restored notes
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 note restored} other{{count} notes restored}}'**
  String restoreSummaryNotesRestored(int count);

  /// Summary item showing count of newly restored folders
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 folder restored} other{{count} folders restored}}'**
  String restoreSummaryFoldersRestored(int count);

  /// Summary item showing count of restored locked notes
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 locked note restored} other{{count} locked notes restored}}'**
  String restoreSummaryLockedNotesRestored(int count);

  /// Summary item showing count of locked notes skipped due to vault mismatch
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 locked note skipped (different vault)} other{{count} locked notes skipped (different vault)}}'**
  String restoreSummaryLockedNotesSkipped(int count);

  /// Summary message when all notes in backup already exist in the database
  ///
  /// In en, this message translates to:
  /// **'No new notes were found in the backup. Your existing notes were preserved.'**
  String get restoreSummaryNoNewNotes;

  /// Informational line in restore summary dialog
  ///
  /// In en, this message translates to:
  /// **'A pre-restore safety copy of your database was preserved.'**
  String get restoreSummarySafetyNotice;

  /// Unified friendly error when restore authentication or integrity check fails
  ///
  /// In en, this message translates to:
  /// **'Wrong recovery key or damaged file.'**
  String get wrongRecoveryKeyOrDamagedFile;

  /// Error message when selected backup file is larger than 64 MB
  ///
  /// In en, this message translates to:
  /// **'Backup file exceeds the 64 MB limit.'**
  String get backupFileExceedsLimit;

  /// Error message when backup format version is newer than supported
  ///
  /// In en, this message translates to:
  /// **'This backup was created with a newer version of LeafLock.'**
  String get backupNewerVersionError;

  /// Error message when decompressed backup exceeds safe size limit
  ///
  /// In en, this message translates to:
  /// **'Decompressed backup exceeds the 64 MB limit.'**
  String get decompressionBombError;

  /// Title or picker label when selecting a backup file to restore
  ///
  /// In en, this message translates to:
  /// **'Select Backup File'**
  String get restorePickFileTitle;

  /// Dialog title prompting for recovery key during restore
  ///
  /// In en, this message translates to:
  /// **'Enter Paper Recovery Key'**
  String get enterRecoveryKeyToRestoreTitle;

  /// Instruction in restore key entry dialog
  ///
  /// In en, this message translates to:
  /// **'Enter the 28-character paper recovery key that was active when this backup was created:'**
  String get enterRecoveryKeyToRestorePrompt;

  /// Title of About screen section describing backups
  ///
  /// In en, this message translates to:
  /// **'Offline Encrypted Backups'**
  String get backupAboutArchitectureTitle;

  /// Description of About screen backup architecture
  ///
  /// In en, this message translates to:
  /// **'Full-database authenticated backups (.llbackup) encrypted with AES-256-GCM. Uses the root 28-character recovery key with HKDF subkey derivation. Never sends data off-device.'**
  String get backupAboutArchitectureDesc;

  /// Button to verify existing paper key and complete vault setup
  ///
  /// In en, this message translates to:
  /// **'Link and Complete Setup'**
  String get linkAndCompleteSetup;

  /// Button or menu action to share backup file
  ///
  /// In en, this message translates to:
  /// **'Share backup file'**
  String get shareBackupAction;

  /// Button to save backup file via Storage Access Framework
  ///
  /// In en, this message translates to:
  /// **'Save to device'**
  String get saveToFileAction;

  /// Friendly error message when backup creation or export fails
  ///
  /// In en, this message translates to:
  /// **'Backup failed. Please try again.'**
  String get backupFailed;

  /// Progress status message while backup is being restored
  ///
  /// In en, this message translates to:
  /// **'Restoring backup...'**
  String get restoreRestoring;

  /// Dialog title when selected backup file exceeds size limit
  ///
  /// In en, this message translates to:
  /// **'File Too Large'**
  String get backupFileOversizeTitle;

  /// Error message when pre-restore database safety copy fails
  ///
  /// In en, this message translates to:
  /// **'Could not create safety copy of database. Restore was cancelled.'**
  String get restoreSafetyCopyFailed;

  /// Error message when safety copy file size differs from source database
  ///
  /// In en, this message translates to:
  /// **'Safety copy size mismatch. Restore was cancelled.'**
  String get restoreSafetyCopySizeMismatch;

  /// Error message when backup contents fail schema or data validation
  ///
  /// In en, this message translates to:
  /// **'The backup contains invalid or corrupted data.'**
  String get restoreInvalidData;

  /// Snackbar message when vault setup is successfully completed
  ///
  /// In en, this message translates to:
  /// **'Locked notes vault ready'**
  String get lockedNotesVaultReady;

  /// Error message when setting up locked notes vault fails
  ///
  /// In en, this message translates to:
  /// **'Vault setup failed. Please try again.'**
  String get vaultSetupFailed;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
