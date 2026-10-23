import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import '../../../../core/crypto/id_generator.dart';
import '../../../../core/database/app_database.dart';
import '../../../locked_notes/presentation/controllers/vault_providers.dart';
import '../../data/notes_repository.dart';
import '../../domain/checklist_item.dart';
import '../../domain/folder.dart';
import '../../domain/note.dart';
import '../../domain/note_sort.dart';
import '../../../settings/domain/app_settings.dart';
import '../../../settings/presentation/controllers/settings_provider.dart';

final appDatabaseProvider = Provider<AppDatabase>((ref) {
  return AppDatabase();
});

final notesRepositoryProvider = Provider<NotesRepository>((ref) {
  final appDb = ref.watch(appDatabaseProvider);
  return SqlNotesRepository(appDatabase: appDb);
});

class NotesListNotifier extends ChangeNotifier {
  final NotesRepository _repository;

  List<Note> _notes = const [];
  List<Folder> _folders = const [];
  String _searchQuery = '';
  String? _selectedFolderId; // null = all, or specific folderId
  NoteSortOption _sortOption = const NoteSortOption();
  bool _isGridView = false;
  final Set<String> _selectedNoteIds = {};

  bool _isLoading = false;
  String? _errorMessage;
  bool _hasPurgedExpiredTrash = false;
  Timer? _searchDebounceTimer;
  int _searchRequestId = 0;
  int _trashRetentionDays = 30;

  NotesListNotifier(this._repository, {AppSettings? settings}) {
    if (settings != null) {
      _sortOption = NoteSortOption(
        field: settings.defaultSortField,
        order: settings.defaultSortOrder,
      );
      _trashRetentionDays = settings.trashRetentionDays;
    }
    _init();
  }

  List<Note> get notes => _notes;
  List<Folder> get folders => _folders;
  String get searchQuery => _searchQuery;
  String? get selectedFolderId => _selectedFolderId;
  NoteSortOption get sortOption => _sortOption;
  bool get isGridView => _isGridView;
  Set<String> get selectedNoteIds => Set.unmodifiable(_selectedNoteIds);
  bool get isSelectionMode => _selectedNoteIds.isNotEmpty;
  int get selectedCount => _selectedNoteIds.length;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  bool get areAllSelectedPinned {
    if (_selectedNoteIds.isEmpty) return false;
    final selectedNotes = _notes.where((n) => _selectedNoteIds.contains(n.id));
    return selectedNotes.isNotEmpty && selectedNotes.every((n) => n.isPinned);
  }

  bool _isDisposed = false;

  @override
  void dispose() {
    _isDisposed = true;
    _searchDebounceTimer?.cancel();
    super.dispose();
  }

  @override
  void notifyListeners() {
    if (!_isDisposed) {
      super.notifyListeners();
    }
  }

  void applySettings(AppSettings newSettings) {
    if (_isDisposed) return;
    _trashRetentionDays = newSettings.trashRetentionDays;
  }

  Future<void> _init() async {
    if (!_hasPurgedExpiredTrash) {
      _hasPurgedExpiredTrash = true;
      try {
        await _repository.purgeExpiredTrash(retentionDays: _trashRetentionDays);
      } catch (_) {}
    }
    await loadFolders();
    await loadNotes();
  }

  Future<void> loadFolders() async {
    try {
      _folders = await _repository.getFolders();
      notifyListeners();
    } catch (_) {}
  }

