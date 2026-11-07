import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import '../domain/file_decoder.dart';

/// Service responsible for receiving files opened via Android ACTION_VIEW intents
/// from Kotlin over the com.privacynotes.app/security channel and navigating
/// to FileViewerScreen.
class FileIntentService {
  final MethodChannel channel;
  final GoRouter router;
  bool _listening = false;

  FileIntentService({
    required this.router,
    this.channel = const MethodChannel('com.privacynotes.app/security'),
  });

  /// Starts listening for warm-start file intents and checks for any cold-start intent.
  void startListening() {
    if (_listening) return;
    _listening = true;

    channel.setMethodCallHandler((call) async {
      if (call.method == 'onFileOpened') {
        final arguments = call.arguments;
        if (arguments is Map) {
          final file = FileDecoder.decodePayload(arguments, isFromExternalApp: true);
          router.push('/file-viewer', extra: file);
        }
      }
    });

    checkInitialFile();
  }

  /// Checks if a file was pending from cold-start intent.
  Future<void> checkInitialFile() async {
    try {
      final result = await channel.invokeMethod<dynamic>('getInitialFile');
      if (result is Map) {
        final file = FileDecoder.decodePayload(result, isFromExternalApp: true);
        router.push('/file-viewer', extra: file);
      }
    } catch (_) {}
  }

  /// Closes the viewer and returns to the calling app via native exitExternalViewer.
  Future<void> exitExternalViewer() async {
    try {
      await channel.invokeMethod('exitExternalViewer');
    } catch (_) {}
  }
}
