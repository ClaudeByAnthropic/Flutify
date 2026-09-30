import 'dart:typed_data';

import 'package:flutify_app/services/auth/proto_codec.dart';
import 'package:flutify_app/services/protocol/storage_resolver.dart';
import 'package:flutify_app/services/protocol/track_metadata.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ProtoWriter.varintAlways', () {
    test('0 值字段也显式写入（proto2 required / repeated enum 场景）', () {
      final bytes = (ProtoWriter()..varintAlways(10, 0)).toBytes();
      final fields = <int, int>{};
      ProtoReader(bytes).forEach((f) {
        if (f.wireType == 0) fields[f.number] = f.varintValue;
      });
      expect(fields.containsKey(10), isTrue);
      expect(fields[10], 0);
    });
  });

  group('TrackMetadata.parse（metadata.proto Track）', () {
    Uint8List buildTrack() {
      final audioFile = (ProtoWriter())
        ..bytes(1, Uint8List.fromList(List.generate(20, (i) => i + 1)))
        ..varintAlways(2, 2); // OGG_VORBIS_320
      final altFile = (ProtoWriter())
        ..bytes(1, Uint8List.fromList(List.generate(20, (i) => 100 + i)))
        ..varintAlways(2, 5); // MP3_160
      final album = (ProtoWriter())
        ..bytes(1, Uint8List(16))
        ..string(2, 'After Hours');
      final artist = (ProtoWriter())
        ..bytes(1, Uint8List(16))
        ..string(2, 'The Weeknd');
      final alternative = (ProtoWriter())
        ..bytes(1, Uint8List(16))
        ..string(2, 'Blinding Lights (Live)')
        ..int32(7, (225000 << 1) ^ (225000 >> 31)) // sint32 zigzag
        ..message(12, altFile);
      return (ProtoWriter()
            ..bytes(1, Uint8List.fromList(List.generate(16, (i) => i)))
            ..string(2, 'Blinding Lights')
            ..message(3, album)
            ..message(4, artist)
            ..varintAlways(7, (225000 << 1) ^ (225000 >> 31)) // duration 225000ms
            ..varintAlways(9, 1) // explicit
            ..message(12, audioFile)
            ..message(13, alternative))
          .toBytes();
    }

    test('字段解析', () {
      final meta = TrackMetadata.parse(buildTrack());
      expect(meta.name, 'Blinding Lights');
      expect(meta.albumName, 'After Hours');
      expect(meta.artistNames, ['The Weeknd']);
      expect(meta.durationMs, 225000);
      expect(meta.explicit, isTrue);
      expect(meta.files.length, 1);
      expect(meta.files.first.format, AudioFileFormat.oggVorbis320);
      expect(meta.files.first.fileIdHex, '0102030405060708090a0b0c0d0e0f1011121314');
      expect(meta.alternatives.length, 1);
      expect(meta.alternatives.first.name, 'Blinding Lights (Live)');
    });

    test('selectFile 按偏好选格式，本曲没有时回退备选', () {
      final meta = TrackMetadata.parse(buildTrack());
      expect(meta.selectFile()?.format, AudioFileFormat.oggVorbis320);
      expect(
        meta.selectFile(const [AudioFileFormat.mp3_160])?.format,
        AudioFileFormat.mp3_160, // 来自 alternative
      );
      expect(meta.selectFile(const [AudioFileFormat.flac]), isNull);
    });
  });

  group('StorageResolveResult.parse（spotify.download.proto）', () {
    test('CDN 结果', () {
      final bytes = (ProtoWriter()
            ..varintAlways(1, 0) // result = CDN
            ..string(2, 'https://audio-cf.spotifycdn.com/audio/aaaa?verify=1-xxx')
            ..string(2, 'https://audio-ak.spotifycdn.com/audio/bbbb')
            ..bytes(4, Uint8List.fromList([1, 2, 3])))
          .toBytes();

      final result = StorageResolveResult.parse(bytes);
      expect(result.isCdn, isTrue);
      expect(result.cdnUrls, [
        'https://audio-cf.spotifycdn.com/audio/aaaa?verify=1-xxx',
        'https://audio-ak.spotifycdn.com/audio/bbbb',
      ]);
      expect(result.fileId.length, 3);
    });

    test('RESTRICTED 结果', () {
      final bytes = (ProtoWriter()..varintAlways(1, 3)).toBytes();
      expect(StorageResolveResult.parse(bytes).isCdn, isFalse);
    });
  });

  group('AP 报文字段号锚定（keyexchange/authentication.proto）', () {
    test('LoginCredentials + SystemInfo 编码后可按字段号读回', () {
      final loginCreds = (ProtoWriter())
        ..string(10, 'alice')
        ..varintAlways(20, 3) // typ = AUTHENTICATION_SPOTIFY_TOKEN
        ..bytes(30, Uint8List.fromList([1, 2]));
      final sysInfo = (ProtoWriter())
        ..varintAlways(10, 2) // cpu_family
        ..varintAlways(60, 1) // os
        ..string(90, 'flutify-protocol')
        ..string(100, 'device-id');
      final packet = (ProtoWriter()
            ..message(10, loginCreds)
            ..message(50, sysInfo)
            ..string(70, 'flutify 1.0'))
          .toBytes();

      final seen = <int, ProtoField>{};
      ProtoReader(packet).forEach((f) {
        if (f.number == 10) {
          final inner = <int, ProtoField>{};
          f.asMessage.forEach((x) => inner[x.number] = x);
          expect(inner[10]!.asString, 'alice');
          expect(inner[20]!.varintValue, 3);
          expect(inner[30]!.bytesValue, [1, 2]);
        }
        if (f.number == 50) {
          final inner = <int, ProtoField>{};
          f.asMessage.forEach((x) => inner[x.number] = x);
          expect(inner[10]!.varintValue, 2);
          expect(inner[60]!.varintValue, 1);
          expect(inner[90]!.asString, 'flutify-protocol');
          expect(inner[100]!.asString, 'device-id');
        }
        seen[f.number] = f;
      });
      expect(seen[70]!.asString, 'flutify 1.0');
    });
  });
}
