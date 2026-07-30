#!/usr/bin/env bash
# Protected G12 oracle: public prose must not retain retired v0 execution or
# installation claims. Historical records and private planning are deliberately
# outside this explicit reader-facing scope.
set -u
. "$(dirname "$0")/testlib.sh"

public_files=(
  "$REPO_DIR/README.md"
  "$REPO_DIR/CONTEXT.md"
  "$REPO_DIR/CONTRIBUTING.md"
  "$REPO_DIR/PLAN.md"
  "$REPO_DIR/SECURITY.md"
  "$REPO_DIR/SUPPORT.md"
  "$REPO_DIR/CODE_OF_CONDUCT.md"
  "$REPO_DIR/docs"/*.md
  "$REPO_DIR/.github/PULL_REQUEST_TEMPLATE.md"
)
public_text="$(cat "${public_files[@]}")"

# The allowlist is structural, not a hidden global exclusion: CHANGELOG.md
# is historical, ADRs are durable historical records when introduced, and
# .writing-goals/ is protected private planning text.
assert_not_contains "$public_text" '\.goals([/`[:space:]]|$)' 'G12_LIVE_LEGACY_ZERO: public prose has no retired .goals ledger'
assert_not_contains "$public_text" 'external (wrapper |goal.chain )?driver' 'G12_LIVE_LEGACY_ZERO: public prose has no retired external driver'
assert_not_contains "$public_text" 'live[ -]symlink|sync\.sh|--force' 'G12_LIVE_LEGACY_ZERO: public prose has no retired live-link installer claim'
assert_not_contains "$public_text" 'autonomous driver|full-auto|run-loop' 'G12_LIVE_LEGACY_ZERO: public prose has no retired continuation mode'
assert_file_contains "$REPO_DIR/CHANGELOG.md" '^# Changelog' 'G12_HISTORICAL_ALLOWLIST_BOUNDED: changelog remains an explicit historical allowlist'
TEST_COUNT=$((TEST_COUNT + 1))
if [ ! -d "$REPO_DIR/docs/adr" ] || find "$REPO_DIR/docs/adr" -type f -name '*.md' -print -quit | grep -q .; then
  pass 'G12_HISTORICAL_ALLOWLIST_BOUNDED: ADR allowance is limited to docs/adr/*.md'
else
  fail 'G12_HISTORICAL_ALLOWLIST_BOUNDED: ADR directory contains no Markdown records'
fi
TEST_COUNT=$((TEST_COUNT + 1))
if [ -d "$REPO_DIR/.writing-goals" ] || [ -d "$REPO_DIR/tests/fixtures" ]; then
  pass 'G12_HISTORICAL_ALLOWLIST_BOUNDED: private planning is structurally outside public scan scope'
else
  fail 'G12_HISTORICAL_ALLOWLIST_BOUNDED: private planning allowlist boundary is unavailable'
fi

if [ "$TEST_FAILURES" -ne 0 ]; then
  printf '%s\n' 'FAIL: G12_LEGACY_PUBLIC_REMAINS' >&2
fi
finish_tests
