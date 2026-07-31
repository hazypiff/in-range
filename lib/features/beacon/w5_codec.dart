/// CA6E binary wire codec — the exact-bytes layer under the semantic oracle
/// (`w5_ownership.dart`). See docs/W5_ENCOUNTER_LEASE_DESIGN.md §Wire format.
///
/// Frame = `ver(1) | type(1) | len(2, u16 BE) | body(len)`, parsed strictly:
/// - unknown `ver` → [W5DecodeLegacyVersion] (peer is lease-incapable,
///   token-read fallback — NOT a close);
/// - unknown type / bad len / over-cap / non-canonical contenders on a
///   SUPPORTED `ver` → [W5DecodeViolation] (drop + close the link);
/// - all ids are exactly 16 bytes; `viewGen` u32 BE; `count ≤ kW5CodecMaxContenders`.
///
/// `setHash` = SHA-256 over the domain-separated encoding
/// `"W5-VIEW-v1" || encounterId(16) || u32BE(viewGen) || Σ(central(16)||linkId(16))`
/// with contenders in ascending (central, linkId) byte order; the **leading**
/// 16 digest bytes ride the wire.
///
/// This codec must stay byte-identical to ios/Runner/W5Codec.swift — both are
/// pinned by test/features/beacon/w5_codec_vectors.json.
library;

import 'dart:typed_data';

import 'package:crypto/crypto.dart' show sha256;

const int kW5CodecVersion = 1;
const int kW5CodecMaxContenders = 5;
const int kW5IdLen = 16;
const int kW5MaxFrame = 185; // one-write/notify budget (design §Constants)

// Frame types (v1).
const int kW5TypeHello = 0x01;
const int kW5TypeHelloAck = 0x02;
const int kW5TypePropose = 0x03;
const int kW5TypeProposeAck = 0x04;
const int kW5TypeReject = 0x05;
const int kW5TypeAliasRoll = 0x06;
const int kW5TypeBye = 0x07;

/// All-zero 16 bytes = "absent" (only meaningful for HELLO.prevAlias).
final Uint8List kW5ZeroId = Uint8List(kW5IdLen);

bool _is16(List<int> b) => b.length == kW5IdLen;

void _check16(List<Uint8List> fields) {
  for (final f in fields) {
    if (!_is16(f)) throw ArgumentError('id field must be 16 bytes');
  }
}

int _cmpBytes(Uint8List a, Uint8List b) {
  for (var i = 0; i < a.length && i < b.length; i++) {
    if (a[i] != b[i]) return a[i] < b[i] ? -1 : 1;
  }
  return a.length == b.length ? 0 : (a.length < b.length ? -1 : 1);
}

/// A wire contender: 16-byte central candidate + 16-byte linkId.
class W5WireContender {
  W5WireContender(this.central, this.linkId) {
    if (!_is16(central) || !_is16(linkId)) {
      throw ArgumentError('contender fields must be 16 bytes');
    }
  }
  final Uint8List central;
  final Uint8List linkId;

  int compareTo(W5WireContender o) {
    final c = _cmpBytes(central, o.central);
    return c != 0 ? c : _cmpBytes(linkId, o.linkId);
  }
}

// ---- messages ----

sealed class W5WireMsg {
  const W5WireMsg();
}

class W5Hello extends W5WireMsg {
  W5Hello(
      this.linkId, this.centralCandidate, this.currentAlias, this.prevAlias) {
    _check16([linkId, centralCandidate, currentAlias, prevAlias]);
  }
  final Uint8List linkId;
  final Uint8List centralCandidate;
  final Uint8List currentAlias;
  final Uint8List prevAlias; // all-zero = absent
}

class W5HelloAck extends W5WireMsg {
  W5HelloAck(this.linkId, this.peripheralCandidate, this.peripheralAlias) {
    _check16([linkId, peripheralCandidate, peripheralAlias]);
  }
  final Uint8List linkId;
  final Uint8List peripheralCandidate;
  final Uint8List peripheralAlias;
}

class W5WirePropose extends W5WireMsg {
  W5WirePropose(this.encounterId, this.viewGen, this.contenders) {
    _check16([encounterId]);
  }
  final Uint8List encounterId;
  final int viewGen;
  final List<W5WireContender> contenders; // canonical ascending, ≤ cap
}