  Future<void> loadNotes() async {
    final currentRequestId = ++_searchRequestId;
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      List<Note> fetchedNotes;
      if (_searchQuery.trim().isEmpty) {
        fetchedNotes = await _repository.getActiveNotes(
          folderId: _selectedFolderId,
          sortOption: _sortOption,
        );
      } else {
        fetchedNotes = await _repository.searchNotes(
          _searchQuery,
          folderId: _selectedFolderId,
          sortOption: _sortOption,
        );
      }

      // Ignore stale responses from out-of-order async queries
      if (currentRequestId != _searchRequestId) {
        return;
      }

      _notes = fetchedNotes;
    } catch (e) {
      if (currentRequestId == _searchRequestId) {
        _errorMessage = 'Failed to load notes. Please retry.';
      }
    } finally {
      if (currentRequestId == _searchRequestId) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  void setSearchQuery(String query) {
    if (_searchQuery == query) return;
    _searchQuery = query;
    clearSelection(); // B8: clear selection on search change
    notifyListeners();

    // B7: 250 ms debounce for search
    _searchDebounceTimer?.cancel();
    _searchDebounceTimer = Timer(const Duration(milliseconds: 250), () {
      loadNotes();
    });
  }

  Future<void> setSelectedFolder(String? folderId) async {
    if (_selectedFolderId == folderId) return;
    _selectedFolderId = folderId;
    clearSelection(); // B8: clear selection on folder filter change
    await loadNotes();
  }

  Future<void> setSortOption(NoteSortOption option) async {
    _sortOption = option;
    await loadNotes();
  }

  void toggleViewMode() {
    _isGridView = !_isGridView;
    notifyListeners();
  }

  // Selection Mode
  void toggleNoteSelection(String noteId) {
    if (_selectedNoteIds.contains(noteId)) {
      _selectedNoteIds.remove(noteId);
    } else {
      _selectedNoteIds.add(noteId);
    }
    notifyListeners();
  }

  void selectAll() {
    _selectedNoteIds.addAll(_notes.map((n) => n.id));
    notifyListeners();
  }

  void clearSelection() {
    if (_selectedNoteIds.isNotEmpty) {
      _selectedNoteIds.clear();
      notifyListeners();
    }
  }

  // Single Actions
  Future<void> togglePin(Note note) async {
    await _repository.setPinned(note.id, !note.isPinned);
    await loadNotes();
  }

  Future<void> trashNote(String id) async {
    await _repository.trashNote(id);
    await loadNotes();
  }

  Future<void> restoreNote(String id) async {
    await _repository.restoreNote(id);
    await loadNotes();
  }

  Future<void> archiveNote(String id) async {
    await _repository.archiveNote(id);
    await loadNotes();
  }

  Future<void> unarchiveNote(String id) async {
    await _repository.unarchiveNote(id);
    await loadNotes();
  }

  // Bulk Multi-Select Actions
  Future<void> toggleBulkPin() async {
    final shouldPin = !areAllSelectedPinned;
    await bulkPin(shouldPin);
  }

  Future<void> bulkPin(bool isPinned) async {
    final ids = _selectedNoteIds.toList();
    if (ids.isEmpty) return;
    await _repository.setPinnedMultiple(ids, isPinned);
    clearSelection();
    await loadNotes();
  }

  Future<List<String>> bulkTrash() async {
    final ids = _selectedNoteIds.toList();
    if (ids.isEmpty) return [];
    await _repository.trashNotes(ids);
    clearSelection();
    await loadNotes();
    return ids;
  }

  Future<void> restoreNotes(List<String> ids) async {
    if (ids.isEmpty) return;
    await _repository.restoreNotes(ids);
    await loadNotes();
  }

  Future<List<String>> bulkArchive() async {
    final ids = _selectedNoteIds.toList();
    if (ids.isEmpty) return [];
    await _repository.archiveNotes(ids);
    clearSelection();
    await loadNotes();
    return ids;
  }

  Future<void> unarchiveNotes(List<String> ids) async {
    if (ids.isEmpty) return;
    await _repository.unarchiveNotes(ids);
    await loadNotes();
  }

  Future<void> bulkMoveToFolder(String? folderId) async {
    final ids = _selectedNoteIds.toList();
    if (ids.isEmpty) return;
    await _repository.moveNotesToFolder(ids, folderId);
    clearSelection();
    await loadNotes();
  }

  // Folder Operations
  Future<Folder> createFolder(String name, {int? color}) async {
    final folder = await _repository.createFolder(name, color: color);
    await loadFolders();
    return folder;
  }

  Future<void> renameFolder(String id, String newName) async {
    await _repository.renameFolder(id, newName);
    await loadFolders();
    await loadNotes();
  }

  Future<void> deleteFolder(String id) async {
    await _repository.deleteFolder(id);
    if (_selectedFolderId == id) {
      _selectedFolderId = null;
    }
    await loadFolders();
    await loadNotes();
  }
}

final notesListProvider =
    ChangeNotifierProvider<NotesListNotifier>((ref) {
  final repo = ref.watch(notesRepositoryProvider);
  final initialSettings = ref.read(settingsProvider).settings;
  final notifier = NotesListNotifier(repo, settings: initialSettings);
  ref.listen<AppSettingsNotifier>(settingsProvider, (previous, next) {
    notifier.applySettings(next.settings);
  });
  return notifier;
});

// Trash Notifier with autoDispose and ErrorState handling
class TrashNotifier extends ChangeNotifier {
  final NotesRepository _repository;
  List<Note> _trashedNotes = const [];
  bool _isLoading = false;
  String? _errorMessage;

