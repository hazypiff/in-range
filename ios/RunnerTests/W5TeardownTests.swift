import XCTest

@testable import Runner

/// H-W5-6 Phase 1 — the teardown matrix. Tests the alias→lease resolution
/// (the miss guard that stops a server encounter_id from acting as an alias)
/// plus the structured result derivation from onTeardown effects. The
/// controller's `dropPeer(alias:)` is a thin wrapper: `leaseForAlias` +
/// `W5TeardownResult.from(hit:effects:)` over `onTeardown`, exercised here.
private let candA = "cand-a"
private let candB = "cand-b"
private let aliasB = "aliasB"

private func ct(_ c: String, _ l: String) -> W5Contender {
  W5Contender(central: c, linkId: l)
}

private func commit(
  _ a: W5Ownership, _ lease: String, _ set: [W5Contender], _ alias: String
) {
  let mine = a.currentProposal(lease)!
  _ = a.onProposeRecv(
    peerAlias: alias, proposal: W5Proposal(encounterId: lease, viewGen: 7, contenders: set))
  _ = a.onAckRecv(
    peerAlias: alias, ack: W5Ack(encounterId: lease, ackViewGen: mine.viewGen, viewHash: mine.viewHash))
}

/// Resolve + tear down exactly as W5LinkController.dropPeer does.
private func teardown(_ a: W5Ownership, alias: String) -> W5TeardownResult {
  guard let lease = a.leaseForAlias(alias) else {
    return W5TeardownResult.from(hit: false, effects: [])
  }
  return W5TeardownResult.from(hit: true, effects: a.onTeardown(leaseId: lease))
}

final class W5TeardownTests: XCTestCase {

  // MISS: an unknown alias (e.g. a server encounter_id mislabeled as an alias)
  // resolves to nothing → lookupHit false, nothing closed, nothing ended.
  func testServerIdOrUnknownAliasIsAMiss() {
    let a = W5Ownership()
    _ = a.onControl(
      handle: "p1", role: .outbound, myCandidate: candA, peerCandidate: candB,
      peerAlias: aliasB, linkId: "L1")
    commit(a, candA, [ct("cand-a", "L1")], aliasB)
    // "12345" is an encounter_id, never a radio alias.
    let r = teardown(a, alias: "12345")
    XCTAssertFalse(r.lookupHit)
    XCTAssertTrue(r.rolesClosed.isEmpty)
    XCTAssertFalse(r.leaseEnded)
    // And the real lease is untouched.
    XCTAssertEqual(a.committedKeeper(candA), "p1")
  }

  // LOCAL HIT (outbound keeper): alias resolves, outbound link closed, ended.
  func testLocalHitOutboundKeeper() {
    let a = W5Ownership()
    _ = a.onControl(
      handle: "p1", role: .outbound, myCandidate: candA, peerCandidate: candB,
      peerAlias: aliasB, linkId: "L1")
    commit(a, candA, [ct("cand-a", "L1")], aliasB)
    let r = teardown(a, alias: aliasB)
    XCTAssertTrue(r.lookupHit)
    XCTAssertEqual(r.rolesClosed, ["outbound"])
    XCTAssertTrue(r.leaseEnded)
    XCTAssertEqual(a.activeLeases, 0)
  }

  // INBOUND-ONLY: a single inbound keeper is rejected on teardown.
  func testInboundOnly() {
    let a = W5Ownership()
    _ = a.onControl(
      handle: "in1", role: .inbound, myCandidate: candA, peerCandidate: candB,
      peerAlias: aliasB, linkId: "L1")
    commit(a, candA, [ct("cand-b", "L1")], aliasB)
    let r = teardown(a, alias: aliasB)
    XCTAssertTrue(r.lookupHit)
    XCTAssertEqual(r.rolesClosed, ["inbound"])
    XCTAssertTrue(r.leaseEnded)
  }

