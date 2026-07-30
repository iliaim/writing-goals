#!/usr/bin/env bash
# Protected G06 oracle: persistable evidence must be redacted in-stream and fail closed.
set -u
. "$(dirname "$0")/testlib.sh"

redactor="$REPO_DIR/assets/redact-stream.sh"
fixtures="$REPO_DIR/tests/fixtures/redaction"

fail_missing_redactor() {
  printf '%s\n' 'FAIL: G06_STREAM_REDACTOR_MISSING' >&2
  exit 1
}

# Keep the intended protected red ahead of all fixture/setup assertions.
[ -f "$redactor" ] || fail_missing_redactor
[ -d "$fixtures" ] || fail_missing_redactor

seed_one='sk_live_G06SeedToken_7f3c2b1a9d'
seed_two='ghp_G06AnotherSeed_4e8a1c9f7b2d'
root_one='/private/g06-redaction-root/workspace'
root_two='/Users/alice/private/g06-source-root'
json_seed='G06JsonSecret_81f2a9c4d7'
windows_root='C:\Users\alice\private\g06-json-root'
client_secret='G06ClientSecret_4b7d91e2c8'
unc_root='\\\\server\\share\\private\\g06-unc-root'
escaped_client_secret='G06EscapedClientSecret_0f2d6a9b'
escaped_secret='G06EscapedSecret_7c1e4d8a'
embedded_escaped_client_secret='G06EmbeddedEscapedClientSecret_3a8f1c6d'
array_client_secret='G06ArrayClientSecret_9d2f4a7c'
nested_client_secret='G06NestedClientSecret_6b1e8c3f'
object_secret='G06ObjectSecret_1c7a5d9e'
secondary_secret='G06SecondarySecret_4f2b8a6c'
colon_api_key='G06ColonApiKey_8e2c5a1d'
colon_client_secret='G06ColonClientSecret_3f7b9d4a'
work="$TEST_TMP/redaction-output"
output="$work/evidence.txt"
redactor_tmp="$work/tmp"
mkdir -p "$redactor_tmp"

scan_for_leaks() {
  local location="$1" pattern
  if [ -e "$location" ]; then
    for pattern in "$seed_one" "$seed_two" "$root_one" "$root_two" "$json_seed" "$windows_root" "$client_secret" "$unc_root" "$escaped_client_secret" "$escaped_secret" "$embedded_escaped_client_secret" "$array_client_secret" "$nested_client_secret" "$object_secret" "$secondary_secret" "$colon_api_key" "$colon_client_secret"; do
      grep -R -a -F -- "$pattern" "$location" 2>/dev/null
    done
  fi
}

assert_no_persisted_leaks() {
  local location="$1" label="$2" leaked
  TEST_COUNT=$((TEST_COUNT + 1))
  leaked="$(scan_for_leaks "$location")"
  if [ -z "$leaked" ]; then
    pass "$label"
  else
    fail "$label (found protected seed in persisted output or temporary path)"
  fi
}

run_command env TMPDIR="$redactor_tmp" bash "$redactor" --output "$output" --max-bytes 160 --max-records 2 < "$fixtures/stream.txt"
assert_success 'G06_REDACT_BEFORE_DISK: known stream is accepted'
assert_no_persisted_leaks "$work" 'G06_REDACT_BEFORE_DISK: no token or absolute root persists beneath output directory'
assert_not_contains "$(cat "$RUN_OUT" "$RUN_ERR")" "$seed_one|$seed_two|$root_one|$root_two" 'G06_REDACT_BEFORE_DISK: command output does not echo a seed'
assert_file_contains "$output" '.' 'G06_REDACT_BEFORE_DISK: sanitized evidence is persisted'

TEST_COUNT=$((TEST_COUNT + 1))
if [ "$(wc -c < "$output" | tr -d ' ')" -le 160 ]; then pass 'G06_REDACT_LIMITS: persisted evidence is byte-bounded'; else fail 'G06_REDACT_LIMITS: persisted evidence exceeds 160 bytes'; fi
TEST_COUNT=$((TEST_COUNT + 1))
if [ "$(wc -l < "$output" | tr -d ' ')" -le 2 ]; then pass 'G06_REDACT_LIMITS: persisted evidence is record-bounded'; else fail 'G06_REDACT_LIMITS: persisted evidence exceeds 2 records'; fi