  TrashNotifier(this._repository) {
    loadTrash();
  }

  List<Note> get trashedNotes => _trashedNotes;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  Future<void> loadTrash() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      _trashedNotes = await _repository.getTrashedNotes();
    } catch (e) {
      _errorMessage = 'Failed to load trash. Please retry.';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> restoreNote(String id) async {
    await _repository.restoreNote(id);
    await loadTrash();
  }

  Future<void> deletePermanently(String id) async {
    await _repository.deleteNotePermanently(id);
    await loadTrash();
  }

  bool _isDisposed = false;

  @override
  void dispose() {
    _isDisposed = true;
    super.dispose();
  }

  @override
  void notifyListeners() {
    if (!_isDisposed) {
      super.notifyListeners();
    }
  }

  Future<void> emptyTrash() async {
    await _repository.emptyTrash();
    await loadTrash();
  }
}

final trashProvider =
    ChangeNotifierProvider.autoDispose<TrashNotifier>((ref) {
  final repo = ref.watch(notesRepositoryProvider);
  return TrashNotifier(repo);
});

// Archive Notifier with autoDispose and ErrorState handling
class ArchiveNotifier extends ChangeNotifier {
  final NotesRepository _repository;
  List<Note> _archivedNotes = const [];
  bool _isLoading = false;
  String? _errorMessage;
  bool _isDisposed = false;

  ArchiveNotifier(this._repository) {
    loadArchive();
  }

  @override
  void dispose() {
    _isDisposed = true;
    super.dispose();
  }

  @override
  void notifyListeners() {
    if (!_isDisposed) {
      super.notifyListeners();
    }
  }

  List<Note> get archivedNotes => _archivedNotes;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  Future<void> loadArchive() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      _archivedNotes = await _repository.getArchivedNotes();
    } catch (e) {
      _errorMessage = 'Failed to load archive. Please retry.';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> unarchiveNote(String id) async {
    await _repository.unarchiveNote(id);
    await loadArchive();
  }

  Future<void> trashNote(String id) async {
    await _repository.trashNote(id);
    await loadArchive();
  }
}

final archiveProvider =
    ChangeNotifierProvider.autoDispose<ArchiveNotifier>((ref) {
  final repo = ref.watch(notesRepositoryProvider);
  return ArchiveNotifier(repo);
});

// Note Editor Notifier with Partial Update and Checklist Support
class NoteEditorNotifier extends ChangeNotifier {
  final NotesRepository _repository;
  final Uint8List? Function()? getVaultKey;
  Note _note;
  List<ChecklistItem> _checklistItems = const [];
  bool _isDirty = false;
  bool _isSaving = false;
  Timer? _debounceTimer;

  NoteEditorNotifier(
    this._repository,
    this._note, {
    this.getVaultKey,
  }) {
    if (_note.checklistJson != null) {
      _checklistItems = ChecklistItem.parseList(_note.checklistJson);
    }
  }

  Note get note => _note;
  List<ChecklistItem> get checklistItems => _checklistItems;
  bool get isDirty => _isDirty;
  bool get isSaving => _isSaving;

  int get wordCount {
    if (_note.isChecklistMode) {
      return ChecklistItem.calculateWordCount(_checklistItems);
    }
    return Note.calculateWordCount(_note.body);
  }

  int get characterCount {
    if (_note.isChecklistMode) {
      return ChecklistItem.calculateCharCount(_checklistItems);
    }
    return _note.body.length;
  }

