#!/usr/bin/env bash
# Protected G06 oracle: retention is bounded, explicit, deterministic, and authority-safe.
set -u
. "$(dirname "$0")/testlib.sh"

pruner="$REPO_DIR/assets/prune-evidence.sh"
fixtures="$REPO_DIR/tests/fixtures/retention"

fail_missing_pruner() {
  printf '%s\n' 'FAIL: G06_PRUNER_MISSING' >&2
  exit 1
}

# Keep the intended protected red ahead of all fixture/setup assertions.
[ -f "$pruner" ] || fail_missing_pruner
[ -d "$fixtures/records" ] || fail_missing_pruner

prepare_records() {
  local destination="$1"
  cp -R "$fixtures/records" "$destination"
}

records="$TEST_TMP/records-one"
manifest="$TEST_TMP/deletions-one.tsv"
prepare_records "$records"

# No selector set means no retention action: an explicit, complete call is required.
before_digest="$(find "$records" -type f -exec shasum -a 256 {} \; | LC_ALL=C sort)"
run_command bash "$pruner" --records-dir "$records"
assert_nonzero 'G06_EXPLICIT_ONLY: incomplete prune request is rejected'
after_digest="$(find "$records" -type f -exec shasum -a 256 {} \; | LC_ALL=C sort)"
TEST_COUNT=$((TEST_COUNT + 1))
if [ "$before_digest" = "$after_digest" ]; then pass 'G06_EXPLICIT_ONLY: incomplete request makes no implicit or periodic deletion'; else fail 'G06_EXPLICIT_ONLY: incomplete request changed retained evidence'; fi

run_command bash "$pruner" --records-dir "$records" --identity run-alpha --plan p01 --cutoff 2025-01-01T00:00:00Z --manifest "$manifest"
assert_success 'G06_RETENTION_LIMITS: exact identity/plan/cutoff prune succeeds'
assert_path_absent "$records/old-unreferenced.receipt" 'G06_RETENTION_LIMITS: expired unreferenced matching record is deleted'
assert_file_contains "$records/new-unreferenced.receipt" 'at cutoff' 'G06_RETENTION_LIMITS: cutoff is strict and retains boundary record'
assert_file_contains "$records/wrong-plan.receipt" 'wrong plan' 'G06_RETENTION_LIMITS: plan selector is exact'
assert_file_contains "$records/wrong-identity.receipt" 'wrong identity' 'G06_RETENTION_LIMITS: identity selector is exact'
assert_file_contains "$records/old-referenced.receipt" 'protected authority' 'G06_REFERENCED_AUTHORITY_PRESERVED: referenced receipt is retained'
assert_file_contains "$records/authority-current.receipt" 'current authority' 'G06_REFERENCED_AUTHORITY_PRESERVED: referring authority is retained'

TEST_COUNT=$((TEST_COUNT + 1))
if cmp -s "$fixtures/expected-manifest.tsv" "$manifest"; then pass 'G06_RETENTION_LIMITS: deletion manifest is exact and sorted'; else fail 'G06_RETENTION_LIMITS: deletion manifest differs from protected expected manifest'; fi

# Identical input must produce byte-identical output, not merely an equivalent set.
records_two="$TEST_TMP/records-two"
manifest_two="$TEST_TMP/deletions-two.tsv"
prepare_records "$records_two"
run_command bash "$pruner" --records-dir "$records_two" --identity run-alpha --plan p01 --cutoff 2025-01-01T00:00:00Z --manifest "$manifest_two"
assert_success 'G06_RETENTION_LIMITS: identical explicit prune reruns successfully'
TEST_COUNT=$((TEST_COUNT + 1))
if cmp -s "$manifest" "$manifest_two"; then pass 'G06_RETENTION_LIMITS: repeated deletion manifest is deterministic'; else fail 'G06_RETENTION_LIMITS: repeated deletion manifest is non-deterministic'; fi

finish_tests
