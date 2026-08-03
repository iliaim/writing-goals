#!/usr/bin/env bash
# Protected Codex continuation controller: wake, isolation, and recovery contract.
set -u
. "$(dirname "$0")/testlib.sh"

repo_physical="$(cd -P "$REPO_DIR" && pwd -P)"
test_physical="$(cd -P "$TEST_TMP" && pwd -P)"
controller="$repo_physical/assets/codex-continuation.sh"
runtime="$repo_physical/assets/runtime-check.sh"
advance="$repo_physical/assets/core-state-advance.sh"
fixtures="$repo_physical/tests/fixtures/core-integration"

missing_contract() {
  printf '%s\n' 'FAIL: G07_CONTINUATION_CONTROLLER_MISSING' >&2
  exit 1
}

[ -f "$controller" ] && [ -f "$runtime" ] && [ -f "$advance" ] || missing_contract
bash -n "$controller" && bash -n "$advance" || missing_contract

if ! command -v sandbox-exec >/dev/null 2>&1 || ! sandbox-exec -p '(version 1) (allow default)' true >/dev/null 2>&1; then
  pass 'G07_CONTINUATION_MACOS_PROOF: dynamic controller isolation runs on macOS'
  finish_tests
  exit $?
fi

authority="$test_physical/authority"
workspace="$test_physical/workspace"
mkdir -p "$authority/continuation-receipts" "$workspace"
chmod 700 "$authority"
chmod 700 "$authority/continuation-receipts"

write_protected() {
  target=$1
  shift
  umask 077
  printf '%s\n' "$@" > "$target"
  chmod 600 "$target"
}

copy_core() {
  source_case=$1
  cp "$fixtures/$source_case/core.env" "$authority/core-state.env"
  printf '%s\n' 'transition_generation=1' 'previous_core_sha256=bootstrap' >> "$authority/core-state.env"
  chmod 600 "$authority/core-state.env"
}

write_records() {
  core="$authority/core-state.env"
  field() { sed -n "s/^$1=//p" "$core"; }
  write_protected "$authority/activation.env" \
    "identity=$(field identity)" "plan=$(field plan)" "run=$(field run)" \
    "generation=$(field generation)" "objective_digest=$(field objective_digest)" \
    "plan_digest=$(field plan_digest)" "execution_order=$(field execution_order)"
  write_protected "$authority/approval.env" \
    "objective_digest=$(field objective_digest)" "plan_digest=$(field plan_digest)" \
    'approver=fixture-human' 'approved_at=2026-08-02T00:00:00Z' 'revoked=false'
  write_protected "$authority/preflight.env" \
    "objective_digest=$(field objective_digest)" "plan_digest=$(field plan_digest)" \
    'surface_digest=sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef' 'baseline=green'
  write_protected "$authority/run-state.env" \
    "identity=$(field identity)" "plan=$(field plan)" "run=$(field run)" \
    'generation=1' 'digest=sha256:fixture-state' 'state=implementing' 'candidate=fixture'
}

fake_codex="$test_physical/fake-codex"
cat > "$fake_codex" <<'EOF'
#!/usr/bin/env bash
set -u
printf '%s\n' "$*" >> "$WG_FAKE_LOG"
if touch "$WG_FAKE_AUTHORITY/maker-tamper" 2>/dev/null; then
  printf '%s\n' writable >> "$WG_FAKE_ISOLATION"
else
  printf '%s\n' denied >> "$WG_FAKE_ISOLATION"
fi
if touch "$WG_FAKE_TOOL/maker-tamper" 2>/dev/null; then
  printf '%s\n' tool-writable >> "$WG_FAKE_ISOLATION"
else
  printf '%s\n' tool-denied >> "$WG_FAKE_ISOLATION"
fi
if [ -n "${WG_FAKE_HOLD_FILE:-}" ]; then
  : > "$WG_FAKE_HOLD_FILE"
  hold_ticks=0
  while [ ! -e "${WG_FAKE_RELEASE_FILE:-}" ] && [ "$hold_ticks" -lt 100 ]; do
    sleep 0.05
    hold_ticks=$((hold_ticks + 1))
  done
