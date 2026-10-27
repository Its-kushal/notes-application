import 'package:flutter/services.dart';

/// Service managing Android window FLAG_SECURE via MethodChannel.
/// Ensures FLAG_SECURE is active only while sensitive screens (vault setup,
/// unlock, locked list, or locked note editor) are visible.
class SecurityWindowService {
  static const MethodChannel _channel = MethodChannel('com.privacynotes.app/security');
  static int _activeSecureContexts = 0;

  static int get activeSecureContexts => _activeSecureContexts;

  /// Enables FLAG_SECURE on the native window.
  static Future<void> enableSecure() async {
    _activeSecureContexts++;
    if (_activeSecureContexts == 1) {
      try {
        await _channel.invokeMethod('enableSecureWindow');
      } catch (_) {}
    }
  }

  /// Disables FLAG_SECURE when no secure screens remain active.
  static Future<void> disableSecure() async {
    if (_activeSecureContexts > 0) {
      _activeSecureContexts--;
    }
    if (_activeSecureContexts == 0) {
      try {
        await _channel.invokeMethod('disableSecureWindow');
      } catch (_) {}
    }
  }

  /// Resets state (primarily for tests).
  static Future<void> reset() async {
    _activeSecureContexts = 0;
    try {
      await _channel.invokeMethod('disableSecureWindow');
    } catch (_) {}
  }
}
