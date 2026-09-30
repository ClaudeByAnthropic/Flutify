import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../../providers/auth_provider.dart';
import '../widgets/auth_form_parts.dart';

/// 阶段：导入可复用凭据（StoredCredential）。
///
/// 两种输入：粘贴 librespot `credentials.json`；或手动填写用户名 + Base64 凭据（+ 可选设备 ID）。
/// 导入后立即用 Login5 验证，验证通过才会保存。
class ImportStage extends StatefulWidget {
  const ImportStage({super.key});

  @override
  State<ImportStage> createState() => _ImportStageState();
}

enum _ImportMode { json, manual }

class _ImportStageState extends State<ImportStage> {
  _ImportMode _mode = _ImportMode.json;
  final _jsonController = TextEditingController();
  final _usernameController = TextEditingController();
  final _blobController = TextEditingController();
  final _deviceController = TextEditingController();

  @override
  void dispose() {
    _jsonController.dispose();
    _usernameController.dispose();
    _blobController.dispose();
    _deviceController.dispose();
    super.dispose();
  }

  Future<void> _pasteInto(TextEditingController controller) async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null) controller.text = data!.text!.trim();
  }

  void _submit() {
    FocusScope.of(context).unfocus();
    final auth = context.read<AuthProvider>();
    if (_mode == _ImportMode.json) {
      auth.importCredential(json: _jsonController.text);
    } else {
      auth.importCredential(
        username: _usernameController.text,
        blob: _blobController.text,
        deviceId: _deviceController.text,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final busy = auth.status == AuthStatus.signingIn;
    const mono = TextStyle(fontFamily: 'monospace', fontSize: 13);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        StageHeader(
          leading: StageHeader.icon(Icons.key_rounded),
          title: '导入已保存凭据',
          subtitle: '复用其他客户端登录后保存的凭据，无需密码与验证码',
        ),
        SegmentedButton<_ImportMode>(
          segments: const [
            ButtonSegment(value: _ImportMode.json, label: Text('credentials.json')),
            ButtonSegment(value: _ImportMode.manual, label: Text('手动填写')),
          ],
          selected: {_mode},
          showSelectedIcon: false,
          onSelectionChanged: busy ? null : (s) => setState(() => _mode = s.first),
        ),
        const SizedBox(height: 16),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: _mode == _ImportMode.json
              ? TextField(
                  key: const ValueKey('json'),
                  controller: _jsonController,
                  enabled: !busy,
                  minLines: 4,
                  maxLines: 8,
                  style: mono,
                  decoration: InputDecoration(
                    hintText: '{"username":"…","auth_type":1,"auth_data":"…"}',
                    border: const OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(20)),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: const OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(20)),
                      borderSide: BorderSide.none,
                    ),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.content_paste_rounded),
                      tooltip: '粘贴',
                      onPressed: () => _pasteInto(_jsonController),
                    ),
                  ),
                )
              : Column(
                  key: const ValueKey('manual'),
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: _usernameController,
                      enabled: !busy,
                      autocorrect: false,
                      decoration: const InputDecoration(
                        hintText: '用户名（Spotify 用户 ID）',
                        prefixIcon: Icon(Icons.person_outline_rounded),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _blobController,
                      enabled: !busy,
                      autocorrect: false,
                      style: mono,
                      decoration: InputDecoration(
                        hintText: '凭据（Base64）',
                        prefixIcon: const Icon(Icons.key_rounded),
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.content_paste_rounded),
                          tooltip: '粘贴',
                          onPressed: () => _pasteInto(_blobController),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _deviceController,
                      enabled: !busy,
                      autocorrect: false,
                      style: mono,
                      decoration: const InputDecoration(
                        hintText: '设备 ID（可选）',
                        prefixIcon: Icon(Icons.devices_rounded),
                      ),
                    ),
                  ],
                ),
        ),
        AuthErrorBanner(message: auth.error),
        const SizedBox(height: 24),
        AuthPrimaryButton(label: '验证并导入', busyLabel: '正在验证凭据…', busy: busy, onPressed: _submit),
        const SizedBox(height: 28),
        const AuthHint(
          icon: Icons.info_outline_rounded,
          text: '凭据与生成它的设备 ID 绑定，跨设备使用时请一并填写原设备 ID，否则可能验证失败。'
              '凭据等同于账号密码，请勿泄露。',
        ),
      ],
    );
  }
}
