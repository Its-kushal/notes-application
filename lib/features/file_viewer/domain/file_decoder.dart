import 'dart:convert';
import 'dart:typed_data';
import 'opened_file.dart';

/// Result of decoding a file.
class FileDecodeResult {
  final String? text;
  final String? error;
  final bool hasInvalidBytes;

  const FileDecodeResult({
    this.text,
    this.error,
    this.hasInvalidBytes = false,
  });

  bool get isSuccess => error == null && text != null;
}

/// Standalone decoder for files opened from external sources.
/// Enforces size limits, BOM detection, UTF-8/UTF-16 decoding,
/// binary rejection, line normalization, and title extraction.
class FileDecoder {
  /// Maximum allowed file size: 2 MB (2,097,152 bytes).
  static const int maxFileBytes = 2 * 1024 * 1024;

  /// Error codes for friendly error states.
  static const String errorTooLarge = 'TOO_LARGE';
  static const String errorBinary = 'BINARY';
  static const String errorEmpty = 'EMPTY';
  static const String errorUnreadable = 'UNREADABLE';

  /// Decodes a raw byte buffer according to M4.6 rules.
  static FileDecodeResult decodeBytes(Uint8List bytes) {
    if (bytes.length > maxFileBytes) {
      return const FileDecodeResult(
        error: errorTooLarge,
      );
    }

    if (bytes.isEmpty) {
      return const FileDecodeResult(
        text: '',
        error: errorEmpty,
      );
    }

    String? decodedText;
    bool hasInvalidBytes = false;

    // Check BOMs
    if (bytes.length >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF) {
      // UTF-16 BE BOM
      decodedText = _decodeUtf16Be(bytes.sublist(2));
    } else if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE) {
      // UTF-16 LE BOM
      decodedText = _decodeUtf16Le(bytes.sublist(2));
    } else if (bytes.length >= 3 &&
        bytes[0] == 0xEF &&
        bytes[1] == 0xBB &&
        bytes[2] == 0xBF) {
      // UTF-8 BOM
      final contentBytes = bytes.sublist(3);
      final utf8Result = _decodeUtf8(contentBytes);
      decodedText = utf8Result.text;
      hasInvalidBytes = utf8Result.hasInvalidBytes;
    } else {
      // No BOM: Check for NUL byte in raw bytes (reject binary file)
      for (int i = 0; i < bytes.length; i++) {
        if (bytes[i] == 0) {
          return const FileDecodeResult(
            error: errorBinary,
          );
        }
      }

      final utf8Result = _decodeUtf8(bytes);
      decodedText = utf8Result.text;
      hasInvalidBytes = utf8Result.hasInvalidBytes;
    }

    if (decodedText == null) {
      return const FileDecodeResult(
        error: errorUnreadable,
      );
    }

    // Check if decoded text contains NUL character (e.g. from UTF-16 encoded binary)
    if (decodedText.contains('\u0000')) {
      return const FileDecodeResult(
        error: errorBinary,
      );
    }

    // Line ending normalization: CRLF -> LF, CR -> LF
    final normalized = decodedText.replaceAll('\r\n', '\n').replaceAll('\r', '\n');

