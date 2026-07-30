#!/usr/bin/env bash
# Executable OS-sandbox evidence, not a claim that JSON hooks alone contain a
# host. The fixture proves the maker/verifier split against protected paths.
set -u
. "$(dirname "$0")/testlib.sh"

profile_template="$REPO_DIR/tests/fixtures/host-isolation/profile.sb.tmpl"
contract_missing=0
for host in claude codex; do
  skill="$REPO_DIR/$host/SKILL.md"
  TEST_COUNT=$((TEST_COUNT + 1))
  if [ -f "$profile_template" ] && [ -f "$skill" ] && grep -Eq 'sandbox-exec|OS-level sandbox' "$skill"; then
    pass "G08_HOST_ISOLATION_MISSING: $host declares OS containment and has a fixture"
  else
    fail "G08_HOST_ISOLATION_MISSING: $host needs an OS-sandbox declaration and fixture"
    contract_missing=1
  fi
done

if [ "$contract_missing" -ne 0 ]; then
  finish_tests
  exit $?
fi

if ! command -v sandbox-exec >/dev/null 2>&1 || ! sandbox-exec -p '(version 1) (allow default)' true >/dev/null 2>&1; then
  # The executable proof is macOS-specific.  CI still checks the declared
  # containment contract here; the macOS matrix entry runs the proof below.
  pass 'G08_UNSUPPORTED_PROOF: sandbox-exec unavailable; dynamic proof runs on macOS'
  finish_tests
  exit $?
fi

for host in claude codex; do
  root="$TEST_TMP/$host"
  source_dir="$root/source"
  protected_dir="$root/protected"
  mkdir -p "$source_dir" "$protected_dir"
  printf 'run-before\n' > "$protected_dir/run"
  printf 'oracle-before\n' > "$protected_dir/oracle"
  printf 'gate-before\n' > "$protected_dir/gate"
  before="$(shasum -a 256 "$protected_dir/run" "$protected_dir/oracle" "$protected_dir/gate" | shasum -a 256 | awk '{print $1}')"
  profile="$root/profile.sb"
  # sandbox-exec compares subpaths literally; mktemp may preserve a doubled
  # slash inherited from TMPDIR, while the kernel presents the canonical path.
  source_phys="$(cd -P "$source_dir" && pwd -P)" || {
    fail "G08_MAKER_ISOLATED: $host source directory cannot be canonicalized"
    continue
  }
  sed -e "s|__SOURCE__|$source_phys|g" "$profile_template" > "$profile"

  run_command sandbox-exec -f "$profile" /bin/sh -c 'printf maker > "$1/owned.txt"' sh "$source_dir"
  assert_success "G08_MAKER_ISOLATED: $host maker can edit its owned source"
  assert_file_contains "$source_dir/owned.txt" '^maker$' "G08_MAKER_ISOLATED: $host owned edit persisted"

  for protected in run oracle gate; do
    run_command sandbox-exec -f "$profile" /bin/sh -c 'printf tampered > "$1/$2"' sh "$protected_dir" "$protected"
    assert_nonzero "G08_MAKER_ISOLATED: $host maker cannot mutate protected $protected state"
  done
  after="$(shasum -a 256 "$protected_dir/run" "$protected_dir/oracle" "$protected_dir/gate" | shasum -a 256 | awk '{print $1}')"
  TEST_COUNT=$((TEST_COUNT + 1))
  if [ "$before" = "$after" ]; then pass "G08_MAKER_ISOLATED: $host protected hashes are unchanged"; else fail "G08_MAKER_ISOLATED: $host protected hashes changed"; fi

  run_command /bin/sh -c 'cat "$1/oracle"' sh "$protected_dir"
  assert_success "G08_FRESH_VERIFIER: $host verifier reads protected evidence outside maker sandbox"
  assert_contains "$(cat "$RUN_OUT")" '^oracle-before$' "G08_FRESH_VERIFIER: $host verifier sees the original evidence"
done

finish_tests
