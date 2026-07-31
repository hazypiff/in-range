import CommonCrypto
import Foundation

// CA6E binary wire codec — must stay byte-identical to
// lib/features/beacon/w5_codec.dart; both are pinned by the shared vectors
// (test/features/beacon/w5_codec_vectors.json, consumed by W5CodecTests).
// See docs/W5_ENCOUNTER_LEASE_DESIGN.md §Wire format.
//
// Frame = ver(1) | type(1) | len(2, u16 BE) | body(len), parsed strictly:
// unknown ver → .legacyVersion (token-read fallback, NOT a close); unknown
// type / bad len / over-cap / non-canonical contenders on a supported ver →
// .violation (drop + close the link). All ids exactly 16 bytes; viewGen u32 BE.

let kW5CodecVersion: UInt8 = 1
let kW5CodecMaxContenders = 5
let kW5IdLen = 16
let kW5MaxFrame = 185 // one-write/notify budget (design §Constants)

enum W5FrameType: UInt8 {
  case hello = 0x01
  case helloAck = 0x02
  case propose = 0x03
  case proposeAck = 0x04
  case reject = 0x05
  case aliasRoll = 0x06
  case bye = 0x07
}

struct W5WireContender: Equatable {
  let central: Data // 16 bytes
  let linkId: Data // 16 bytes

  func cmp(_ o: W5WireContender) -> Int {
    let c = w5CmpBytes(central, o.central)
    return c != 0 ? c : w5CmpBytes(linkId, o.linkId)
  }
}

func w5CmpBytes(_ a: Data, _ b: Data) -> Int {
  for i in 0..<min(a.count, b.count) {
    let x = a[a.startIndex + i], y = b[b.startIndex + i]
    if x != y { return x < y ? -1 : 1 }
  }
  if a.count == b.count { return 0 }
  return a.count < b.count ? -1 : 1
}

enum W5WireMsg: Equatable {
  case hello(linkId: Data, centralCandidate: Data, currentAlias: Data, prevAlias: Data)
  case helloAck(linkId: Data, peripheralCandidate: Data, peripheralAlias: Data)
  case propose(encounterId: Data, viewGen: UInt32, contenders: [W5WireContender])
  case proposeAck(encounterId: Data, viewGen: UInt32, setHash: Data)
  case reject(encounterId: Data, viewGen: UInt32, linkId: Data)
  case aliasRoll(newAlias: Data)
  case bye
}

enum W5DecodeResult: Equatable {
  case ok(W5WireMsg)
  /// Unknown ver: peer is lease-incapable → token-read fallback, never close.
  case legacyVersion(UInt8)
  /// Malformed/unknown-type/over-cap on a supported ver: drop + close the link.
  case violation(String)
}

enum W5CodecError: Error {
  case contract(String)
}

// MARK: - setHash

/// SHA-256("W5-VIEW-v1" || encounterId || u32BE(viewGen) || Σ(central||linkId)),
/// contenders in ascending (central, linkId) byte order; LEADING 16 bytes.
func w5SetHash(encounterId: Data, viewGen: UInt32, contenders: [W5WireContender])
  -> Data {
  precondition(encounterId.count == kW5IdLen, "encounterId must be 16 bytes")
  var input = Data("W5-VIEW-v1".utf8)
  input.append(encounterId)
  input.append(w5U32BE(viewGen))
  for c in contenders.sorted(by: { $0.cmp($1) < 0 }) {
    input.append(c.central)
    input.append(c.linkId)
  }
  var digest = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
  input.withUnsafeBytes { buf in
    _ = CC_SHA256(buf.baseAddress, CC_LONG(buf.count), &digest)
  }
  return Data(digest.prefix(kW5IdLen))
}

func w5U32BE(_ v: UInt32) -> Data {
  Data([
    UInt8((v >> 24) & 0xFF), UInt8((v >> 16) & 0xFF),
    UInt8((v >> 8) & 0xFF), UInt8(v & 0xFF),
  ])
}

// MARK: - encode

