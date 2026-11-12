import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../services/backup_service.dart';

/// Manifest containing all exported data for a .llbackup container (B3).
@immutable
class BackupManifest {
  static const int currentSchemaVersion = 1;
  static const String currentAppVersion = '1.0.0';

  /// Settings keys that are permitted to be included in an exported backup (B3, M6 Closure Requirement 6).
  static const Set<String> allowedSettingsKeys = {
    'theme_mode',
    'font_size_multiplier',
    'default_sort_field',
    'default_sort_order',
    'show_timestamps',
    'show_word_count',
    'trash_retention_days',
  };

  /// Known column names for the folders table.
  static const Set<String> knownFolderColumns = {
    'id',
    'name',
    'color',
    'created_at',
    'updated_at',
  };

  /// Known column names for the notes table.
  static const Set<String> knownNoteColumns = {
    'id',
    'title',
    'body',
    'checklist_json',
    'is_checklist_mode',
    'folder_id',
    'color_label',
    'is_pinned',
    'is_archived',
    'is_locked',
    'trashed_at',
    'encrypted_payload',
    'payload_iv',
    'payload_tag',
    'payload_format_version',
    'created_at',
    'updated_at',
    'word_count',
  };

  /// Known column names for the vault_metadata table.
  static const Set<String> knownVaultColumns = {
    'id',
    'salt',
    'kdf_algorithm',
    'kdf_iterations',
    'credential_type',
    'wrapped_vault_key',
    'wrapped_vault_key_iv',
    'wrapped_vault_key_tag',
    'version',
    'recovery_salt',
    'recovery_wrapped_key',
    'recovery_iv',
    'recovery_tag',
    'recovery_version',
    'created_at',
    'updated_at',
  };

  final int schemaVersion;
  final String appVersion;
  final int createdAt;
  final List<Map<String, dynamic>> folders;
  final List<Map<String, dynamic>> notes;
  final Map<String, dynamic>? vaultMetadata;
  final Map<String, String> settings;

  const BackupManifest({
    required this.schemaVersion,
    required this.appVersion,
    required this.createdAt,
    required this.folders,
    required this.notes,
    this.vaultMetadata,
    required this.settings,
  });

  Map<String, dynamic> toMap() {
    return {
      'schema_version': schemaVersion,
      'app_version': appVersion,
      'created_at': createdAt,
      'folders': folders,
      'notes': notes,
      if (vaultMetadata != null) 'vault_metadata': vaultMetadata,
      'settings': settings,
    };
  }

  factory BackupManifest.fromMap(Map<String, dynamic> map) {
    final version = map['schema_version'] as int? ?? 1;
    final appVer = map['app_version'] as String? ?? currentAppVersion;
    final created = map['created_at'] as int? ?? DateTime.now().millisecondsSinceEpoch;

    final rawFolders = map['folders'] as List? ?? [];
    final folders = rawFolders
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();

    final rawNotes = map['notes'] as List? ?? [];
    final notes = rawNotes
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();

    Map<String, dynamic>? vaultMetadata;
    if (map['vault_metadata'] is Map) {
      vaultMetadata = Map<String, dynamic>.from(map['vault_metadata'] as Map);
    }

    final rawSettings = map['settings'] as Map? ?? {};
    final settings = <String, String>{};
    rawSettings.forEach((k, v) {
      if (k != null && v != null && allowedSettingsKeys.contains(k.toString())) {
        settings[k.toString()] = v.toString();
      }
    });

    return BackupManifest(
      schemaVersion: version,
      appVersion: appVer,
      createdAt: created,
      folders: folders,
      notes: notes,
      vaultMetadata: vaultMetadata,
      settings: settings,
    );
  }

