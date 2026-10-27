import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// On Android without All files access, picking a NeoSync standalone save
/// folder went through the user-data resolver, which swaps any folder for
/// NeoStation's own app storage on the SD card when one is present: a real
/// folder was refused as missing, and with user data on the SD card the "save
/// folder" became NeoStation's own files. The picker now keeps the folder that
/// was picked, falls back to the in-app picker like the other folder pickers,
/// and no longer reports an empty folder as synced.
void main() {
  final view = File(
    'lib/screens/neo_sync_screen/login_screen/custom_save_folders_view.dart',
  ).readAsStringSync();

  // The body of a class method: from its signature to the closing brace at
  // the class member indent.
  String method(String source, String signature) {
    final start = source.indexOf(signature);
    expect(start, isNot(-1), reason: '$signature not found');
    final end = source.indexOf('\n  }\n', start);
    expect(end, isNot(-1), reason: '$signature has no end');
    return source.substring(start, end);
  }

  String picker() => method(
    view,
    'Future<void> _selectFolderFor(String system, String emulatorSlug)',
  );

  test('the picker keeps the folder that was picked', () {
    final body = picker();
    expect(body, isNot(contains('resolveAndroidUserDataPath')));
    expect(body, contains('UserDataLocationService.safUriToRealPath('));
  });

  test("the picker says when a picked folder can't be used", () {
    final body = picker();
    expect(body, contains('unusable = selected == null;'));
    final shown = body.indexOf('if (unusable && mounted) {');
    expect(shown, isNot(-1));
    expect(
      body.indexOf('AppLocale.wizardFolderNotUsable', shown),
      greaterThan(shown),
    );
  });

  test('the picker falls back to the in-app picker when the system one '
      "can't open", () {
    final body = picker();
    final caught = body.indexOf('on PlatformException catch (e) {');
    expect(caught, isNot(-1));
    final fallback = body.substring(caught);
    expect(fallback, contains("e.code == 'PICKER_FAILED' && mounted"));
    expect(fallback, contains('TvDirectoryPicker.show(context)'));
  });

  test('an empty folder says no save files were found, not synced', () {
    final body = picker();
    final empty = body.indexOf('if (!wasBusy && provider.totalFiles == 0) {');
    expect(empty, isNot(-1));
    final complete = body.indexOf('AppLocale.customFolderUploadComplete');
    expect(complete, greaterThan(empty));
    final branch = body.substring(empty, complete);
    expect(branch, contains('AppLocale.neoSyncNoSave'));
    expect(branch, contains('} else {'));
  });

  test('only an empty folder mentions All files access, and only when it '
      'is missing', () {
    final body = picker();
    final empty = body.indexOf('if (!wasBusy && provider.totalFiles == 0) {');
    final hint = body.indexOf('AppLocale.userDataFolderGrantAllFiles');
    expect(hint, greaterThan(empty));
    expect('AppLocale.userDataFolderGrantAllFiles'.allMatches(body).length, 1);
    final branch = body.substring(empty, hint);
    expect(branch, contains('!await PermissionService.hasAllFilesAccess()'));
    expect(branch, contains('allFilesHint = needsAllFilesAccess'));
    expect(
      body.substring(empty),
      contains(
        "'\${AppLocale.neoSyncNoSave.getString(context)}\$allFilesHint'",
      ),
    );
  });

  test('a sync already running is not reported as an empty folder', () {
    final body = picker();
    final busy = body.indexOf('final wasBusy = provider.isSyncing;');
    final upload = body.indexOf('await provider.syncCustomSaveFolder(');
    expect(busy, isNot(-1));
    expect(upload, greaterThan(busy));
  });
}
