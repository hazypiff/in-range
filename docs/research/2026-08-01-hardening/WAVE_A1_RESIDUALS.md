# Wave A.1 — tracked non-blocking residuals (filed per panel 2026-08-06 #6)

These were filed by the panel as **non-blocking** (they did NOT gate the Wave A
HOLD and must not be used to re-gate it). Tracked here so they are not silently
dropped. Owner/coordinator to schedule as a separate Wave A.1 pass.

## Puller threat-model residuals (attacker with local write access to the checkout)

All require a stronger attacker than C1's committed-symlink model (they need write
access to the working tree, not just a crafted committed symlink):

1. **Hardlink carry-over** publishes outside content (panel executed, rc=0). A
   carried file that is a hardlink (`st_nlink > 1`) to content outside `OUT_ROOT`
   is copied in. Direction: `cp --no-dereference` + reject carried files with
   `st_nlink > 1`.
2. **Symlinked `OUT_ROOT`** publishes outside the worktree (panel executed, rc=0).
   If `OUT_ROOT` itself is a symlink, publication lands outside. Direction:
   canonicalize + reject a symlinked `OUT_ROOT`.
3. **TOCTOU window** between the `[ ! -L ]` check and `cp` (panel traced; not won
   in 400 strict iterations). Direction: open-then-fstat, or `cp --no-dereference`.

The 51-case harness covers none of these three; add fixtures with the fix. A
one-line explicit threat-model note ("puller trusts a non-hostile local checkout")
is an acceptable interim if the fix is deferred.

## CI floor / manifest hygiene

4. CI floors are **lower bounds**, not a pinned discovered set; there is no
   committed test manifest, and the Runner-side floor has **no named-test anchor**
   (the diag side has `testHandleUsesProvisionedRunSecret`). Direction: pin the
   expected discovered set or add a Runner-side named anchor.
5. Commit `0bf9db3`'s message says "55 / 98" while the workflow file says
   **55 / 101** (superseded correctly by later floor bumps to 103, but the commit
   trail is sloppy). No action beyond noting; the live floor is authoritative.

## Evidence-wording hygiene

6. The committed native logs are **raw xcodebuild logs**, not "privacy-sanitized":
   they contain local macOS user paths (~2,400 lines), a simulator UDID, and
   terminal/launch session IDs — nothing dangerous (no hardware ECID, no secret
   values). Packet wording corrected to "raw xcodebuild logs, reviewed for
   secrets"; a future pass may scrub the paths if a cleaner artifact is wanted.
7. The logs contain no literal `<SHA>` string; provenance is hash + commit
   adjacency only. Direction (optional): stamp the SHA into the log header.

## Isolation reproducibility

8. `check_release_isolation.sh` / `check_final_binary_isolation.sh` fail closed on
   Linux (they need xcodebuild + built bundles). The `diag-syms=0` production
   claim rests on the author's macOS runs and was not reproducible by a
   Linux-only reviewer. Direction: the exact-SHA iOS CI run (billing-blocked)
   would reproduce it independently; no code change needed.
