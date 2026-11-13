import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:leaflock/features/file_viewer/domain/file_decoder.dart';
import 'package:leaflock/features/file_viewer/domain/opened_file.dart';
import 'package:leaflock/features/file_viewer/services/file_intent_service.dart';

class MockGoRouter implements GoRouter {
  final List<String> pushedLocations = [];
  final List<dynamic> pushedExtras = [];

  @override
  Future<T?> push<T extends Object?>(String location, {Object? extra}) async {
    pushedLocations.add(location);
    pushedExtras.add(extra);
    return null;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockGoRouter mockRouter;
  late MethodChannel channel;
  final List<MethodCall> log = [];
  Map<String, dynamic>? initialFileResponse;

  setUp(() {
    mockRouter = MockGoRouter();
    channel = const MethodChannel('com.leaflock.app/security_test');
    log.clear();
    initialFileResponse = null;

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      log.add(call);
      if (call.method == 'getInitialFile') {
        return initialFileResponse;
      } else if (call.method == 'exitExternalViewer') {
        return true;
      }
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  group('FileIntentService - Production Path Fake Channel Tests (C1)', () {
    test('cold-start: channel supplies UTF-8 with BOM bytes', () async {
      final bom = [0xEF, 0xBB, 0xBF];
      final textBytes = utf8.encode('BOM Header\r\nLine 2');
      initialFileResponse = {
        'name': 'bom_doc.txt',
        'bytes': Uint8List.fromList([...bom, ...textBytes]),
        'error': null,
      };

      final service = FileIntentService(
        router: mockRouter,
        channel: channel,
      );

      service.startListening();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(log.any((call) => call.method == 'getInitialFile'), isTrue);
      expect(mockRouter.pushedLocations, contains('/file-viewer'));
      final opened = mockRouter.pushedExtras.first as OpenedFile;
      expect(opened.name, equals('bom_doc.txt'));
      expect(opened.text, equals('BOM Header\nLine 2'));
      expect(opened.hasInvalidBytes, isFalse);
      expect(opened.error, isNull);
      expect(opened.isFromExternalApp, isTrue);
    });

    test('cold-start: channel supplies UTF-16 LE bytes', () async {
      final bom = [0xFF, 0xFE];
      // "Hi\r\nBye" in UTF-16 LE
      final leBytes = [
        0x48, 0x00, // H
        0x69, 0x00, // i
        0x0D, 0x00, // \r
        0x0A, 0x00, // \n
        0x42, 0x00, // B
        0x79, 0x00, // y
        0x65, 0x00, // e
      ];
      initialFileResponse = {
        'name': 'utf16_le.txt',
        'bytes': Uint8List.fromList([...bom, ...leBytes]),
        'error': null,
      };

      final service = FileIntentService(
        router: mockRouter,
        channel: channel,
      );

      service.startListening();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final opened = mockRouter.pushedExtras.first as OpenedFile;
      expect(opened.name, equals('utf16_le.txt'));
      expect(opened.text, equals('Hi\nBye'));
      expect(opened.hasInvalidBytes, isFalse);
      expect(opened.error, isNull);
    });

    test('cold-start: channel supplies UTF-16 BE bytes', () async {
      final bom = [0xFE, 0xFF];
      // "Hi" in UTF-16 BE
      final beBytes = [
        0x00, 0x48, // H
        0x00, 0x69, // i
      ];
      initialFileResponse = {
        'name': 'utf16_be.txt',
        'bytes': Uint8List.fromList([...bom, ...beBytes]),
        'error': null,
      };

      final service = FileIntentService(
        router: mockRouter,
        channel: channel,
      );

      service.startListening();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final opened = mockRouter.pushedExtras.first as OpenedFile;
      expect(opened.name, equals('utf16_be.txt'));
      expect(opened.text, equals('Hi'));
      expect(opened.error, isNull);
    });

    test('channel supplies invalid bytes with replacement char and warning', () async {
      final bytes = Uint8List.fromList([0x48, 0x65, 0xFF, 0x6C, 0x6F]);
      initialFileResponse = {
        'name': 'corrupted.txt',
        'bytes': bytes,
        'error': null,
      };

      final service = FileIntentService(
        router: mockRouter,
        channel: channel,
      );

      service.startListening();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final opened = mockRouter.pushedExtras.first as OpenedFile;
      expect(opened.text, equals('He\uFFFDlo'));
      expect(opened.hasInvalidBytes, isTrue);
      expect(opened.error, isNull);
    });

    test('channel supplies exactly 2 MB bytes (passes)', () async {
      const size = 2 * 1024 * 1024;
      final bytes = Uint8List(size)..fillRange(0, size, 0x61);
      initialFileResponse = {
        'name': 'exact_2mb.txt',
        'bytes': bytes,
        'error': null,
      };

      final service = FileIntentService(
        router: mockRouter,
        channel: channel,
      );

      service.startListening();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final opened = mockRouter.pushedExtras.first as OpenedFile;
      expect(opened.error, isNull);
      expect(opened.text.length, equals(size));
    });

    test('channel supplies 2 MB + 1 byte (fails with TOO_LARGE)', () async {
      const size = 2 * 1024 * 1024 + 1;
      final bytes = Uint8List(size)..fillRange(0, size, 0x61);
      initialFileResponse = {
        'name': 'over_2mb.txt',
        'bytes': bytes,
        'error': null,
      };

      final service = FileIntentService(
        router: mockRouter,
        channel: channel,
      );

      service.startListening();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final opened = mockRouter.pushedExtras.first as OpenedFile;
      expect(opened.error, equals(FileDecoder.errorTooLarge));
      expect(opened.text, isEmpty);
    });

    test('does not route when cold-start initial file is null', () async {
      initialFileResponse = null;

      final service = FileIntentService(
        router: mockRouter,
        channel: channel,
      );

      service.startListening();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(log.any((call) => call.method == 'getInitialFile'), isTrue);
      expect(mockRouter.pushedLocations, isEmpty);
    });

    test('warm-start: onFileOpened method call decodes raw bytes', () async {
      final service = FileIntentService(
        router: mockRouter,
        channel: channel,
      );

      service.startListening();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      mockRouter.pushedLocations.clear();
      mockRouter.pushedExtras.clear();

      final warmPayload = {
        'name': 'warm_doc.md',
        'bytes': Uint8List.fromList(utf8.encode('# Warm Start\r\nOpened live')),
        'error': null,
      };

      final byteData = const StandardMethodCodec().encodeMethodCall(
        MethodCall('onFileOpened', warmPayload),
      );

      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage('com.leaflock.app/security_test', byteData, (_) {});

      expect(mockRouter.pushedLocations, contains('/file-viewer'));
      final opened = mockRouter.pushedExtras.first as OpenedFile;
      expect(opened.name, equals('warm_doc.md'));
      expect(opened.text, equals('# Warm Start\nOpened live'));
      expect(opened.error, isNull);
    });

    test('exitExternalViewer invokes native exitExternalViewer channel method', () async {
      final service = FileIntentService(
        router: mockRouter,
        channel: channel,
      );

      await service.exitExternalViewer();

      expect(log.any((call) => call.method == 'exitExternalViewer'), isTrue);
    });
  });
}
