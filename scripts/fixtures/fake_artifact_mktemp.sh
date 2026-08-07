#!/usr/bin/env bash
# Test-only mktemp shim: model a writable filesystem root without writing there.
set -euo pipefail

REAL_MKTEMP_BIN="${REAL_MKTEMP_BIN:-/usr/bin/mktemp}"
case "${2-}" in
  /./native-*|//native-*)
    [ -n "${FAKE_WRITABLE_ROOT_DIR:-}" ] || exit 90
    mkdir -p "$FAKE_WRITABLE_ROOT_DIR"
    exec "$REAL_MKTEMP_BIN" -d "$FAKE_WRITABLE_ROOT_DIR/native.XXXXXX"
    ;;
esac
exec "$REAL_MKTEMP_BIN" "$@"
