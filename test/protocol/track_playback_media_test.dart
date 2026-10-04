import 'dart:convert';

import 'package:flutify_app/services/protocol/track_playback_media.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  PlaybackFile f(String key, int bitrate, {String? encodingId}) => PlaybackFile(
    fileIdHex: 'ab$bitrate',
    format: 10,
    bitrate: bitrate,
    formatKey: key,
    encodingId: encodingId,
  );

  group('TrackPlaybackMedia.selectCbcsForFairPlay', () {
    test('只取 file_ids_mp4_cbcs 分组，选最低码率', () {
      final media = TrackPlaybackMedia(
        name: 't',
        durationMs: 1000,
        mp4Files: [
          f('file_ids_mp4', 96000),
          f('file_ids_mp4_cbcs', 256000),
          f('file_ids_mp4_cbcs', 128000),
        ],
      );
      final sel = media.selectCbcsForFairPlay();
      expect(sel, isNotNull);
      expect(sel!.bitrate, 128000);
      expect(sel.formatKey, 'file_ids_mp4_cbcs');
    });

    test('无 cbcs 分组 → null（macOS 判定「不可用」）', () {
      final media = TrackPlaybackMedia(
        name: 't',
        durationMs: 1000,
        mp4Files: [f('file_ids_mp4', 96000), f('file_ids_mp4', 256000)],
      );
      expect(media.selectCbcsForFairPlay(), isNull);
    });

  });
  group('TrackPlaybackMedia.selectForFree', () {
    for (final reversed in [false, true]) {
      test('同码率 CBCS 不参与 Widevine 选择，倒序=$reversed', () {
        final files = [
          f('file_ids_mp4_cbcs', 128000),
          f('file_ids_mp4', 128000),
          f('file_ids_mp4', 256000),
          f('file_ids_mp4_cbcs', 256000),
        ];
        final media = TrackPlaybackMedia(
          name: 't',
          durationMs: 1000,
          mp4Files: reversed ? files.reversed.toList() : files,
        );
        final selected = media.selectForFree()!;
        expect(selected.formatKey, 'file_ids_mp4');
        expect(selected.bitrate, 128000);
      });
    }
    test('CBCS 码率更低时仍选 CENC 中的最低码率', () {
      final media = TrackPlaybackMedia(
        name: 't',
        durationMs: 1000,
        mp4Files: [
          f('file_ids_mp4_cbcs', 96000),
          f('file_ids_mp4', 256000),
          f('file_ids_mp4', 128000),
        ],
      );
      expect(media.selectForFree()!.bitrate, 128000);
      expect(media.selectForFree()!.formatKey, 'file_ids_mp4');
    });
    test('缺少已知 CENC 分组时返回不可用', () {
      for (final files in <List<PlaybackFile>>[
        [],
        [f('file_ids_mp4_cbcs', 128000)],
        [f('file_ids_mp4_unknown', 128000)],
        [f('', 128000)],
      ]) {
        expect(
          TrackPlaybackMedia(
            name: 't',
            durationMs: 1000,
            mp4Files: files,
          ).selectForFree(),
          isNull,
        );
      }
    });
  });
  group('fetchTrackPlaybackMedia 解析', () {
    Future<TrackPlaybackMedia> parse(List<Map<String, dynamic>> files) {
      const uri = 'spotify:track:abc';
      final client = MockClient(
        (_) async => http.Response(
          jsonEncode({
            'media': {
              uri: {
                'item': {
                  'metadata': {'name': 'n', 'duration': 1000},
                  'manifest': {'file_ids_mp4': files},
                },
              },
            },
          }),
          200,
        ),
      );
      return fetchTrackPlaybackMedia(
        'abc',
        headers: () async => {},
        client: client,
      );
    }

    test('encoding_id 为数字 / 对象时不抛 TypeError，按字符串保留', () async {
      final media = await parse([
        {'file_id': 'aa', 'format': 10, 'bitrate': 96000, 'encoding_id': 42},
        {
          'file_id': 'bb',
          'format': 10,
          'bitrate': 128000,
          'encoding_id': {'k': 1},
        },
        {
          'file_id': 'cc',
          'format': 10,
          'bitrate': 256000,
          'encoding_id': 'enc',
        },
        {'file_id': 'dd', 'format': 10, 'bitrate': 320000},
      ]);
      expect(media.mp4Files.map((f) => f.encodingId).toList(), [
        '42',
        '{k: 1}',
        'enc',
        null,
      ]);
    });
  });
}
