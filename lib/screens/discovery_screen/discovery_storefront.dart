import 'package:flutter/material.dart';
import 'package:flutter_localization/flutter_localization.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:neostation/l10n/app_locale.dart';

import '../../models/database_game_model.dart';
import '../../models/discovery_models.dart';
import '../../providers/file_provider.dart';
import 'discovery_mosaic.dart';
import 'widgets/discovery_hero_card.dart';
import 'widgets/discovery_tile.dart';

/// Gap between tiles, and between the mosaic and the edge of the screen.
const double _kGap = 10;

/// Clearance for the floating global header, which is 46.r tall.
///
/// Tighter than the 64.r the scrolling tabs reserve, and deliberately so: this
/// board never scrolls, so anything it does not use at the top is dead space
/// for the whole session rather than a strip you can push content through. The
/// header's own left slot holds the Re-roll pill, so nothing of the board's
/// belongs in that band and it only has to clear it, not share it.
const double _kHeaderClearance = 52;

/// The board: a single screen, laid out as the concept has it — the headline
/// panel down the left, a grid of picks filling the right of the top block, and
/// a strip of wide tiles across the foot.
///
/// Nothing here scrolls vertically. Every tile is sized from the viewport, so
/// the whole board is visible at once on a handheld's screen and the cursor
/// never has to travel off-screen to reach a pick. Only the bottom strip
/// scrolls, and only on a library with more genres than it has room for.
class DiscoveryStorefront extends StatelessWidget {
  const DiscoveryStorefront({
    super.key,
    required this.board,
    required this.mosaic,
    required this.fileProvider,
    required this.selectedTile,
    required this.onTileTapped,
    this.shuffleSlotId,
    this.shuffleGame,
  });

  final DiscoveryBoard board;
  final DiscoveryMosaic mosaic;
  final FileProvider fileProvider;

  /// The tile the cursor is on, or null when nothing is focusable.
  final DiscoveryTile? selectedTile;

  /// Slot currently being re-rolled, and the game flashing past in it.
  ///
  /// The substitution happens here rather than in the board so the tile keeps
  /// its identity: the cursor, the selection ring and the tap target all still
  /// belong to the real pick while the artwork inside flickers.
  final String? shuffleSlotId;
  final DatabaseGameModel? shuffleGame;

  /// Fired by touch/mouse. The tap both moves the cursor and acts, matching
  /// what pressing A on that tile would do.
  final void Function(DiscoveryTile tile) onTileTapped;