class W5WireProposeAck extends W5WireMsg {
  W5WireProposeAck(this.encounterId, this.viewGen, this.setHash) {
    _check16([encounterId, setHash]);
  }
  final Uint8List encounterId;
  final int viewGen;
  final Uint8List setHash; // 16 bytes
}

class W5WireReject extends W5WireMsg {
  W5WireReject(this.encounterId, this.viewGen, this.linkId) {
    _check16([encounterId, linkId]);
  }
  final Uint8List encounterId;
  final int viewGen;
  final Uint8List linkId;
}

class W5WireAliasRoll extends W5WireMsg {
  W5WireAliasRoll(this.newAlias) {
    _check16([newAlias]);
  }
  final Uint8List newAlias;
}

class W5WireBye extends W5WireMsg {
  const W5WireBye();
}

// ---- decode results ----

sealed class W5DecodeResult {
  const W5DecodeResult();
}

class W5DecodeOk extends W5DecodeResult {
  const W5DecodeOk(this.msg);
  final W5WireMsg msg;
}

/// Unknown `ver`: peer is lease-incapable → token-read fallback, never close.
class W5DecodeLegacyVersion extends W5DecodeResult {
  const W5DecodeLegacyVersion(this.version);
  final int version;
}

/// Malformed/unknown-type/over-cap on a supported `ver`: drop + close the link.
class W5DecodeViolation extends W5DecodeResult {
  const W5DecodeViolation(this.reason);
  final String reason;
}

// ---- setHash ----

/// SHA-256("W5-VIEW-v1" || encounterId || u32BE(viewGen) || Σ contenders),
/// contenders in ascending (central, linkId) byte order; leading 16 bytes.
Uint8List w5SetHash(
    Uint8List encounterId, int viewGen, List<W5WireContender> contenders) {
  _checkU32(viewGen);
  if (!_is16(encounterId)) throw ArgumentError('encounterId must be 16 bytes');
  final sorted = [...contenders]..sort((a, b) => a.compareTo(b));
  final b = BytesBuilder(copy: false)
    ..add('W5-VIEW-v1'.codeUnits)
    ..add(encounterId)
    ..add(_u32be(viewGen));
  for (final c in sorted) {
    b.add(c.central);
    b.add(c.linkId);
  }
  return Uint8List.fromList(
      sha256.convert(b.takeBytes()).bytes.sublist(0, kW5IdLen));
}

// ---- encode ----

Uint8List w5Encode(W5WireMsg msg) {
  final body = switch (msg) {
    W5Hello m =>
      _cat([m.linkId, m.centralCandidate, m.currentAlias, m.prevAlias]),
    W5HelloAck m => _cat([m.linkId, m.peripheralCandidate, m.peripheralAlias]),
    W5WirePropose m => _encodePropose(m),
    W5WireProposeAck m => _cat([m.encounterId, _u32be(m.viewGen), m.setHash]),
    W5WireReject m => _cat([m.encounterId, _u32be(m.viewGen), m.linkId]),
    W5WireAliasRoll m => _cat([m.newAlias]),
    W5WireBye _ => Uint8List(0),
  };
  final type = switch (msg) {
    W5Hello _ => kW5TypeHello,
    W5HelloAck _ => kW5TypeHelloAck,
    W5WirePropose _ => kW5TypePropose,
    W5WireProposeAck _ => kW5TypeProposeAck,
    W5WireReject _ => kW5TypeReject,
    W5WireAliasRoll _ => kW5TypeAliasRoll,
    W5WireBye _ => kW5TypeBye,
  };
  final frame = Uint8List(4 + body.length);
  frame[0] = kW5CodecVersion;
  frame[1] = type;
  frame[2] = (body.length >> 8) & 0xFF;
  frame[3] = body.length & 0xFF;
  frame.setRange(4, frame.length, body);
  if (frame.length > kW5MaxFrame) {
    throw StateError('frame exceeds one-write budget: ${frame.length}');
  }
  return frame;
}

Uint8List _encodePropose(W5WirePropose m) {
  _checkU32(m.viewGen);
  if (m.contenders.length > kW5CodecMaxContenders) {
    throw ArgumentError('over cap: ${m.contenders.length}');
  }
  for (var i = 1; i < m.contenders.length; i++) {
    if (m.contenders[i - 1].compareTo(m.contenders[i]) >= 0) {
      throw ArgumentError('contenders must be strictly ascending');
    }
  }
  final b = BytesBuilder(copy: false)
    ..add(m.encounterId)
    ..add(_u32be(m.viewGen))
    ..addByte(m.contenders.length);
  for (final c in m.contenders) {
    b.add(c.central);
    b.add(c.linkId);
  }
  return b.takeBytes();
}