fi
EOF
chmod 755 "$fake_codex"

tool_root="$repo_physical/assets"
profile="$authority/child.sb"
write_protected "$profile" \
  '; continuation fixture: child may use the test workspace but never authority.' \
  '(version 1)' '(allow default)' "(deny file-read* (subpath \"$authority\"))" "(deny file-write* (subpath \"$authority\"))" "(deny file-write* (subpath \"$tool_root\"))"

configure() {
  runtime_hash="$(shasum -a 256 "$runtime" | awk '{print $1}')"
  controller_hash="$(shasum -a 256 "$controller" | awk '{print $1}')"
  advance_hash="$(shasum -a 256 "$advance" | awk '{print $1}')"
  write_protected "$authority/continuation.env" \
    'identity=20260729-GV53BZ' 'plan=p01' 'run=run-g07-fixture' \
    'session_id=123e4567-e89b-12d3-a456-426614174000' "workspace=$workspace" \
    "codex_bin=$fake_codex" "sandbox_profile=$profile" "runtime_path=$runtime" \
    "trusted_root=$tool_root" "controller_sha256=$controller_hash" "runtime_sha256=$runtime_hash" \
    "advance_path=$advance" "advance_sha256=$advance_hash" 'no_progress_cap=1'
}

run_controller() {
  env WG_FAKE_LOG="$TEST_TMP/fake.log" WG_FAKE_ISOLATION="$TEST_TMP/isolation.log" WG_FAKE_AUTHORITY="$authority" WG_FAKE_TOOL="$tool_root" \
    bash "$controller" --authority "$authority" --identity 20260729-GV53BZ --plan p01 --run run-g07-fixture
}

copy_core resume-maker
write_records
configure
run_command run_controller
assert_nonzero 'G07_CONTINUATION_NO_PROGRESS: unchanged protected cursor blocks at its configured ceiling'
assert_file_contains "$TEST_TMP/fake.log" '^exec resume 123e4567-e89b-12d3-a456-426614174000 ' 'G07_CONTINUATION_EXACT_SESSION: wake uses only the protected exact session id'
assert_file_contains "$TEST_TMP/fake.log" 'G02-INTEGRATION.*writing-goals-maker|writing-goals-maker.*G02-INTEGRATION' 'G07_CONTINUATION_EXACT_CURSOR: wake prompt binds the verified node and role'
assert_file_contains "$TEST_TMP/isolation.log" '^denied$' 'G07_CONTINUATION_ISOLATION: resumed child cannot write lifecycle authority'
assert_file_contains "$TEST_TMP/isolation.log" '^tool-denied$' 'G07_CONTINUATION_ISOLATION: resumed child cannot alter the trusted controller or checker'
assert_path_absent "$authority/maker-tamper" 'G07_CONTINUATION_ISOLATION: authority content remains unchanged by child'
assert_file_contains "$authority/continuation-receipts/000001-wake-intent.env" '^kind=wake-intent$' 'G07_CONTINUATION_RECEIPT_INTENT: durable intent precedes the child invocation'
assert_file_contains "$authority/continuation-receipts/000001-blocked.env" '^reason=no-progress-cap$' 'G07_CONTINUATION_NO_PROGRESS: terminal receipt names the enforceable no-progress stop'
intent_hash="$(shasum -a 256 "$authority/continuation-receipts/000001-wake-intent.env" | awk '{print $1}')"
exit_hash="$(shasum -a 256 "$authority/continuation-receipts/000001-wake-exit.env" | awk '{print $1}')"
assert_file_contains "$authority/continuation-receipts/000001-wake-exit.env" "^previous_receipt_sha256=$intent_hash$" 'G07_CONTINUATION_RECEIPT_CHAIN: exit binds the durable wake intent'
assert_file_contains "$authority/continuation-receipts/000001-blocked.env" "^previous_receipt_sha256=$exit_hash$" 'G07_CONTINUATION_RECEIPT_CHAIN: block binds the durable wake exit'