  // TWO-ROLE: both an outbound and an inbound link close, role-correct + ended.
  func testTwoRoleTeardown() {
    let a = W5Ownership()
    _ = a.onControl(
      handle: "p1", role: .outbound, myCandidate: candA, peerCandidate: candB,
      peerAlias: aliasB, linkId: "L1")
    _ = a.onControl(
      handle: "p2", role: .inbound, myCandidate: candA, peerCandidate: candB,
      peerAlias: aliasB, linkId: "L2")
    let r = teardown(a, alias: aliasB)
    XCTAssertTrue(r.lookupHit)
    XCTAssertEqual(Set(r.rolesClosed), ["outbound", "inbound"])
    XCTAssertEqual(r.rolesClosed.count, 2)
    XCTAssertTrue(r.leaseEnded)
    XCTAssertEqual(a.activeLeases, 0)
  }

  // STALE ALIAS: an alias that WAS live but whose lease already ended → miss.
  func testStaleAliasAfterTeardownIsAMiss() {
    let a = W5Ownership()
    _ = a.onControl(
      handle: "p1", role: .outbound, myCandidate: candA, peerCandidate: candB,
      peerAlias: aliasB, linkId: "L1")
    commit(a, candA, [ct("cand-a", "L1")], aliasB)
    _ = teardown(a, alias: aliasB)  // first teardown ends it
    let r = teardown(a, alias: aliasB)  // second: alias no longer maps
    XCTAssertFalse(r.lookupHit)
    XCTAssertFalse(r.leaseEnded)
  }

  // REAL CONTROLLER ENTRY (B1): drive the actual W5LinkController.dropPeer, not
  // a reconstruction. An unknown/rotated/stale alias on a controller with no
  // live lease must miss through the real method — nothing torn down.
  func testControllerDropPeerRealEntryMissesUnknownAlias() {
    // Hold a STRONG ref: W5LinkController.bb is `unowned`, so a temporary
    // BackgroundBeacon() would be freed right after init and any bb access
    // would crash (unowned-read-after-free).
    let bb = BackgroundBeacon()
    let ctl = W5LinkController(bb: bb)
    withExtendedLifetime(bb) {
      let r = ctl.dropPeer(alias: "12345")  // encounter_id-shaped, never an alias
      XCTAssertFalse(r.lookupHit)
      XCTAssertTrue(r.rolesClosed.isEmpty)
      XCTAssertFalse(r.leaseEnded)
      // Idempotent: a second real call is still a clean miss.
      let r2 = ctl.dropPeer(alias: "aabbccddeeff00112233445566778899")
      XCTAssertFalse(r2.lookupHit)
    }
  }

  // REAL CONTROLLER HIT (B1): a genuinely live, established lease seeded into
  // the controller is torn down through the REAL dropPeer path — hit, role
  // closed, lease ended, ownership emptied — and a repeat is then a clean miss.
  func testControllerDropPeerRealHitTearsDownLiveLease() {
    // Strong ref (see above): the seed's apply()/requestPersist dereferences the
    // unowned bb, so a temporary would crash.
    let bb = BackgroundBeacon()
    let ctl = W5LinkController(bb: bb)
    withExtendedLifetime(bb) {
      ctl.testSeedOutboundLink(
        peripheralID: UUID(), myCand: "cand-a", peerCand: "cand-b",
        alias: "aliasB", linkId: "L1")
      XCTAssertEqual(ctl.testActiveLeaseCount, 1, "seed established a live lease")
      XCTAssertTrue(ctl.testIsCommitted(alias: "aliasB"),
        "seed COMMITTED the lease (propose+ack), not merely established")
      let r = ctl.dropPeer(alias: "aliasB")
      XCTAssertTrue(r.lookupHit, "a genuinely committed lease is a HIT")
      XCTAssertTrue(r.leaseEnded)
      XCTAssertEqual(r.rolesClosed, ["outbound"])
      XCTAssertEqual(ctl.testActiveLeaseCount, 0, "lease erased")
      XCTAssertFalse(ctl.dropPeer(alias: "aliasB").lookupHit, "repeat is a miss")
    }
  }

