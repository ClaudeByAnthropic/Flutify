import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import '../models/playback_context.dart';
import '../models/playback_error.dart';
import '../models/playback_state.dart';
import '../models/track.dart';
import '../services/audio_player_service.dart';
import '../services/protocol/track_audio_loader.dart';
import '../services/storage_service.dart';

export '../models/playback_error.dart';

/// 队列条目：[uid] 在所属列表中唯一，用作拖拽排序时的稳定 Key
/// （同一首歌可能被多次加入队列）。
class QueueEntry {
  final int uid;
  final SpotifyTrack track;

  const QueueEntry(this.uid, this.track);
}

/// 播放状态与队列管理。
///
/// 性能约定：
/// - 播放进度（每秒多次）只写入 [positionNotifier]，**不会**调用 notifyListeners，
///   需要进度的组件通过 ValueListenableBuilder 局部重建。
/// - 其余低频状态（切歌、播放/暂停、随机、循环、队列、音量）走 notifyListeners，
///   组件应使用 `context.select` 只订阅自己关心的字段。
///
/// 队列语义与 Spotify 一致：
/// - [userQueue]：用户手动 "Add to queue" 的曲目，优先播放（Next in queue）。
/// - [upNext]：当前上下文（歌单/专辑等）中剩余的曲目（Next from: ...）。
class PlaybackProvider extends ChangeNotifier {
  final AudioPlayerService _audio;
  final StorageService _storage;

  /// 协议链路完整曲目加载器（AP 密钥 + CDN 解密）；为空（未接入）时任何曲目都无法播放，
  /// 会报 [TrackPlaybackFailure.notSignedIn] 错误。
  final TrackAudioSource? audioLoader;
  final Random _random;

  /// 协议加载代次号：连续切歌时丢弃过期的加载结果，避免串音。
  int _loadGeneration = 0;

  /// 已经把音频交给播放器的曲目 id；与当前曲目不一致时，点播放需要（重新）加载。
  String? _loadedTrackId;

  /// 连续「不可播放 → 自动跳过」的次数；超过一轮上下文长度就停下，避免整个歌单都不可播时死循环。
  int _consecutiveSkips = 0;

  /// 连续多少首不可播放时自动暂停（[pauseAfterFailures] 开启时生效）。
  static const int failureLimit = 3;

  bool _pauseAfterFailures;

  /// 最近一次播放失败（成功开始播放新曲目或调用 [clearPlaybackError] 后为 null）。
  PlaybackError? _playbackError;
  int _errorSerial = 0;
  final StreamController<PlaybackError> _errorController = StreamController<PlaybackError>.broadcast();

  /// 曲目下载 / 解密进度（0~1），仅在 [isBuffering] 且走完整加载时有意义。
  final ValueNotifier<double> loadProgressNotifier = ValueNotifier(0);

  /// 高频进度通知器，独立于 ChangeNotifier。
  final ValueNotifier<Duration> positionNotifier = ValueNotifier(Duration.zero);

  SpotifyTrack? _currentTrack;
  PlaybackContext _context = PlaybackContext.none;

  /// 上下文原始曲目顺序。
  List<SpotifyTrack> _contextTracks = [];

  /// 实际播放顺序（指向 [_contextTracks] 的下标），随机播放时为洗牌后的顺序。
  List<int> _order = [];

  /// 当前上下文曲目在 [_order] 中的位置。
  int _orderPos = 0;

  final List<QueueEntry> _userQueue = [];
  int _nextQueueUid = 0;

  bool _isPlaying = false;
  bool _isBuffering = false;

  /// 正在通过协议链路加载曲目（下载 + 解密），此时播放器还没有新音源。
  bool _isLoadingTrack = false;
  Duration _duration = Duration.zero;
  bool _shuffle = false;
  SpotifyRepeatMode _repeatMode = SpotifyRepeatMode.off;
  double _volume;
  double _volumeBeforeMute;
  ProcessingState? _lastProcessingState;

  StreamSubscription<Duration>? _posSub;
  StreamSubscription<Duration?>? _durSub;
  StreamSubscription<PlayerState>? _stateSub;

