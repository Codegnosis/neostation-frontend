import 'package:flutter/widgets.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:neostation/l10n/app_locale.dart';

import '../../models/discovery_models.dart';
import '../../utils/genre_buckets.dart';

/// Tiles in the grid block: three columns by two rows, as the concept has it.
const int kMosaicGridSlots = 6;

/// Band tiles shown at once. A board with more than this many leftovers keeps
/// them reachable by scrolling the strip sideways rather than by dropping them.
const int kMosaicBandVisible = 5;

/// Width of the hero panel, as a flex share of the top block.
const int kMosaicHeroFlex = 5;

/// Width of the grid block beside the hero, as a flex share.
///
/// Slightly the wider half, as in the concept: the grid carries six tiles to
/// the hero's one without the headline losing its billing.
const int kMosaicGridFlex = 6;

/// Most columns the grid block ever has.
const int kMosaicGridColumns = 3;

/// How wide the grid block is for [count] picks.
///
/// Three across is the concept's shape and what a full board gets, but a
/// library with only four genres reads far better as a filled 2x2 than as a
/// row of three with a hole beside it. Up to three picks stay on one row.
int discoveryGridColumns(int count) {
  if (count <= 0) return 0;
  final rows = count <= kMosaicGridColumns ? 1 : 2;
  return (count / rows).ceil();
}

/// Where a tile sits on the board.
enum DiscoveryTileKind {
  /// The headline panel down the left of the top block.
  hero,

  /// One cell of the 3x2 grid filling the right of the top block.
  grid,

  /// One of the short, wide tiles across the foot of the board.
  band,
}

/// One tile of the mosaic, as both the layout and the cursor see it.
///
/// A tile is identified by object identity rather than by value: the hero
/// occupies a cell in both grid nav rows, and comparing instances is what lets
/// the cursor tell "still on the hero" from "moved somewhere new".
class DiscoveryTile {
  const DiscoveryTile({
    required this.kind,
    required this.labelKey,
    required this.icon,
    this.entry,
    this.noticeKey,
    this.achievementCount = 0,
  });

  final DiscoveryTileKind kind;

  /// [AppLocale] key drawn across the tile — the genre it was picked for, or
  /// the name of the feature it stands for.
  final String labelKey;

  final IconData icon;

  /// The pick shown here. Null only on a notice tile, which explains a section
  /// that could not be filled.
  final DiscoveryBoardEntry? entry;

  /// [AppLocale] key of the message on a notice tile.
  final String? noticeKey;

  /// Size of the game's RetroAchievements set; 0 hides the count.
  final int achievementCount;

  /// Whether the cursor can land here. Notices carry no game, so they are
  /// stepped over rather than being a dead stop.
  bool get isFocusable => entry != null;

  /// A copy of this tile showing [replacement] instead of its own pick.
  ///
  /// The re-roll shuffle uses it to flash games through a tile: the section
  /// keeps its label, icon and place on the board while the game inside it
  /// changes. The copy is deliberately a new instance — the cursor compares
  /// tiles by identity, so callers must keep testing the original.
  DiscoveryTile withEntry(DiscoveryBoardEntry replacement) => DiscoveryTile(
    kind: kind,
    labelKey: labelKey,
    icon: icon,
    entry: replacement,
    noticeKey: noticeKey,
    achievementCount: achievementCount,
  );
}

/// The board's tiles, in display order, plus the grid the cursor walks.
class DiscoveryMosaic {
  const DiscoveryMosaic({
    required this.hero,
    required this.grid,
    required this.band,
    required this.navRows,
    required this.navRowCentres,
  });

  const DiscoveryMosaic.empty()
    : hero = null,
      grid = const [],
      band = const [],
      navRows = const [],
      navRowCentres = const [];

  final DiscoveryTile? hero;

  /// The 3x2 block, in reading order. At most [kMosaicGridSlots] long.
  final List<DiscoveryTile> grid;

  /// The strip along the bottom, left to right.
  final List<DiscoveryTile> band;

  /// The tiles as rows of cells the cursor moves between.
  ///
  /// The hero is the first cell of every grid row rather than a row of its own,
  /// which is how a tall panel beside a two-row grid behaves under a D-pad:
  /// Right enters the grid at the height the cursor was already at.
  final List<List<DiscoveryTile>> navRows;

  /// Where each cell sits across the width of the board, 0 (left edge) to 1
  /// (right edge).
  ///
  /// Column indices say nothing about position here — the band spans the whole
  /// width while the grid only covers the right of it — so Up and Down move by
  /// where a tile actually is rather than by which index it holds. Derived from
  /// the same flex constants the storefront lays out with.
  final List<List<double>> navRowCentres;

  /// How wide the grid block is — see [discoveryGridColumns].
  int get gridColumns => discoveryGridColumns(grid.length);