  // REAL CHANNEL COMMITTED HIT (B1): a genuinely committed lease torn down
  // through BackgroundBeacon.dropPeerByToken — the exact boundary Dart invokes —
  // not just the controller. Diag-only: the w5Link gate is compile-false
  // otherwise.
  #if INRANGE_DIAG
    func testChannelDropPeerByTokenCommittedHit() {
      let bb = BackgroundBeacon()
      withExtendedLifetime(bb) {
        // W5 is enable-able only with a real fleet key provisioned (native
        // fail-closed gate), so the seed exercises the REAL w5Link path.
        W5Diag.provisionRunSecret(String(repeating: "ab", count: 32))
        bb.testEnableW5Links()
        bb.w5Link.testSeedOutboundLink(
          peripheralID: UUID(), myCand: "cand-a", peerCand: "cand-b",
          alias: "aliasZ", linkId: "L9")
        XCTAssertTrue(bb.w5Link.testIsCommitted(alias: "aliasZ"))
        let d = bb.dropPeerByToken("aliasZ")
        XCTAssertEqual(d["lookupHit"] as? Bool, true, "committed lease → hit")
        XCTAssertEqual(d["leaseEnded"] as? Bool, true)
        XCTAssertEqual(d["rolesClosed"] as? [String], ["outbound"])
        // No raw CA5E session was seeded (needs a CBPeripheral), so 0 reaped;
        // the reap loop itself is exercised by the field soak.
        XCTAssertEqual(d["rawSessionsReaped"] as? Int, 0)
        // A server-id-shaped token remains inert through the same real boundary.
        let miss = bb.dropPeerByToken("0badc0de5758583300000000deadbeef")
        XCTAssertEqual(miss["lookupHit"] as? Bool, false)
      }
    }

    // R4: a restored IN-GRACE live encounter carries NO handle/peripheral, so
    // every adapter map/timer is empty — yet ownership.activeLeases == 1. Real
    // quiescence must count the lease: isW5Quiescent MUST be false and secret
    // destruction MUST be refused. (Before the fix, isQuiescent ignored
    // activeLeases and reported quiescent, authorizing destruction while live.)
    func testRestoredInGraceLeaseIsNotQuiescentAndBlocksDestroy() {
      let diag = UserDefaults(suiteName: "io.inrange.diag")
      diag?.removeObject(forKey: "bb.w5.snapshot")
      W5Diag.provisionRunSecret(String(repeating: "ab", count: 32))
      let id = UUID()
      let bb1 = BackgroundBeacon()
      withExtendedLifetime(bb1) {
        bb1.testEnableW5Links()
        bb1.w5Link.testSeedOutboundLink(
          peripheralID: id, myCand: "a", peerCand: "b", alias: "aliasG",
          linkId: "LG")
        XCTAssertEqual(bb1.w5Link.testActiveLeaseCount, 1, "seeded live lease")
        bb1.w5Link.linkDown(id)  // established link dies → enters grace
        XCTAssertEqual(
          bb1.w5Link.testActiveLeaseCount, 1, "in-grace encounter still live")
        bb1.w5Link.testForcePersist()  // capture the in-grace snapshot
      }
      let bb2 = BackgroundBeacon()
      withExtendedLifetime(bb2) {
        bb2.testEnableW5Links()
        bb2.w5Link.restoreFromPersistence(restoredPeripherals: [])  // no rebind
        XCTAssertEqual(
          bb2.w5Link.testActiveLeaseCount, 1,
          "restored a live in-grace encounter with no handle/peripheral")
        XCTAssertFalse(
          bb2.isW5Quiescent,
          "a live lease ⇒ NOT quiescent despite empty adapter maps (R4)")
        XCTAssertGreaterThan(
          bb2.w5Link.testGraceTimerCount, 0,
          "restore re-armed the grace deadline (no lingering-forever lease)")
        XCTAssertEqual(
          W5Diag.destroySessionSecret(w5Quiescent: bb2.isW5Quiescent)["rejected"]
            as? String, "w5-active", "destroy refused while a lease is live")
      }
      diag?.removeObject(forKey: "bb.w5.snapshot")
    }

