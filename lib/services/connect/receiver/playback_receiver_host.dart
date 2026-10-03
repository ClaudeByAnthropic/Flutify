import 'dart:async';

import '../../../models/album.dart';
import '../../../models/artist.dart';
import '../../../models/image.dart';
import '../../../models/playback_context.dart';
import '../../../models/playback_state.dart';
import '../../../models/track.dart';
import '../../../providers/playback_provider.dart';
import 'connect_receiver.dart';
import 'track_playback_state.dart';

/// 把 [ConnectReceiver] 接到本机 [PlaybackProvider]：
/// - 远程命令 → 本机播放（[playLocal] 不经远程转发）；
/// - 本机状态变化（切歌 / 暂停 / 拖动 / 播满 30 秒 / 音量）→ 回报给 [ConnectReceiver]。
///
/// 本机按状态机的「播完自动进入」顺序排队，播完一首由 PlaybackProvider 自己接下一首，
/// 再由 [ConnectReceiver.onLocalTrackChanged] 对回状态机里的目标状态。
class PlaybackReceiverHost implements ReceiverHost {
  final PlaybackProvider playback;
  late final ConnectReceiver receiver;

  String? _lastTrackUri;
  bool _lastPlaying = false;
  int _lastPositionMs = 0;
  double _lastVolume;

  /// 正在执行远程命令：期间本机变化是命令造成的，不回报。
  int _applyingCount = 0;
  bool get _applying => _applyingCount > 0;

  /// 本机在 Connect 之外开始出声（继续上次的歌、本地队列切歌等）时调用：把当前曲目、待播与进度
  /// 交给服务端，服务端再以 replace_state 下发回本机。和官方客户端一样，任何播放都对其他设备可见。
  Future<void> Function(int positionMs)? handOver;
  bool _handingOver = false;
  String? _handedOverUri;

  /// 本机改了随机 / 循环时调用：经 Connect 命令发给服务端（本机即目标设备），其他设备同步显示。
  void Function(bool shuffle, SpotifyRepeatMode repeat)? onLocalOptions;
  bool _applyingOptions = false;
  late bool _lastShuffle = playback.shuffle;
  late SpotifyRepeatMode _lastRepeat = playback.repeatMode;

  PlaybackReceiverHost(this.playback) : _lastVolume = playback.volume {
    playback.addListener(_onPlaybackChanged);
    playback.positionNotifier.addListener(_onPosition);
  }

  void dispose() {
    playback.removeListener(_onPlaybackChanged);
    playback.positionNotifier.removeListener(_onPosition);
  }

  @override
  Future<void> load(
    TpStateMachine machine,
    List<int> order, {
    required int positionMs,
    required bool paused,
  }) async {
    final tracks = [
      for (final i in order)
        if (machine.trackOf(machine.states[i]) case final t?) _toTrack(t),
    ];
    if (tracks.isEmpty) return;
    // 交接回来的就是正在放的这首：只对齐进度 / 暂停，不重新加载
    if (playback.currentTrack?.uri == tracks.first.uri) {
      _lastTrackUri = tracks.first.uri;
      updateQueue(machine, order);
      return sync(positionMs: positionMs, paused: paused);
    }
    await _apply(() async {
      _lastTrackUri = tracks.first.uri;
      await playback.playLocal(
        tracks.first,
        contextQueue: tracks,
        context: PlaybackContext.none,
        startAt: Duration(milliseconds: positionMs),
        paused: paused,
      );
      // 服务端已经排过随机顺序，本机不要再随机一次。
      playback.updateReceiverQueue(tracks);
    });
  }

  @override
  void updateQueue(TpStateMachine machine, List<int> order) {
    _applyingCount++;
    try {
      playback.updateReceiverQueue([
        for (final i in order)
          if (machine.state(i) case final state?)
            if (machine.trackOf(state) case final track?) _toTrack(track),
      ]);
    } finally {
      _applyingCount--;
    }
  }

  @override
  int get positionMs => playback.position.inMilliseconds;

