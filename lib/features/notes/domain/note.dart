import 'dart:typed_data';
import '../../../core/crypto/id_generator.dart';

/// Note domain entity mapping directly to the SQLite `notes` table.
class Note {
  final String id;
  final String title;
  final String body;
  final String? checklistJson;
  final bool isChecklistMode;
  final String? folderId;
  final int colorLabel;
  final bool isPinned;
  final bool isArchived;
  final bool isLocked;
  final int? trashedAt;
  final Uint8List? encryptedPayload;
  final Uint8List? payloadIv;
  final Uint8List? payloadTag;
  final int payloadFormatVersion;
  final int createdAt;
  final int updatedAt;
  final int wordCount;

  const Note({
    required this.id,
    required this.title,
    required this.body,
    this.checklistJson,
    this.isChecklistMode = false,
    this.folderId,
    this.colorLabel = 0,
    this.isPinned = false,
    this.isArchived = false,
    this.isLocked = false,
    this.trashedAt,
    this.encryptedPayload,
    this.payloadIv,
    this.payloadTag,
    this.payloadFormatVersion = 1,
    required this.createdAt,
    required this.updatedAt,
    required this.wordCount,
  });

  bool get isTrashed => trashedAt != null;

  /// Creates a new note with a fresh RFC 4122 UUID v4 and timestamps.
  factory Note.create({
    String? id,
    String title = '',
    String body = '',
    String? checklistJson,
    bool isChecklistMode = false,
    String? folderId,
    int colorLabel = 0,
    bool isPinned = false,
    bool isArchived = false,
  }) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final generatedId = id ?? IdGenerator.generateUuidV4();
    final count = calculateWordCount(body);

    return Note(
      id: generatedId,
      title: title,
      body: body,
      checklistJson: checklistJson,
      isChecklistMode: isChecklistMode,
      folderId: folderId,
      colorLabel: colorLabel,
      isPinned: isPinned,
      isArchived: isArchived,
      isLocked: false,
      trashedAt: null,
      encryptedPayload: null,
      payloadIv: null,
      payloadTag: null,
      payloadFormatVersion: 1,
      createdAt: now,
      updatedAt: now,
      wordCount: count,
    );
  }

  static int calculateWordCount(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return 0;
    return trimmed.split(RegExp(r'\s+')).length;
  }

  Note copyWith({
    String? id,
    String? title,
    String? body,
    String? checklistJson,
    bool? isChecklistMode,
    String? folderId,
    bool clearFolderId = false,
    int? colorLabel,
    bool? isPinned,
    bool? isArchived,
    bool? isLocked,
    int? trashedAt,
    bool clearTrashedAt = false,
    Uint8List? encryptedPayload,
    Uint8List? payloadIv,
    Uint8List? payloadTag,
    int? payloadFormatVersion,
    int? createdAt,
    int? updatedAt,
    int? wordCount,
  }) {
    final newBody = body ?? this.body;
    return Note(
      id: id ?? this.id,
      title: title ?? this.title,
      body: newBody,
      checklistJson: checklistJson ?? this.checklistJson,
      isChecklistMode: isChecklistMode ?? this.isChecklistMode,
      folderId: clearFolderId ? null : (folderId ?? this.folderId),
      colorLabel: colorLabel ?? this.colorLabel,
      isPinned: isPinned ?? this.isPinned,
      isArchived: isArchived ?? this.isArchived,
      isLocked: isLocked ?? this.isLocked,
      trashedAt: clearTrashedAt ? null : (trashedAt ?? this.trashedAt),
      encryptedPayload: encryptedPayload ?? this.encryptedPayload,
      payloadIv: payloadIv ?? this.payloadIv,
      payloadTag: payloadTag ?? this.payloadTag,
      payloadFormatVersion: payloadFormatVersion ?? this.payloadFormatVersion,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? DateTime.now().millisecondsSinceEpoch,
      wordCount: wordCount ?? calculateWordCount(newBody),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'body': body,
      'checklist_json': checklistJson,
      'is_checklist_mode': isChecklistMode ? 1 : 0,
      'folder_id': folderId,
      'color_label': colorLabel,
      'is_pinned': isPinned ? 1 : 0,
      'is_archived': isArchived ? 1 : 0,
      'is_locked': isLocked ? 1 : 0,
      'trashed_at': trashedAt,
      'encrypted_payload': encryptedPayload,
      'payload_iv': payloadIv,
      'payload_tag': payloadTag,
      'payload_format_version': payloadFormatVersion,
      'created_at': createdAt,
      'updated_at': updatedAt,
      'word_count': wordCount,
    };
  }

  factory Note.fromMap(Map<String, dynamic> map) {
    return Note(
      id: map['id'] as String,
      title: map['title'] as String? ?? '',
      body: map['body'] as String? ?? '',
      checklistJson: map['checklist_json'] as String?,
      isChecklistMode: (map['is_checklist_mode'] as int? ?? 0) == 1,
      folderId: map['folder_id'] as String?,
      colorLabel: map['color_label'] as int? ?? 0,
      isPinned: (map['is_pinned'] as int? ?? 0) == 1,
      isArchived: (map['is_archived'] as int? ?? 0) == 1,
      isLocked: (map['is_locked'] as int? ?? 0) == 1,
      trashedAt: map['trashed_at'] as int?,
      encryptedPayload: map['encrypted_payload'] != null
          ? (map['encrypted_payload'] is Uint8List
              ? map['encrypted_payload'] as Uint8List
              : Uint8List.fromList(List<int>.from(map['encrypted_payload'] as List)))
          : null,
      payloadIv: map['payload_iv'] != null
          ? (map['payload_iv'] is Uint8List
              ? map['payload_iv'] as Uint8List
              : Uint8List.fromList(List<int>.from(map['payload_iv'] as List)))
          : null,
      payloadTag: map['payload_tag'] != null
          ? (map['payload_tag'] is Uint8List
              ? map['payload_tag'] as Uint8List
              : Uint8List.fromList(List<int>.from(map['payload_tag'] as List)))
          : null,
      payloadFormatVersion: map['payload_format_version'] as int? ?? 1,
      createdAt: map['created_at'] as int,
      updatedAt: map['updated_at'] as int,
      wordCount: map['word_count'] as int? ?? 0,
    );
  }
}