# This is valid UTF-8, so a maker may redact and persist it or fail closed. The
# accepted mixed stream above prevents implementing that second option globally.
json_work="$TEST_TMP/redaction-json-output"
json_tmp="$json_work/tmp"
json_output="$json_work/json-evidence.txt"
mkdir -p "$json_tmp"
# The record is intentionally below this cap: do not let byte truncation hide
# a JSON-field or Windows-path leak from this protected regression.
run_command env TMPDIR="$json_tmp" bash "$redactor" --output "$json_output" --max-bytes 1000 --max-records 2 < "$fixtures/valid-json-secret.json"
if [ "$RUN_STATUS" -eq 0 ]; then
  assert_file_contains "$json_output" '"event"[[:space:]]*:[[:space:]]*"evidence"' 'G06_REDACT_JSON_WINDOWS: accepted JSON retains sanitized evidence content'
  TEST_COUNT=$((TEST_COUNT + 1))
  if ! grep -a -F -- "$json_seed" "$json_output" >/dev/null 2>&1 && ! grep -a -F -- "$windows_root" "$json_output" >/dev/null 2>&1; then
    pass 'G06_REDACT_JSON_WINDOWS: accepted JSON contains no secret or Windows root'
  else
    fail 'G06_REDACT_JSON_WINDOWS: accepted JSON leaks a secret or Windows root'
  fi
else
  assert_path_absent "$json_output" 'G06_FAIL_CLOSED_JSON_WINDOWS: rejected valid JSON creates no final evidence file'
fi
assert_no_persisted_leaks "$json_work" 'G06_REDACT_JSON_WINDOWS: JSON secret and Windows root never persist beneath output directory'
assert_not_contains "$(cat "$RUN_OUT" "$RUN_ERR")" "$json_seed|C:\\\\Users\\\\alice\\\\private\\\\g06-json-root" 'G06_REDACT_JSON_WINDOWS: command output does not echo JSON secret or Windows root'

client_work="$TEST_TMP/redaction-client-secret-output"
client_tmp="$client_work/tmp"
client_output="$client_work/client-evidence.txt"
mkdir -p "$client_tmp"
run_command env TMPDIR="$client_tmp" bash "$redactor" --output "$client_output" --max-bytes 1000 --max-records 2 < "$fixtures/valid-json-client-secret.json"
if [ "$RUN_STATUS" -eq 0 ]; then
  assert_file_contains "$client_output" '"event"[[:space:]]*:[[:space:]]*"client-evidence"' 'G06_REDACT_CLIENT_SECRET_UNC: accepted JSON retains sanitized evidence content'
  TEST_COUNT=$((TEST_COUNT + 1))
  if ! grep -a -F -- "$client_secret" "$client_output" >/dev/null 2>&1 && ! grep -a -F -- "$unc_root" "$client_output" >/dev/null 2>&1; then
    pass 'G06_REDACT_CLIENT_SECRET_UNC: accepted JSON contains no client secret or UNC root'
  else
    fail 'G06_REDACT_CLIENT_SECRET_UNC: accepted JSON leaks a client secret or UNC root'
  fi
else
  assert_path_absent "$client_output" 'G06_FAIL_CLOSED_CLIENT_SECRET_UNC: rejected valid JSON creates no final evidence file'
fi
assert_no_persisted_leaks "$client_work" 'G06_REDACT_CLIENT_SECRET_UNC: client secret and UNC root never persist beneath output directory'
assert_not_contains "$(cat "$RUN_OUT" "$RUN_ERR")" "$client_secret|\\\\\\\\server\\\\share\\\\private" 'G06_REDACT_CLIENT_SECRET_UNC: command output does not echo client secret or UNC root'

