import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Windows, Steam, and Xbox definitions include supported game files', () {
    final expectedExtensions = <String, Set<String>>{
      'windows.json': {'exe', 'steam'},
      'steam.json': {'steam'},
      'xbox.json': {'xbe', 'iso'},
      'xbox360.json': {'xex'},
    };

    for (final entry in expectedExtensions.entries) {
      final file = File('assets/systems/${entry.key}');
      final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      final system = json['system'] as Map<String, dynamic>;
      final extensions = (system['extensions'] as List<dynamic>)
          .map((extension) => extension.toString().toLowerCase())
          .toSet();

      expect(
        extensions,
        containsAll(entry.value),
        reason:
            '${entry.key} must include executable game files so they are '
            'detected and passed to ScreenScraper.',
      );
    }
  });

  test('PC store systems scrape as PC Windows games', () {
    int? screenScraperId(String fileName) {
      final file = File('assets/systems/$fileName');
      final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      final system = json['system'] as Map<String, dynamic>;
      return (system['ids'] as Map<String, dynamic>)['screenscraper'] as int?;
    }

    // Steam, Amazon, GOG and Epic hold Windows games launched through their
    // store, so ScreenScraper lists them under its PC Windows platform. A
    // system without an id can't be scraped or identified at all.
    final windows = screenScraperId('windows.json');
    expect(windows, 138);
    for (final store in [
      'steam.json',
      'amazon.json',
      'gog.json',
      'epic.json',
    ]) {
      expect(
        screenScraperId(store),
        windows,
        reason: '$store must use the PC Windows ScreenScraper platform.',
      );
    }
  });
}