    // C2/A3: OFF must be a real atomic teardown, not a Boolean echo. A restored
    // in-grace lease (live W5 state under a stale key) must be REAPED by the
    // effective-OFF transaction — afterward isW5Quiescent is true, the lease and
    // grace timer are gone, and the persisted snapshot is cleared. Before the
    // fix, disabling the flag left this restored state running (the R4 test above
    // shows a mere restore stays NOT-quiescent); w5EffectiveOff is what empties it.
    func testEffectiveOffReapsRestoredInGraceLease() {
      let diag = UserDefaults(suiteName: "io.inrange.diag")
      diag?.removeObject(forKey: "bb.w5.snapshot")
      W5Diag.provisionRunSecret(String(repeating: "ab", count: 32))
      let id = UUID()
      let bb1 = BackgroundBeacon()
      withExtendedLifetime(bb1) {
        bb1.testEnableW5Links()
        bb1.w5Link.testSeedOutboundLink(
          peripheralID: id, myCand: "a", peerCand: "b", alias: "aliasEO",
          linkId: "LEO")
        bb1.w5Link.linkDown(id)          // → grace
        bb1.w5Link.testForcePersist()    // capture the in-grace snapshot
      }
      let bb2 = BackgroundBeacon()
      withExtendedLifetime(bb2) {
        bb2.testEnableW5Links()
        bb2.w5Link.restoreFromPersistence(restoredPeripherals: [])
        // Precondition: the restored live lease makes W5 NOT quiescent.
        XCTAssertEqual(bb2.w5Link.testActiveLeaseCount, 1, "restored live lease")
        XCTAssertFalse(bb2.isW5Quiescent, "restored lease ⇒ not quiescent")
        // The effective-OFF transaction reaps EVERY W5-specific producer.
        bb2.w5EffectiveOff()
        XCTAssertEqual(
          bb2.w5Link.testActiveLeaseCount, 0, "effective-OFF reaped the lease")
        XCTAssertEqual(
          bb2.w5Link.testGraceTimerCount, 0, "effective-OFF invalidated timers")
        XCTAssertTrue(
          bb2.isW5Quiescent, "W5 is quiescent after the effective-OFF teardown")
        XCTAssertNil(
          diag?.dictionary(forKey: "bb.w5.snapshot"),
          "effective-OFF cleared the persisted restoration snapshot")
      }
      diag?.removeObject(forKey: "bb.w5.snapshot")
    }

    // C5/B3-B4: the foreign-flavor transition is TRANSACTIONAL. On a PARTIAL
    // evidence wipe, the old-flavor keys are RETAINED and the stamp is NOT
    // advanced — so no new-key success marker is appended into stranded old-key
    // evidence, and the wipe retries next launch. A clean wipe completes normally.
    func testForeignFlavorWipeIsTransactionalOnPartialFailure() {
      let d = BackgroundBeacon.operationalDefaults()
      W5Diag.testEnvSecretOverride = nil
      W5EvidenceWriter.resetInjectedFailures()
      let schemaKey = BackgroundBeacon.testSchemaKey
      let foreign = "foreign.vX"

      // A real evidence file must exist for the wipe to (fail to) remove it.
      W5Diag.provisionRunSecret(String(repeating: "ab", count: 32))
      W5Diag.emit(.beat, role: .app)

      // Seed a FOREIGN stamp + sentinel old-flavor secret keys.
      d.set(foreign, forKey: schemaKey)
      d.set("abc", forKey: "bb.w5diag.provisionedsecret")
      d.set("def", forKey: "bb.w5diag.runsecret")

      // Inject a wipe failure on the events family → PARTIAL wipe.
      W5EvidenceWriter.injectedFailures["w5_events.jsonl.wipe"] = 1
      let bb = BackgroundBeacon()
      withExtendedLifetime(bb) { bb.testReconcileStateStamp() }
      XCTAssertEqual(
        d.string(forKey: "bb.w5diag.provisionedsecret"), "abc",
        "partial wipe RETAINS the old-flavor secret key (no orphaning)")
      XCTAssertEqual(
        d.string(forKey: schemaKey), foreign,
        "partial wipe does NOT advance the stamp (retry next launch)")

      // GREEN control: no injected failure ⇒ the transition completes.
      W5EvidenceWriter.resetInjectedFailures()
      let bb2 = BackgroundBeacon()
      withExtendedLifetime(bb2) { bb2.testReconcileStateStamp() }
      XCTAssertNil(
        d.string(forKey: "bb.w5diag.provisionedsecret"),
        "clean wipe deletes the old-flavor secret keys")
      XCTAssertEqual(
        d.string(forKey: schemaKey), BackgroundBeacon.testStateSchemaStamp,
        "clean wipe advances the stamp to this flavor")
      W5EvidenceWriter.resetInjectedFailures()
    }

