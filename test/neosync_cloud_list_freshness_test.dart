import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:neostation/models/game_model.dart';
import 'package:neostation/models/neo_sync_models.dart';
import 'package:neostation/models/user.dart';
import 'package:neostation/providers/neo_sync_provider.dart';
import 'package:neostation/repositories/neosync_save_folder_repository.dart';
import 'package:neostation/services/neosync/auth_service.dart';
import 'package:neostation/services/neosync/neo_sync_service.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'database_test_helper.dart';

// A game's NeoSync sync compared its saves with a list of the cloud's files
// fetched once, at the first game the user highlighted, and kept until the
// app closed. Saves changed on another device were missed, so an old local
// save could be uploaded over newer progress, and the list outlived signing
// out into another account.

/// Lists [cloud] (or fails when [listFails]), records uploads and downloads,
/// and never touches the network or the real save folders.
class _FakeNeoSync extends NeoSyncService {
  List<NeoSyncFile> cloud = [];
  bool listFails = false;
  int listCalls = 0;
  final uploads = <String>[];
  final downloads = <String>[];

  @override
  Future<Map<String, dynamic>> getAllFiles({NeoSyncFileFilter? filter}) async {
    listCalls++;
    if (listFails) return {'success': false, 'message': 'Network error'};
    return {'success': true, 'files': List<NeoSyncFile>.of(cloud)};
  }

  @override
  Future<Map<String, dynamic>> syncFile(
    File file,
    String gameName, {
    String? customFilename,
    String? systemId,
    String? emulatorId,
    String? gameHash,
    bool? isState,
    String? scope,
    String? type,
  }) async {
    uploads.add(p.basename(file.path));
    return {'success': true};
  }

  @override
  Future<Map<String, dynamic>> downloadFile(String fileId) async {
    downloads.add(fileId);
    return {'success': false, 'message': 'File not found (404)'};
  }

  @override
  Future<Map<String, dynamic>> deleteFile(String fileId) async => {
    'success': true,
  };
}

class _SignedIn extends AuthService {
  String userId = 'player-one';

  @override
  bool get isLoggedIn => true;