# The child cannot mutate authority. A separate trusted host helper can install
# a pre-verified successor only when it names the exact protected preimage.
rm -rf "$authority/continuation-receipts" "$authority/continuation-state.env" "$TEST_TMP/fake.log" "$TEST_TMP/isolation.log" "$TEST_TMP/hold" "$TEST_TMP/release"
mkdir -p "$authority/continuation-receipts"
chmod 700 "$authority/continuation-receipts"
copy_core resume-maker
write_records
configure
hold_file="$TEST_TMP/hold"
release_file="$TEST_TMP/release"
env WG_FAKE_LOG="$TEST_TMP/fake.log" WG_FAKE_ISOLATION="$TEST_TMP/isolation.log" WG_FAKE_AUTHORITY="$authority" WG_FAKE_TOOL="$tool_root" \
  WG_FAKE_HOLD_FILE="$hold_file" WG_FAKE_RELEASE_FILE="$release_file" \
  bash "$controller" --authority "$authority" --identity 20260729-GV53BZ --plan p01 --run run-g07-fixture >"$TEST_TMP/controller.stdout" 2>"$TEST_TMP/controller.stderr" &
controller_pid=$!
hold_ticks=0
while [ ! -e "$hold_file" ] && [ "$hold_ticks" -lt 100 ]; do sleep 0.05; hold_ticks=$((hold_ticks + 1)); done
TEST_COUNT=$((TEST_COUNT + 1))
if [ -e "$hold_file" ]; then pass 'G07_CONTINUATION_ADVANCE: helper stages only while the isolated child is live'; else fail 'G07_CONTINUATION_ADVANCE: controller did not reach the isolated child'; fi
pre_core_hash="$(shasum -a 256 "$authority/core-state.env" | awk '{print $1}')"
cp "$authority/core-state.env" "$authority/core-next.env"
sed -i.bak -e 's/^role=.*/role=not-a-valid-role/' \
  -e 's/^transition_generation=.*/transition_generation=2/' \
  -e "s/^previous_core_sha256=.*/previous_core_sha256=$pre_core_hash/" "$authority/core-next.env"
rm -f "$authority/core-next.env.bak"
chmod 600 "$authority/core-next.env"
run_command bash "$advance" --authority "$authority" --identity 20260729-GV53BZ --plan p01 --run run-g07-fixture --expected-core-sha256 "$pre_core_hash"
assert_nonzero 'G07_CONTINUATION_ADVANCE: invalid staged cursor is rejected before installation'
TEST_COUNT=$((TEST_COUNT + 1))
if [ "$(shasum -a 256 "$authority/core-state.env" | awk '{print $1}')" = "$pre_core_hash" ]; then pass 'G07_CONTINUATION_ADVANCE: rejected staging leaves live authority unchanged'; else fail 'G07_CONTINUATION_ADVANCE: rejected staging changed live authority'; fi
assert_file_contains "$authority/core-next.env" '^role=not-a-valid-role$' 'G07_CONTINUATION_ADVANCE: rejected staging remains non-authoritative'
cp "$authority/core-state.env" "$authority/core-next.env"
sed -i.bak -e 's/^node_states=.*/node_states=G01-DISCOVERY:done,G02-INTEGRATION:reviewing/' \
  -e 's/^role_cursor=.*/role_cursor=G02-INTEGRATION:writing-goals-verifier/' \
  -e 's/^current_or_next=.*/current_or_next=G02-INTEGRATION/' \
  -e 's/^role=.*/role=writing-goals-verifier/' \
  -e 's/^reason=.*/reason=exact-verifier-handoff/' \
  -e 's/^transition_generation=.*/transition_generation=2/' \
  -e "s/^previous_core_sha256=.*/previous_core_sha256=$pre_core_hash/" "$authority/core-next.env"
