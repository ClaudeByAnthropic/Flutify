import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/md3e_shapes.dart';

/// 分格验证码输入框（iOS 一次性验证码风格）。
///
/// 实现：一个透明的 TextField 覆盖在分格之上负责真正的输入 / 粘贴 / 系统自动填充，
/// 分格只负责展示；输满 [length] 位时回调 [onCompleted]。
class CodeInputField extends StatefulWidget {
  final int length;
  final TextEditingController controller;
  final ValueChanged<String>? onCompleted;
  final bool enabled;
  final bool hasError;

  const CodeInputField({
    super.key,
    required this.length,
    required this.controller,
    this.onCompleted,
    this.enabled = true,
    this.hasError = false,
  });

  @override
  State<CodeInputField> createState() => _CodeInputFieldState();
}

class _CodeInputFieldState extends State<CodeInputField> {
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChanged);
    _focus.addListener(_onChanged);
    // 进入页面即弹出键盘
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.enabled) _focus.requestFocus();
    });
  }

  @override
  void didUpdateWidget(covariant CodeInputField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onChanged);
      widget.controller.addListener(_onChanged);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChanged);
    _focus.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final text = widget.controller.text;
    final focused = _focus.hasFocus;

    return SizedBox(
      height: 60,
      child: Stack(
        children: [
          Row(
            children: [
              for (var i = 0; i < widget.length; i++) ...[
                if (i > 0) const SizedBox(width: 8),
                Expanded(
                  child: _CodeCell(
                    char: i < text.length ? text[i] : '',
                    // 光标所在格高亮；输满后最后一格保持高亮
                    active: focused && (i == text.length || (text.length == widget.length && i == widget.length - 1)),
                    hasError: widget.hasError,
                    colorScheme: colorScheme,
                  ),
                ),
              ],
            ],
          ),
          Positioned.fill(
            child: TextField(
              controller: widget.controller,
              focusNode: _focus,
              enabled: widget.enabled,
              autofillHints: const [AutofillHints.oneTimeCode],
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(widget.length),
              ],
              showCursor: false,
              enableInteractiveSelection: false,
              style: const TextStyle(color: Colors.transparent, fontSize: 1),
              decoration: const InputDecoration(
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                disabledBorder: InputBorder.none,
                counterText: '',
              ),
              onChanged: (value) {
                if (value.length == widget.length) widget.onCompleted?.call(value);
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _CodeCell extends StatelessWidget {
  final String char;
  final bool active;
  final bool hasError;
  final ColorScheme colorScheme;

  const _CodeCell({
    required this.char,
    required this.active,
    required this.hasError,
    required this.colorScheme,
  });

  @override
  Widget build(BuildContext context) {
    final borderColor = hasError
        ? colorScheme.error
        : active
            ? colorScheme.primary
            : Colors.transparent;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOut,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh,
        borderRadius: MD3EShapes.roundedMedium,
        border: Border.all(color: borderColor, width: 1.5),
      ),
      child: Text(
        char,
        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
      ),
    );
  }
}
