import 'dart:convert';
import 'dart:typed_data';

import 'package:flutify_app/services/eme/widevine_init_data.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List pssh({int marker = 1, bool version1 = false}) {
  const uuid = [
    0xed,
    0xef,
    0x8b,
    0xa9,
    0x79,
    0xd6,
    0x4a,
    0xce,
    0xa3,
    0xc8,
    0x27,
    0xdc,
    0xd5,
    0x1d,
    0x21,
    0xed,
  ];
  final bytes = Uint8List.fromList([
    0,
    0,
    0,
    0,
    ...'pssh'.codeUnits,
    version1 ? 1 : 0,
    0,
    0,
    0,
    ...uuid,
    if (version1) ...[0, 0, 0, 1, ...List.filled(16, 0)],
    0,
    0,
    0,
    1,
    marker,
  ]);
  ByteData.sublistView(bytes).setUint32(0, bytes.length);
  return bytes;
}

String key(Uint8List bytes, {String? uri, String? format}) =>
    '#EXT-X-KEY:METHOD=SAMPLE-AES-CTR,'
    'URI="${uri ?? 'data:application/octet-stream;base64,${base64Encode(bytes)}'}",'
    'KEYFORMAT="${format ?? 'urn:uuid:edef8ba9-79d6-4ace-a3c8-27dcd51d21ed'}"';

void main() {
  test('keeps source-provided PSSH intact for both supported box versions', () {
    for (final version1 in [false, true]) {
      final bytes = pssh(version1: version1);
      expect(widevinePsshFromHls('#EXTM3U\r\n${key(bytes)}\r\n'), bytes);
      expect(
        widevinePsshFromHls(key(bytes, format: 'com.widevine.alpha')),
        bytes,
      );
    }
  });
  test('returns no override when HLS has no Widevine key', () {
    expect(widevinePsshFromHls(''), isNull);
    expect(widevinePsshFromHls('#EXTM3U\n#EXT-X-KEY:METHOD=NONE'), isNull);
    expect(
      widevinePsshFromHls(
        key(pssh(), format: 'com.apple.streamingkeydelivery'),
      ),
      isNull,
    );
  });
  test('never fetches remote key URLs or silently accepts malformed data', () {
    for (final uri in [
      'https://license.example/key',
      'data:application/octet-stream;base64,%%%bad',
      'data:text/plain,hello',
      'data:application/octet-stream;base64,${'A' * (49 * 1024)}',
    ]) {
      expect(
        () => widevinePsshFromHls(key(pssh(), uri: uri)),
        throwsFormatException,
      );
    }
  });
  test('rejects wrong system, lengths, flags and overflowing key ID count', () {
    for (final bytes in [
      Uint8List(5),
      pssh()..[12] = 0,
      pssh()..[3] = 1,
      pssh()..[9] = 1,
      pssh()..[8] = 2,
      pssh()..[31] = 0,
      pssh(version1: true)..[28] = 255,
    ]) {
      expect(() => widevinePsshFromHls(key(bytes)), throwsFormatException);
    }
  });
  test(
    'repeated identical key is allowed, changing initialization data fails',
    () {
      final first = key(pssh());
      expect(widevinePsshFromHls('$first\n$first'), pssh());
      expect(
        () => widevinePsshFromHls('$first\n${key(pssh(marker: 2))}'),
        throwsFormatException,
      );
    },
  );
}