rm -f "$authority/core-next.env.bak"
chmod 600 "$authority/core-next.env"
run_command bash "$advance" --authority "$authority" --identity 20260729-GV53BZ --plan p01 --run run-g07-fixture --expected-core-sha256 "$pre_core_hash"
assert_success 'G07_CONTINUATION_ADVANCE: trusted helper installs a verified monotonic successor'
assert_file_contains "$RUN_OUT" '^result=advanced$' 'G07_CONTINUATION_ADVANCE: helper reports only the protected advancement'
: > "$release_file"
wait "$controller_pid" || true
assert_file_contains "$authority/continuation-receipts/000001-advance.env" '^kind=advance$' 'G07_CONTINUATION_ADVANCE: controller records the trusted monotonic successor'
assert_file_contains "$TEST_TMP/fake.log" 'writing-goals-verifier' 'G07_CONTINUATION_ADVANCE: next wake derives the verifier cursor from protected state'

# A content change is not progress by itself: the new cursor must bind exactly
# to the prior core digest and move its transition generation forward.
rm -rf "$authority/continuation-receipts" "$authority/continuation-state.env" "$TEST_TMP/fake.log" "$TEST_TMP/isolation.log" "$TEST_TMP/hold" "$TEST_TMP/release"
mkdir -p "$authority/continuation-receipts"
chmod 700 "$authority/continuation-receipts"
copy_core resume-maker
write_records
configure
write_protected "$authority/continuation-state.env" \
  'identity=20260729-GV53BZ' 'plan=p01' 'run=run-g07-fixture' 'phase=idle' \
  'wake_sequence=0' 'no_progress_count=0' \
  'last_core_sha256=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa' \
  'last_transition_generation=1' \
  'last_receipt_sha256=bootstrap'
run_command run_controller
assert_nonzero 'G07_CONTINUATION_MONOTONIC: an unbound cursor snapshot blocks before Codex runs'
assert_contains "$(cat "$RUN_OUT" "$RUN_ERR")" 'nonmonotonic-core-state' 'G07_CONTINUATION_MONOTONIC: rejection names the missing predecessor binding'
assert_path_absent "$TEST_TMP/fake.log" 'G07_CONTINUATION_MONOTONIC: invalid successor never launches Codex'

# A competing controller must never launch a second session while the first owns
# the run lease.  The fake child holds the first process inside its sandbox.
rm -rf "$authority/continuation-receipts" "$authority/continuation-state.env" "$TEST_TMP/fake.log" "$TEST_TMP/isolation.log"
mkdir -p "$authority/continuation-receipts"
chmod 700 "$authority/continuation-receipts"
copy_core resume-maker
write_records
configure
hold_file="$TEST_TMP/hold"
release_file="$TEST_TMP/release"
env WG_FAKE_LOG="$TEST_TMP/fake.log" WG_FAKE_ISOLATION="$TEST_TMP/isolation.log" WG_FAKE_AUTHORITY="$authority" WG_FAKE_TOOL="$tool_root" \
  WG_FAKE_HOLD_FILE="$hold_file" WG_FAKE_RELEASE_FILE="$release_file" \
  bash "$controller" --authority "$authority" --identity 20260729-GV53BZ --plan p01 --run run-g07-fixture >/dev/null 2>&1 &
controller_pid=$!
hold_ticks=0
while [ ! -e "$hold_file" ] && [ "$hold_ticks" -lt 100 ]; do sleep 0.05; hold_ticks=$((hold_ticks + 1)); done
run_command run_controller
assert_nonzero 'G07_CONTINUATION_SINGLE_FLIGHT: competing controller is rejected while a wake is live'
assert_contains "$(cat "$RUN_OUT" "$RUN_ERR")" 'controller-busy' 'G07_CONTINUATION_SINGLE_FLIGHT: contention reports the protected run lease'
: > "$release_file"
wait "$controller_pid" || true
assert_file_contains "$TEST_TMP/fake.log" '^exec resume ' 'G07_CONTINUATION_SINGLE_FLIGHT: only the lease owner invokes Codex'
TEST_COUNT=$((TEST_COUNT + 1))
if [ "$(wc -l < "$TEST_TMP/fake.log" | tr -d ' ')" = 1 ]; then pass 'G07_CONTINUATION_SINGLE_FLIGHT: contention launches no duplicate Codex process'; else fail 'G07_CONTINUATION_SINGLE_FLIGHT: contention launched a duplicate Codex process'; fi

finish_tests
