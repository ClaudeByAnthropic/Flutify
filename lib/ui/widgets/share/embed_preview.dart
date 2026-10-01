import 'package:flutter/material.dart';

import '../../../core/theme/flutify_tokens.dart';
import '../../../models/share_target.dart';
import '../cover_image.dart';

/// 嵌入播放器的示意预览：`EmbedWebView` 加载期间的占位，以及没有 WebView / 加载失败时的退回。
///
/// 按官方播放器的版式缩小绘制，随尺寸 / 主题即时变化：
/// - 标准：大封面 + 标题 / 副标题 + 右下角播放键；
/// - 紧凑：一行小封面 + 文字 + 播放键。
/// 深色为官方的 #282828；跟随封面时用强调色压暗模拟封面取色。
class EmbedPreview extends StatelessWidget {
  final ShareTarget target;
  final EmbedSize size;
  final bool dark;

  const EmbedPreview({super.key, required this.target, required this.size, required this.dark});

  /// 预览高度：约为真实高度的一半，保持两档的比例关系。
  static double heightFor(EmbedSize size) => size == EmbedSize.standard ? 168 : 76;

  static const Color _darkSurface = Color(0xFF282828);

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final duration = context.motion(const Duration(milliseconds: 320));
    final background = dark ? _darkSurface : Color.lerp(tokens.accent, Colors.black, 0.55)!;
    final height = heightFor(size);
    final compact = size == EmbedSize.compact;

    return ExcludeSemantics(
      child: AnimatedContainer(
        duration: duration,
        curve: Curves.easeOutCubic,
        height: height,
        padding: EdgeInsets.all(compact ? 10 : 14),
        decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(12)),
        child: LayoutBuilder(
          builder: (context, constraints) {
            // 封面为正方形：取内容区高度，但不超过宽度的 40%（极窄时给文字留位置）
            final cover = constraints.maxHeight.clamp(0.0, constraints.maxWidth * 0.4);
            return SizedBox(
              height: cover,
              child: Row(
                children: [
                  CoverImage(
                    url: target.imageUrl,
                    size: cover,
                    circular: target.kind == ShareKind.artist,
                    borderRadius: BorderRadius.circular(compact ? 6 : 8),
                    placeholderIcon: target.kind == ShareKind.artist ? Icons.person_rounded : Icons.music_note_rounded,
                  ),
                  SizedBox(width: compact ? 10 : 14),
                  Expanded(
                    child: _Texts(target: target, compact: compact),
                  ),
                  Align(
                    alignment: compact ? Alignment.center : Alignment.bottomRight,
                    child: _PlayDot(size: compact ? 32 : 40),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

/// 标题 + 副标题；标准尺寸下文字靠上，与官方版式一致。
class _Texts extends StatelessWidget {
  final ShareTarget target;
  final bool compact;

  const _Texts({required this.target, required this.compact});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      mainAxisAlignment: compact ? MainAxisAlignment.center : MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          target.title,
          maxLines: compact ? 1 : 2,
          overflow: TextOverflow.ellipsis,
          style: (compact ? textTheme.titleSmall : textTheme.titleMedium)?.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
        if (target.subtitle.isNotEmpty)
          Text(
            target.subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: textTheme.bodySmall?.copyWith(color: Colors.white70),
          ),
      ],
    );
  }
}

/// 官方播放器右下角的白底播放键。
class _PlayDot extends StatelessWidget {
  final double size;

  const _PlayDot({required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
      child: Icon(Icons.play_arrow_rounded, color: Colors.black, size: size * 0.6),
    );
  }
}