  PlaybackProvider(this._audio, this._storage, {Random? random, this.audioLoader})
      : _random = random ?? Random(),
        _pauseAfterFailures = _storage.pauseAfterFailures,
        _volume = _storage.volume,
        _volumeBeforeMute = _storage.volume > 0 ? _storage.volume : 0.8 {
    _initAudioListeners();
    _audio.setVolume(_volume);
    // 初始没有当前曲目、没有上下文：播放器条隐藏，直到用户点播一首歌
  }

  // ---------------------------------------------------------------------------
  // Getters
  // ---------------------------------------------------------------------------
  SpotifyTrack? get currentTrack => _currentTrack;

  /// 最近一次播放失败；UI 读取后提示用户，并可调用 [clearPlaybackError] 清除。
  /// 对话框 / SnackBar 建议监听 [playbackErrors]（每次失败触发一次事件）。
  PlaybackError? get playbackError => _playbackError;

  /// 播放失败事件流（广播）：不可播放、未登录、网络错误等都会在这里发出一次。
  Stream<PlaybackError> get playbackErrors => _errorController.stream;
  PlaybackContext get playbackContext => _context;
  bool get isPlaying => _isPlaying;
  /// 缓冲中：播放器自身缓冲，或正在下载 / 解密整首曲目。
  bool get isBuffering => _isBuffering || _isLoadingTrack;
  Duration get position => positionNotifier.value;
  Duration get duration => _duration;
  bool get shuffle => _shuffle;
  SpotifyRepeatMode get repeatMode => _repeatMode;
  double get volume => _volume;

  /// 连续 [failureLimit] 首无法播放时自动暂停，而不是继续跳过（设置页「播放」分组，持久化）。
  bool get pauseAfterFailures => _pauseAfterFailures;

  void setPauseAfterFailures(bool value) {
    if (value == _pauseAfterFailures) return;
    _pauseAfterFailures = value;
    _storage.setPauseAfterFailures(value);
    notifyListeners();
  }

  /// 用户手动添加的待播队列（只读）。
  List<QueueEntry> get userQueue => List.unmodifiable(_userQueue);

  /// 上下文中接下来要播放的曲目（按实际播放顺序），uid 为其在上下文中的下标。
  List<QueueEntry> get upNext {
    if (_order.isEmpty || _orderPos + 1 >= _order.length) return const [];
    return [
      for (final i in _order.sublist(_orderPos + 1)) QueueEntry(i, _contextTracks[i]),
    ];
  }

  bool isCurrent(String trackId) => _currentTrack?.id == trackId;

  /// 当前是否正在播放给定上下文（用于详情页大播放按钮的 播放/暂停 状态）。
  bool isPlayingContext(String contextUri) =>
      _isPlaying && contextUri.isNotEmpty && _context.uri == contextUri;

  // ---------------------------------------------------------------------------
  // Audio engine listeners
  // ---------------------------------------------------------------------------
  void _initAudioListeners() {
    _posSub = _audio.positionStream.listen((pos) {
      positionNotifier.value = pos;
    });

    _durSub = _audio.durationStream.listen((dur) {
      if (dur != null && dur != Duration.zero && dur != _duration) {
        _duration = dur;
        notifyListeners();
      }
    });

    _stateSub = _audio.playerStateStream.listen((state) {
      final ps = state.processingState;
      final playing = state.playing && ps != ProcessingState.completed;
      final buffering = ps == ProcessingState.loading || ps == ProcessingState.buffering;

      if (_isPlaying != playing || _isBuffering != buffering) {
        _isPlaying = playing;
        _isBuffering = buffering;
        notifyListeners();
      }

      // 只在「进入 completed」的那一刻处理，避免重复事件导致连跳多首。
      if (ps == ProcessingState.completed && _lastProcessingState != ProcessingState.completed) {
        _handleTrackEnded();
      }
      _lastProcessingState = ps;
    });
  }

  void _handleTrackEnded() {
    if (_repeatMode == SpotifyRepeatMode.track) {
      seekTo(Duration.zero);
      unawaited(_audio.play());
    } else {
      nextTrack();
    }
  }