  @override
  Widget build(BuildContext context) {
    // The header clearance sits OUTSIDE the mosaic on purpose: the global
    // header floats over the whole tab, so the board has to start below it or
    // the top row rides up behind it.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(height: _kHeaderClearance.r),
        Expanded(
          child: Padding(
            padding: EdgeInsets.fromLTRB(_kGap.r, 0, _kGap.r, _kGap.r),
            child: LayoutBuilder(
              builder: (context, constraints) {
                // The strip takes a share of the height rather than a fixed
                // one, then is held between a legible floor and a ceiling that
                // stops it eating the grid on a tall screen.
                final bandHeight = mosaic.band.isEmpty
                    ? 0.0
                    : (constraints.maxHeight * 0.22)
                          .clamp(46.r, 84.r)
                          .toDouble();

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: _buildTopBlock(context)),
                    if (mosaic.band.isNotEmpty) ...[
                      SizedBox(height: _kGap.r),
                      SizedBox(
                        height: bandHeight,
                        child: _DiscoveryBand(
                          tiles: mosaic.band,
                          fileProvider: fileProvider,
                          selectedTile: selectedTile,
                          onTileTapped: onTileTapped,
                          present: _present,
                        ),
                      ),
                    ],
                  ],
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  /// The headline panel and the grid beside it.
  Widget _buildTopBlock(BuildContext context) {
    final hero = mosaic.hero;
    final hasGrid = mosaic.grid.isNotEmpty;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (hero != null)
          Expanded(
            // The same shares the cursor navigates by — see [kMosaicHeroFlex].
            flex: hasGrid ? kMosaicHeroFlex : 1,
            child: DiscoveryHeroCard(
              tile: _present(hero),
              isSelected: identical(selectedTile, hero),
              fileProvider: fileProvider,
              weekLabel: _weekLabel(context),
              onTap: () => onTileTapped(hero),
            ),
          ),
        if (hero != null && hasGrid) SizedBox(width: _kGap.r),
        if (hasGrid)
          Expanded(
            flex: hero != null ? kMosaicGridFlex : 1,
            child: _buildGrid(),
          ),
      ],
    );
  }

  /// The grid block. It is as wide as the picks justify — see
  /// [discoveryGridColumns] — and a short last row keeps its columns rather
  /// than stretching, so its tiles stay lined up with the row above.
  Widget _buildGrid() {
    final columns = mosaic.gridColumns;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var row = 0; row < mosaic.gridRowCount; row++) ...[
          if (row > 0) SizedBox(height: _kGap.r),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var column = 0; column < columns; column++) ...[
                  if (column > 0) SizedBox(width: _kGap.r),
                  Expanded(child: _buildGridCell(row * columns + column)),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildGridCell(int index) {
    if (index >= mosaic.grid.length) return const SizedBox.shrink();
    final tile = mosaic.grid[index];
    return DiscoveryGridTile(
      tile: _present(tile),
      isSelected: identical(selectedTile, tile),
      fileProvider: fileProvider,
      onTap: () => onTileTapped(tile),
    );
  }

  /// The tile as it should be drawn this frame.
  ///
  /// Everything but the game itself comes from the real tile; only a slot in
  /// the middle of a re-roll shows something else.
  DiscoveryTile _present(DiscoveryTile tile) {
    final game = shuffleGame;
    final slotId = shuffleSlotId;
    final entry = tile.entry;
    if (game == null || slotId == null || entry == null) return tile;
    if (entry.pick.slotId != slotId) return tile;
    return tile.withEntry(DiscoveryBoardEntry(pick: entry.pick, game: game));
  }

  /// The week the board belongs to, rendered from its own key.
  ///
  /// Formatted from the key rather than from `DateTime.now()` so it always
  /// names the week the picks are actually for, even if the board was built
  /// before midnight on a Sunday.
  String _weekLabel(BuildContext context) => AppLocale.discoveryWeekOf
      .getString(context)
      .replaceFirst('{date}', board.weekKey);
}

/// The strip of wide tiles across the foot of the board.
///
/// Sized so [kMosaicBandVisible] tiles exactly fill the width. A library with
/// more genre picks than the mosaic has room for scrolls the extras in from the
/// right rather than losing them, which keeps every pick of the week reachable.
class _DiscoveryBand extends StatefulWidget {
  const _DiscoveryBand({
    required this.tiles,
    required this.fileProvider,
    required this.selectedTile,
    required this.onTileTapped,
    required this.present,
  });

  final List<DiscoveryTile> tiles;
  final FileProvider fileProvider;
  final DiscoveryTile? selectedTile;
  final void Function(DiscoveryTile tile) onTileTapped;

  /// Substitutes the game a re-rolling tile is currently showing.
  final DiscoveryTile Function(DiscoveryTile tile) present;

  @override
  State<_DiscoveryBand> createState() => _DiscoveryBandState();
}

class _DiscoveryBandState extends State<_DiscoveryBand> {
  final ScrollController _controller = ScrollController();
  double _tileWidth = 0;

  @override
  void didUpdateWidget(_DiscoveryBand oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.selectedTile, oldWidget.selectedTile)) {
      _scrollSelectionIntoView();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Keeps the selected tile on screen as the cursor walks the strip.
  ///
  /// Runs after the frame because the extent is only known once the list has
  /// laid out — on the frame the cursor first arrives, it has not.
  void _scrollSelectionIntoView() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_controller.hasClients || _tileWidth <= 0) return;
      final selected = widget.selectedTile;
      if (selected == null) return;
      final index = widget.tiles.indexWhere((t) => identical(t, selected));
      if (index < 0) return;

      final extent = _tileWidth + _kGap.r;
      final target = (index * extent) - extent / 2;
      _controller.animateTo(
        target.clamp(
          _controller.position.minScrollExtent,
          _controller.position.maxScrollExtent,
        ),
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final visible = widget.tiles.length < kMosaicBandVisible
            ? widget.tiles.length
            : kMosaicBandVisible;
        final gaps = _kGap.r * (visible - 1);
        _tileWidth = (constraints.maxWidth - gaps) / visible;

        return ListView.separated(
          controller: _controller,
          scrollDirection: Axis.horizontal,
          padding: EdgeInsets.zero,
          // Nothing to scroll to when everything already fits, and a strip that
          // bounces under a thumb reads as broken rather than as scrollable.
          physics: widget.tiles.length <= kMosaicBandVisible
              ? const NeverScrollableScrollPhysics()
              : const ClampingScrollPhysics(),
          itemCount: widget.tiles.length,
          separatorBuilder: (_, _) => SizedBox(width: _kGap.r),
          itemBuilder: (context, index) {
            final tile = widget.tiles[index];
            return SizedBox(
              width: _tileWidth,
              child: DiscoveryBandTile(
                tile: widget.present(tile),
                isSelected: identical(widget.selectedTile, tile),
                fileProvider: widget.fileProvider,
                onTap: () => widget.onTileTapped(tile),
              ),
            );
          },
        );
      },
    );
  }
}