  @override
  User? get currentUser => User(
    id: userId,
    username: userId,
    email: '$userId@example.com',
    plan: 'free',
    storageQuotaBytes: 0,
    storageUsedBytes: 0,
    emailVerified: true,
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  final dbHelper = DatabaseTestHelper();
  late Directory folder;
  late _FakeNeoSync service;
  late _SignedIn auth;
  late NeoSyncProvider provider;
  late DateTime now;

  final game = GameModel(
    romname: 'Zelda.iso',
    realname: 'Zelda',
    name: 'Zelda',
    year: '2002',
    developer: '',
    publisher: '',
    genre: '',
    players: '',
    rating: 0,
    romPath: '/roms/gc/Zelda.iso',
    systemFolderName: 'gc',
    cloudSyncEnabled: true,
  );

  NeoSyncFile cloudSave(String name, {String gameName = 'Zelda'}) =>
      NeoSyncFile(
        id: name,
        fileName: name,
        filePath: name,
        type: 'custom',
        fileSize: 4,
        gameName: gameName,
        uploadedAt: DateTime(2026, 10, 1),
        userId: 'player',
        checksum: '',
        systemName: 'gc',
        emulator: 'dolphin',
      );

  Future<GameSyncStatus?> sync() async {
    await provider.detectGameSaveFiles(game);
    return provider.getGameSyncState(game.romname)?.status;
  }

  void later(Duration by) => now = now.add(by);

  setUp(() async {
    final db = await dbHelper.setUp();
    await db.execute(
      "INSERT INTO app_systems (id, real_name, folder_name, neosync_json) "
      "VALUES ('gc', 'GameCube', 'gc', '{\"sync\": true}')",
    );
    await db.execute(
      "INSERT INTO user_detected_systems (app_system_id, actual_folder_name) "
      "VALUES ('gc', 'gc')",
    );
    folder = await Directory.systemTemp.createTemp('neosync_cloud_list_');
    await NeoSyncSaveFolderRepository.saveFolder('gc', 'dolphin', folder.path);
    service = _FakeNeoSync();
    auth = _SignedIn();
    now = DateTime(2026, 10, 29, 12);
    provider = NeoSyncProvider(service, now: () => now)..setAuthService(auth);
  });

  tearDown(() async {
    await folder.delete(recursive: true);
    await dbHelper.tearDown();
  });

  test('a save added on another device is fetched once the list is '
      'old', () async {
    service.cloud = [cloudSave('Mario.sav', gameName: 'Mario')];
    await sync();
    expect(service.downloads, isEmpty);

    service.cloud = [
      cloudSave('Mario.sav', gameName: 'Mario'),
      cloudSave('Zelda.sav'),
    ];
    later(const Duration(minutes: 2));
    await sync();

    expect(service.downloads, ['Zelda.sav']);
  });

  test('a save deleted on another device is not fetched once the list is '
      'old', () async {
    service.cloud = [cloudSave('Zelda.sav')];
    await sync();
    service.downloads.clear();

    service.cloud = [];
    later(const Duration(minutes: 2));
    await sync();

    expect(service.downloads, isEmpty);
  });

  test('a recent list is reused rather than fetched again', () async {
    service.cloud = [cloudSave('Mario.sav', gameName: 'Mario')];
    await sync();
    later(const Duration(seconds: 10));
    await sync();

    expect(service.listCalls, 1);
  });

  test('a failed download fetches the list again next time', () async {
    service.cloud = [cloudSave('Zelda.sav')];
    await sync();
    later(const Duration(seconds: 5));
    await sync();

    expect(service.listCalls, 2);
  });

  test('a game about to launch fetches a list that is not '
      'brand new', () async {
    service.cloud = [cloudSave('Mario.sav', gameName: 'Mario')];
    await sync();
    later(const Duration(seconds: 15));

    await provider.syncGameSavesBeforeLaunch(game);

    expect(service.listCalls, 2);
  });

  test('a game launched right after its list was fetched reuses it', () async {
    service.cloud = [cloudSave('Mario.sav', gameName: 'Mario')];
    await sync();
    later(const Duration(seconds: 2));

    await provider.syncGameSavesBeforeLaunch(game);

    expect(service.listCalls, 1);
  });

  test('a game that has just closed is compared with a fresh list', () async {
    // So a save made on another device meanwhile is picked up.
    service.cloud = [cloudSave('Mario.sav', gameName: 'Mario')];
    await sync();
    later(const Duration(seconds: 15));

    await provider.syncGameSavesAfterClose(game);

    expect(service.listCalls, 2);
  });

  test('without a cloud list, nothing is downloaded and the sync '
      'fails', () async {
    service.listFails = true;

    expect(await sync(), GameSyncStatus.error);
    expect(service.downloads, isEmpty);
  });

  test('a list the save list just loaded is reused', () async {
    service.cloud = [cloudSave('Mario.sav', gameName: 'Mario')];
    await provider.loadFiles();
    later(const Duration(seconds: 5));

    await sync();

    expect(service.listCalls, 1);
  });

  test('without a cloud list, nothing is uploaded and the sync '
      'fails', () async {
    File(p.join(folder.path, 'Zelda.sav')).writeAsBytesSync(const [1, 2, 3]);
    service.listFails = true;

    expect(await sync(), GameSyncStatus.error);
    expect(service.uploads, isEmpty);
  });

  test("another account never sees the previous account's list", () async {
    service.cloud = [cloudSave('Mario.sav', gameName: 'Mario')];
    await sync();

    auth.userId = 'player-two';
    service.cloud = [];
    later(const Duration(seconds: 5));
    await sync();

    expect(service.listCalls, 2);
    expect(provider.files, isEmpty);
  });

  test('a save deleted from the save list leaves the cloud list', () async {
    service.cloud = [cloudSave('Zelda.sav')];
    await sync();
    expect(provider.files.map((f) => f.id), ['Zelda.sav']);

    await provider.deleteOnlineFile('Zelda.sav');

    expect(provider.files, isEmpty);
  });
}