escaped_work="$TEST_TMP/redaction-escaped-key-output"
escaped_tmp="$escaped_work/tmp"
escaped_output="$escaped_work/escaped-key-evidence.txt"
mkdir -p "$escaped_tmp"
run_command env TMPDIR="$escaped_tmp" bash "$redactor" --output "$escaped_output" --max-bytes 1000 --max-records 2 < "$fixtures/valid-json-escaped-keys.json"
if [ "$RUN_STATUS" -eq 0 ]; then
  assert_file_contains "$escaped_output" '"event"[[:space:]]*:[[:space:]]*"escaped-key-evidence"' 'G06_REDACT_ESCAPED_KEYS: accepted JSON retains sanitized evidence content'
  TEST_COUNT=$((TEST_COUNT + 1))
  if ! grep -a -F -- "$escaped_client_secret" "$escaped_output" >/dev/null 2>&1 && ! grep -a -F -- "$escaped_secret" "$escaped_output" >/dev/null 2>&1; then
    pass 'G06_REDACT_ESCAPED_KEYS: accepted JSON contains no escaped-key secret values'
  else
    fail 'G06_REDACT_ESCAPED_KEYS: accepted JSON leaks an escaped-key secret value'
  fi
else
  assert_path_absent "$escaped_output" 'G06_FAIL_CLOSED_ESCAPED_KEYS: rejected valid JSON creates no final evidence file'
fi
assert_no_persisted_leaks "$escaped_work" 'G06_REDACT_ESCAPED_KEYS: escaped-key secret values never persist beneath output directory'
assert_not_contains "$(cat "$RUN_OUT" "$RUN_ERR")" "$escaped_client_secret|$escaped_secret" 'G06_REDACT_ESCAPED_KEYS: command output does not echo escaped-key secret values'

embedded_work="$TEST_TMP/redaction-embedded-escaped-key-output"
embedded_tmp="$embedded_work/tmp"
embedded_output="$embedded_work/embedded-escaped-key-evidence.txt"
mkdir -p "$embedded_tmp"
run_command env TMPDIR="$embedded_tmp" bash "$redactor" --output "$embedded_output" --max-bytes 1000 --max-records 2 < "$fixtures/timestamped-embedded-escaped-key.log"
if [ "$RUN_STATUS" -eq 0 ]; then
  assert_file_contains "$embedded_output" '2026-07-30T10:11:12Z' 'G06_REDACT_EMBEDDED_ESCAPED_KEY: accepted timestamped record retains sanitized evidence content'
  TEST_COUNT=$((TEST_COUNT + 1))
  if ! grep -a -F -- "$embedded_escaped_client_secret" "$embedded_output" >/dev/null 2>&1; then
    pass 'G06_REDACT_EMBEDDED_ESCAPED_KEY: accepted timestamped record contains no escaped-key secret value'
  else
    fail 'G06_REDACT_EMBEDDED_ESCAPED_KEY: accepted timestamped record leaks an escaped-key secret value'
  fi
else
  assert_path_absent "$embedded_output" 'G06_FAIL_CLOSED_EMBEDDED_ESCAPED_KEY: rejected timestamped record creates no final evidence file'
fi
assert_no_persisted_leaks "$embedded_work" 'G06_REDACT_EMBEDDED_ESCAPED_KEY: timestamped embedded secret never persists beneath output directory'
assert_not_contains "$(cat "$RUN_OUT" "$RUN_ERR")" "$embedded_escaped_client_secret" 'G06_REDACT_EMBEDDED_ESCAPED_KEY: command output does not echo embedded escaped-key secret value'

