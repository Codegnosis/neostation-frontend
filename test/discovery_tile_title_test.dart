import 'package:flutter/material.dart';
import 'package:flutter_localization/flutter_localization.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marquee/marquee.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:neostation/l10n/app_locale.dart';
import 'package:neostation/models/database_game_model.dart';
import 'package:neostation/models/discovery_models.dart';
import 'package:neostation/providers/file_provider.dart';
import 'package:neostation/screens/discovery_screen/discovery_mosaic.dart';
import 'package:neostation/screens/discovery_screen/widgets/discovery_tile.dart';
import 'package:neostation/themes/corner_radii.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Tests for how a Discovery tile prints its game's name.
///
/// The board's tiles are small and truncate most titles, and since the footer
/// went there is nowhere else on the board a pick's full name appears. The
/// focused tile therefore scrolls its title; every other tile keeps the
/// ellipsis, so the board is not a wall of moving text.
const _longName =
    'Phoenix Wright: Ace Attorney - Justice for All - Special Edition';

DiscoveryTile _tile({String name = _longName}) => DiscoveryTile(
  kind: DiscoveryTileKind.grid,
  labelKey: AppLocale.genreAdventure,
  icon: Symbols.explore_rounded,
  entry: DiscoveryBoardEntry(
    pick: const DiscoveryPick(
      weekKey: '2026-W33',
      slotId: 'genre:adventure',
      section: DiscoverySection.genrePick,
      romPath: '/roms/nds/pw.nds',
    ),
    // No system folder, so the tile draws its placeholder rather than asking
    // the file provider for art.
    game: DatabaseGameModel(
      filename: 'pw.nds',
      romPath: '/roms/nds/pw.nds',
      realName: name,
    ),
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await FlutterLocalization.instance.ensureInitialized();
    FlutterLocalization.instance.init(
      mapLocales: [MapLocale('en', AppLocale.en)],
      initLanguageCode: 'en',
    );
  });

  Future<void> mount(WidgetTester tester, Widget tile) async {
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(size: Size(1920, 1080)),
        child: ScreenUtilInit(
          designSize: const Size(640, 480),
          builder: (context, child) => MaterialApp(
            localizationsDelegates:
                FlutterLocalization.instance.localizationsDelegates,
            supportedLocales: FlutterLocalization.instance.supportedLocales,
            theme: ThemeData(extensions: [CornerRadii.m()]),
            home: Scaffold(
              body: Center(
                child: SizedBox(width: 160, height: 110, child: tile),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
  }

  /// A running marquee keeps a timer armed between rounds, which the test
  /// binding rejects once the test ends; unmount it and let the timer lapse.
  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
  }

  group('grid tile', () {
    testWidgets('scrolls a truncated title while focused', (tester) async {
      await mount(
        tester,
        DiscoveryGridTile(
          tile: _tile(),
          isSelected: true,
          fileProvider: FileProvider(),
        ),
      );
      expect(find.byType(Marquee), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('keeps the ellipsis while not focused', (tester) async {
      await mount(
        tester,
        DiscoveryGridTile(
          tile: _tile(),
          isSelected: false,
          fileProvider: FileProvider(),
        ),
      );
      expect(find.byType(Marquee), findsNothing);
      expect(find.text(_longName), findsOneWidget);
    });

    testWidgets('does not scroll a title that already fits', (tester) async {
      await mount(
        tester,
        DiscoveryGridTile(
          tile: _tile(name: 'Tetris'),
          isSelected: true,
          fileProvider: FileProvider(),
        ),
      );
      expect(find.byType(Marquee), findsNothing);
      expect(find.text('Tetris'), findsOneWidget);
    });
  });

  group('band tile', () {
    testWidgets('scrolls a truncated title while focused', (tester) async {
      await mount(
        tester,
        DiscoveryBandTile(
          tile: _tile(),
          isSelected: true,
          fileProvider: FileProvider(),
        ),
      );
      expect(find.byType(Marquee), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('keeps the ellipsis while not focused', (tester) async {
      await mount(
        tester,
        DiscoveryBandTile(
          tile: _tile(),
          isSelected: false,
          fileProvider: FileProvider(),
        ),
      );
      expect(find.byType(Marquee), findsNothing);
    });
  });
}
