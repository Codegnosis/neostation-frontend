import 'package:flutter_test/flutter_test.dart';
import 'package:neostation/l10n/app_locale.dart';
import 'package:neostation/models/database_game_model.dart';
import 'package:neostation/models/discovery_models.dart';
import 'package:neostation/screens/discovery_screen/discovery_mosaic.dart';
import 'package:neostation/utils/genre_buckets.dart';

/// Tests for the board's layout and the cursor that walks it.
///
/// The mosaic has a fixed shape and a variable amount of content, so what is
/// worth pinning down is how the picks are dealt into it — and that every pick
/// dealt in stays reachable by the D-pad, including the tall hero beside a
/// two-row grid and the notice tile that holds no game at all.
void main() {
  DiscoveryBoardEntry entry(
    String slotId,
    DiscoverySection section, {
    GenreBucket? genre,
    int order = 0,
    int achievementCount = 0,
  }) {
    return DiscoveryBoardEntry(
      pick: DiscoveryPick(
        weekKey: '2026-W33',
        slotId: slotId,
        section: section,
        romPath: '/roms/snes/$slotId.zip',
        genre: genre,
        slotOrder: order,
      ),
      game: DatabaseGameModel(
        filename: '$slotId.zip',
        romPath: '/roms/snes/$slotId.zip',
        realName: slotId,
        systemFolderName: 'snes',
      ),
      achievementCount: achievementCount,
    );
  }

  DiscoveryBoardEntry genreEntry(GenreBucket bucket, int order) => entry(
    genreSlotId(bucket),
    DiscoverySection.genrePick,
    genre: bucket,
    order: order,
  );

  DiscoveryBoard boardWith({
    bool hero = true,
    int genres = 0,
    bool gem = false,
    bool achievement = false,
    bool scrapeCoverageLow = false,
  }) {
    final buckets = GenreBucket.values.take(genres).toList();
    return DiscoveryBoard(
      weekKey: '2026-W33',
      scrapeCoverageLow: scrapeCoverageLow,
      entries: [
        if (hero) entry(kSlotGameOfTheWeek, DiscoverySection.gameOfTheWeek),
        for (var i = 0; i < buckets.length; i++) genreEntry(buckets[i], i),
        if (gem) entry(kSlotHiddenGem, DiscoverySection.hiddenGem),
        if (achievement)
          entry(
            kSlotAchievementSpotlight,
            DiscoverySection.achievementSpotlight,
            achievementCount: 42,
          ),
      ],
    );
  }

  group('buildDiscoveryMosaic', () {
    test('deals genre picks into the grid and the leftovers into the band', () {
      final mosaic = buildDiscoveryMosaic(
        boardWith(genres: 8, gem: true, achievement: true),
      );

      expect(mosaic.hero?.entry?.pick.slotId, kSlotGameOfTheWeek);
      expect(mosaic.grid.length, kMosaicGridSlots);
      expect(mosaic.gridRowCount, 2);

      // Gem first, the two genres the grid had no room for next, spotlight
      // last: the two one-off features bookend the strip.
      expect(mosaic.band.map((t) => t.entry?.pick.slotId).toList(), [
        kSlotHiddenGem,
        genreSlotId(GenreBucket.values[6]),
        genreSlotId(GenreBucket.values[7]),
        kSlotAchievementSpotlight,
      ]);
    });

    test('keeps every pick on the board when there are more than tiles', () {
      final board = boardWith(genres: 13, gem: true, achievement: true);
      final mosaic = buildDiscoveryMosaic(board);

      final shown = [
        mosaic.hero,
        ...mosaic.grid,
        ...mosaic.band,
      ].map((t) => t?.entry?.pick.slotId).toSet();

      for (final boardEntry in board.entries) {
        expect(
          shown,
          contains(boardEntry.pick.slotId),
          reason: 'every pick has a tile; the band scrolls rather than drops',
        );
      }
    });

    test('the grid is only as wide as the picks justify', () {
      // Four picks square up rather than sitting three-across with a hole.
      final four = buildDiscoveryMosaic(boardWith(genres: 4));
      expect(four.gridColumns, 2);
      expect(four.gridRowCount, 2);
      expect(four.navRows.map((r) => r.length).toList(), [3, 3]);

      // Up to three stay on one row beside the hero.
      final three = buildDiscoveryMosaic(boardWith(genres: 3));
      expect(three.gridColumns, 3);
      expect(three.gridRowCount, 1);

      // A full board is the concept's 3x2.
      final six = buildDiscoveryMosaic(boardWith(genres: 6));
      expect(six.gridColumns, kMosaicGridColumns);
      expect(six.gridRowCount, 2);

      // Five leaves the one hole there is no way to avoid.
      final five = buildDiscoveryMosaic(boardWith(genres: 5));
      expect(five.gridColumns, 3);
      expect(five.navRows.map((r) => r.length).toList(), [4, 3]);
    });

    test('promotes a pick into the headline when the hero slot is empty', () {
      final mosaic = buildDiscoveryMosaic(boardWith(hero: false, genres: 2));

      expect(mosaic.hero, isNotNull);
      expect(mosaic.hero?.entry?.pick.genre, GenreBucket.values.first);
      // The promoted pick is the headline, not also a grid tile.
      expect(mosaic.grid.length, 1);
      expect(mosaic.hero?.labelKey, isNot(AppLocale.discoveryGameOfTheWeek));
    });

    test('the scrape gate replaces the gem with a notice, not a gap', () {
      final mosaic = buildDiscoveryMosaic(
        boardWith(genres: 2, gem: true, scrapeCoverageLow: true),
      );

      expect(mosaic.band.length, 1);
      expect(mosaic.band.single.entry, isNull);
      expect(mosaic.band.single.noticeKey, AppLocale.discoveryNeedsScraping);
      expect(mosaic.band.single.isFocusable, isFalse);
    });

    test('a board with only a hero is still a board', () {
      final mosaic = buildDiscoveryMosaic(boardWith());

      expect(mosaic.grid, isEmpty);
      expect(mosaic.band, isEmpty);
      expect(mosaic.navRows, [
        [mosaic.hero],
      ]);
      expect(mosaic.firstFocusable, (0, 0));
    });

    test('an empty board has nothing to focus', () {
      final mosaic = buildDiscoveryMosaic(
        const DiscoveryBoard.empty('2026-W33'),
      );

      expect(mosaic.hasFocusableTile, isFalse);
      expect(mosaic.firstFocusable, isNull);
    });
  });

  group('cursor', () {
    // Hero + 6 genres + gem + spotlight: the full mosaic.
    final full = buildDiscoveryMosaic(
      boardWith(genres: 6, gem: true, achievement: true),
    );

    test('Right off the hero enters the grid on the row the cursor is on', () {
      expect(full.step(0, 0, dCol: 1), (0, 1));
      expect(full.step(1, 0, dCol: 1), (1, 1));
    });

    test('Left off the grid returns to the hero', () {
      expect(full.step(0, 1, dCol: -1), (0, 0));
      expect(full.step(1, 3, dCol: -1), (1, 2));
    });

    test('Down the grid walks its two rows and then the band', () {
      expect(full.step(0, 2, dRow: 1), (1, 2));
      expect(full.step(1, 2, dRow: 1), (2, 1));
    });

    test('Down the hero skips its second row and lands on the band', () {
      // The hero occupies (0,0) and (1,0): stepping onto itself is not a move,
      // so Down carries on to the strip below.
      expect(full.step(0, 0, dRow: 1), (2, 0));
    });

    test('Up from the band lands on whatever the tile sits under', () {
      // The strip spans the full width while the grid covers only the right of
      // it, so Up is answered by position and not by column index: the left
      // half of the strip is under the hero, the right half under the grid.
      expect(full.step(2, 1, dRow: -1), (1, 2));
      expect(full.step(2, 0, dRow: -1), (1, 0));
    });

    test('the edges of the board stop the cursor', () {
      expect(full.step(0, 0, dCol: -1), isNull);
      expect(full.step(0, 0, dRow: -1), isNull);
      expect(full.step(0, 3, dCol: 1), isNull);
      expect(full.step(2, full.band.length - 1, dCol: 1), isNull);
      expect(full.step(2, 0, dRow: 1), isNull);
    });

    test('a full strip lines up with the grid above it', () {
      // Five band tiles across the whole width against three grid columns down
      // the right of it: the rightmost of each still meet.
      final wide = buildDiscoveryMosaic(
        boardWith(genres: 9, gem: true, achievement: true),
      );

      expect(wide.band.length, kMosaicBandVisible);
      expect(wide.step(2, wide.band.length - 1, dRow: -1), (1, 3));
    });

    test('a notice is stepped over rather than being a dead stop', () {
      // Gem gated out, so the band leads with a notice tile: the cursor never
      // lands on it, and it does not swallow the press either.
      final gated = buildDiscoveryMosaic(
        boardWith(genres: 7, achievement: true, scrapeCoverageLow: true),
      );

      expect(gated.band.first.isFocusable, isFalse);
      expect(gated.firstFocusable, (0, 0));
      expect(gated.step(2, 0, dCol: 1), (2, 1));
      // Nothing focusable to the left of the strip's first pick.
      expect(gated.step(2, 1, dCol: -1), isNull);
      // Nor does Up ever answer with the notice.
      expect(gated.step(1, 1, dRow: 1)?.$2, isNot(0));
    });
  });
}