func w5Encode(_ msg: W5WireMsg) throws -> Data {
  func check16(_ fields: [Data]) throws {
    for f in fields where f.count != kW5IdLen {
      throw W5CodecError.contract("id field must be 16 bytes")
    }
  }
  var body = Data()
  let type: W5FrameType
  switch msg {
  case .hello(let linkId, let cand, let cur, let prev):
    try check16([linkId, cand, cur, prev])
    type = .hello
    body = linkId + cand + cur + prev
  case .helloAck(let linkId, let cand, let alias):
    try check16([linkId, cand, alias])
    type = .helloAck
    body = linkId + cand + alias
  case .propose(let enc, let gen, let contenders):
    try check16([enc])
    guard contenders.count <= kW5CodecMaxContenders else {
      throw W5CodecError.contract("over cap: \(contenders.count)")
    }
    for i in 1..<max(contenders.count, 1)
    where contenders.count > 1 && contenders[i - 1].cmp(contenders[i]) >= 0 {
      throw W5CodecError.contract("contenders must be strictly ascending")
    }
    for c in contenders { try check16([c.central, c.linkId]) }
    type = .propose
    body = enc + w5U32BE(gen) + Data([UInt8(contenders.count)])
    for c in contenders {
      body.append(c.central)
      body.append(c.linkId)
    }
  case .proposeAck(let enc, let gen, let hash):
    try check16([enc, hash])
    type = .proposeAck
    body = enc + w5U32BE(gen) + hash
  case .reject(let enc, let gen, let linkId):
    try check16([enc, linkId])
    type = .reject
    body = enc + w5U32BE(gen) + linkId
  case .aliasRoll(let alias):
    try check16([alias])
    type = .aliasRoll
    body = alias
  case .bye:
    type = .bye
  }
  var frame = Data([
    kW5CodecVersion, type.rawValue,
    UInt8((body.count >> 8) & 0xFF), UInt8(body.count & 0xFF),
  ])
  frame.append(body)
  guard frame.count <= kW5MaxFrame else {
    throw W5CodecError.contract("frame exceeds one-write budget: \(frame.count)")
  }
  return frame
}

// MARK: - decode

func w5Decode(_ frame: Data) -> W5DecodeResult {
  let f = [UInt8](frame) // normalize indices
  if f.count < 4 { return .violation("short header") }
  if f[0] != kW5CodecVersion { return .legacyVersion(f[0]) }
  if f.count > kW5MaxFrame { return .violation("oversize") }
  let len = (Int(f[2]) << 8) | Int(f[3])
  if f.count != 4 + len { return .violation("len mismatch") }
  let body = Array(f[4...])
  func id(_ index: Int) -> Data {
    Data(body[(index * kW5IdLen)..<((index + 1) * kW5IdLen)])
  }
  func u32(_ off: Int) -> UInt32 {
    (UInt32(body[off]) << 24) | (UInt32(body[off + 1]) << 16)
      | (UInt32(body[off + 2]) << 8) | UInt32(body[off + 3])
  }
  guard let type = W5FrameType(rawValue: f[1]) else {
    return .violation("unknown type")
  }
  switch type {
  case .hello:
    guard len == 4 * kW5IdLen else { return .violation("HELLO len") }
    return .ok(.hello(
      linkId: id(0), centralCandidate: id(1), currentAlias: id(2), prevAlias: id(3)))
  case .helloAck:
    guard len == 3 * kW5IdLen else { return .violation("HELLO_ACK len") }
    return .ok(.helloAck(
      linkId: id(0), peripheralCandidate: id(1), peripheralAlias: id(2)))
  case .propose:
    guard len >= kW5IdLen + 5 else { return .violation("PROPOSE len") }
    let count = Int(body[kW5IdLen + 4])
    guard count <= kW5CodecMaxContenders else {
      return .violation("PROPOSE over cap")
    }
    guard len == kW5IdLen + 5 + 32 * count else {
      return .violation("PROPOSE len/count")
    }
    var contenders: [W5WireContender] = []
    for i in 0..<count {
      let off = kW5IdLen + 5 + 32 * i
      contenders.append(W5WireContender(
        central: Data(body[off..<(off + 16)]),
        linkId: Data(body[(off + 16)..<(off + 32)])))
    }
    if contenders.count > 1 {
      for i in 1..<contenders.count
      where contenders[i - 1].cmp(contenders[i]) >= 0 {
        return .violation("PROPOSE non-canonical")
      }
    }
    return .ok(.propose(encounterId: id(0), viewGen: u32(kW5IdLen), contenders: contenders))
  case .proposeAck:
    guard len == kW5IdLen + 4 + kW5IdLen else { return .violation("PROPOSE_ACK len") }
    return .ok(.proposeAck(
      encounterId: id(0), viewGen: u32(kW5IdLen),
      setHash: Data(body[(kW5IdLen + 4)...])))
  case .reject:
    guard len == kW5IdLen + 4 + kW5IdLen else { return .violation("REJECT len") }
    return .ok(.reject(
      encounterId: id(0), viewGen: u32(kW5IdLen),
      linkId: Data(body[(kW5IdLen + 4)...])))
  case .aliasRoll:
    guard len == kW5IdLen else { return .violation("ALIAS_ROLL len") }
    return .ok(.aliasRoll(newAlias: id(0)))
  case .bye:
    guard len == 0 else { return .violation("BYE len") }
    return .ok(.bye)
  }
}
