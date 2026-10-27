import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neostation/services/update_service.dart';
import 'package:neostation/utils/chunked_file_writer.dart';

/// The app update was written through an IOSink. When a write failed (a full
/// disk), the error went unhandled, the rest of the download still came in
/// and was dropped, and the partial file stayed in the temporary folder. It
/// now stops at the failed write and removes what it wrote.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
  late Directory temp;
  late HttpServer server;
  HttpOverrides? previousOverrides;
  const chunk = 64 * 1024;
  const chunks = 64; // 4 MiB

  setUp(() async {
    // The test binding fakes HTTP; this test needs a real loopback server.
    previousOverrides = HttpOverrides.current;
    HttpOverrides.global = null;
    temp = await Directory.systemTemp.createTemp('neostation_update_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProvider, (call) async => temp.path);
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      request.response.contentLength = chunk * chunks;
      try {
        for (var i = 0; i < chunks; i++) {
          request.response.add(List<int>.filled(chunk, 7));
          await request.response.flush();
        }
        await request.response.close();
      } catch (_) {
        // The client went away.
      }
    });
  });

  tearDown(() async {
    openFileForChunks = defaultOpenFileForChunks;
    HttpOverrides.global = previousOverrides;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProvider, null);
    await server.close(force: true);
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  test(
    'a failed write stops the download and leaves no partial file',
    () async {
      final diskFull = FileSystemException(
        'No space left on device',
        '',
        const OSError('No space left on device', 28),
      );
      openFileForChunks = (file) async {
        final handle = await defaultOpenFileForChunks(file);
        return _FailingAfterFirstWrite(handle, diskFull);
      };
      final progress = <double>[];
      final uncaught = <Object>[];

      final file = await runZonedGuarded(
        () => UpdateService.downloadUpdateFile(
          'http://${server.address.host}:${server.port}/neostation.AppImage',
          'neostation.AppImage',
          progress.add,
        ),
        (error, _) => uncaught.add(error),
      );

      expect(file, isNull);
      expect(uncaught, isEmpty, reason: 'the write error went unhandled');
      expect(
        File('${temp.path}/neostation.AppImage').existsSync(),
        isFalse,
        reason: 'the partial download was kept',
      );
      expect(
        progress.isEmpty ? 0.0 : progress.last,
        lessThan(1.0),
        reason: 'the download carried on after the failed write',
      );
    },
  );
}

/// A file whose writes fail after the first one, as a disk filling up.
class _FailingAfterFirstWrite implements RandomAccessFile {
  _FailingAfterFirstWrite(this._inner, this._error);

  final RandomAccessFile _inner;
  final Object _error;
  var _writes = 0;

  @override
  Future<RandomAccessFile> writeFrom(
    List<int> buffer, [
    int start = 0,
    int? end,
  ]) async {
    if (_writes++ > 0) throw _error;
    await _inner.writeFrom(buffer, start, end);
    return this;
  }

  @override
  Future<void> close() => _inner.close();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