  /// How many rows the grid block occupies (0, 1 or 2).
  int get gridRowCount => grid.isEmpty ? 0 : (grid.length / gridColumns).ceil();

  DiscoveryTile? tileAt(int row, int col) {
    if (row < 0 || row >= navRows.length) return null;
    final tiles = navRows[row];
    if (col < 0 || col >= tiles.length) return null;
    return tiles[col];
  }

  /// The cell holding [tile], or null when it is not on the board.
  (int, int)? locate(DiscoveryTile tile) {
    for (var row = 0; row < navRows.length; row++) {
      for (var col = 0; col < navRows[row].length; col++) {
        if (identical(navRows[row][col], tile)) return (row, col);
      }
    }
    return null;
  }

  /// The cell the cursor starts and returns to.
  (int, int)? get firstFocusable {
    for (var row = 0; row < navRows.length; row++) {
      for (var col = 0; col < navRows[row].length; col++) {
        if (navRows[row][col].isFocusable) return (row, col);
      }
    }
    return null;
  }

  bool get hasFocusableTile => firstFocusable != null;

  /// The cell reached by stepping [dRow]/[dCol] from ([row], [col]), or null
  /// when the edge of the board stops the cursor.
  ///
  /// Two cells are stepped over rather than landed on: the hero, when it is
  /// already where the cursor is (it spans both grid rows), and any notice,
  /// which holds no game. Both keep walking in the same direction instead of
  /// swallowing the press.
  (int, int)? step(int row, int col, {int dRow = 0, int dCol = 0}) {
    final current = tileAt(row, col);
    if (current == null) return null;
    if (dRow != 0) return _stepVertically(row, col, current, dRow);

    var c = col;
    while (true) {
      c += dCol;
      final tile = tileAt(row, c);
      if (tile == null) return null;
      if (identical(tile, current) || !tile.isFocusable) continue;
      return (row, c);
    }
  }

  /// The nearest tile above or below, measured across the width of the board.
  (int, int)? _stepVertically(
    int row,
    int col,
    DiscoveryTile current,
    int dRow,
  ) {
    final from = navRowCentres[row][col];
    for (var r = row + dRow; r >= 0 && r < navRows.length; r += dRow) {
      // A row the cursor is already in is not below or above it: the hero
      // spans both grid rows, so Down off the hero belongs to the band rather
      // than to the tile diagonally beside it.
      if (navRows[r].any((tile) => identical(tile, current))) continue;

      var best = -1;
      var bestDistance = double.infinity;
      for (var c = 0; c < navRows[r].length; c++) {
        final tile = navRows[r][c];
        if (!tile.isFocusable) continue;
        final distance = (navRowCentres[r][c] - from).abs();
        if (distance < bestDistance) {
          bestDistance = distance;
          best = c;
        }
      }
      // A row of nothing but the hero the cursor is already on, or nothing but
      // notices, is passed through rather than being a stop.
      if (best >= 0) return (r, best);
    }
    return null;
  }
}

