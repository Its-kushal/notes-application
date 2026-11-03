/// Model representing a file opened from an external app.
class OpenedFile {
  final String name;
  final String text;
  final String? error;
  final bool hasInvalidBytes;
  final bool isFromExternalApp;

  const OpenedFile({
    required this.name,
    required this.text,
    this.error,
    this.hasInvalidBytes = false,
    this.isFromExternalApp = true,
  });

  bool get isSuccess => error == null;

  factory OpenedFile.fromMap(Map<dynamic, dynamic> map, {bool isFromExternalApp = true}) {
    return OpenedFile(
      name: map['name'] as String? ?? 'Untitled Note',
      text: map['text'] as String? ?? '',
      error: map['error'] as String?,
      hasInvalidBytes: map['hasInvalidBytes'] as bool? ?? false,
      isFromExternalApp: isFromExternalApp,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'text': text,
      'error': error,
      'hasInvalidBytes': hasInvalidBytes,
      'isFromExternalApp': isFromExternalApp,
    };
  }
}
