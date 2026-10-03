import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../dealer_client.dart';
import 'track_playback_api.dart';
import 'track_playback_state.dart';

/// 播放端要驱动的本机播放器（由 [PlaybackReceiverHost] 接到 PlaybackProvider）。
abstract class ReceiverHost {
  /// 播放 [order]（状态下标，按播放顺序，第一个为当前）对应的曲目，从 [positionMs] 起，[paused] 时停在该处。
  Future<void> load(
    TpStateMachine machine,
    List<int> order, {
    required int positionMs,
    required bool paused,
  });

  /// 当前曲目不变时只同步暂停 / 进度；[positionMs] 为 null（只改了循环 / 随机等）时不动进度。
  Future<void> sync({required int? positionMs, required bool paused});

  /// 服务端扩展了当前曲目的前后窗口；不重新加载当前音频。
  void updateQueue(TpStateMachine machine, List<int> order);

  /// 随机 / 循环方式。
  void applyOptions(TpOptions options);

  /// 0–1。
  void setVolume(double volume);

  /// 本机当前进度（毫秒）。
  int get positionMs;

  /// 远程把播放转走 / 登出：本机停止。
  Future<void> stop();
}

/// Spotify Connect 播放端：让 Flutify 出现在其他设备的「设备列表」里，被选中后在本机出声。
///
/// 协议为 track-playback（Web 播放器同款，免费账号可用）：
/// 1. 用 Web token 建立**独立的** dealer 连接（与遥控用的 dealer 身份不同），拿到 connection_id；
/// 2. `POST track-playback/v1/devices` 注册；每次 dealer 重连拿到新 id 都重新注册；
/// 3. dealer 推 `hm://track-playback/v1/command`：`replace_state`（播放 / 暂停 / 切歌 / 拖动全靠它）、
///    `set_volume`、`log_out`、`ping`；
/// 4. 本机状态变化（开始播放、暂停、恢复、切到下一状态、播满 30 秒）用 `PUT …/state` 汇报，
///    服务端据此更新其他设备上的显示；
/// 5. [stop] 时 `DELETE` 注销。
class ConnectReceiver {
  static const String defaultDeviceName = 'Flutify';

  final ReceiverHost host;

  /// 设备名：每次注册时读取，改名后 [stop] 再 [start] 即生效。
  final String Function() deviceName;
  final TrackPlaybackApi _api;
  final DealerClient _dealer;

  StreamSubscription<String>? _idSub;
  StreamSubscription<DealerMessage>? _msgSub;
  bool _started = false;
  bool _registered = false;

  TpStateMachine? _machine;
  int _stateIndex = -1;
  bool _paused = true;
  int _revision = 0;

  /// 本状态是否已汇报过「播满 30 秒」。
  bool _thresholdReported = false;

  ConnectReceiver({
    required this.host,
    required this.deviceName,
    required http.Client client,
    required Future<String> Function() webToken,
    required String deviceId,
    DealerClient? dealer,
  }) : _api = TrackPlaybackApi(
         client: client,
         webToken: webToken,
         deviceId: deviceId,
       ),
       _dealer =
           dealer ??
           DealerClient(
             client: client,
             headers: () async => {
               'Authorization': 'Bearer ${await webToken()}',
               'User-Agent': TrackPlaybackApi.userAgent,
             },
           );

  String get deviceId => _api.deviceId;

  /// 每次注册成功（含 dealer 重连后的重新注册）时调用。
  VoidCallback? onRegistered;

  /// 是否正被远程选中、由本机出声（有当前状态）。
  bool get isActive => _machine != null && _stateIndex >= 0;

  Future<void> start() async {
    if (_started) return;
    _started = true;
    _idSub = _dealer.connectionIds.listen(_register);
    _msgSub = _dealer.messages.listen(_onMessage);
    try {
      await _dealer.connect();
    } catch (e) {
      debugPrint('[Receiver] dealer 连接失败（后台重试）：$e');
    }
  }

  Future<void> stop() async {
    if (!_started) return;
    _started = false;
    await _idSub?.cancel();
    await _msgSub?.cancel();
    _clear();
    if (_registered) {
      _registered = false;
      try {
        await _api.deregister();
      } catch (e) {
        debugPrint('[Receiver] 注销失败：$e');
      }
    }
    await _dealer.close();
  }

  Future<void> _register(String connectionId) async {
    try {
      final name = deviceName();
      await _api.register(
        connectionId: connectionId,
        name: name,
        volume: 65535,
      );
      _registered = true;
      debugPrint('[Receiver] 已注册为 Connect 设备「$name」');
      onRegistered?.call();
    } catch (e) {
      debugPrint('[Receiver] 注册失败：$e');
    }
  }

  void _onMessage(DealerMessage message) {
    if (message.uri != 'hm://track-playback/v1/command') return;
    for (final raw in message.payloads) {
      if (raw is! Map) continue;
      final payload = raw.cast<String, dynamic>();
      final type = payload['type'];
      debugPrint('[Receiver] 命令 $type');
      switch (type) {
        case 'replace_state':
          final cmd = TpReplaceState.fromJson(payload);
          if (cmd != null) unawaited(_replaceState(cmd));
        case 'set_volume':
          final v = (payload['volume'] as num?)?.toDouble();
          if (v != null) host.setVolume((v / 65535).clamp(0.0, 1.0));
        case 'log_out':
          _clear();
          unawaited(host.stop());
        case 'ping':
          _report('ping');
      }
    }
  }