structured_work="$TEST_TMP/redaction-structured-credentials-output"
structured_tmp="$structured_work/tmp"
structured_output="$structured_work/structured-credentials-evidence.txt"
mkdir -p "$structured_tmp"
run_command env TMPDIR="$structured_tmp" bash "$redactor" --output "$structured_output" --max-bytes 1000 --max-records 2 < "$fixtures/valid-json-structured-credentials.json"
if [ "$RUN_STATUS" -eq 0 ]; then
  assert_file_contains "$structured_output" '"event"[[:space:]]*:[[:space:]]*"structured-credential-evidence"' 'G06_REDACT_STRUCTURED_CREDENTIALS: accepted JSON retains sanitized evidence content'
  TEST_COUNT=$((TEST_COUNT + 1))
  if ! grep -a -F -- "$array_client_secret" "$structured_output" >/dev/null 2>&1 && ! grep -a -F -- "$nested_client_secret" "$structured_output" >/dev/null 2>&1 && ! grep -a -F -- "$object_secret" "$structured_output" >/dev/null 2>&1 && ! grep -a -F -- "$secondary_secret" "$structured_output" >/dev/null 2>&1; then
    pass 'G06_REDACT_STRUCTURED_CREDENTIALS: accepted JSON contains no array or object credential values'
  else
    fail 'G06_REDACT_STRUCTURED_CREDENTIALS: accepted JSON leaks an array or object credential value'
  fi
else
  assert_path_absent "$structured_output" 'G06_FAIL_CLOSED_STRUCTURED_CREDENTIALS: rejected valid JSON creates no final evidence file'
fi
assert_no_persisted_leaks "$structured_work" 'G06_REDACT_STRUCTURED_CREDENTIALS: structured credential values never persist beneath output directory'
assert_not_contains "$(cat "$RUN_OUT" "$RUN_ERR")" "$array_client_secret|$nested_client_secret|$object_secret|$secondary_secret" 'G06_REDACT_STRUCTURED_CREDENTIALS: command output does not echo structured credential values'

colon_work="$TEST_TMP/redaction-colon-credentials-output"
colon_tmp="$colon_work/tmp"
colon_output="$colon_work/colon-credentials-evidence.txt"
mkdir -p "$colon_tmp"
run_command env TMPDIR="$colon_tmp" bash "$redactor" --output "$colon_output" --max-bytes 1000 --max-records 10 < "$fixtures/colon-delimited-credentials.log"
if [ "$RUN_STATUS" -eq 0 ]; then
  assert_file_contains "$colon_output" 'event=colon-credential-evidence' 'G06_REDACT_COLON_CREDENTIALS: accepted record retains sanitized evidence content'
  TEST_COUNT=$((TEST_COUNT + 1))
  if ! grep -a -F -- "$colon_api_key" "$colon_output" >/dev/null 2>&1 && ! grep -a -F -- "$colon_client_secret" "$colon_output" >/dev/null 2>&1; then
    pass 'G06_REDACT_COLON_CREDENTIALS: accepted record contains no colon-delimited credential values'
  else
    fail 'G06_REDACT_COLON_CREDENTIALS: accepted record leaks a colon-delimited credential value'
  fi
else
  assert_path_absent "$colon_output" 'G06_FAIL_CLOSED_COLON_CREDENTIALS: rejected colon-delimited record creates no final evidence file'
fi
assert_no_persisted_leaks "$colon_work" 'G06_REDACT_COLON_CREDENTIALS: colon-delimited credential values never persist beneath output directory'
assert_not_contains "$(cat "$RUN_OUT" "$RUN_ERR")" "$colon_api_key|$colon_client_secret" 'G06_REDACT_COLON_CREDENTIALS: command output does not echo colon-delimited credential values'

malformed="$TEST_TMP/malformed-input.bin"
hex="$(tr -d '\n' < "$fixtures/malformed-encoding.hex")"
printf '%s' "$hex" | xxd -r -p > "$malformed"
malformed_work="$TEST_TMP/redaction-malformed-output"
malformed_tmp="$malformed_work/tmp"
failed_output="$malformed_work/malformed-evidence.txt"
mkdir -p "$malformed_tmp"
run_command env TMPDIR="$malformed_tmp" bash "$redactor" --output "$failed_output" --max-bytes 160 --max-records 2 < "$malformed"
assert_nonzero 'G06_FAIL_CLOSED_UNCERTAIN: malformed encoding is rejected'
assert_path_absent "$failed_output" 'G06_FAIL_CLOSED_UNCERTAIN: malformed input creates no final evidence file'
assert_no_persisted_leaks "$malformed_work" 'G06_FAIL_CLOSED_UNCERTAIN: malformed token never reaches disk'

finish_tests
