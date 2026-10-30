import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localization/flutter_localization.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../models/game_model.dart';
import '../../../providers/file_provider.dart';
import '../../../themes/corner_radii.dart';
import '../../search_screen/search_filter.dart';
import '../discovery_mosaic.dart';
import 'discovery_tile.dart';

/// The board's headline panel: the tall tile down the left of the mosaic.
///
/// Built entirely from the user's own scraped art — fanart behind, the game's
/// wheel logo in front — so it looks like a storefront without any of the
/// content coming from outside the device. It takes whatever box the mosaic
/// gives it rather than sizing itself, since its height is the height of the
/// grid beside it.
class DiscoveryHeroCard extends StatelessWidget {
  const DiscoveryHeroCard({
    super.key,
    required this.tile,
    required this.isSelected,
    required this.fileProvider,
    required this.weekLabel,
    this.onTap,
  });

  final DiscoveryTile tile;
  final bool isSelected;
  final FileProvider fileProvider;

  /// Human-readable week, already localized by the caller.
  final String weekLabel;

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final radii = theme.extension<CornerRadii>();
    final entry = tile.entry!;
    final game = GameModel.fromDatabaseModel(entry.game);
    final folder = entry.game.systemFolderName ?? '';

    final backdrop = folder.isEmpty
        ? null
        : discoveryFirstExistingImage([
            game.getImagePath(folder, 'fanarts', fileProvider),
            game.getImagePath(folder, 'screenshots', fileProvider),
            game.getImagePath(folder, 'box2d', fileProvider),
          ]);
    final wheel = folder.isEmpty
        ? null
        : discoveryFirstExistingImage([
            game.getImagePath(folder, 'wheels', fileProvider),
          ]);

    final rating = entry.game.rating;
    final hasRating = rating != null && rating > 0;

    final radius = radii?.radiusExternal ?? BorderRadius.circular(14.r);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: theme.cardColor.withValues(alpha: 0.3),
          borderRadius: radius,
        ),
        // The ring goes in front of the art, not behind it: the backdrop is
        // clipped to this same rounded rect, so a background border is painted
        // over — which read as a corner cut off rather than as a missing ring.
        foregroundDecoration: BoxDecoration(
          borderRadius: radius,
          border: Border.all(
            color: isSelected
                ? scheme.primary
                : scheme.primary.withValues(alpha: 0.15),
            width: isSelected ? 2.r : 1.r,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (backdrop != null)
              Image.file(
                File(backdrop),
                fit: BoxFit.cover,
                cacheWidth: 1280,
                errorBuilder: (_, _, _) => const SizedBox.shrink(),
              ),
            // The art is arbitrary, so the text needs its own contrast rather
            // than trusting whatever happens to be behind it. The panel is
            // taller than it is wide now, so the scrim runs bottom-up: it sits
            // under the title block and leaves the middle of the art clear.
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.9),
                    Colors.black.withValues(alpha: 0.15),
                  ],
                  stops: const [0.15, 0.85],
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.all(12.r),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _buildBanner(context, scheme),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (wheel != null)
                        ConstrainedBox(
                          constraints: BoxConstraints(
                            maxHeight: 52.r,
                            maxWidth: 240.r,
                          ),
                          child: Image.file(
                            File(wheel),
                            fit: BoxFit.contain,
                            alignment: Alignment.centerLeft,
                            cacheWidth: 480,
                            errorBuilder: (_, _, _) =>
                                _titleText(context, scheme),
                          ),
                        )
                      else
                        _titleText(context, scheme),
                      SizedBox(height: 8.r),
                      Row(
                        children: [
                          if (hasRating)
                            _Pill(
                              icon: Symbols.star_rounded,
                              // Stored 0..20, shown out of 10 — the scale the
                              // rest of the app displays.
                              label: searchRatingScore(
                                rating,
                              ).toStringAsFixed(1),
                              color: scheme.primary,
                            ),
                          if (hasRating) SizedBox(width: 6.r),
                          _Pill(
                            icon: Symbols.sports_esports_rounded,
                            label:
                                entry.game.systemShortName ??
                                entry.game.systemRealName ??
                                '',
                            color: Colors.white,
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The section banner across the top: what this panel is, and for which week.
  ///
  /// The label is the tile's rather than a constant, because a board with no
  /// eligible Game of the Week promotes another pick into the headline and the
  /// banner has to say so.
  Widget _buildBanner(BuildContext context, ColorScheme scheme) => Row(
    children: [
      Container(
        padding: EdgeInsets.symmetric(horizontal: 8.r, vertical: 4.r),
        decoration: BoxDecoration(
          color: scheme.primary.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(999.r),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(tile.icon, size: 12.r, color: scheme.onPrimary),
            SizedBox(width: 5.r),
            Text(
              tile.labelKey.getString(context).toUpperCase(),
              style: TextStyle(
                fontSize: 9.r,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.8.r,
                color: scheme.onPrimary,
              ),
            ),
          ],
        ),
      ),
      // Expanded rather than a Spacer and a Flexible: those two split the
      // leftover width between them, which left the week label half the room
      // it needed and ellipsized the year.
      SizedBox(width: 6.r),
      Expanded(
        child: Text(
          weekLabel,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.right,
          style: TextStyle(
            fontSize: 8.r,
            color: Colors.white.withValues(alpha: 0.7),
            shadows: const [Shadow(blurRadius: 4, color: Colors.black87)],
          ),
        ),
      ),
    ],
  );

  Widget _titleText(BuildContext context, ColorScheme scheme) => Text(
    tile.entry!.game.realName ?? tile.entry!.game.filename,
    maxLines: 2,
    overflow: TextOverflow.ellipsis,
    style: TextStyle(
      fontSize: 18.r,
      fontWeight: FontWeight.w800,
      color: Colors.white,
      shadows: const [Shadow(blurRadius: 8, color: Colors.black87)],
    ),
  );
}

class _Pill extends StatelessWidget {
  const _Pill({required this.icon, required this.label, required this.color});

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    if (label.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8.r, vertical: 4.r),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999.r),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10.r, color: color),
          SizedBox(width: 4.r),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 8.r,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