  // ---------------------------------------------------------------------------
  // Order helpers
  // ---------------------------------------------------------------------------

  /// 以 [currentIndex] 为当前曲目重建播放顺序。
  /// 随机模式：当前曲目置顶，其余洗牌；顺序模式：自然顺序。
  void _rebuildOrder(int currentIndex) {
    final n = _contextTracks.length;
    if (n == 0) {
      _order = [];
      _orderPos = 0;
      return;
    }
    if (_shuffle) {
      final rest = [for (var i = 0; i < n; i++) if (i != currentIndex) i]..shuffle(_random);
      _order = [currentIndex, ...rest];
      _orderPos = 0;
    } else {
      _order = List.generate(n, (i) => i);
      _orderPos = currentIndex;
    }
  }

  Future<void> _startTrack(SpotifyTrack track, {bool isRetry = false}) async {
    _currentTrack = track;
    _duration = Duration(milliseconds: track.durationMs);
    positionNotifier.value = Duration.zero;
    if (!isRetry) {
      _consecutiveSkips = 0;
      // 用户主动开始新曲目：旧错误作废。自动跳过时保留，让 UI 能读到「哪首被跳过、为什么」
      _playbackError = null;
    }
    notifyListeners();
    await _playAudio(track);
  }

  /// 通过协议链路加载并播放完整曲目（metadata → AP 音频密钥 → CDN 解密 → 本地文件）。
  ///
  /// 失败规则：
  /// - [TrackPlaybackFailure.unavailable]（无权限 / DRM / 地区限制 / 文件损坏）：记录错误并自动跳到下一首；
  /// - [TrackPlaybackFailure.notSignedIn] / [TrackPlaybackFailure.network]：记录错误并停在当前曲目，
  ///   用户再点播放即重试，不跳歌（跳过没有意义）。
  Future<void> _playAudio(SpotifyTrack track) async {
    final generation = ++_loadGeneration;
    _loadedTrackId = null;
    loadProgressNotifier.value = 0;
    // 新曲目加载期间先停掉上一首，避免「点了新歌还在放旧歌」
    await _audio.pause();
    _setLoading(true);

    try {
      final loader = audioLoader;
      if (loader == null) {
        throw const TrackPlaybackException(TrackPlaybackFailure.notSignedIn, '请先登录 Spotify 账号再播放');
      }
      if (!track.isPlayable) {
        throw const TrackPlaybackException(TrackPlaybackFailure.unavailable, '这首歌在你所在的地区暂不可播放');
      }
      final audio = await loader.load(
        track.id.isNotEmpty ? track.id : track.uri,
        progress: (p) {
          if (generation == _loadGeneration) loadProgressNotifier.value = p;
        },
      );
      if (generation != _loadGeneration) return; // 已切歌，丢弃
      await _audio.playFile(audio.path);
      if (generation != _loadGeneration) return;
      _loadedTrackId = track.id;
      _consecutiveSkips = 0;
      _setLoading(false);
      _prefetchNext();
    } catch (e) {
      if (generation != _loadGeneration) return;
      final failure = e is TrackPlaybackException
          ? e
          : TrackPlaybackException(TrackPlaybackFailure.network, '播放失败，请稍后重试', e);
      await _handleLoadFailure(track, failure);
    }
  }

  /// 处理加载失败：暴露错误状态；「不可播放」类自动跳到下一首（有上限）。
  ///
  /// 上限有两层：
  /// - 开启 [pauseAfterFailures]（默认）：连续第 [failureLimit] 首仍不可播放时停下，标记 autoPaused；
  /// - 始终：跳过次数不超过一轮上下文长度，避免整个歌单都不可播时死循环。
  Future<void> _handleLoadFailure(SpotifyTrack track, TrackPlaybackException failure) async {
    final failures = _consecutiveSkips + 1;
    final hitLimit = failure.shouldSkip && _pauseAfterFailures && failures >= failureLimit;
    final canSkip = failure.shouldSkip && !hitLimit &&
        _consecutiveSkips < max(max(_order.length, _userQueue.length + 1), 1) &&
        (_userQueue.isNotEmpty || _orderPos + 1 < _order.length || _repeatMode == SpotifyRepeatMode.context);
    _playbackError = PlaybackError(
      serial: ++_errorSerial,
      track: track,
      exception: failure,
      skipped: canSkip,
      autoPaused: hitLimit,
      consecutiveFailures: failures,
    );
    _errorController.add(_playbackError!);
    _setLoading(false);
    if (canSkip) {
      _consecutiveSkips++;
      await nextTrack(isAutoSkip: true);
    } else {
      notifyListeners();
    }
  }

