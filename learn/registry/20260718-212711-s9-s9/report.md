# Training run 20260718-212711-s9-s9

- pair: **s9-s9**, walks: 2026-07-18-desk-test (2 eval rows)
- dataset sha256: `4c92d78d1c99690a52eddfc26e9f5d4ec87da0fdea71394057506bd45971d460`
- tiers: `close:0-15,near:16-40,inrange:41-100000` | baseline: `s9`
- validation: IN-SAMPLE ONLY (single walk)

| metric | GNB | rules |
|---|---|---|
| macro-F1 | 0.3333 | 0.3333 |
| accuracy | 1.0 | 1.0 |
| dangerous (close<->inrange) | 0 | 0 |

## GNB confusion
| true \ pred | close | inrange | near |
|---|---|---|---|
| close | 2 | 0 | 0 |
| inrange | 0 | 0 | 0 |
| near | 0 | 0 | 0 |

## Rules confusion
| true \ pred | close | inrange | near |
|---|---|---|---|
| close | 2 | 0 | 0 |
| inrange | 0 | 0 | 0 |
| near | 0 | 0 | 0 |

## Verdict

**NOT PROMOTABLE — needs >=2 walks for held-out validation**