  int get checklistCompletedCount =>
      _checklistItems.where((i) => i.isChecked).length;
  int get checklistTotalCount => _checklistItems.length;

  /// Returns true if the note has neither title nor body/checklist content.
  bool get isEmptyContent {
    if (_note.title.trim().isNotEmpty) return false;
    if (_note.isChecklistMode) {
      if (_checklistItems.isEmpty) return true;
      return _checklistItems.every((item) => item.text.trim().isEmpty);
    }
    return _note.body.trim().isEmpty;
  }

  bool _isDisposed = false;

  @override
  void dispose() {
    _isDisposed = true;
    _debounceTimer?.cancel();
    super.dispose();
  }

  @override
  void notifyListeners() {
    if (!_isDisposed) {
      super.notifyListeners();
    }
  }

  void _triggerAutosave() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 500), () {
      saveImmediately();
    });
  }

  void toggleChecklistMode() {
    final nextMode = !_note.isChecklistMode;
    if (nextMode) {
      // Plain text -> Checklist mode
      // Convert plain text lines into checklist items without data loss
      var items = ChecklistItem.fromPlainText(_note.body);
      if (items.isEmpty) {
        items = [ChecklistItem(id: IdGenerator.generateUuidV4(), text: '')];
      }
      _checklistItems = items;
      final encoded = ChecklistItem.encodeList(_checklistItems);
      final count = ChecklistItem.calculateWordCount(_checklistItems);
      final plainText = _checklistItems.map((i) => i.text).join('\n');
      _note = _note.copyWith(
        isChecklistMode: true,
        body: plainText,
        checklistJson: encoded,
        wordCount: count,
      );
    } else {
      // Checklist mode -> Plain text
      // Convert checklist items to markdown lines without data loss
      final text = ChecklistItem.toPlainText(_checklistItems);
      final count = Note.calculateWordCount(text);
      _note = _note.copyWith(
        isChecklistMode: false,
        body: text,
        wordCount: count,
      );
    }
    _isDirty = true;
    notifyListeners();
    _triggerAutosave();
  }

  void updateContent({String? title, String? body}) {
    final newTitle = title ?? _note.title;
    final newBody = body ?? _note.body;

    if (newTitle == _note.title && newBody == _note.body) return;

    final count = _note.isChecklistMode
        ? ChecklistItem.calculateWordCount(_checklistItems)
        : Note.calculateWordCount(newBody);

    _note = _note.copyWith(title: newTitle, body: newBody, wordCount: count);
    _isDirty = true;
    notifyListeners();
    _triggerAutosave();
  }

  String addChecklistItem({int? afterIndex, String text = ''}) {
    final newItem = ChecklistItem(
      id: IdGenerator.generateUuidV4(),
      text: text,
      isChecked: false,
    );
    final mutable = List<ChecklistItem>.from(_checklistItems);
    if (afterIndex != null && afterIndex >= 0 && afterIndex < mutable.length) {
      mutable.insert(afterIndex + 1, newItem);
    } else {
      mutable.add(newItem);
    }
    _checklistItems = mutable;
    final encoded = ChecklistItem.encodeList(_checklistItems);
    final count = ChecklistItem.calculateWordCount(_checklistItems);
    final plainText = mutable.map((i) => i.text).join('\n');
    _note = _note.copyWith(body: plainText, checklistJson: encoded, wordCount: count);
    _isDirty = true;
    notifyListeners();
    _triggerAutosave();
    return newItem.id;
  }

  void updateChecklistItem(String id, {String? text, bool? isChecked}) {
    final mutable = _checklistItems.map((item) {
      if (item.id == id) {
        return item.copyWith(text: text, isChecked: isChecked);
      }
      return item;
    }).toList();

    _checklistItems = mutable;
    final encoded = ChecklistItem.encodeList(_checklistItems);
    final count = ChecklistItem.calculateWordCount(_checklistItems);
    final plainText = mutable.map((i) => i.text).join('\n');
    _note = _note.copyWith(body: plainText, checklistJson: encoded, wordCount: count);
    _isDirty = true;
    notifyListeners();
    _triggerAutosave();
  }

  void deleteChecklistItem(String id) {
    var mutable = _checklistItems.where((i) => i.id != id).toList();
    if (mutable.isEmpty) {
      mutable = [ChecklistItem(id: IdGenerator.generateUuidV4(), text: '')];
    }
    _checklistItems = mutable;
    final encoded = ChecklistItem.encodeList(_checklistItems);
    final count = ChecklistItem.calculateWordCount(_checklistItems);
    final plainText = mutable.map((i) => i.text).join('\n');
    _note = _note.copyWith(body: plainText, checklistJson: encoded, wordCount: count);
    _isDirty = true;
    notifyListeners();
    _triggerAutosave();
  }

  void reorderChecklistItems(int oldIndex, int newIndex) {
    final mutable = List<ChecklistItem>.from(_checklistItems);
    if (newIndex > oldIndex) {
      newIndex -= 1;
    }
    final item = mutable.removeAt(oldIndex);
    mutable.insert(newIndex, item);
    _checklistItems = mutable;
    final encoded = ChecklistItem.encodeList(_checklistItems);
    final plainText = mutable.map((i) => i.text).join('\n');
    _note = _note.copyWith(body: plainText, checklistJson: encoded);
    _isDirty = true;
    notifyListeners();
    _triggerAutosave();
  }

  Future<void> setColorLabel(int labelIndex) async {
    if (_note.colorLabel == labelIndex) return;
    _note = _note.copyWith(colorLabel: labelIndex);
    notifyListeners();
    await _repository.setColorLabel(_note.id, labelIndex);
  }

  Future<void> togglePin() async {
    final newPin = !_note.isPinned;
    _note = _note.copyWith(isPinned: newPin);
    notifyListeners();
    await _repository.setPinned(_note.id, newPin);
  }

  Future<void> setFolder(String? folderId) async {
    _note = _note.copyWith(folderId: folderId);
    notifyListeners();
    await _repository.moveNotesToFolder([_note.id], folderId);
  }

  Future<void> saveImmediately() async {
    _debounceTimer?.cancel();
    if (!_isDirty || _isSaving) return;

    if (isEmptyContent) {
      _isSaving = true;
      notifyListeners();
      try {
        final existing = await _repository.getNoteById(_note.id);
        if (existing != null) {
          // If emptied, delete from database so no phantom empty note persists
          await _repository.deleteNotePermanently(_note.id);
        }
        _isDirty = false;
      } catch (_) {
      } finally {
        _isSaving = false;
        notifyListeners();
      }
      return;
    }

    _isSaving = true;
    notifyListeners();

    try {
      if (_note.isLocked) {
        final key = getVaultKey?.call();
        if (key != null) {
          await _repository.updateLockedNoteContent(
            id: _note.id,
            title: _note.title,
            body: _note.body,
            checklistJson: _note.checklistJson,
            isChecklistMode: _note.isChecklistMode,
            vaultKey: key,
          );
        }
        _isDirty = false;
        return;
      }

      final existing = await _repository.getNoteById(_note.id);
      if (existing == null) {
        // First insert of brand new note
        await _repository.insertNote(_note);
      } else {
        // M1 FIX 2 / M3: Partial update of content only.
        // Saves ONLY title, body, checklist_json, is_checklist_mode, word_count, and updated_at.
        await _repository.updateNoteContent(
          id: _note.id,
          title: _note.title,
          body: _note.body,
          checklistJson: _note.checklistJson,
          isChecklistMode: _note.isChecklistMode,
          wordCount: _note.wordCount,
        );

        final refreshed = await _repository.getNoteById(_note.id);
        if (refreshed != null) {
          _note = _note.copyWith(
            updatedAt: refreshed.updatedAt,
            wordCount: refreshed.wordCount,
          );
        }
      }
      _isDirty = false;
    } catch (_) {
      // Keep dirty flag if save failed
    } finally {
      _isSaving = false;
      notifyListeners();
    }
  }
}

final noteEditorProvider = ChangeNotifierProvider.autoDispose
    .family<NoteEditorNotifier, Note>((ref, note) {
  final repo = ref.watch(notesRepositoryProvider);
  final vaultNotifier = ref.watch(vaultProvider);
  return NoteEditorNotifier(
    repo,
    note,
    getVaultKey: () => vaultNotifier.vaultKey,
  );
});