    // §3 persisted-restoration schema: a snapshot carries an explicit
    // version + flavor + key generation. Restore FAILS CLOSED (rejects AND wipes)
    // on an unknown/future/stale version, a wrong flavor, a stale key generation,
    // or corrupt fields — never reinterpreting unusable bytes as valid state. A
    // valid snapshot still restores (positive control).
    func testSchemaBoundaryRejectsAndWipesBadSnapshots() {
      let d = BackgroundBeacon.operationalDefaults()
      W5Diag.testEnvSecretOverride = nil
      W5EvidenceWriter.resetInjectedFailures()
      W5Diag.provisionRunSecret(String(repeating: "ab", count: 32))  // confirms launch key

      func seedValidSnapshot() {
        d.removeObject(forKey: "bb.w5.snapshot")
        let id = UUID()
        let bb1 = BackgroundBeacon()
        withExtendedLifetime(bb1) {
          bb1.testEnableW5Links()
          bb1.w5Link.testSeedOutboundLink(
            peripheralID: id, myCand: "a", peerCand: "b", alias: "aliasS",
            linkId: "LS")
          bb1.w5Link.linkDown(id)          // → grace (a live in-grace lease)
          bb1.w5Link.testForcePersist()
        }
      }

      func rejectsAndWipes(_ label: String, _ mutate: (inout [String: Any]) -> Void) {
        seedValidSnapshot()
        var payload = d.dictionary(forKey: "bb.w5.snapshot") as? [String: Any] ?? [:]
        mutate(&payload)
        d.set(payload, forKey: "bb.w5.snapshot")
        let bb2 = BackgroundBeacon()
        withExtendedLifetime(bb2) {
          bb2.testEnableW5Links()
          bb2.w5Link.restoreFromPersistence(restoredPeripherals: [])
          XCTAssertEqual(
            bb2.w5Link.testActiveLeaseCount, 0, "\(label): no lease restored")
        }
        XCTAssertNil(
          d.dictionary(forKey: "bb.w5.snapshot"), "\(label): snapshot wiped")
      }

      rejectsAndWipes("future-version") { $0["schemaVersion"] = 99 }
      rejectsAndWipes("stale-version") { $0["schemaVersion"] = 0 }
      rejectsAndWipes("no-version") { $0.removeValue(forKey: "schemaVersion") }
      rejectsAndWipes("wrong-flavor") { $0["flavor"] = "prod.v1.FOREIGN" }
      rejectsAndWipes("stale-generation") { $0["keyEpoch"] = 999_999 }
      rejectsAndWipes("corrupt-snapshot") { $0["snapshot"] = "@@@not-base64@@@" }
      rejectsAndWipes("missing-linkMeta") { $0.removeValue(forKey: "linkMeta") }
      // A well-formed top-level snapshot with a CORRUPT inner link entry (an
      // `out:` link missing its linkId) is internally inconsistent → reject+wipe,
      // never silently skipped and reported loaded (codex).
      rejectsAndWipes("corrupt-linkmeta") {
        var lm = ($0["linkMeta"] as? [String: [String: Any]]) ?? [:]
        lm["out:00000000-0000-0000-0000-000000000000"] = [
          "linkIdHex": "", "myCandidateHex": "x", "peerAliasHex": "y",
        ]
        $0["linkMeta"] = lm
      }
      // An UNKNOWN handle kind (neither out: nor in:, e.g. "garbage") is a shape
      // this build never writes → corrupt, even with three string values (codex).
      rejectsAndWipes("garbage-handle") {
        var lm = ($0["linkMeta"] as? [String: [String: Any]]) ?? [:]
        lm["garbage"] = [
          "linkIdHex": "x", "myCandidateHex": "y", "peerAliasHex": "z",
        ]
        $0["linkMeta"] = lm
      }

      // Positive control: an UNMUTATED valid snapshot restores the live lease.
      seedValidSnapshot()
      let bb3 = BackgroundBeacon()
      withExtendedLifetime(bb3) {
        bb3.testEnableW5Links()
        bb3.w5Link.restoreFromPersistence(restoredPeripherals: [])
        XCTAssertEqual(
          bb3.w5Link.testActiveLeaseCount, 1, "valid snapshot restores the lease")
      }
      d.removeObject(forKey: "bb.w5.snapshot")
    }

