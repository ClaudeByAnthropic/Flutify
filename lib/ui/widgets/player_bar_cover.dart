import 'package:flutter/material.dart';

import '../../core/theme/flutify_tokens.dart';
import '../../l10n/l10n.dart';
import '../shell/shell_layout_controller.dart';
import 'cover_image.dart';
import 'hover_builder.dart';

/// 播放栏左侧封面（本机 / 远程播放栏共用），与官方桌面端一致：
///
/// - 三栏框架下右栏没有显示「播放状态」时：悬停浮出右上角展开箭头，点击打开右栏「正在播放」；
/// - 右栏已显示时：点击执行 [onOpenFallback]（本机为全屏播放器，远程为空 = 不响应）；
/// - 没有框架（[layout] 为 null）时同样执行 [onOpenFallback]。
class PlayerBarCover extends StatelessWidget {
  static const double size = 56;

  final String url;
  final ShellLayoutController? layout;
  final VoidCallback? onOpenFallback;

  const PlayerBarCover({super.key, required this.url, required this.layout, this.onOpenFallback});

  @override
  Widget build(BuildContext context) {
    final layout = this.layout;
    final canExpand = layout != null && !layout.playbackStatusVisible;
    final onTap = canExpand ? layout.togglePlaybackStatus : onOpenFallback;
    final radius = BorderRadius.circular(8);

    final cover = HoverBuilder(
      builder: (context, hovered) => Stack(
        children: [
          CoverImage(url: url, size: size, borderRadius: radius),
          if (canExpand)
            Positioned(
              top: 4,
              right: 4,
              child: AnimatedOpacity(
                opacity: hovered ? 1 : 0,
                duration: context.motion(const Duration(milliseconds: 140)),
                child: const _ExpandBadge(),
              ),
            ),
        ],
      ),
    );

    if (onTap == null) return cover;
    return Tooltip(
      message: canExpand ? context.l10n.shellPlaybackStatus : context.l10n.openNowPlaying,
      child: InkWell(borderRadius: radius, onTap: onTap, child: cover),
    );
  }
}

/// 封面右上角的展开箭头：半透明深色圆底 + 白色上箭头。
class _ExpandBadge extends StatelessWidget {
  const _ExpandBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(color: Colors.black.withAlpha(170), shape: BoxShape.circle),
      child: const Icon(Icons.keyboard_arrow_up_rounded, size: 18, color: Colors.white),
    );
  }
}
