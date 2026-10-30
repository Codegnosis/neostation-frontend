import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:neostation/services/neosync/neo_sync_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

// NeoSync's requests had no time limit. A server that took the connection and
// then said nothing (or a route that dropped mid-request) left the save list
// on "Refreshing..." and a game's sync on "syncing" for as long as the socket
// lived, which against a silent server is for ever.

/// Never answers, and records each request's abort trigger firing.
class _SilentClient extends http.BaseClient {
  int aborted = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    if (request is http.Abortable) {
      request.abortTrigger?.then((_) => aborted++);
    }
    return Completer<http.StreamedResponse>().future;
  }
}

/// Sends its headers at once, then never the body.
class _StallingClient extends http.BaseClient {
  int aborted = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request is http.Abortable) {
      request.abortTrigger?.then((_) => aborted++);
    }
    return http.StreamedResponse(StreamController<List<int>>().stream, 200);
  }
}

/// Answers every request at once with [body].
class _QuickClient extends http.BaseClient {
  _QuickClient(this.body);

  final String body;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async =>
      http.StreamedResponse(Stream.value(body.codeUnits), 200);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  const limit = Duration(milliseconds: 200);

  final calls = <String, Future<Map<String, dynamic>> Function(NeoSyncService)>{
    'listing the files': (s) => s.getFiles(),
    'listing every file': (s) => s.getAllFiles(),
    'loading the quota': (s) => s.getQuota(),
    'deleting a file': (s) => s.deleteFile('save-1'),
    'requesting a download': (s) => s.downloadFile('save-1'),
  };

  for (final MapEntry(key: name, value: call) in calls.entries) {
    test('$name gives up when the server never answers', () async {
      final client = _SilentClient();
      final service = NeoSyncService(client: client, requestTimeout: limit);

      final result = await call(service).timeout(const Duration(seconds: 5));

      expect(result['success'], isFalse);
      await pumpEventQueue();
      expect(client.aborted, 1, reason: 'the connection is closed');
    });
  }

  test('checking a file gives up when the server never answers, and says '
      'it timed out', () async {
    final client = _SilentClient();
    final service = NeoSyncService(client: client, requestTimeout: limit);

    final result = await service
        .checkFileExists('game.srm', 'hash', 4)
        .timeout(const Duration(seconds: 5));

    expect(result['timed_out'], isTrue);
    await pumpEventQueue();
    expect(client.aborted, 1);
  });

  test('a file check that timed out uploads nothing', () async {
    // The cloud copy may be newer; no answer is no reason to replace it.
    final dir = await Directory.systemTemp.createTemp('neosync_timeout_');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/game.srm')..writeAsBytesSync([1, 2, 3]);
    final service = NeoSyncService(
      client: _SilentClient(),
      requestTimeout: limit,
    );

    final result = await service
        .syncFile(file, 'Game')
        .timeout(const Duration(seconds: 5));

    expect(result['success'], isFalse);
    expect(result['message'], contains('did not answer the file check'));
  });

  test('a server that sends its headers and then stalls is given up '
      'on', () async {
    final client = _StallingClient();
    final service = NeoSyncService(client: client, requestTimeout: limit);

    final result = await service.getQuota().timeout(const Duration(seconds: 5));

    expect(result['success'], isFalse);
    await pumpEventQueue();
    expect(client.aborted, 1);
  });

  test('a server that answers in time is unaffected', () async {
    final service = NeoSyncService(
      client: _QuickClient(
        '{"files": [], "total": 0, "systems": [], "emulators": []}',
      ),
      requestTimeout: limit,
    );

    final result = await service.getFiles();

    expect(result['success'], isTrue);
    expect(result['total'], 0);
  });

  test('requests wait 15 seconds by default', () {
    expect(NeoSyncService.defaultRequestTimeout, const Duration(seconds: 15));
  });
}