    // §3: a restore under an UNCONFIRMED current fleet key is refused WITHOUT
    // wiping (the snapshot may be valid — it just can't be trusted yet); once the
    // key is confirmed it restores. Guards against reconstructing a lease whose
    // handles/generation can't be validated on a pre-Dart boot.
    func testRestoreRefusedUntilLaunchKeyConfirmed() {
      let d = BackgroundBeacon.operationalDefaults()
      W5Diag.testEnvSecretOverride = nil
      W5Diag.provisionRunSecret(String(repeating: "ab", count: 32))
      d.removeObject(forKey: "bb.w5.snapshot")
      let id = UUID()
      let bb1 = BackgroundBeacon()
      withExtendedLifetime(bb1) {
        bb1.testEnableW5Links()
        bb1.w5Link.testSeedOutboundLink(
          peripheralID: id, myCand: "a", peerCand: "b", alias: "aliasK", linkId: "LK")
        bb1.w5Link.linkDown(id)
        bb1.w5Link.testForcePersist()
      }
      // Arm the gate (fresh launch, key not yet confirmed) — restore must refuse
      // but NOT wipe.
      W5Diag.beginLaunchKeyGate()
      let bb2 = BackgroundBeacon()
      withExtendedLifetime(bb2) {
        bb2.testEnableW5Links()
        bb2.w5Link.restoreFromPersistence(restoredPeripherals: [])
        XCTAssertEqual(
          bb2.w5Link.testActiveLeaseCount, 0, "no restore under unconfirmed key")
      }
      XCTAssertNotNil(
        d.dictionary(forKey: "bb.w5.snapshot"),
        "unconfirmed-key refusal does NOT wipe a possibly-valid snapshot")
      // Confirm the key, then restore succeeds.
      W5Diag.provisionRunSecret(String(repeating: "ab", count: 32))
      let bb3 = BackgroundBeacon()
      withExtendedLifetime(bb3) {
        bb3.testEnableW5Links()
        bb3.w5Link.restoreFromPersistence(restoredPeripherals: [])
        XCTAssertEqual(
          bb3.w5Link.testActiveLeaseCount, 1, "restores once the key is confirmed")
      }
      d.removeObject(forKey: "bb.w5.snapshot")
    }

