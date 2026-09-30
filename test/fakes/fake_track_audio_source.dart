import 'dart:io';
import 'dart:typed_data';

import 'package:flutify_app/services/protocol/track_audio_loader.dart';
import 'package:flutify_app/services/protocol/track_metadata.dart';
/// 不走网络的 [TrackAudioSource] 替身：按曲目 id 返回成功（假文件）或预设的失败。
class FakeTrackAudioSource implements TrackAudioSource {
  /// 预设失败（[TrackPlaybackException] 或任意意外异常）：key 为曲目 id。未预设的曲目一律加载成功。
  final Map<String, Object> failures = {};

  /// 每次 load 的曲目 id（按调用顺序）。
  final List<String> loaded = [];

  /// 每次 prefetch 的曲目 id。
  final List<String> prefetched = [];

  @override
  Future<LoadedAudio> load(String trackIdOrUri, {void Function(double progress)? progress}) async {
    loaded.add(trackIdOrUri);
    final failure = failures[trackIdOrUri];
    if (failure != null) throw failure;
    progress?.call(1);
    return LoadedAudio(
      file: File('fake_audio_$trackIdOrUri.ogg'),
      source: TrackAudioFile(fileId: Uint8List(20), format: AudioFileFormat.oggVorbis160),
      durationMs: 1000,
      trackId: trackIdOrUri,
    );
  }

  @override
  Future<void> prefetch(String trackIdOrUri) async => prefetched.add(trackIdOrUri);
}
