# W5 convergence — frozen acceptance ledger + owner provenance (2026-08-04)

Executing `MAC_THREE_MODEL_CONVERGENCE_WORK_ORDER_2026-08-04.md` (report commit
`30ae71e` on `docs/android-panel-assist-2026-08-03`). Implementation baseline
`adb475c47042f76948ef111fe31d2a762388137a`; convergence branch
`fix/w5-convergence-2026-08-04`. PR #11 frozen at `c816f09`. No stack, merge,
deploy, history rewrite, or install before the corresponding gate.

Models available on this Mac (recorded honestly, no silent substitution):
Claude Code (this coordinator, `claude-opus-4-8`), `kimi` CLI 1.49.0, `codex`
(GPT) CLI 0.146.0. The work order names "Claude Opus 5 / Kimi3 / GPT Sol".

### Requested backend identities (A6, established 2026-08-05, tool version vs backend)

| Requested | Tool | Backend identity (probed) | Available? |
|---|---|---|---|
| GPT Sol | `codex` CLI 0.146.0 | `gpt-5.6-sol` (self-reported) | YES (default model) |
| Kimi 3 | `kimi` CLI 1.49.0 | `kimi-code/k3` (config; use `-m kimi-code/k3`) | YES |
| Opus 5 (Claude Opus 5) | this coordinator | `claude-opus-4-8` | **NO** |

The Wave A model-ownership table assigns the **primary implementer/coordinator**
role to **Opus 5**. This coordinator runs as `claude-opus-4-8`; there is no
Claude Opus 5 in the available model set to invoke. Per the panel A6 rule, a
requested backend that is unavailable must be reported as `EXTERNAL_BLOCKER`, not
silently substituted — which is what was reported.

**Owner ruling (2026-08-05, model substitution AUTHORIZED — value-free record):**
the owner accepted that Claude Opus 5 is unavailable and explicitly authorized
`claude-opus-4-8` as its substitute throughout this convergence work order,
including the Wave A implementation/coordinator duties and the later Opus-review
role. Primary implementer/coordinator: `claude-opus-4-8`. Independent non-author
reviewers: `kimi-code/k3` (via `kimi -m kimi-code/k3`) and `gpt-5.6-sol` (via
`codex`), both AVAILABLE. The ruling changes model assignment only; it does not
weaken any A1–A6 predicate, red-before/green-after test, zero-skip requirement,
exact-SHA discipline, or the two-reviewer approval requirement. This is the
single authoritative statement of the substitution; the evidence packet records
it identically.

## Owner provenance — fleet-key persistence (value-free)

The following ruling was issued by the owner in the dispatch message that
delivered this work order (the coordinator did NOT author it):

> For the diagnostic matrix, the shared fleet key persists across
> relaunch/restoration and case resets. `resetCase` retains it and rotates only
> the public evidence epoch; destructive secret clearing is a separate operation
> allowed only while W5 is stopped.

Source: owner-sent dispatch accompanying the work order at `30ae71e`. No key
value is recorded here or anywhere in the repo.

## Frozen contracts (may be strengthened by tests, never weakened)

1. W5 and every diagnostic control are compile-gated and absent from production
   behavior/artifacts.
2. A server `encounter_id` never crosses an alias-keyed native boundary.
3. A stale radio alias may be attempted, but freshness + the exact native
   outcome are reported. Never fabricate an alias.
4. A raw-session-only reap is NOT a teardown miss.
5. Native-unavailable is NOT natively-persisted evidence.
6. A pass = immediate teardown of the currently mapped lease when a trustworthy
   alias exists; NOT a durable no-redial identity ledger.
7. One shared fleet secret spans one matrix run. `resetCase` retains it, rotates
   the evidence epoch, clears controls, resets sequence/run. Secret destruction
   is a separate stopped-W5 op.
8. NO wildcard fault or delay target.
9. v1 wire format frozen; no `HELLO_ACK prevAlias` field.
10. H-W5-7 stable-identity re-key stays a separate release-enablement design gate.
11. No history rewrite / force-push; only repair the value-free proposal.

## Gates (only these count)

`CODE_READY` (internal) → `PREFLIGHT_READY` (one phone) → `MATRIX_READY`
(three phones) → `MERGE_READY`. `PARTIAL` / "no objections" / a green workflow
with a controlling skip satisfy none.

## Lane progress

- **Wave A (B3/B4 atomic session substrate)** — owner-ruling `resetCase`
  (retain secret + rotate public case epoch + clear controls/seq + wipe
  artifacts, serialized on the writer lock) and `destroySessionSecret` (W5-
  stopped only); events snapshot one atomic `{secret, keyEpoch, caseEpoch}` and
  derive every handle from it inside the serialized boundary; key change rotates
  a visible key epoch + wipes; no-wildcard fault; invalid-secret no-op. Native
  diag 69/69. Cross-review + B4 writer op-injection tests continue.
- Waves B, C1–C3, integration, CI, artifact inspection: in progress.
