import 'dart:typed_data';

import 'package:flutify_app/services/eme/cenc_audio.dart';
import 'package:flutter_test/flutter_test.dart';

List<int> u32(int n) => (ByteData(4)..setUint32(0, n)).buffer.asUint8List();
List<int> box(String type, List<int> data) => [
  ...u32(data.length + 8),
  ...type.codeUnits,
  ...data,
];

// Small synthetic ISO BMFF fixture with a clear lead-in followed by CENC data.
// Two sample descriptions, tfhd default size AND duration, and fragmented data
// offsets reproduce the important structure of real audio without bundling it.
Uint8List fixture({
  bool subsamples = false,
  bool omitSenc = false,
  int sencCount = 2,
}) {
  final kid = List<int>.generate(16, (i) => i);
  final tenc = box('tenc', [0, 0, 0, 0, 0, 0, 1, 8, ...kid]);
  final sinf = box('sinf', [
    ...box('frma', 'mp4a'.codeUnits),
    ...box('schm', [...u32(0), ...'cenc'.codeUnits, ...u32(0x10000)]),
    ...box('schi', tenc),
  ]);
  final stsd = box('stsd', [
    ...u32(0),
    ...u32(2),
    ...box('enca', [...List.filled(28, 0), ...sinf]),
    ...box('mp4a', List.filled(28, 0)),
  ]);
  final trak = box('trak', [
    ...box('tkhd', [
      ...u32(0),
      ...u32(0),
      ...u32(0),
      ...u32(1),
      ...u32(0),
      ...u32(0),
    ]),
    ...box('mdia', [
      ...box('hdlr', [...u32(0), ...u32(0), ...'soun'.codeUnits]),
      ...box('minf', box('stbl', stsd)),
    ]),
  ]);
  final moov = box('moov', [
    ...trak,
    ...box(
      'mvex',
      box('trex', [
        ...u32(0),
        ...u32(1),
        ...u32(1),
        ...u32(1024),
        ...u32(4),
        ...u32(0),
      ]),
    ),
    ...box('pssh', [
      ...u32(0),
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
      ...u32(0),
    ]),
  ]);
  List<int> fragment(bool encrypted) {
    final tfhd = box('tfhd', [
      ...u32(0x2001a),
      ...u32(1),
      ...u32(encrypted ? 1 : 2),
      ...u32(1024),
      ...u32(4),
    ]);
    final senc = encrypted && !omitSenc
        ? box('senc', [
            ...u32(subsamples ? 2 : 0),
            ...u32(sencCount),
            for (var i = 0; i < 2; i++) ...[
              ...List<int>.filled(8, i + 1),
              if (subsamples) ...[0, 1, 0, 1, ...u32(3)],
            ],
          ])
        : <int>[];
    List<int> moof(int offset) => box(
      'moof',
      box('traf', [
        ...tfhd,
        ...box('trun', [...u32(1), ...u32(2), ...u32(offset)]),
        ...senc,
      ]),
    );
    final header = moof(moof(0).length + 8);
    return [
      ...header,
      ...box('mdat', [11, 12, 13, 14, 21, 22, 23, 24]),
    ];
  }

  return Uint8List.fromList([...moov, ...fragment(false), ...fragment(true)]);
}

void main() {
  test(
    'description switch preserves clear lead-in and parses default sample sizes',
    () {
      final bytes = fixture();
      final before = Uint8List.fromList(bytes);
      final audio = CencAudio.parse(bytes);
      expect(audio.samples, hasLength(2));
      expect(audio.samples.map((s) => s.size), [4, 4]);
      expect(audio.samples.first.iv, List.filled(8, 1));
      expect(audio.samples.first.kid, List.generate(16, (i) => i));
      expect(
        bytes.sublist(
          audio.samples.first.offset,
          audio.samples.first.offset + 4,
        ),
        [11, 12, 13, 14],
      );
      final output = Uint8List.fromList(bytes);
      audio.markClear(output);
      expect(output.length, bytes.length);
      expect(bytes, before);
      expect(String.fromCharCodes(output), isNot(contains('enca')));
      expect(String.fromCharCodes(output), isNot(contains('senc')));
    },
  );
  test('subsample clear and cipher lengths are retained', () {
    final audio = CencAudio.parse(fixture(subsamples: true));
    expect(audio.samples.first.subsamples, [(clear: 1, cipher: 3)]);
  });
  test('encrypted description without sample IVs is rejected', () {
    expect(
      () => CencAudio.parse(fixture(omitSenc: true)),
      throwsFormatException,
    );
  });
  test('mismatched senc count is rejected', () {
    expect(() => CencAudio.parse(fixture(sencCount: 1)), throwsFormatException);
  });
  test('truncated and zero-size boxes cannot loop or overread', () {
    final bytes = fixture();
    for (final length in [0, 1, 7, 10, bytes.length - 1]) {
      expect(
        () => CencAudio.parse(Uint8List.sublistView(bytes, 0, length)),
        throwsFormatException,
      );
    }
    final invalid = fixture();
    ByteData.sublistView(invalid).setUint32(0, 4);
    expect(() => CencAudio.parse(invalid), throwsFormatException);
  });
}
