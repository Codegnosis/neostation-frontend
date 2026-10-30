import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localization/flutter_localization.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:neostation/l10n/app_locale.dart';

import '../../../models/game_model.dart';
import '../../../providers/file_provider.dart';
import '../../../themes/corner_radii.dart';
import '../../../widgets/marquee_text.dart';
import '../discovery_mosaic.dart';

/// One cell of the mosaic's 3x2 grid.
///
/// Reads like the concept's category tiles: scene art edge to edge with the
/// label burned across the foot of it, rather than a cover with a caption
/// underneath. The game's own name sits under the label, smaller, because here
/// the tile is a single game and not a category to browse.
class DiscoveryGridTile extends StatelessWidget {
  const DiscoveryGridTile({
    super.key,
    required this.tile,
    required this.isSelected,
    required this.fileProvider,
    this.onTap,
  });

  final DiscoveryTile tile;
  final bool isSelected;
  final FileProvider fileProvider;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final entry = tile.entry;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: discoveryTileBackground(context),
        foregroundDecoration: discoveryTileBorder(
          context,
          isSelected: isSelected,
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            DiscoveryTileArt(tile: tile, fileProvider: fileProvider),
            const _BottomScrim(),
            Padding(
              padding: EdgeInsets.all(8.r),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    tile.labelKey.getString(context).toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13.r,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.6.r,
                      height: 1.1,
                      color: Colors.white,
                      shadows: const [
                        Shadow(blurRadius: 6, color: Colors.black87),
                      ],
                    ),
                  ),
                  // Grid tiles are narrow and truncate most names, and the
                  // board has nowhere else to print one in full, so the focused
                  // tile scrolls its title the way the game lists do.
                  if (entry != null)
                    MarqueeText(
                      text: entry.game.realName ?? entry.game.filename,
                      isActive: isSelected,
                      style: TextStyle(
                        fontSize: 8.r,
                        fontWeight: FontWeight.w500,
                        color: Colors.white.withValues(alpha: 0.72),
                        shadows: const [
                          Shadow(blurRadius: 4, color: Colors.black87),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            if (_isNeverPlayed(tile))
              // Bounded on the left so a long translation ellipsises before it
              // reaches the selection icon (6.r + 14.r) in the opposite corner.
              Positioned(
                top: 6.r,
                left: 24.r,
                right: 6.r,
                child: const Align(
                  alignment: Alignment.centerRight,
                  child: DiscoveryNeverPlayedBadge(),
                ),
              ),
            if (isSelected)
              Positioned(
                top: 6.r,
                left: 6.r,
                child: Icon(
                  tile.icon,
                  size: 14.r,
                  color: scheme.primary,
                  shadows: const [Shadow(blurRadius: 6, color: Colors.black)],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// One of the short, wide tiles along the foot of the board.
///
/// Carries an icon chip beside its label the way the concept's bottom row does,
/// which is what separates the two one-off features from the genre picks
/// sharing the strip with them.
class DiscoveryBandTile extends StatelessWidget {
  const DiscoveryBandTile({
    super.key,
    required this.tile,
    required this.isSelected,
    required this.fileProvider,
    this.onTap,
  });

  final DiscoveryTile tile;
  final bool isSelected;
  final FileProvider fileProvider;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final entry = tile.entry;
    final notice = tile.noticeKey;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: discoveryTileBackground(context),
        foregroundDecoration: discoveryTileBorder(
          context,
          isSelected: isSelected,
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            DiscoveryTileArt(tile: tile, fileProvider: fileProvider),
            // Wide tiles carry their text across the art rather than under
            // it, so they need a scrim over the whole face and not just the
            // foot of it.
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [
                    Colors.black.withValues(alpha: 0.85),
                    Colors.black.withValues(alpha: 0.3),
                  ],
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 8.r, vertical: 6.r),
              child: Row(
                children: [
                  Container(
                    padding: EdgeInsets.all(5.r),
                    decoration: BoxDecoration(
                      color: scheme.primary.withValues(alpha: 0.9),
                      borderRadius: BorderRadius.circular(8.r),
                    ),
                    child: Icon(tile.icon, size: 12.r, color: scheme.onPrimary),
                  ),
                  SizedBox(width: 7.r),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          tile.labelKey.getString(context).toUpperCase(),
                          // Two lines: a long section name such as
                          // Achievement Spotlight otherwise ellipsises before
                          // it can be read.
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 9.r,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.5.r,
                            height: 1.2,
                            color: Colors.white,
                          ),
                        ),
                        MarqueeText(
                          text: notice != null
                              ? notice.getString(context)
                              : entry?.game.realName ??
                                    entry?.game.filename ??
                                    '',
                          isActive: isSelected,
                          style: TextStyle(
                            fontSize: 7.5.r,
                            color: Colors.white.withValues(alpha: 0.7),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (tile.achievementCount > 0)
                    Text(
                      '${tile.achievementCount}',
                      style: TextStyle(
                        fontSize: 8.r,
                        fontWeight: FontWeight.w700,
                        color: Colors.white.withValues(alpha: 0.75),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The badge marking a game the user has never launched — the whole point of
/// most of the board, so it is called out on the tile itself.
class DiscoveryNeverPlayedBadge extends StatelessWidget {
  const DiscoveryNeverPlayedBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 7.r, vertical: 3.r),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(999.r),
      ),
      child: Text(
        AppLocale.discoveryNeverPlayed.getString(context),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 8.r,
          fontWeight: FontWeight.w700,
          color: theme.colorScheme.onPrimary,
        ),
      ),
    );
  }
}

/// The art behind a tile.
///
/// Landscape art first: these tiles are wider than they are tall, so a scene
/// fills them where a cover would be cropped to its middle. Box art is the
/// fallback for the many games scraped without either.
class DiscoveryTileArt extends StatelessWidget {
  const DiscoveryTileArt({
    super.key,
    required this.tile,
    required this.fileProvider,
  });

  final DiscoveryTile tile;
  final FileProvider fileProvider;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final entry = tile.entry;
    final folder = entry?.game.systemFolderName ?? '';
    // A notice stands for a section that has no pick, so it has no art and no
    // missing art either: the placeholder would read as a broken tile.
    if (entry == null) return const SizedBox.shrink();

    final path = folder.isEmpty
        ? null
        : discoveryFirstExistingImage([
            GameModel.fromDatabaseModel(
              entry.game,
            ).getImagePath(folder, 'fanarts', fileProvider),
            GameModel.fromDatabaseModel(
              entry.game,
            ).getImagePath(folder, 'screenshots', fileProvider),
            GameModel.fromDatabaseModel(
              entry.game,
            ).getImagePath(folder, 'box2d', fileProvider),
          ]);

    if (path == null) return _placeholder(theme);

    return LayoutBuilder(
      builder: (context, constraints) => Image.file(
        File(path),
        fit: BoxFit.cover,
        // Decode at roughly the size actually drawn: a board of
        // full-resolution art is the fastest way to blow the image cache on a
        // handheld.
        cacheWidth: constraints.maxWidth.isFinite
            ? (constraints.maxWidth * 2).round()
            : 640,
        errorBuilder: (_, _, _) => _placeholder(theme),
      ),
    );
  }

  Widget _placeholder(ThemeData theme) => ColoredBox(
    color: theme.cardColor.withValues(alpha: 0.45),
    child: Center(
      child: Icon(
        Symbols.videogame_asset_rounded,
        size: 22.r,
        color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
      ),
    ),
  );
}

/// A tile's shape: its corner radius, shared by the clip and both decorations.
BorderRadius discoveryTileRadius(BuildContext context) =>
    Theme.of(context).extension<CornerRadii>()?.radiusInternal ??
    BorderRadius.circular(10.r);

/// What sits behind a tile, in the gap art of the wrong aspect leaves.
BoxDecoration discoveryTileBackground(BuildContext context) => BoxDecoration(
  color: Theme.of(context).cardColor.withValues(alpha: 0.35),
  borderRadius: discoveryTileRadius(context),
);

/// The frame every tile shares: a hairline normally, the primary colour when
/// the cursor is on it.
///
/// Belongs in a `foregroundDecoration`, never in the background one. Tile art
/// is clipped to the same rounded rect the border is drawn on, so a background
/// border is painted over by the art — the ring vanishes on any tile that has
/// artwork, which is all of them.
BoxDecoration discoveryTileBorder(
  BuildContext context, {
  required bool isSelected,
}) {
  final theme = Theme.of(context);
  return BoxDecoration(
    borderRadius: discoveryTileRadius(context),
    border: Border.all(
      color: isSelected
          ? theme.colorScheme.primary
          : theme.colorScheme.onSurface.withValues(alpha: 0.12),
      width: isSelected ? 2.r : 1.r,
    ),
  );
}

/// The first path that is actually on disk, or null.
///
/// `getImagePath` returns a best-effort path even when nothing matched, so the
/// existence check is what decides between fanart, screenshot, cover and
/// placeholder.
String? discoveryFirstExistingImage(List<String> paths) {
  for (final path in paths) {
    if (path.isNotEmpty && File(path).existsSync()) return path;
  }
  return null;
}

bool _isNeverPlayed(DiscoveryTile tile) {
  final game = tile.entry?.game;
  if (game == null) return false;
  return game.lastPlayed == null && (game.playTime ?? 0) == 0;
}

/// The gradient that keeps a label legible over arbitrary art.
class _BottomScrim extends StatelessWidget {
  const _BottomScrim();

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.bottomCenter,
        end: Alignment.topCenter,
        colors: [
          Colors.black.withValues(alpha: 0.88),
          Colors.black.withValues(alpha: 0.1),
        ],
        stops: const [0.0, 0.65],
      ),
    ),
  );
}
