import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:neostation/services/update_service.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// The app update was installed without checking it was the file the release
/// lists: a captive portal's page, a proxy's error or a damaged download went
/// to the installer, and on Linux replaced the working AppImage. Downloads
/// were also never removed, and Linux without an AppImage was offered an
/// update it could only fail to install, after downloading all of it.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
  late Directory temp;
  late HttpServer server;
  HttpOverrides? previousOverrides;
  const chunk = 64 * 1024;
  const chunks = 16; // 1 MiB
  final body = List<int>.filled(chunk * chunks, 7);
  final bodySha256 = sha256.convert(body).toString();

  setUp(() async {
    // The test binding fakes HTTP; this test needs a real loopback server.
    previousOverrides = HttpOverrides.current;
    HttpOverrides.global = null;
    temp = await Directory.systemTemp.createTemp('neostation_update_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProvider, (call) async => temp.path);
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final path = request.uri.path;
      // Without a Content-Length the body arrives chunked, and a short one
      // isn't noticed by the HTTP client.
      if (!path.startsWith('/nolen')) {
        request.response.contentLength = body.length;
      }
      final sent = switch (path) {
        '/nolen-short' => body.length ~/ 2,
        '/nolen-long' => body.length * 2,
        _ => body.length,
      };
      try {
        for (var i = 0; i < sent; i += chunk) {
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
    UpdateService.environment = () => Platform.environment;
    UpdateService.debugUseHttpClient(null);
    HttpOverrides.global = previousOverrides;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProvider, null);
    await server.close(force: true);
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  String url(String path) =>
      'http://${server.address.host}:${server.port}$path';

  File downloaded() => File('${temp.path}/neostation.AppImage');

  group('the download is checked against the release', () {
    test('a file matching the release size and SHA-256 is kept', () async {
      final file = await UpdateService.downloadUpdateFile(
        url('/full'),
        'neostation.AppImage',
        null,
        expectedSize: body.length,
        expectedSha256: bodySha256,
      );

      expect(file, isNotNull);
      expect(downloaded().existsSync(), isTrue);
    });

    test('a different SHA-256 fails the download and removes it', () async {
      final file = await UpdateService.downloadUpdateFile(
        url('/full'),
        'neostation.AppImage',
        null,
        expectedSize: body.length,
        expectedSha256: '0' * 64,
      );

      expect(file, isNull);
      expect(downloaded().existsSync(), isFalse);
    });

    test('a short body without a Content-Length fails the download', () async {
      final file = await UpdateService.downloadUpdateFile(
        url('/nolen-short'),
        'neostation.AppImage',
        null,
        expectedSize: body.length,
      );

      expect(file, isNull);
      expect(downloaded().existsSync(), isFalse);
    });

    test('a longer body without a Content-Length stops at the size', () async {
      final progress = <double>[];

      final file = await UpdateService.downloadUpdateFile(
        url('/nolen-long'),
        'neostation.AppImage',
        progress.add,
        expectedSize: body.length,
      );

      expect(file, isNull);
      expect(downloaded().existsSync(), isFalse);
      // Past 100% the dialogue hides Cancel and says it's installing.
      expect(progress.where((p) => p > 1.0), isEmpty);
    });

    test('a server announcing another size fails before downloading', () async {
      final progress = <double>[];

      final file = await UpdateService.downloadUpdateFile(
        url('/full'),
        'neostation.AppImage',
        progress.add,
        expectedSize: body.length * 2,
      );

      expect(file, isNull);
      expect(progress, isEmpty);
      expect(downloaded().existsSync(), isFalse);
    });

    test('without a SHA-256 the right size is enough', () async {
      final file = await UpdateService.downloadUpdateFile(
        url('/full'),
        'neostation.AppImage',
        null,
        expectedSize: body.length,
      );

      expect(file, isNotNull);
    });

    test('progress is shown when the server sends no length', () async {
      final progress = <double>[];

      await UpdateService.downloadUpdateFile(
        url('/nolen'),
        'neostation.AppImage',
        progress.add,
        expectedSize: body.length,
      );

      expect(progress, isNotEmpty);
      expect(progress.last, 1.0);
    });

    test('a damaged download is reported as a download failure', () async {
      // Never let a test reach the Linux installer with a real APPIMAGE.
      UpdateService.environment = () => {'HOME': '/home/user'};

      final outcome = await UpdateService.downloadAndInstall(
        UpdateInfo(
          currentVersion: '0.1.0',
          latestVersion: '99.0.0',
          downloadUrl: url('/full'),
          fileName: 'neostation.AppImage',
          fileSize: body.length,
          sha256: '0' * 64,
        ),
        null,
      );

      expect(outcome, UpdateOutcome.downloadFailed);
      expect(downloaded().existsSync(), isFalse);
    });
  });

  test('a download of the wrong size is reported as a failure', () async {
    // A release without a digest still has its size checked.
    UpdateService.environment = () => {'HOME': '/home/user'};

    final outcome = await UpdateService.downloadAndInstall(
      UpdateInfo(
        currentVersion: '0.1.0',
        latestVersion: '99.0.0',
        downloadUrl: url('/nolen'),
        fileName: 'neostation.AppImage',
        fileSize: body.length + 1,
      ),
      null,
    );

    expect(outcome, UpdateOutcome.downloadFailed);
    expect(downloaded().existsSync(), isFalse);
  });

  group('the release digest', () {
    test('gives the SHA-256 in lower case', () {
      expect(UpdateService.sha256FromDigest('sha256:${'AB' * 32}'), 'ab' * 32);
    });

    test('is ignored when missing or not a SHA-256', () {
      expect(UpdateService.sha256FromDigest(null), isNull);
      expect(UpdateService.sha256FromDigest(''), isNull);
      expect(UpdateService.sha256FromDigest('md5:${'a' * 32}'), isNull);
      expect(UpdateService.sha256FromDigest('sha256:abc'), isNull);
      expect(UpdateService.sha256FromDigest('sha256:${'g' * 64}'), isNull);
    });
  });

  group('on Linux', () {
    final requests = <Uri>[];

    setUp(() {
      requests.clear();
      PackageInfo.setMockInitialValues(
        appName: 'NeoStation',
        packageName: 'neostation',
        version: '0.1.0',
        buildNumber: '1',
        buildSignature: '',
      );
      UpdateService.debugUseHttpClient(
        MockClient((request) async {
          requests.add(request.url);
          return http.Response(
            jsonEncode({
              'tag_name': 'v99.0.0+1',
              'body': 'Notes',
              'assets': [
                for (final arch in ['x86_64', 'arm64'])
                  {
                    'name': 'neostation-linux-$arch-99.0.0+1.AppImage',
                    'browser_download_url': url('/full'),
                    'size': body.length,
                    'digest': 'sha256:$bodySha256',
                  },
              ],
            }),
            200,
          );
        }),
      );
    });

    test('no update is offered when not running from an AppImage', () async {
      UpdateService.environment = () => {'HOME': '/home/user'};

      final info = await UpdateService.checkForUpdates();

      expect(info, isNull);
      expect(requests, isEmpty, reason: 'it still asked GitHub');
    }, skip: !Platform.isLinux);

    test('an empty APPIMAGE counts as not running from one', () async {
      UpdateService.environment = () => {'APPIMAGE': ''};

      expect(await UpdateService.checkForUpdates(), isNull);
      expect(requests, isEmpty);
    }, skip: !Platform.isLinux);

    test('an update from an AppImage carries the release SHA-256', () async {
      UpdateService.environment = () => {'APPIMAGE': '/apps/neo.AppImage'};

      final info = await UpdateService.checkForUpdates();

      expect(info, isNotNull);
      expect(info!.sha256, bodySha256);
      expect(info.fileSize, body.length);
    }, skip: !Platform.isLinux);

    test('a download that failed to install is removed', () async {
      // Without APPIMAGE the Linux installer refuses.
      UpdateService.environment = () => {'HOME': '/home/user'};

      final outcome = await UpdateService.downloadAndInstall(
        UpdateInfo(
          currentVersion: '0.1.0',
          latestVersion: '99.0.0',
          downloadUrl: url('/full'),
          fileName: 'neostation.AppImage',
          fileSize: body.length,
          sha256: bodySha256,
        ),
        null,
      );

      expect(outcome, UpdateOutcome.installFailed);
      expect(downloaded().existsSync(), isFalse);
    }, skip: !Platform.isLinux);
  });

  test('cleaning up removes earlier update downloads only', () async {
    final updates = [
      'neostation-android-arm64-v8a-0.15.1+132.apk',
      'neostation-android-armeabi-v7a-0.15.1+132.apk',
      'neostation-linux-x86_64-0.15.1+132.AppImage',
      'neostation-linux-arm64-0.15.1+132.AppImage',
      'neostation-windows-x64-0.15.1+132.zip',
      'neostation-macos-universal-0.15.1+132.dmg',
      'NeoStation-99.0.0-linux-x86_64-UAT.AppImage',
    ];
    final others = [
      'neostation.db',
      'neostation-notes.txt',
      'other-linux-x86_64-1.0.AppImage',
      'update_stage2.bat',
      'update_xcopy.log',
    ];
    for (final name in [...updates, ...others]) {
      File('${temp.path}/$name').writeAsStringSync('x');
    }
    File('${temp.path}/neostation_update/neostation.exe')
      ..createSync(recursive: true)
      ..writeAsStringSync('x');
    Directory('${temp.path}/unrelated').createSync();

    await UpdateService.cleanUpDownloads();

    for (final name in updates) {
      expect(File('${temp.path}/$name').existsSync(), isFalse, reason: name);
    }
    for (final name in others) {
      expect(File('${temp.path}/$name').existsSync(), isTrue, reason: name);
    }
    expect(Directory('${temp.path}/neostation_update').existsSync(), isFalse);
    expect(Directory('${temp.path}/unrelated').existsSync(), isTrue);
  });
}
