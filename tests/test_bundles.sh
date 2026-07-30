#!/usr/bin/env bash
# G09's protected oracle: portable bundle creation and legacy-source removal.
set -u
. "$(dirname "$0")/testlib.sh"

builder="$REPO_DIR/scripts/build-bundles.sh"
fixture="$REPO_DIR/tests/fixtures/install/protected-preimages.sha256"

# This check is intentionally first: before the maker supplies the builder,
# the exact red acceptance tuple must be unambiguous.
if [ ! -f "$builder" ]; then
  printf 'FAIL: G09_BUNDLE_BUILDER_MISSING: scripts/build-bundles.sh is absent\n' >&2
  exit 1
fi

assert_file_contains "$fixture" '^34aa3301a468d8bac5d4834f39d9f8dbf914f2b02bfdaae645143fdb6227b4eb  sync\.sh$' 'G09 protected sync.sh preimage is frozen'
assert_file_contains "$fixture" '^855dac6ef1a098dad65197a5374c7d2be7deacdc802bd5fff1f3092c4cd1a4ac  tests/test_sync\.sh$' 'G09 protected legacy-test preimage is frozen'

first="$TEST_TMP/bundle-first"
second="$TEST_TMP/bundle-second"
run_command bash "$builder" "$first"
assert_success 'G09 first bundle build succeeds'
run_command bash "$builder" "$second"
assert_success 'G09 second bundle build succeeds'

assert_path_absent "$first/.git" 'bundle excludes checkout metadata'
assert_file_contains "$first/MANIFEST.sha256" '^[0-9a-f]{64}  ' 'bundle supplies a SHA-256 manifest'
assert_file_contains "$second/MANIFEST.sha256" '^[0-9a-f]{64}  ' 'second bundle supplies a SHA-256 manifest'
run_command diff -ru "$first" "$second"
assert_success 'G09 independently built bundles are byte-for-byte deterministic'

for required in claude/SKILL.md codex/SKILL.md shared/method.md assets/gate.codex.sh install.sh MANIFEST.sha256; do
  TEST_COUNT=$((TEST_COUNT + 1))
  if [ -f "$first/$required" ]; then
    pass "bundle includes $required"
  else
    fail "bundle is missing $required"
  fi
done

run_command find "$first" -type l -print
assert_empty_file "$RUN_OUT" 'G09 bundle contains no symbolic links'
repo_escaped="$(printf '%s' "$REPO_DIR" | sed 's/[.[\\*^$()+?{|]/\\\\&/g')"
run_command grep -R -n -E -- "$repo_escaped|/Users/|/home/" "$first"
assert_nonzero 'G09 bundle contains no checkout or absolute-home source leak'

# Postconditions intentionally remain meaningful after the approved deletion.
assert_path_absent "$REPO_DIR/sync.sh" 'G09_SOURCE_REMOVAL_PROVED: legacy sync source is absent'
assert_path_absent "$REPO_DIR/tests/test_sync.sh" 'G09_SYNC_CASES_MIGRATED: legacy sync cases are removed only after replacement oracle exists'

finish_tests