/// Lays the week's picks out as the mosaic.
///
/// The shape is fixed and the content is not, so the picks are dealt into it in
/// order of prominence: the headline leads, the genre picks fill the grid, and
/// whatever is left over — the two one-off features and any genre the grid had
/// no room for — forms the band.
DiscoveryMosaic buildDiscoveryMosaic(DiscoveryBoard board) {
  final genres = [...board.genreEntries];
  var gem = board.scrapeCoverageLow ? null : board.hiddenGemEntry;
  var achievement = board.achievementEntry;

  // The hero is the one tile the layout cannot do without, so a board whose
  // headline slot went unfilled promotes its next-best pick rather than opening
  // with a hole.
  var heroEntry = board.heroEntry;
  var heroLabelKey = AppLocale.discoveryGameOfTheWeek;
  var heroIcon = Symbols.local_fire_department_rounded;
  if (heroEntry == null) {
    if (genres.isNotEmpty) {
      final promoted = genres.removeAt(0);
      heroEntry = promoted;
      heroLabelKey = _genreLabelKey(promoted);
      heroIcon = Symbols.category_rounded;
    } else if (gem != null) {
      heroEntry = gem;
      heroLabelKey = AppLocale.discoveryHiddenGem;
      heroIcon = Symbols.diamond_rounded;
      gem = null;
    } else if (achievement != null) {
      heroEntry = achievement;
      heroLabelKey = AppLocale.discoveryAchievementSpotlight;
      heroIcon = Symbols.trophy_rounded;
      achievement = null;
    }
  }

  final hero = heroEntry == null
      ? null
      : DiscoveryTile(
          kind: DiscoveryTileKind.hero,
          labelKey: heroLabelKey,
          icon: heroIcon,
          entry: heroEntry,
        );

  final grid = [
    for (final entry in genres.take(kMosaicGridSlots))
      DiscoveryTile(
        kind: DiscoveryTileKind.grid,
        labelKey: _genreLabelKey(entry),
        icon: Symbols.category_rounded,
        entry: entry,
      ),
  ];

  final band = <DiscoveryTile>[
    if (gem != null)
      DiscoveryTile(
        kind: DiscoveryTileKind.band,
        labelKey: AppLocale.discoveryHiddenGem,
        icon: Symbols.diamond_rounded,
        entry: gem,
      )
    else if (board.scrapeCoverageLow)
      // The gate tripped: say why the feature is missing rather than leaving a
      // gap in the strip the user cannot explain.
      const DiscoveryTile(
        kind: DiscoveryTileKind.band,
        labelKey: AppLocale.discoveryHiddenGem,
        icon: Symbols.diamond_rounded,
        noticeKey: AppLocale.discoveryNeedsScraping,
      ),
    for (final entry in genres.skip(kMosaicGridSlots))
      DiscoveryTile(
        kind: DiscoveryTileKind.band,
        labelKey: _genreLabelKey(entry),
        icon: Symbols.category_rounded,
        entry: entry,
      ),
    if (achievement != null)
      DiscoveryTile(
        kind: DiscoveryTileKind.band,
        labelKey: AppLocale.discoveryAchievementSpotlight,
        icon: Symbols.trophy_rounded,
        entry: achievement,
        achievementCount: achievement.achievementCount,
      ),
  ];

  final navRows = <List<DiscoveryTile>>[];
  final navRowCentres = <List<double>>[];

  final gridColumns = discoveryGridColumns(grid.length);
  final columns = _gridColumnCentres(
    hasHero: hero != null,
    columns: gridColumns,
  );
  for (var i = 0; i < grid.length; i += gridColumns) {
    final end = i + gridColumns;
    final gridRow = grid.sublist(i, end > grid.length ? grid.length : end);
    navRows.add([?hero, ...gridRow]);
    navRowCentres.add([
      if (hero != null) _heroCentre(hasGrid: true),
      for (var c = 0; c < gridRow.length; c++) columns[c],
    ]);
  }
  if (navRows.isEmpty && hero != null) {
    navRows.add([hero]);
    navRowCentres.add([_heroCentre(hasGrid: false)]);
  }

  if (band.isNotEmpty) {
    // The strip spans the full width, split evenly between the tiles on show.
    final across = band.length < kMosaicBandVisible
        ? band.length
        : kMosaicBandVisible;
    navRows.add(band);
    navRowCentres.add([
      for (var i = 0; i < band.length; i++) (i + 0.5) / across,
    ]);
  }

  return DiscoveryMosaic(
    hero: hero,
    grid: grid,
    band: band,
    navRows: navRows,
    navRowCentres: navRowCentres,
  );
}

/// Where the hero sits across the width of the board.
double _heroCentre({required bool hasGrid}) =>
    hasGrid ? kMosaicHeroFlex / (2 * (kMosaicHeroFlex + kMosaicGridFlex)) : 0.5;

/// Where each grid column sits across the width of the board.
List<double> _gridColumnCentres({required bool hasHero, required int columns}) {
  if (columns <= 0) return const [];
  final left = hasHero
      ? kMosaicHeroFlex / (kMosaicHeroFlex + kMosaicGridFlex)
      : 0.0;
  final width = (1 - left) / columns;
  return [for (var c = 0; c < columns; c++) left + (c + 0.5) * width];
}

String _genreLabelKey(DiscoveryBoardEntry entry) {
  final bucket = entry.pick.genre;
  return bucket == null
      ? AppLocale.discoveryGenrePicks
      : genreBucketLabelKey(bucket);
}

/// The [AppLocale] key naming [bucket] on a tile.
///
/// Lives here rather than beside [GenreBucket] so the bucket table itself stays
/// free of any Flutter or localization dependency and remains directly
/// unit-testable.
String genreBucketLabelKey(GenreBucket bucket) => switch (bucket) {
  GenreBucket.platform => AppLocale.genrePlatform,
  GenreBucket.rpg => AppLocale.genreRpg,
  GenreBucket.shooter => AppLocale.genreShooter,
  GenreBucket.fighting => AppLocale.genreFighting,
  GenreBucket.racing => AppLocale.genreRacing,
  GenreBucket.puzzle => AppLocale.genrePuzzle,
  GenreBucket.sports => AppLocale.genreSports,
  GenreBucket.adventure => AppLocale.genreAdventure,
  GenreBucket.strategy => AppLocale.genreStrategy,
  GenreBucket.simulation => AppLocale.genreSimulation,
  GenreBucket.action => AppLocale.genreAction,
  GenreBucket.arcade => AppLocale.genreArcade,
  GenreBucket.other => AppLocale.genreOther,
};
