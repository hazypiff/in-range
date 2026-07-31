// Generates test/features/beacon/w5_codec_vectors.json — the shared CA6E codec
// conformance vectors consumed by BOTH the Dart suite (w5_codec_test.dart) and
// the Swift suite (RunnerTests/W5CodecTests.swift).
//
//   dart run test/features/beacon/w5_codec_vectors_gen.dart
//
// Positive frame bytes are produced by the Dart encoder; the setHash anchor is
// INDEPENDENTLY computed (python hashlib, see "anchor" below) so Dart and Swift
// cannot share a systematic hash error. Regenerate only on a deliberate wire
// change, in the same commit as both codecs.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:in_range/features/beacon/w5_codec.dart';

Uint8List rep(int b) => Uint8List.fromList(List.filled(16, b));
Uint8List seq() => Uint8List.fromList(List.generate(16, (i) => i));
String hexOf(List<int> b) =>
    b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

void main() {
  final enc = seq();
  final c1 = W5WireContender(rep(0x20), rep(0x21));
  final c2 = W5WireContender(rep(0x30), rep(0x31));
  final maxContenders = [
    for (var i = 0; i < kW5CodecMaxContenders; i++)
      W5WireContender(rep(0x40 + i), rep(0x50 + i)),
  ];

  final positives = <Map<String, Object>>[
    {
      'name': 'HELLO',
      'type': 'hello',
      'fields': {
        'linkId': hexOf(rep(0x01)),
        'centralCandidate': hexOf(rep(0x02)),
        'currentAlias': hexOf(rep(0x03)),
        'prevAlias': hexOf(rep(0x00)), // all-zero = absent
      },
      'frame':
          hexOf(w5Encode(W5Hello(rep(0x01), rep(0x02), rep(0x03), rep(0x00)))),
    },
    {
      'name': 'HELLO_ACK',
      'type': 'helloAck',
      'fields': {
        'linkId': hexOf(rep(0x01)),
        'peripheralCandidate': hexOf(rep(0x04)),
        'peripheralAlias': hexOf(rep(0x05)),
      },
      'frame': hexOf(w5Encode(W5HelloAck(rep(0x01), rep(0x04), rep(0x05)))),
    },
    {
      'name': 'PROPOSE two contenders',
      'type': 'propose',
      'fields': {
        'encounterId': hexOf(enc),
        'viewGen': 7,
        'contenders': [
          {'central': hexOf(c1.central), 'linkId': hexOf(c1.linkId)},
          {'central': hexOf(c2.central), 'linkId': hexOf(c2.linkId)},
        ],
      },
      'frame': hexOf(w5Encode(W5WirePropose(enc, 7, [c1, c2]))),
    },
    {
      'name': 'PROPOSE at cap fills the one-write budget exactly',
      'type': 'propose',
      'fields': {
        'encounterId': hexOf(enc),
        'viewGen': 0xFFFFFFFF,
        'contenders': [
          for (final c in maxContenders)
            {'central': hexOf(c.central), 'linkId': hexOf(c.linkId)},
        ],
      },
      'frame': hexOf(w5Encode(W5WirePropose(enc, 0xFFFFFFFF, maxContenders))),
      'expectFrameLen': kW5MaxFrame,
    },
    {
      'name': 'PROPOSE_ACK',
      'type': 'proposeAck',
      'fields': {
        'encounterId': hexOf(enc),
        'viewGen': 7,
        'setHash': hexOf(w5SetHash(enc, 7, [c1, c2])),
      },
      'frame': hexOf(
          w5Encode(W5WireProposeAck(enc, 7, w5SetHash(enc, 7, [c1, c2])))),
    },
    {
      'name': 'REJECT',
      'type': 'reject',
      'fields': {
        'encounterId': hexOf(enc),
        'viewGen': 3,
        'linkId': hexOf(rep(0x01)),
      },
      'frame': hexOf(w5Encode(W5WireReject(enc, 3, rep(0x01)))),
    },
    {
      'name': 'ALIAS_ROLL',
      'type': 'aliasRoll',
      'fields': {'newAlias': hexOf(rep(0x06))},
      'frame': hexOf(w5Encode(W5WireAliasRoll(rep(0x06)))),
    },
    {
      'name': 'BYE',
      'type': 'bye',
      'fields': <String, Object>{},
      'frame': hexOf(w5Encode(const W5WireBye())),
    },
  ];

  String frameHex(int ver, int type, List<int> body) => hexOf(
      [ver, type, (body.length >> 8) & 0xFF, body.length & 0xFF, ...body]);
  final proposeDescBody = [
    ...enc,
    0, 0, 0, 7,
    2,
    ...rep(0x30), ...rep(0x31), // descending: violates canonical order
    ...rep(0x20), ...rep(0x21),
  ];
  final overCapBody = [...enc, 0, 0, 0, 7, 6, ...rep(0x20), ...rep(0x21)];

  final negatives = <Map<String, Object>>[
    {
      'name': 'unknown version → legacy fallback, never close',
      'frame': frameHex(2, kW5TypeHello, List.filled(64, 0)),
      'expect': 'legacy',
    },
    {
      'name': 'version 0 → legacy fallback',
      'frame': frameHex(0, kW5TypeBye, const []),
      'expect': 'legacy',
    },
    {
      'name': 'unknown type on supported version → violation',
      'frame': frameHex(kW5CodecVersion, 0x99, const []),
      'expect': 'violation',
    },
    {
      'name': 'short header → violation',
      'frame': hexOf([kW5CodecVersion]),
      'expect': 'violation',
    },
    {
      'name': 'len mismatch → violation',
      'frame': hexOf([kW5CodecVersion, kW5TypeBye, 0x00, 0x01]),
      'expect': 'violation',
    },
    {
      'name': 'trailing bytes → violation',
      'frame': '${frameHex(kW5CodecVersion, kW5TypeBye, const [])}ff',
      'expect': 'violation',
    },
    {
      'name': 'HELLO wrong body length → violation',
      'frame': frameHex(kW5CodecVersion, kW5TypeHello, List.filled(63, 0)),
      'expect': 'violation',
    },
    {
      'name': 'PROPOSE count over cap → violation',
      'frame': frameHex(kW5CodecVersion, kW5TypePropose, overCapBody),
      'expect': 'violation',
    },
    {
      'name': 'PROPOSE non-canonical contender order → violation',
      'frame': frameHex(kW5CodecVersion, kW5TypePropose, proposeDescBody),
      'expect': 'violation',
    },
    {
      'name': 'oversize frame (> one-write budget) → violation',
      'frame': frameHex(
          kW5CodecVersion, kW5TypePropose, List.filled(kW5MaxFrame - 3, 0)),
      'expect': 'violation',
    },
  ];

  // Independently computed with python hashlib (NOT by this codec):
  //   sha256(b"W5-VIEW-v1" + bytes(range(16)) + (7).to_bytes(4,'big')
  //          + 0x20*16 + 0x21*16 + 0x30*16 + 0x31*16).hexdigest()[:32]
  const anchor = 'c134b190eb5ab02b2e1a30e1277443c8';

  final out = const JsonEncoder.withIndent('  ').convert({
    'version': kW5CodecVersion,
    'maxContenders': kW5CodecMaxContenders,
    'maxFrame': kW5MaxFrame,
    'positives': positives,
    'negatives': negatives,
    'setHashAnchor': {
      'encounterId': hexOf(enc),
      'viewGen': 7,
      'contenders': [
        // given DESCENDING on purpose: hash must sort canonically first
        {'central': hexOf(c2.central), 'linkId': hexOf(c2.linkId)},
        {'central': hexOf(c1.central), 'linkId': hexOf(c1.linkId)},
      ],
      'expected': anchor,
    },
  });
  File('test/features/beacon/w5_codec_vectors.json')
      .writeAsStringSync('$out\n');
  final got = hexOf(w5SetHash(enc, 7, [c2, c1]));
  stdout.writeln('wrote vectors; dart setHash=$got anchor=$anchor '
      '${got == anchor ? "MATCH" : "MISMATCH"}');
}
