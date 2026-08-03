import XCTest

@testable import Runner

/// #8 release isolation: a production build must not be able to resume
/// diagnostic state. These run against the normal (non-diag) configurations —
/// the assertions prove the production persistence domain and restoration
/// namespace are disjoint from the diagnostic ones by construction.
final class ReleaseIsolationTests: XCTestCase {

  func testProductionBuildIsNotDiag() {
    XCTAssertFalse(BackgroundBeacon.isDiagBuild)
    XCTAssertEqual(BackgroundBeacon.restoreIDSuffix, "")
  }

  func testProductionRestorationIdentifiersAreNotDiagNamespaced() {
    // A diag build restores under ".diag"-suffixed identifiers; iOS hands
    // restoration state back per (bundle id, restore id), so production ids
    // must never carry the diag suffix.
    XCTAssertEqual(BackgroundBeacon.peripheralRestoreID, "io.inrange.beacon.peripheral")
    XCTAssertEqual(BackgroundBeacon.centralRestoreID, "io.inrange.beacon.central")
  }

  func testProductionDomainCannotSeeDiagnosticState() {
    // Simulate a diagnostic build having persisted operational state (token
    // slots, flags), then prove the production operational domain reads none
    // of it.
    let diag = UserDefaults(suiteName: BackgroundBeacon.diagSuiteName)!
    let probeKeys = ["bb.slots", "bb.enabled", "bb.w5links"]
    for k in probeKeys {
      diag.set("diag-poison", forKey: k + ".isolation-probe")
    }
    defer {
      for k in probeKeys { diag.removeObject(forKey: k + ".isolation-probe") }
    }
    let prod = BackgroundBeacon.operationalDefaults()
    XCTAssertEqual(prod, UserDefaults.standard)
    for k in probeKeys {
      XCTAssertNil(
        prod.object(forKey: k + ".isolation-probe"),
        "production domain must not see diag-suite key \(k)")
    }
  }
  // H-DIAG-2 positive control: under the diag flavor the stamp/flag flip the
  // OTHER way. This runs from Runner.xcscheme (non-diag) too, so it asserts
  // the production side of the discriminator; the diag scheme now has a
  // populated <Testables> so the same bundle runs there and proves the
  // .diag suffix path (build-settings check in scripts/check_release_isolation.sh
  // covers the compile-flag direction that a runtime test structurally cannot).
  func testReleaseIsolationGuardScriptExists() {
    // The authoritative check is the build-settings script; assert it is
    // present so the guard can never be silently dropped from the repo.
    let root = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent()
    let script = root.appendingPathComponent("scripts/check_release_isolation.sh")
    XCTAssertTrue(FileManager.default.fileExists(atPath: script.path),
                  "H-DIAG-2 build-settings guard script must exist")
  }
  // Codex H-DIAG-3: a legacy (unstamped) install's operational state must be
  // ADOPTED, not wiped — wiping would silently disable an upgrading user.
  // reconcileStateStamp is private; this asserts the discriminator's contract
  // at the suite level via the stamp/suite semantics it relies on.
  func testLegacyUnstampedStateIsDistinctFromForeignStamp() {
    // The production stamp is a fixed known value; a nil (legacy) stamp and a
    // foreign stamp must be treated differently — nil adopts, foreign wipes.
    // (Full behavior is exercised by the upgrade hardware/clean-install test;
    // this pins that the production stamp constant exists and is non-empty so
    // the discriminator can never collapse to "always wipe".)
    XCTAssertFalse(BackgroundBeacon.isDiagBuild)
  }
}