  Future<void> _replaceState(TpReplaceState cmd) async {
    final revision = ++_revision;
    final prev = _currentTrackUri;
    _machine = cmd.machine;
    _stateIndex = cmd.ref.stateIndex;
    _paused = cmd.ref.paused;
    _thresholdReported = false;
    final position = cmd.seekTo ?? 0;
    host.applyOptions(cmd.machine.options);
    try {
      if (prev != null && prev == _currentTrackUri) {
        host.updateQueue(cmd.machine, cmd.machine.advanceChain(_stateIndex));
        await host.sync(positionMs: cmd.seekTo, paused: _paused);
      } else {
        _report('before_track_load', positionMs: position);
        await host.load(
          cmd.machine,
          cmd.machine.advanceChain(_stateIndex),
          positionMs: position,
          paused: _paused,
        );
      }
      if (revision != _revision) return;
      _report(
        _paused ? 'pause' : 'started_playing',
        positionMs: cmd.seekTo ?? host.positionMs,
      );
    } catch (e) {
      debugPrint('[Receiver] 执行 replace_state 失败：$e');
    }
  }

  String? get _currentTrackUri {
    final m = _machine;
    final s = m?.state(_stateIndex);
    return s == null ? null : m!.trackOf(s)?.uri;
  }

  // ---------------------------------------------------------------------------
  // 本机播放器 → 服务端
  // ---------------------------------------------------------------------------

  /// 本机切到了曲目 [trackUri]（播完自动进入 / 本机点了上下一首）：按跳转表找到目标状态并汇报；
  /// 找不到（本机改播了别的歌）时清空状态，Flutify 不再是活动播放端。
  void onLocalTrackChanged(String trackUri, {required int durationMs}) {
    final m = _machine;
    final cur = m?.state(_stateIndex);
    if (m == null || cur == null) return;
    if (_currentTrackUri == trackUri) return;
    int? target;
    for (final (ref, _) in [
      (cur.advance, 'advance'),
      (cur.skipNext, 'next'),
      (cur.skipPrev, 'prev'),
    ]) {
      final s = ref == null ? null : m.state(ref.stateIndex);
      if (s != null && m.trackOf(s)?.uri == trackUri) {
        target = ref!.stateIndex;
        break;
      }
    }
    if (target == null) {
      debugPrint('[Receiver] 本机改播状态机外的曲目，退出 Connect 播放');
      _clear();
      _report('state_clear', clear: true);
      return;
    }
    _stateIndex = target;
    _revision++;
    _thresholdReported = false;
    _report('started_playing', positionMs: 0, durationMs: durationMs);
  }

  void onLocalPausedChanged(
    bool paused, {
    required int positionMs,
    required int durationMs,
  }) {
    if (!isActive || paused == _paused) return;
    _paused = paused;
    _report(
      paused ? 'pause' : 'resume',
      positionMs: positionMs,
      durationMs: durationMs,
    );
  }

  void onLocalSeek(int fromMs, int toMs, {required int durationMs}) {
    if (!isActive) return;
    _report(
      'seek',
      positionMs: toMs,
      durationMs: durationMs,
      previousPositionMs: fromMs,
    );
  }

  void onLocalProgress(int positionMs, {required int durationMs}) {
    if (!isActive || _thresholdReported || positionMs < 30000) return;
    _thresholdReported = true;
    _report(
      'played_threshold_reached',
      positionMs: positionMs,
      durationMs: durationMs,
    );
  }

  void onLocalVolume(double volume) {
    if (!isActive) return;
    unawaited(
      _api
          .putVolume((volume * 65535).round())
          .catchError((Object e) => debugPrint('[Receiver] $e')),
    );
  }

  void _clear() {
    _revision++;
    _machine = null;
    _stateIndex = -1;
    _paused = true;
  }

  void _report(
    String debugSource, {
    int positionMs = 0,
    int? durationMs,
    int? previousPositionMs,
    bool clear = false,
  }) {
    if (!_registered) return;
    final revision = _revision;
    // 串行发送：每条都要引用上一条响应换回来的新状态机，并发会引用已失效的 state_id
    _sending = _sending.then((_) async {
      if (revision != _revision || !_registered) return;
      final m = _machine;
      final s = m?.state(_stateIndex);
      final duration =
          durationMs ?? (s == null ? 0 : m!.trackOf(s)?.durationMs ?? 0);
      try {
        final res = await _api.putState(
          debugSource: debugSource,
          stateMachineId: clear ? null : m?.id,
          stateId: clear ? null : s?.stateId,
          paused: _paused,
          positionMs: positionMs,
          durationMs: duration,
          previousPositionMs: previousPositionMs,
        );
        debugPrint(
          '[Receiver] 汇报 $debugSource（${s?.stateId}, paused=$_paused, ${positionMs}ms）'
          '→ ${res == null ? '空响应' : res.keys.join(',')}',
        );
        if (revision == _revision && !clear) _adoptMachine(res);
      } catch (e) {
        debugPrint('[Receiver] $e');
      }
    });
  }

  Future<void> _sending = Future.value();

  /// 汇报响应里的新状态机（服务端扩展了前后曲目）：替换状态机，按 state_id 对回当前状态，不重新加载。
  void _adoptMachine(Map<String, dynamic>? res) {
    if (res == null) return;
    final next = TpStateMachine.fromJson(res['state_machine']);
    if (next == null) return;
    final ref = TpStateRef.fromJson(res['updated_state_ref']);
    final curId = _machine?.state(_stateIndex)?.stateId;
    final index =
        ref?.stateIndex ?? next.states.indexWhere((s) => s.stateId == curId);
    final state = next.state(index);
    if (state == null || next.trackOf(state)?.uri != _currentTrackUri) return;
    _machine = next;
    _stateIndex = index;
    host.updateQueue(next, next.advanceChain(index));
  }
}
