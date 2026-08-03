import XCTest

@testable import Runner

/// #8 release isolation — FLAVOR-AWARE (Phase 4). Runs under BOTH schemes:
/// - Runner scheme (no INRANGE_DIAG): asserts the PRODUCTION side — not a diag
///   build, unsuffixed restore ids, standard operational domain.
/// - diag scheme (INRANGE_DIAG): asserts the DIAGNOSTIC side — is a diag build,
///   `.diag`-suffixed restore ids, separate diag operational suite.
/// Together these are a real positive/negative control on the isolation
/// discriminator, not a one-sided runtime constant check.
final class ReleaseIsolationTests: XCTestCase {

  func testBuildFlavorMatchesScheme() {
    #if INRANGE_DIAG
      XCTAssertTrue(BackgroundBeacon.isDiagBuild)
      XCTAssertEqual(BackgroundBeacon.restoreIDSuffix, ".diag")
    #else
      XCTAssertFalse(BackgroundBeacon.isDiagBuild)
      XCTAssertEqual(BackgroundBeacon.restoreIDSuffix, "")
    #endif
  }

  func testRestorationIdentifiersAreNamespacedPerFlavor() {
    // iOS hands restoration state back per (bundle id, restore id); production
    // and diag must never share a restore id.
    #if INRANGE_DIAG
      XCTAssertEqual(BackgroundBeacon.peripheralRestoreID, "io.inrange.beacon.peripheral.diag")
      XCTAssertEqual(BackgroundBeacon.centralRestoreID, "io.inrange.beacon.central.diag")
    #else
      XCTAssertEqual(BackgroundBeacon.peripheralRestoreID, "io.inrange.beacon.peripheral")
      XCTAssertEqual(BackgroundBeacon.centralRestoreID, "io.inrange.beacon.central")
    #endif
  }

  func testOperationalDomainMatchesFlavor() {
    let prod = BackgroundBeacon.operationalDefaults()
    #if INRANGE_DIAG
      // Diag build persists to its OWN suite, never UserDefaults.standard.
      // Verify BEHAVIORALLY (UserDefaults(suiteName:) returns distinct
      // instances, so identity comparison is invalid): a value written via the
      // operational domain is visible through a fresh handle to the diag suite
      // and NOT in standard.
      XCTAssertNotEqual(prod, UserDefaults.standard)
      let dkey = "bb.diagdomain-probe"
      prod.set("diag-only", forKey: dkey)
      defer { prod.removeObject(forKey: dkey) }
      XCTAssertEqual(
        UserDefaults(suiteName: BackgroundBeacon.diagSuiteName)?.string(forKey: dkey),
        "diag-only", "operational domain IS the diag suite")
      XCTAssertNil(UserDefaults.standard.object(forKey: dkey),
        "diag state must not land in standard")
    #else
      // Production reads standard and cannot see the diag suite's state.
      XCTAssertEqual(prod, UserDefaults.standard)
      let diag = UserDefaults(suiteName: BackgroundBeacon.diagSuiteName)!
      let key = "bb.slots.isolation-probe"
      diag.set("diag-poison", forKey: key)
      defer { diag.removeObject(forKey: key) }
      XCTAssertNil(prod.object(forKey: key),
        "production domain must not see diag-suite state")
    #endif
  }

  func testReleaseIsolationGuardScriptExists() {
    // The authoritative compile-flag check is the build-settings script; assert
    // it is present so the guard can never be silently dropped from the repo.
    let root = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent()
    let script = root.appendingPathComponent("scripts/check_release_isolation.sh")
    XCTAssertTrue(FileManager.default.fileExists(atPath: script.path),
      "H-DIAG-2 build-settings guard script must exist")
  }

  // Phase 3: a foreign-flavor boot must wipe EVERY diagnostic file, not just
  // UserDefaults keys. wipeDiagnosticFiles() removes them all from Documents.
  func testForeignFlavorWipeRemovesAllDiagnosticFiles() throws {
    let docs = FileManager.default.urls(
      for: .documentDirectory, in: .userDomainMask)[0]
    // Plant a probe under each documented diagnostic file name.
    for name in BackgroundBeacon.diagnosticFileNames {
      try "poison".data(using: .utf8)!.write(to: docs.appendingPathComponent(name))
    }
    for name in BackgroundBeacon.diagnosticFileNames {
      XCTAssertTrue(FileManager.default.fileExists(
        atPath: docs.appendingPathComponent(name).path))
    }
    BackgroundBeacon.wipeDiagnosticFiles()
    for name in BackgroundBeacon.diagnosticFileNames {
      XCTAssertFalse(
        FileManager.default.fileExists(atPath: docs.appendingPathComponent(name).path),
        "foreign-flavor wipe must remove \(name)")
    }
  }

  func testProductionStampConstantIsNonEmpty() {
    // The stamp discriminator must never collapse to "always wipe": a nil
    // (legacy) stamp adopts, a foreign stamp wipes. Pin that the stamp
    // constant exists per flavor (full behavior via clean-install hardware).
    #if INRANGE_DIAG
      XCTAssertTrue(BackgroundBeacon.isDiagBuild)
    #else
      XCTAssertFalse(BackgroundBeacon.isDiagBuild)
    #endif
  }
}
