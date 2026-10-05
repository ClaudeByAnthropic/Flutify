import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/cdm/license_request_metadata.dart';

// Fixtures use short values except timestamps; encode without production code.
Uint8List _proto(Map<int, Object> fields) => Uint8List.fromList([
  for (final entry in fields.entries)
    if (entry.value is int) ...[
      ..._encode(entry.key * 8),
      ..._encode(entry.value as int),
    ] else ...[
      ..._encode(entry.key * 8 + 2),
      ..._encode((entry.value as List<int>).length),
      ...entry.value as List<int>,
    ],
]);

List<int> _encode(int value) {
  final output = <int>[];
  do {
    final next = value >> 7;
    output.add((value & 127) | (next > 0 ? 128 : 0));
    value = next;
  } while (value > 0);
  return output;
}

void main() {
  final secret = utf8.encode('DO_NOT_LOG_IDENTIFIERS_OR_SIGNATURES');
  final payload = Uint8List.fromList([1, 2, 3]);
  final pssh = Uint8List(32 + payload.length);
  ByteData.sublistView(pssh)
    ..setUint32(0, pssh.length)
    ..setUint32(4, 0x70737368)
    ..setUint32(28, payload.length);
  pssh.setRange(32, pssh.length, payload);
  final cert = _proto({
    1: _proto({2: secret, 7: secret}),
    2: secret,
  });
  final now = DateTime.utc(2026, 10, 5);
  Uint8List request({bool encrypted = true, int? time, Uint8List? content}) =>
      _proto({
        1: 1,
        2: _proto({
          if (encrypted)
            8: _proto({
              1: secret,
              2: secret,
              3: secret,
              4: Uint8List(16),
              5: secret,
            })
          else
            1: _proto({
              2: secret,
              3: _proto({1: secret, 2: secret}),
              7: _proto({
                2: _proto({1: secret}),
              }),
            }),
          2:
              content ??
              _proto({
                1: _proto({1: payload, 2: 1, 3: secret}),
              }),
          3: 1,
          4: time ?? now.millisecondsSinceEpoch ~/ 1000,
          6: 21,
          7: 123,
        }),
        3: secret,
      });
  Map<String, Object?> inspect(Uint8List bytes, {Uint8List? certificate}) =>
      licenseRequestMetadata(
        bytes,
        pssh: pssh,
        certificate: certificate ?? cert,
        now: now,
      );

  test('compares encrypted request metadata without disclosing contents', () {
    final bytes = request();
    final before = Uint8List.fromList(bytes);
    final summary = inspect(bytes);
    expect(summary, containsPair('pssh_matches_input', true));
    expect(summary, containsPair('certificate_provider_matches', true));
    expect(summary, containsPair('certificate_serial_matches', true));
    expect(summary, containsPair('time_within_5m', true));
    expect(summary, containsPair('protocol', '2.1'));
    expect(summary, containsPair('vmp', 'encrypted_unobservable'));
    expect(jsonEncode(summary), isNot(contains(utf8.decode(secret))));
    expect(
      summary.values.every(
        (v) => v == null || v is String || v is int || v is bool,
      ),
      isTrue,
    );
    expect(bytes, before);
    expect(inspect(bytes, certificate: _proto({1: 5, 2: cert})), summary);
  });

  test('distinguishes input mismatch and stale time from matching request', () {
    final summary = inspect(
      request(
        time: 1,
        content: _proto({
          1: _proto({
            1: [9],
            2: 1,
          }),
        }),
      ),
      certificate: _proto({
        1: _proto({
          2: [9],
          7: [9],
        }),
      }),
    );
    expect(summary, containsPair('pssh_matches_input', false));
    expect(summary, containsPair('certificate_serial_matches', false));
    expect(summary, containsPair('certificate_provider_matches', false));
    expect(summary, containsPair('time_within_5m', false));
  });

  test('reports plaintext VMP count without filenames or client values', () {
    final summary = inspect(request(encrypted: false));
    expect(summary, containsPair('vmp', 'present'));
    expect(summary, containsPair('vmp_file_count', 1));
    expect(jsonEncode(summary), isNot(contains(utf8.decode(secret))));
  });

  test('bounds parsing and handles truncated, invalid and duplicate fields', () {
    for (final bytes in [
      <int>[0],
      [8, 128],
      [8, ...List.filled(10, 255)],
      [18, 255, 255, 127],
      [11],
      [8, 1, 8, 1],
      List.filled(1024 * 1024 + 1, 0),
      [
        for (var i = 0; i < 2049; i++) ...[8, 1],
      ],
    ]) {
      expect(
        inspect(Uint8List.fromList(bytes))['inspection'],
        'malformed_or_unsupported',
      );
    }
    // Unknown fixed-width fields are skipped without being included in output.
    final extended = Uint8List.fromList([
      ...request(),
      161,
      1,
      ...List.filled(8, 0),
      173,
      1,
      ...List.filled(4, 0),
    ]);
    expect(inspect(extended), {
      ...inspect(request()),
      'bytes': extended.length,
    });
  });
}