  /// Strictly validates manifest fields, column names, types, length limits,
  /// and database constraints before restore application (Requirement 5).
  void validate() {
    if (schemaVersion > currentSchemaVersion) {
      throw const BackupUnsupportedVersionException();
    }
    if (schemaVersion < 1) {
      throw BackupInvalidDataException('Invalid schema version: $schemaVersion');
    }

    // 1. Validate Folders
    for (final folder in folders) {
      for (final key in folder.keys) {
        if (!knownFolderColumns.contains(key)) {
          throw BackupInvalidDataException('Unknown folder column: $key');
        }
      }
      final id = folder['id'];
      if (id is! String || id.isEmpty || id.length > 100) {
        throw const BackupInvalidDataException('Folder id must be a non-empty string <= 100 chars');
      }
      final name = folder['name'];
      if (name is! String || name.isEmpty || name.length > 255) {
        throw const BackupInvalidDataException('Folder name must be a non-empty string <= 255 chars');
      }
      final color = folder['color'];
      if (color != null && color is! int) {
        throw const BackupInvalidDataException('Folder color must be an integer');
      }
      final createdAt = folder['created_at'];
      if (createdAt is! int || createdAt <= 0) {
        throw const BackupInvalidDataException('Folder created_at must be a positive integer');
      }
      final updatedAt = folder['updated_at'];
      if (updatedAt is! int || updatedAt <= 0) {
        throw const BackupInvalidDataException('Folder updated_at must be a positive integer');
      }
    }

    // 2. Validate Notes
    for (final note in notes) {
      for (final key in note.keys) {
        if (!knownNoteColumns.contains(key)) {
          throw BackupInvalidDataException('Unknown note column: $key');
        }
      }
      final id = note['id'];
      if (id is! String || id.isEmpty || id.length > 100) {
        throw const BackupInvalidDataException('Note id must be a non-empty string <= 100 chars');
      }
      final title = note['title'];
      if (title is! String || title.length > 1000) {
        throw const BackupInvalidDataException('Note title must be a string <= 1000 chars');
      }
      final body = note['body'];
      if (body is! String || body.length > 2000000) {
        throw const BackupInvalidDataException('Note body must be a string <= 2MB');
      }
      final checklistJson = note['checklist_json'];
      if (checklistJson != null && (checklistJson is! String || checklistJson.length > 2000000)) {
        throw const BackupInvalidDataException('Note checklist_json must be a string <= 2MB');
      }
      final isChecklistMode = note['is_checklist_mode'];
      if (isChecklistMode != null && (isChecklistMode is! int || (isChecklistMode != 0 && isChecklistMode != 1))) {
        throw const BackupInvalidDataException('Note is_checklist_mode must be 0 or 1');
      }
      final folderId = note['folder_id'];
      if (folderId != null && (folderId is! String || folderId.length > 100)) {
        throw const BackupInvalidDataException('Note folder_id must be a string <= 100 chars');
      }
      final colorLabel = note['color_label'];
      if (colorLabel != null && colorLabel is! int) {
        throw const BackupInvalidDataException('Note color_label must be an integer');
      }
      final isPinned = note['is_pinned'];
      if (isPinned != null && (isPinned is! int || (isPinned != 0 && isPinned != 1))) {
        throw const BackupInvalidDataException('Note is_pinned must be 0 or 1');
      }
      final isArchived = note['is_archived'];
      if (isArchived != null && (isArchived is! int || (isArchived != 0 && isArchived != 1))) {
        throw const BackupInvalidDataException('Note is_archived must be 0 or 1');
      }
      final isLocked = note['is_locked'];
      if (isLocked != null && (isLocked is! int || (isLocked != 0 && isLocked != 1))) {
        throw const BackupInvalidDataException('Note is_locked must be 0 or 1');
      }
      final trashedAt = note['trashed_at'];
      if (trashedAt != null && (trashedAt is! int || trashedAt <= 0)) {
        throw const BackupInvalidDataException('Note trashed_at must be null or positive integer');
      }
      final encryptedPayload = note['encrypted_payload'];
      if (encryptedPayload != null && encryptedPayload is! List && encryptedPayload is! Uint8List) {
        throw const BackupInvalidDataException('Note encrypted_payload must be byte array');
      }
      final payloadIv = note['payload_iv'];
      if (payloadIv != null &&
          ((payloadIv is! List && payloadIv is! Uint8List) || (payloadIv as dynamic).length != 12)) {
        throw const BackupInvalidDataException('Note payload_iv must be 12 bytes');
      }
      final payloadTag = note['payload_tag'];
      if (payloadTag != null &&
          ((payloadTag is! List && payloadTag is! Uint8List) || (payloadTag as dynamic).length != 16)) {
        throw const BackupInvalidDataException('Note payload_tag must be 16 bytes');
      }
      final payloadFormatVersion = note['payload_format_version'];
      if (payloadFormatVersion != null && (payloadFormatVersion is! int || payloadFormatVersion < 1)) {
        throw const BackupInvalidDataException('Note payload_format_version must be >= 1');
      }
      final createdAt = note['created_at'];
      if (createdAt is! int || createdAt <= 0) {
        throw const BackupInvalidDataException('Note created_at must be a positive integer');
      }
      final updatedAt = note['updated_at'];
      if (updatedAt is! int || updatedAt <= 0) {
        throw const BackupInvalidDataException('Note updated_at must be a positive integer');
      }
      final wordCount = note['word_count'];
      if (wordCount != null && (wordCount is! int || wordCount < 0)) {
        throw const BackupInvalidDataException('Note word_count must be an integer >= 0');
      }

      // SQLite Check Invariant
      if (isLocked == 1) {
        if (encryptedPayload == null || payloadIv == null || payloadTag == null) {
          throw const BackupInvalidDataException('Locked note missing encrypted payload or cipher params');
        }
        if (title.isNotEmpty || body.isNotEmpty || checklistJson != null || (wordCount != null && wordCount != 0)) {
          throw const BackupInvalidDataException('Locked note contains plaintext fields');
        }
      } else {
        if (encryptedPayload != null || payloadIv != null || payloadTag != null) {
          throw const BackupInvalidDataException('Unlocked note contains encrypted payload');
        }
      }
    }

    // 3. Validate Vault Metadata (if present)
    if (vaultMetadata != null) {
      for (final key in vaultMetadata!.keys) {
        if (!knownVaultColumns.contains(key)) {
          throw BackupInvalidDataException('Unknown vault_metadata column: $key');
        }
      }
      final credType = vaultMetadata!['credential_type'];
      if (credType != null && credType != 'pin' && credType != 'pattern') {
        throw const BackupInvalidDataException('vault_metadata credential_type must be pin or pattern');
      }
    }

    // 4. Validate Settings
    for (final key in settings.keys) {
      if (!allowedSettingsKeys.contains(key)) {
        throw BackupInvalidDataException('Settings contain unapproved key: $key');
      }
    }
  }

  String toJsonString() => jsonEncode(toMap());

  factory BackupManifest.fromJsonString(String jsonString) {
    final decoded = jsonDecode(jsonString);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Root backup JSON must be an object.');
    }
    return BackupManifest.fromMap(decoded);
  }
}

/// Summary returned after completing a non-destructive restore (B5).
@immutable
class RestoreSummary {
  final int addedNotes;
  final int skippedNotes;
  final int addedFolders;
  final int skippedFolders;
  final int lockedNotesSkipped;
  final bool vaultAdopted;

  const RestoreSummary({
    required this.addedNotes,
    required this.skippedNotes,
    required this.addedFolders,
    required this.skippedFolders,
    required this.lockedNotesSkipped,
    this.vaultAdopted = false,
  });

  @override
  String toString() {
    return 'RestoreSummary(addedNotes: $addedNotes, skippedNotes: $skippedNotes, '
        'addedFolders: $addedFolders, skippedFolders: $skippedFolders, '
        'lockedNotesSkipped: $lockedNotesSkipped, vaultAdopted: $vaultAdopted)';
  }
}