  @override
  void applyOptions(TpOptions options) {
    _applyingOptions = true;
    if (options.shuffle case final shuffle?) playback.setShuffle(shuffle);
    if (options.repeatTrack != null || options.repeatContext != null) {
      final track =
          options.repeatTrack ?? playback.repeatMode == SpotifyRepeatMode.track;
      final context =
          options.repeatContext ?? playback.repeatMode != SpotifyRepeatMode.off;
      playback.setRepeatMode(
        track
            ? SpotifyRepeatMode.track
            : context
            ? SpotifyRepeatMode.context
            : SpotifyRepeatMode.off,
      );
    }
    _lastShuffle = playback.shuffle;
    _lastRepeat = playback.repeatMode;
    _applyingOptions = false;
  }

  @override
  Future<void> sync({required int? positionMs, required bool paused}) =>
      _apply(() async {
        if (positionMs != null &&
            (playback.position.inMilliseconds - positionMs).abs() > 2000) {
          await playback.seekTo(Duration(milliseconds: positionMs));
        }
        if (paused) {
          await playback.pause();
        } else if (!playback.isPlaying) {
          await playback.togglePlayPause();
        }
      });

  @override
  void setVolume(double volume) {
    _lastVolume = volume;
    playback.setVolume(volume, persist: true);
  }

  @override
  Future<void> stop() => _apply(playback.pause);

  Future<void> _apply(Future<void> Function() action) async {
    _applyingCount++;
    try {
      await action();
    } finally {
      _applyingCount--;
      _lastPlaying = playback.isPlaying;
      _lastPositionMs = playback.position.inMilliseconds;
    }
  }

  void _onPlaybackChanged() {
    if (_applying) return;
    final track = playback.currentTrack;
    final durationMs = playback.duration.inMilliseconds;
    final position = playback.position.inMilliseconds;
    if (track != null && track.uri != _lastTrackUri) {
      _lastTrackUri = track.uri;
      receiver.onLocalTrackChanged(track.uri, durationMs: durationMs);
    }
    // 出声了但服务端不知道：交接一次（同一首只交接一次，失败不反复重试）
    if (playback.isPlaying &&
        !receiver.isActive &&
        track != null &&
        !_handingOver &&
        _handedOverUri != track.uri) {
      final hand = handOver;
      if (hand != null) {
        _handingOver = true;
        _handedOverUri = track.uri;
        unawaited(hand(position).whenComplete(() => _handingOver = false));
      }
    }
    // 加载 / 缓冲中的「未播放」不算暂停
    if (!playback.isBuffering && playback.isPlaying != _lastPlaying) {
      _lastPlaying = playback.isPlaying;
      receiver.onLocalPausedChanged(
        !_lastPlaying,
        positionMs: position,
        durationMs: durationMs,
      );
    }
    if (!_applyingOptions &&
        (playback.shuffle != _lastShuffle ||
            playback.repeatMode != _lastRepeat)) {
      _lastShuffle = playback.shuffle;
      _lastRepeat = playback.repeatMode;
      if (receiver.isActive) onLocalOptions?.call(_lastShuffle, _lastRepeat);
    }
    if ((playback.volume - _lastVolume).abs() > 0.01) {
      _lastVolume = playback.volume;
      receiver.onLocalVolume(_lastVolume);
    }
  }

  void _onPosition() {
    final pos = playback.position.inMilliseconds;
    final prev = _lastPositionMs;
    _lastPositionMs = pos;
    if (_applying) return;
    final durationMs = playback.duration.inMilliseconds;
    // 进度流约每 200ms 一次，跳变超过 3 秒视为拖动
    if ((pos - prev).abs() > 3000 &&
        playback.currentTrack?.uri == _lastTrackUri) {
      receiver.onLocalSeek(prev, pos, durationMs: durationMs);
    }
    receiver.onLocalProgress(pos, durationMs: durationMs);
  }

  static SpotifyTrack _toTrack(TpTrack t) {
    String idOf(String uri) => uri.split(':').last;
    final images = [for (final url in t.imageUrls) SpotifyImage(url: url)];
    return SpotifyTrack(
      id: idOf(t.uri),
      name: t.name,
      uri: t.uri,
      durationMs: t.durationMs,
      explicit: t.explicit,
      artists: [
        for (final a in t.artists)
          SpotifyArtist(id: idOf(a.uri), name: a.name, uri: a.uri),
      ],
      album: SpotifyAlbum(
        id: idOf(t.albumUri),
        name: t.albumName,
        uri: t.albumUri,
        images: images,
      ),
    );
  }
}