    return FileDecodeResult(
      text: normalized,
      error: null,
      hasInvalidBytes: hasInvalidBytes,
    );
  }

  static ({String? text, bool hasInvalidBytes}) _decodeUtf8(Uint8List bytes) {
    try {
      final text = const Utf8Decoder(allowMalformed: false).convert(bytes);
      return (text: text, hasInvalidBytes: false);
    } on FormatException {
      final text = const Utf8Decoder(allowMalformed: true).convert(bytes);
      return (text: text, hasInvalidBytes: true);
    } catch (_) {
      return (text: null, hasInvalidBytes: false);
    }
  }

  static String _decodeUtf16Le(Uint8List bytes) {
    final buffer = StringBuffer();
    for (int i = 0; i + 1 < bytes.length; i += 2) {
      final codeUnit = bytes[i] | (bytes[i + 1] << 8);
      buffer.writeCharCode(codeUnit);
    }
    return buffer.toString();
  }

  static String _decodeUtf16Be(Uint8List bytes) {
    final buffer = StringBuffer();
    for (int i = 0; i + 1 < bytes.length; i += 2) {
      final codeUnit = (bytes[i] << 8) | bytes[i + 1];
      buffer.writeCharCode(codeUnit);
    }
    return buffer.toString();
  }

  /// Decodes a payload received from native platform or fake channel.
  /// Expects:
  /// - 'name': String? (display name)
  /// - 'bytes': `Uint8List?` or `List<int>?` (raw content bytes)
  /// - 'error': String? (read error, if any)
  static OpenedFile decodePayload(
    Map<dynamic, dynamic> map, {
    bool isFromExternalApp = true,
  }) {
    final name = (map['name'] as String?)?.trim();
    final displayName = (name != null && name.isNotEmpty) ? name : 'Untitled Note';
    final error = map['error'] as String?;
    if (error != null) {
      return OpenedFile(
        name: displayName,
        text: '',
        error: error,
        hasInvalidBytes: false,
        isFromExternalApp: isFromExternalApp,
      );
    }

    final rawBytes = map['bytes'];
    if (rawBytes == null) {
      final directText = map['text'] as String?;
      if (directText != null) {
        return OpenedFile(
          name: displayName,
          text: directText,
          error: map['error'] as String?,
          hasInvalidBytes: map['hasInvalidBytes'] as bool? ?? false,
          isFromExternalApp: isFromExternalApp,
        );
      }
      return OpenedFile(
        name: displayName,
        text: '',
        error: errorUnreadable,
        hasInvalidBytes: false,
        isFromExternalApp: isFromExternalApp,
      );
    }

    final Uint8List bytes;
    if (rawBytes is Uint8List) {
      bytes = rawBytes;
    } else if (rawBytes is List) {
      bytes = Uint8List.fromList(rawBytes.cast<int>());
    } else {
      return OpenedFile(
        name: displayName,
        text: '',
        error: errorUnreadable,
        hasInvalidBytes: false,
        isFromExternalApp: isFromExternalApp,
      );
    }

    final result = decodeBytes(bytes);
    return OpenedFile(
      name: displayName,
      text: result.text ?? '',
      error: result.error,
      hasInvalidBytes: result.hasInvalidBytes,
      isFromExternalApp: isFromExternalApp,
    );
  }

  static final RegExp _knownTextExtensionRegex = RegExp(
    r'\.(txt|md|markdown|text)$',
    caseSensitive: false,
  );

  /// Extracts the note title from the file display name according to M4.6 rules:
  /// - Strips ONLY known text extensions (.txt, .md, .markdown, .text)
  /// - Preserves dots that are part of the title (e.g. 'Meeting 3.5 summary' -> 'Meeting 3.5 summary')
  /// - Strips known extension when present (e.g. 'Meeting 3.5 summary.txt' -> 'Meeting 3.5 summary')
  /// - If the result is blank (e.g. '.txt' or empty), falls back to 'Untitled Note'
  static String extractTitle(String? fileName) {
    if (fileName == null) {
      return 'Untitled Note';
    }
    final trimmed = fileName.trim();
    if (trimmed.isEmpty) {
      return 'Untitled Note';
    }

    final match = _knownTextExtensionRegex.firstMatch(trimmed);
    final base = (match != null) ? trimmed.substring(0, match.start).trim() : trimmed;
    return base.isEmpty ? 'Untitled Note' : base;
  }

  /// Caps the body text to 2 MB limit for saving.
  static String capBody(String body) {
    if (body.length <= maxFileBytes) {
      return body;
    }
    return body.substring(0, maxFileBytes);
  }
}
