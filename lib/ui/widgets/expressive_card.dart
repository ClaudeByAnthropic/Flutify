import 'package:flutter/material.dart';
import '../../core/theme/md3e_shapes.dart';
import 'cover_image.dart';

class ExpressiveCard extends StatelessWidget {
  final String title;
  final String? subtitle;
  final String imageUrl;
  final bool isCircular;
  final VoidCallback onTap;
  final VoidCallback? onPlayTap;
  final double width;

  const ExpressiveCard({
    super.key,
    required this.title,
    this.subtitle,
    required this.imageUrl,
    this.isCircular = false,
    required this.onTap,
    this.onPlayTap,
    this.width = 148,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      width: width,
      margin: const EdgeInsets.only(right: 14.0),
      child: InkWell(
        onTap: onTap,
        borderRadius: MD3EShapes.roundedLarge,
        child: Padding(
          padding: const EdgeInsets.all(6.0),
          child: Column(
            crossAxisAlignment: isCircular ? CrossAxisAlignment.center : CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Artwork Container
              Stack(
                children: [
                  AspectRatio(
                    aspectRatio: 1.0,
                    child: Container(
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHigh,
                        shape: isCircular ? BoxShape.circle : BoxShape.rectangle,
                        borderRadius: isCircular ? null : MD3EShapes.roundedMedium,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withAlpha(60),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: CoverImage(
                        url: imageUrl,
                        size: width - 12,
                        placeholderIcon: isCircular ? Icons.person_rounded : Icons.music_note_rounded,
                      ),
                    ),
                  ),

                  // Floating Play Button
                  if (onPlayTap != null)
                    Positioned(
                      bottom: 8,
                      right: 8,
                      child: GestureDetector(
                        onTap: onPlayTap,
                        child: Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: colorScheme.primary,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withAlpha(120),
                                blurRadius: 8,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.play_arrow_rounded,
                            color: Colors.black,
                            size: 26,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 10),

              // Title
              Text(
                title,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: colorScheme.onSurface,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: isCircular ? TextAlign.center : TextAlign.start,
              ),

              // Subtitle
              if (subtitle != null && subtitle!.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: isCircular ? TextAlign.center : TextAlign.start,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