  void _setLoading(bool value) {
    if (_isLoadingTrack == value) return;
    _isLoadingTrack = value;
    notifyListeners();
  }

  /// 预取下一首（用户队列优先，其次上下文顺序）；失败静默。
  void _prefetchNext() {
    final loader = audioLoader;
    if (loader == null) return;
    SpotifyTrack? next;
    if (_userQueue.isNotEmpty) {
      next = _userQueue.first.track;
    } else if (_orderPos + 1 < _order.length) {
      next = _contextTracks[_order[_orderPos + 1]];
    }
    if (next != null && next.isPlayable && next.id.isNotEmpty) {
      unawaited(loader.prefetch(next.id));
    }
  }

  /// 清除播放错误状态（UI 提示已读时调用）。
  void clearPlaybackError() {
    if (_playbackError == null) return;
    _playbackError = null;
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Playback commands
  // ---------------------------------------------------------------------------

  /// 播放指定曲目。[contextQueue] 为所在列表（歌单/专辑/搜索结果），
  /// 未提供时以单曲作为上下文。
  Future<void> playTrack(
    SpotifyTrack track, {
    List<SpotifyTrack>? contextQueue,
    PlaybackContext? context,
  }) async {
    var tracks = (contextQueue == null || contextQueue.isEmpty) ? [track] : List.of(contextQueue);
    var index = tracks.indexWhere((t) => t.id == track.id);
    if (index == -1) {
      tracks = [track, ...tracks];
      index = 0;
    }
    _contextTracks = tracks;
    _context = context ?? PlaybackContext.none;
    _rebuildOrder(index);
    await _startTrack(track);
  }

  /// 从头播放整个上下文（详情页大播放按钮）。随机模式下从随机曲目开始。
  Future<void> playContext(List<SpotifyTrack> tracks, PlaybackContext context) async {
    if (tracks.isEmpty) return;
    final start = _shuffle ? _random.nextInt(tracks.length) : 0;
    await playTrack(tracks[start], contextQueue: tracks, context: context);
  }

  Future<void> togglePlayPause() async {
    final track = _currentTrack;
    if (track == null) return;

    if (_isLoadingTrack) return; // 正在加载，忽略重复点击
    if (_isPlaying) {
      await _audio.pause();
    } else if (_loadedTrackId != track.id) {
      // 还没加载过 / 上次加载失败（重试）
      _playbackError = null;
      await _playAudio(track);
    } else {
      unawaited(_audio.play()); // play() 到暂停 / 结束才完成，不能 await
    }
  }

  /// 下一首。[isAutoSkip] 表示由「不可播放自动跳过」触发（不重置连续跳过计数）。
  Future<void> nextTrack({bool isAutoSkip = false}) async {
    if (_userQueue.isNotEmpty) {
      await _startTrack(_userQueue.removeAt(0).track, isRetry: isAutoSkip);
      return;
    }

    if (_orderPos + 1 < _order.length) {
      _orderPos++;
      await _startTrack(_contextTracks[_order[_orderPos]], isRetry: isAutoSkip);
      return;
    }

    if (_repeatMode == SpotifyRepeatMode.context && _order.isNotEmpty) {
      if (_shuffle) _order.shuffle(_random);
      _orderPos = 0;
      await _startTrack(_contextTracks[_order[_orderPos]], isRetry: isAutoSkip);
      return;
    }

    // 上下文播放完毕：停在当前曲目开头
    await _audio.pause();
    await seekTo(Duration.zero);
  }

  Future<void> previousTrack() async {
    if (position.inSeconds > 3 || _orderPos == 0 || _order.isEmpty) {
      await seekTo(Duration.zero);
      return;
    }
    _orderPos--;
    await _startTrack(_contextTracks[_order[_orderPos]]);
  }

  Future<void> seekTo(Duration pos) async {
    final maxMs = _duration.inMilliseconds;
    final clamped = Duration(milliseconds: pos.inMilliseconds.clamp(0, maxMs > 0 ? maxMs : pos.inMilliseconds));
    positionNotifier.value = clamped;
    await _audio.seek(clamped);
  }

  void toggleShuffle() {
    _shuffle = !_shuffle;
    if (_order.isNotEmpty) _rebuildOrder(_order[_orderPos]);
    notifyListeners();
  }

  void cycleRepeatMode() {
    _repeatMode = switch (_repeatMode) {
      SpotifyRepeatMode.off => SpotifyRepeatMode.context,
      SpotifyRepeatMode.context => SpotifyRepeatMode.track,
      SpotifyRepeatMode.track => SpotifyRepeatMode.off,
    };
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Volume
  // ---------------------------------------------------------------------------

  /// 拖动过程中 [persist] 为 false，松手时再写盘，避免每帧写 SharedPreferences。
  void setVolume(double value, {bool persist = false}) {
    _volume = value.clamp(0.0, 1.0);
    if (_volume > 0) _volumeBeforeMute = _volume;
    _audio.setVolume(_volume);
    if (persist) _storage.setVolume(_volume);
    notifyListeners();
  }

  void toggleMute() {
    setVolume(_volume > 0 ? 0 : _volumeBeforeMute, persist: true);
  }

  // ---------------------------------------------------------------------------
  // Queue management
  // ---------------------------------------------------------------------------
  void addToQueue(SpotifyTrack track) {
    _userQueue.add(QueueEntry(_nextQueueUid++, track));
    notifyListeners();
  }

  void clearUserQueue() {
    if (_userQueue.isEmpty) return;
    _userQueue.clear();
    notifyListeners();
  }

  void removeFromUserQueue(int index) {
    if (index < 0 || index >= _userQueue.length) return;
    _userQueue.removeAt(index);
    notifyListeners();
  }

  /// [newIndex] 为移除原条目后的目标位置（与 SliverReorderableList.onReorderItem 一致）。
  void reorderUserQueue(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= _userQueue.length) return;
    final item = _userQueue.removeAt(oldIndex);
    _userQueue.insert(newIndex.clamp(0, _userQueue.length), item);
    notifyListeners();
  }

  /// 从上下文待播列表中移除（仅从本轮播放顺序中跳过，不修改原歌单）。
  void removeFromUpNext(int index) {
    final pos = _orderPos + 1 + index;
    if (index < 0 || pos >= _order.length) return;
    _order.removeAt(pos);
    notifyListeners();
  }

  /// [newIndex] 为移除原条目后的目标位置（与 SliverReorderableList.onReorderItem 一致）。
  void reorderUpNext(int oldIndex, int newIndex) {
    final base = _orderPos + 1;
    final count = _order.length - base;
    if (oldIndex < 0 || oldIndex >= count) return;
    final item = _order.removeAt(base + oldIndex);
    _order.insert(base + newIndex.clamp(0, count - 1), item);
    notifyListeners();
  }

  /// 点击 "Next in queue" 中的曲目：跳过它之前的排队曲目并立即播放。
  Future<void> playFromUserQueue(int index) async {
    if (index < 0 || index >= _userQueue.length) return;
    _userQueue.removeRange(0, index);
    await _startTrack(_userQueue.removeAt(0).track);
  }

  /// 点击 "Next from" 中的曲目：直接跳到该位置。
  Future<void> playFromUpNext(int index) async {
    final pos = _orderPos + 1 + index;
    if (index < 0 || pos >= _order.length) return;
    _orderPos = pos;
    await _startTrack(_contextTracks[_order[_orderPos]]);
  }

  @override
  void dispose() {
    _posSub?.cancel();
    _durSub?.cancel();
    _stateSub?.cancel();
    _errorController.close();
    positionNotifier.dispose();
    loadProgressNotifier.dispose();
    _audio.dispose();
    super.dispose();
  }
}
