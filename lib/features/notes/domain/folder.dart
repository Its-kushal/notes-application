import '../../../core/crypto/id_generator.dart';

/// Folder entity mapping directly to the SQLite `folders` table.
class Folder {
  final String id;
  final String name;
  final int? color;
  final int createdAt;
  final int updatedAt;

  const Folder({
    required this.id,
    required this.name,
    this.color,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Folder.create({
    String? id,
    required String name,
    int? color,
  }) {
    final now = DateTime.now().millisecondsSinceEpoch;
    return Folder(
      id: id ?? IdGenerator.generateUuidV4(),
      name: name,
      color: color,
      createdAt: now,
      updatedAt: now,
    );
  }

  Folder copyWith({
    String? id,
    String? name,
    int? color,
    int? createdAt,
    int? updatedAt,
  }) {
    return Folder(
      id: id ?? this.id,
      name: name ?? this.name,
      color: color ?? this.color,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? DateTime.now().millisecondsSinceEpoch,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'color': color,
      'created_at': createdAt,
      'updated_at': updatedAt,
    };
  }

  factory Folder.fromMap(Map<String, dynamic> map) {
    return Folder(
      id: map['id'] as String,
      name: map['name'] as String,
      color: map['color'] as int?,
      createdAt: map['created_at'] as int,
      updatedAt: map['updated_at'] as int,
    );
  }
}
