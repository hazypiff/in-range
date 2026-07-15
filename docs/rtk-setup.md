# rtk token compression — dev machine setup

[rtk](https://github.com/rtk-ai/rtk) compresses CLI output before it reaches
Claude Code's context (60–90% token savings). This repo ships project-local
adb filters in `.rtk/filters.toml` — measured on realistic output:
logcat **85.7%**, dumpsys activity **88.1%**, getprop **83%**, with all
W/E/F lines, Flutter exceptions, and stack traces guaranteed to survive.

## One-time setup per machine (Mac or Linux)

```sh
# 1. install rtk (single binary -> ~/.local/bin)
curl -fsSL https://raw.githubusercontent.com/rtk-ai/rtk/refs/heads/master/install.sh | sh

# 2. register the Claude Code hook (then restart Claude Code)
rtk init -g
#    if it says MANUAL STEP, add the printed hooks block to ~/.claude/settings.json

# 3. trust this repo's filters (interactive y/N prompt, run inside the repo)
cd <repo> && rtk trust
```

## Verify

```sh
rtk --version          # rtk X.Y.Z
rtk gain               # savings dashboard; grows as you work
rtk adb logcat -d      # should come back compact, errors intact
```

Notes
- `.rtk/filters.toml` (this repo) takes precedence over the user-global
  `filters.toml`; edits here reach every machine on the next pull.
- Filters never strip `W/E/F`-level lines — only `[VDI]` system-tag noise.
- rtk v0.43.0: `rtk trust` is interactive (no `--yes`), and inline filter
  tests only run for trusted project-local files (`rtk verify`).
