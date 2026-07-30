#!/bin/sh
# Test fixture: fail exactly one installer backup move, then delegate normally.
if [ "${1:-}" = "${WG_FAIL_MV_SOURCE:-}" ]; then
  exit 92
fi
exec "$REAL_MV" "$@"
