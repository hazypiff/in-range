import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:in_range/features/beacon/w5_codec.dart';

/// CA6E codec conformance — driven by the SHARED vectors
/// (w5_codec_vectors.json), the same file the Swift suite consumes. The
/// setHash anchor in the vectors is independently computed (python hashlib),
/// so both codecs are pinned to an external reference.
Uint8List unhex(String h) => Uint8List.fromList([
      for (var i = 0; i < h.length; i += 2)
        int.parse(h.substring(i, i + 2), radix: 16),
    ]);
String hexOf(List<int> b) =>
    b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

void main() {
  final vectors = jsonDecode(
          File('test/features/beacon/w5_codec_vectors.json').readAsStringSync())
      as Map<String, dynamic>;

  W5WireMsg buildMsg(String type, Map<String, dynamic> f) => switch (type) {
        'hello' => W5Hello(unhex(f['linkId']), unhex(f['centralCandidate']),
            unhex(f['currentAlias']), unhex(f['prevAlias'])),
        'helloAck' => W5HelloAck(unhex(f['linkId']),
            unhex(f['peripheralCandidate']), unhex(f['peripheralAlias'])),
        'propose' =>
          W5WirePropose(unhex(f['encounterId']), f['viewGen'] as int, [
            for (final c in f['contenders'] as List)
              W5WireContender(unhex(c['central']), unhex(c['linkId'])),
          ]),
        'proposeAck' => W5WireProposeAck(
            unhex(f['encounterId']), f['viewGen'] as int, unhex(f['setHash'])),
        'reject' => W5WireReject(
            unhex(f['encounterId']), f['viewGen'] as int, unhex(f['linkId'])),
        'aliasRoll' => W5WireAliasRoll(unhex(f['newAlias'])),
        'bye' => const W5WireBye(),
        _ => throw StateError('unknown vector type $type'),
      };

  test('constants agree with the vectors file', () {
    expect(vectors['version'], kW5CodecVersion);
    expect(vectors['maxContenders'], kW5CodecMaxContenders);
    expect(vectors['maxFrame'], kW5MaxFrame);
  });

  for (final v in vectors['positives'] as List) {
    test('encode+decode round-trip: ${v['name']}', () {
      final msg = buildMsg(v['type'], (v['fields'] as Map).cast());
      final frame = w5Encode(msg);
      expect(hexOf(frame), v['frame'], reason: 'encoded bytes');
      if (v['expectFrameLen'] != null) {
        expect(frame.length, v['expectFrameLen']);
      }
      final decoded = w5Decode(unhex(v['frame']));
      expect(decoded, isA<W5DecodeOk>(), reason: 'decode must succeed');
      // Re-encoding the decoded message reproduces the exact frame.
      expect(hexOf(w5Encode((decoded as W5DecodeOk).msg)), v['frame'],
          reason: 're-encode of decode');
    });
  }

  for (final v in vectors['negatives'] as List) {
    test('negative: ${v['name']}', () {
      final decoded = w5Decode(unhex(v['frame']));
      switch (v['expect']) {
        case 'legacy':
          expect(decoded, isA<W5DecodeLegacyVersion>(),
              reason: 'legacy version is fallback, NEVER a violation/close');
        case 'violation':
          expect(decoded, isA<W5DecodeViolation>());
        default:
          fail('unknown expectation ${v['expect']}');
      }
    });
  }

  test('setHash matches the independently computed anchor', () {
    final a = vectors['setHashAnchor'] as Map<String, dynamic>;
    final got = w5SetHash(unhex(a['encounterId']), a['viewGen'] as int, [
      for (final c in a['contenders'] as List)
        W5WireContender(unhex(c['central']), unhex(c['linkId'])),
    ]);
    expect(hexOf(got), a['expected']);
    expect(got.length, kW5IdLen);
  });

  test('setHash is order-invariant (canonical sort inside)', () {
    final a = vectors['setHashAnchor'] as Map<String, dynamic>;
    final cs = [
      for (final c in a['contenders'] as List)
        W5WireContender(unhex(c['central']), unhex(c['linkId'])),
    ];
    expect(
        hexOf(w5SetHash(unhex(a['encounterId']), a['viewGen'] as int, cs)),
        hexOf(w5SetHash(unhex(a['encounterId']), a['viewGen'] as int,
            cs.reversed.toList())));
  });

  test('encoder refuses out-of-contract input (fail closed at source)', () {
    final id = Uint8List(16);
    expect(() => W5WirePropose(Uint8List(15), 0, []), throwsArgumentError);
    expect(() => w5Encode(W5WirePropose(id, -1, [])), throwsArgumentError);
    expect(() => w5Encode(W5WirePropose(id, 0x100000000, [])),
        throwsArgumentError);
    final six = [
      for (var i = 0; i < 6; i++)
        W5WireContender(Uint8List.fromList(List.filled(16, i)),
            Uint8List.fromList(List.filled(16, i + 0x80))),
    ];
    expect(() => w5Encode(W5WirePropose(id, 0, six)), throwsArgumentError);
  });
}