// ---- decode ----

W5DecodeResult w5Decode(Uint8List frame) {
  if (frame.length < 4) return const W5DecodeViolation('short header');
  final ver = frame[0];
  if (ver != kW5CodecVersion) return W5DecodeLegacyVersion(ver);
  if (frame.length > kW5MaxFrame) return const W5DecodeViolation('oversize');
  final type = frame[1];
  final len = (frame[2] << 8) | frame[3];
  if (frame.length != 4 + len) {
    return const W5DecodeViolation('len mismatch');
  }
  final body = Uint8List.sublistView(frame, 4);
  switch (type) {
    case kW5TypeHello:
      if (len != 4 * kW5IdLen) return const W5DecodeViolation('HELLO len');
      return W5DecodeOk(
          W5Hello(_id(body, 0), _id(body, 1), _id(body, 2), _id(body, 3)));
    case kW5TypeHelloAck:
      if (len != 3 * kW5IdLen) return const W5DecodeViolation('HELLO_ACK len');
      return W5DecodeOk(W5HelloAck(_id(body, 0), _id(body, 1), _id(body, 2)));
    case kW5TypePropose:
      if (len < kW5IdLen + 5) return const W5DecodeViolation('PROPOSE len');
      final count = body[kW5IdLen + 4];
      if (count > kW5CodecMaxContenders) {
        return const W5DecodeViolation('PROPOSE over cap');
      }
      if (len != kW5IdLen + 5 + 32 * count) {
        return const W5DecodeViolation('PROPOSE len/count');
      }
      final contenders = <W5WireContender>[];
      for (var i = 0; i < count; i++) {
        final off = kW5IdLen + 5 + 32 * i;
        contenders.add(W5WireContender(
            Uint8List.fromList(body.sublist(off, off + 16)),
            Uint8List.fromList(body.sublist(off + 16, off + 32))));
      }
      for (var i = 1; i < contenders.length; i++) {
        if (contenders[i - 1].compareTo(contenders[i]) >= 0) {
          return const W5DecodeViolation('PROPOSE non-canonical');
        }
      }
      return W5DecodeOk(
          W5WirePropose(_id(body, 0), _u32at(body, kW5IdLen), contenders));
    case kW5TypeProposeAck:
      if (len != kW5IdLen + 4 + kW5IdLen) {
        return const W5DecodeViolation('PROPOSE_ACK len');
      }
      return W5DecodeOk(W5WireProposeAck(_id(body, 0), _u32at(body, kW5IdLen),
          Uint8List.fromList(body.sublist(kW5IdLen + 4))));
    case kW5TypeReject:
      if (len != kW5IdLen + 4 + kW5IdLen) {
        return const W5DecodeViolation('REJECT len');
      }
      return W5DecodeOk(W5WireReject(_id(body, 0), _u32at(body, kW5IdLen),
          Uint8List.fromList(body.sublist(kW5IdLen + 4))));
    case kW5TypeAliasRoll:
      if (len != kW5IdLen) return const W5DecodeViolation('ALIAS_ROLL len');
      return W5DecodeOk(W5WireAliasRoll(_id(body, 0)));
    case kW5TypeBye:
      if (len != 0) return const W5DecodeViolation('BYE len');
      return const W5DecodeOk(W5WireBye());
    default:
      return const W5DecodeViolation('unknown type');
  }
}

// ---- helpers ----

Uint8List _id(Uint8List body, int index) =>
    Uint8List.fromList(body.sublist(index * kW5IdLen, (index + 1) * kW5IdLen));

int _u32at(Uint8List b, int off) =>
    (b[off] << 24) | (b[off + 1] << 16) | (b[off + 2] << 8) | b[off + 3];

Uint8List _u32be(int v) {
  _checkU32(v);
  return Uint8List.fromList(
      [(v >> 24) & 0xFF, (v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF]);
}

void _checkU32(int v) {
  if (v < 0 || v > 0xFFFFFFFF) throw ArgumentError('u32 out of range: $v');
}

Uint8List _cat(List<Uint8List> parts) {
  final b = BytesBuilder(copy: false);
  parts.forEach(b.add);
  return b.takeBytes();
}
