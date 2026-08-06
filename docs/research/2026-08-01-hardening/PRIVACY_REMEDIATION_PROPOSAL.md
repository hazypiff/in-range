# Privacy remediation proposal — already-published raw evidence (value-free)

**Status: PROPOSAL for owner decision. No shared history is rewritten under the
current authorization.** This records, in value-free terms, machine-local values
that reached the published Git history so the owner can decide whether a history
rewrite (or upstream cache/mirror purge) is warranted. It contains NO raw
identifier values — only content hashes, class names, and counts.

## What the forward commit already fixed (tip is now clean)

The branch tip no longer carries any of these values. The whole-tip scanner
(`scripts/privacy_scan.sh`) passes. Specifically, this docs commit:

- removed the four raw `xcodebuild` logs and replaced them with deterministic
  sanitized derivatives (`*.sanitized.log`, allowlist-extracted; test
  names/counts/summaries and a recomputable `raw_input_sha256` preserved);
- replaced two real device UDIDs in `scripts/ios_station_check.sh` with
  environment lookups (`INRANGE_IPHONE14_UDID` / `INRANGE_IPHONE15P_UDID`);
- replaced one real device UDID in `docs/PROXIMITY_TIERS.md` with the
  `"$INRANGE_IPHONE14_UDID"` placeholder;
- left the Herald library signal-characteristic UUID in
  `docs/IOS_PROXIMITY_RESEARCH_2026-07-24.md` in place (a public library
  constant, not a device identifier; explicitly approved in the scanner).

## Residual exposure in HISTORY (not the tip)

Because history is not rewritten, the following remain reachable via older
commits and any remote/cache/fork that fetched them.

### A. Raw xcodebuild logs (published in the `b956015`→`d70b0a7` docs history)

Each raw blob, identified by its content hash (recomputable; not a secret),
contained an absolute macOS home path (`/Users/<name>`) on the stated number of
lines and 4 distinct machine-local UUIDs (a simulator `RUN_DESTINATION_DEVICE_UDID`,
`TERM_SESSION_ID`, `LaunchInstanceID`, and a `CLAUDE_CODE_SESSION_ID`). No fleet
run secret, no hardware ECID, and no secret VALUES were present (verified by name-
only scan).

| raw blob sha256 | home-path lines | distinct UUIDs |
|---|---|---|
| `d74a2508b01bf44cf83527de03ce053a0f6997e0b082669141bb5735a97433e5` | 2396 | 4 |
| `1eaa8f565d3387b69afa2fec96c02bed46fc3c58c9027d43156c7faefc7c1d4b` | 3345 | 4 |
| `da46c68b26d3b3d69d3b7231f049fb2989ea94f54310ba72f6f625878e358fa5` | 2403 | 4 |
| `e2f4e4577df9091d0f6c53e09ad5a459de43bc5c9de316350032af13edc26d1a` | 3327 | 4 |

The four UUIDs are ephemeral, session/simulator-scoped values (a simulator clone
UDID and per-launch/terminal/tool session IDs). Their standalone re-identification
risk is low, but they are machine-local and should not persist in published
evidence.

### B. Real device UDIDs (pre-existing, older than this evidence packet)

Two real iPhone device UDIDs (an iPhone 14 and an iPhone 15 Plus) were committed
long before this hardening packet, in `scripts/ios_station_check.sh` and (the
iPhone 14 one) in `docs/PROXIMITY_TIERS.md`. Class: **CoreDevice device UDID**.
These identify specific physical handsets and are the higher-value exposure of
the two categories. The tip is now clean; history still contains them.

## Recommended owner options (pick one)

1. **Accept (no rewrite).** The exposed values are (A) ephemeral session/simulator
   identifiers of low standalone value and (B) device UDIDs that are only useful to
   an actor with physical/provisioning access to those two handsets. If the repos
   are private and the fork/mirror set is trusted, accepting the historical
   exposure and relying on the now-clean tip + scanner gate is defensible.
2. **Targeted history rewrite.** If category B (device UDIDs) is deemed
   unacceptable, rewrite the affected blobs out of both remotes' history
   (`git filter-repo`), rotate nothing (no secret was exposed), force-update both
   remotes, and invalidate any fork/cache that fetched them. This is a shared-
   history rewrite and requires explicit owner authorization — it is out of scope
   for the current mandate.
3. **Rotate the identifiers.** Device UDIDs are hardware-fixed and cannot be
   rotated. The session/simulator UUIDs are already gone on regeneration. So
   rotation is not applicable; only options 1 or 2 apply.

## Guardrail now in place regardless of the above

`scripts/privacy_scan.sh` runs whole-tip and fails on `/Users/<name>`, UUID/UDID
forms, Bluetooth/MAC identifiers, machine-local env identifiers, the fleet run
secret value, and raw `native_*.log` files lacking the sanitizer header. It
should be wired as a required gate before any future evidence publish, and
promoted onto the implementation line before the PR-#11 evidence is frozen (the
`ios_station_check.sh` UDID fix must land there too).