    // E-B2: the installed selected-peer control lists eligible peers as run-scoped
    // HANDLES (never raw), arms a one-shot fault + delay by handle, and fails
    // closed on a nil / empty / ineligible (wrong/stale/wildcard) selection.
    func testDiagSelectedPeerControlArmsByHandleAndFailsClosed() {
      W5Diag.testEnvSecretOverride = nil
      W5Diag.provisionRunSecret(String(repeating: "ab", count: 32))
      W5Diag.disarmFault()
      let bb = BackgroundBeacon()
      withExtendedLifetime(bb) {
        bb.testEnableW5Links()
        bb.w5Link.testSeedOutboundLink(
          peripheralID: UUID(), myCand: "a", peerCand: "b", alias: "peerAAA",
          linkId: "L1")
        bb.w5Link.testSeedOutboundLink(
          peripheralID: UUID(), myCand: "c", peerCand: "d", alias: "peerBBB",
          linkId: "L2")

        let peers = bb.diagListW5Peers()
        XCTAssertEqual(peers.count, 2, "two eligible peers listed")
        let h0 = peers[0]["handle"] as! String
        XCTAssertTrue(h0.hasPrefix("id:"), "handles only — no raw token crosses")

        // Fail closed: nil / empty / ineligible selections never arm.
        XCTAssertEqual(
          bb.armW5FaultForPeer(handle: nil, delaySeconds: 0)["rejected"] as? String,
          "no-peer")
        XCTAssertEqual(
          bb.armW5FaultForPeer(handle: "", delaySeconds: 0)["rejected"] as? String,
          "no-peer")
        XCTAssertEqual(
          bb.armW5FaultForPeer(handle: "id:deadbeefdeadbe", delaySeconds: 0)[
            "rejected"] as? String, "peer-not-eligible")
        XCTAssertFalse(W5Diag.isFaultArmed, "no fault armed after fail-closed tries")

        // Arm the intended peer by handle — one-shot fault + delay together.
        let ack = bb.armW5FaultForPeer(handle: h0, delaySeconds: 2.0)
        XCTAssertEqual(ack["ok"] as? Bool, true)
        XCTAssertEqual(ack["peer"] as? String, h0, "armed the selected handle")
        XCTAssertEqual(ack["delaySeconds"] as? Double, 2.0, "delay armed with fault")
        XCTAssertTrue(W5Diag.isFaultArmed)

        let st = bb.w5DiagStatus()
        XCTAssertEqual(st["armed"] as? Bool, true)
        XCTAssertEqual(st["eligibleCount"] as? Int, 2)

        W5Diag.disarmFault()
        XCTAssertFalse(W5Diag.isFaultArmed, "disarm clears the control")
      }
    }

    // C2 (kimi): isQuiescent counts myPrevTokenTimer, so the effective-OFF
    // teardown MUST invalidate it too — otherwise a live my-prev-token timer keeps
    // W5 non-quiescent after OFF and the ack's quiescent flag never clears.
    func testEffectiveOffClearsMyPrevTokenTimer() {
      W5Diag.testEnvSecretOverride = nil
      W5Diag.provisionRunSecret(String(repeating: "ab", count: 32))
      let bb = BackgroundBeacon()
      withExtendedLifetime(bb) {
        bb.testEnableW5Links()
        bb.w5Link.testArmMyPrevTokenTimer()
        XCTAssertTrue(
          bb.w5Link.testMyPrevTokenTimerArmed, "armed a my-prev-token timer")
        XCTAssertFalse(
          bb.isW5Quiescent, "a live my-prev-token timer ⇒ not quiescent")
        bb.w5EffectiveOff()
        XCTAssertFalse(
          bb.w5Link.testMyPrevTokenTimerArmed, "effective-OFF cleared the timer")
        XCTAssertTrue(bb.isW5Quiescent, "quiescent after effective-OFF")
      }
    }
  #endif

  // REAL CHANNEL ENTRY (B1): the platform-channel handler itself. A server
  // encounter_id fed through dropPeerByToken tears down nothing and reaps no
  // raw sessions — the H-W5-6 guarantee at the real boundary Dart calls.
  func testChannelDropPeerByTokenServerIdIsInert() {
    let dict = BackgroundBeacon().dropPeerByToken("0badc0de5758583300000000deadbeef")
    XCTAssertEqual(dict["lookupHit"] as? Bool, false)
    XCTAssertEqual(dict["leaseEnded"] as? Bool, false)
    XCTAssertEqual(dict["rawSessionsReaped"] as? Int, 0)
    XCTAssertEqual((dict["rolesClosed"] as? [String])?.isEmpty, true)
    // No raw identifier ever appears in the structured result.
    XCTAssertNil(dict["alias"])
    XCTAssertNil(dict["token"])
  }

  // Result → dict shape (channel contract, no raw ids).
  func testResultDictShape() {
    let r = W5TeardownResult.from(
      hit: true, effects: [.closeOutbound(handle: "p1"), .ended(leaseId: "x")])
    let d = r.asDict
    XCTAssertEqual(d["lookupHit"] as? Bool, true)
    XCTAssertEqual(d["rolesClosed"] as? [String], ["outbound"])
    XCTAssertEqual(d["leaseEnded"] as? Bool, true)
    XCTAssertNil(d["handle"])  // never leaks raw identifiers
  }
}
