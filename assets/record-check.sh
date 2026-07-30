#!/usr/bin/env bash
# Validate a completed receipt against exact expected bindings.  This never
# executes recorded argv; receipts are evidence, not instructions.
set -u

receipt= expected=
while [ "$#" -gt 0 ]; do
  case "$1" in
    --receipt) receipt=${2:-}; shift 2 ;;
    --expected) expected=${2:-}; shift 2 ;;
    *) exit 2 ;;
  esac
done
[ -f "$receipt" ] && [ -f "$expected" ] || exit 2
value() { sed -n "s/^$2=//p" "$1" | head -n 1; }
one_value() { [ "$(grep -c "^$2=" "$1")" -eq 1 ] || fail; value "$1" "$2"; }
valid_sha() { printf '%s' "$1" | grep -Eq '^[0-9a-f]{64}$'; }
valid_id() { printf '%s' "$1" | grep -Eq '^[A-Za-z0-9][A-Za-z0-9._:-]*$'; }
fail() { exit 1; }

state=$(one_value "$receipt" state); task_class=$(one_value "$receipt" task_class)
kind=$(one_value "$receipt" kind); result=$(one_value "$receipt" result)
role=$(one_value "$receipt" role); actor=$(one_value "$receipt" actor)
context=$(one_value "$receipt" context); output_bytes=$(one_value "$receipt" output_bytes)
output_sha=$(one_value "$receipt" output_sha256); receipt_sha=$(one_value "$receipt" receipt_sha256)
[ "$state" = completed ] || fail
case "$task_class" in behavioral_code|docs_config|refactor|research_design) ;; *) fail;; esac
case "$kind:$role" in check:verifier|review:reviewer) ;; *) fail;; esac
case "$task_class:$kind" in
  behavioral_code:check|behavioral_code:review|docs_config:check|docs_config:review|refactor:check|refactor:review|research_design:review) ;;
  *) fail ;;
esac
case "$result" in pass|fail) ;; *) fail;; esac
valid_id "$actor" && valid_id "$context" || fail
printf '%s' "$output_bytes" | grep -Eq '^[0-9]+$' || fail
[ "$output_bytes" -le 65536 ] 2>/dev/null || fail
valid_sha "$output_sha" && valid_sha "$receipt_sha" || fail

for key in task_class objective criterion oracle_sha256 candidate_commit candidate_tree; do
  actual=$(one_value "$receipt" "$key"); want=$(value "$expected" "$key")
  [ -n "$actual" ] && [ "$actual" = "$want" ] || fail
done
valid_sha "$(value "$receipt" oracle_sha256)" || fail
printf '%s' "$(value "$receipt" candidate_commit)" | grep -Eq '^[0-9a-f]{40}$' || fail
printf '%s' "$(value "$receipt" candidate_tree)" | grep -Eq '^[0-9a-f]{40}$' || fail

forbidden=$(value "$expected" forbidden_context)
[ -z "$forbidden" ] || [ "$context" != "$forbidden" ] || fail
if [ "$kind" = check ]; then
  argv=$(one_value "$receipt" argv); want=$(value "$expected" argv)
  [ -n "$argv" ] && [ "$argv" = "$want" ] || fail
else
  scope=$(one_value "$receipt" review_scope); want=$(value "$expected" review_scope)
  [ -n "$scope" ] && [ "$scope" = "$want" ] || fail
fi
red_kind=$(one_value "$receipt" red_kind); required_red=$(value "$expected" required_red_kind)
[ "$red_kind" = "$required_red" ] || fail
if [ "$required_red" = none ]; then
  [ "$result" = pass ] || fail
else
  [ "$result" = fail ] || fail
  required_assertion=$(value "$expected" required_red_assertion)
  [ "$(one_value "$receipt" red_assertion)" = "$required_assertion" ] || fail
fi
if [ "$task_class" = research_design ] && [ "$result" != pass ]; then fail; fi
remediation=$(value "$expected" remediation_of)
expected_characterization=$(value "$expected" characterization_sha256)
if [ -n "$expected_characterization" ]; then
  [ "$(value "$receipt" characterization_sha256)" = "$expected_characterization" ] && valid_sha "$expected_characterization" || fail
fi
expected_output=$(value "$expected" output_sha256)
[ -z "$expected_output" ] || [ "$output_sha" = "$expected_output" ] || fail
expected_receipt=$(value "$expected" receipt_sha256)
[ -z "$expected_receipt" ] || [ "$receipt_sha" = "$expected_receipt" ] || fail
if [ -n "$remediation" ]; then
  [ "$(value "$receipt" remediation_of)" = "$remediation" ] || fail
  [ "$(value "$receipt" candidate_tree)" != "$(value "$expected" previous_candidate_tree)" ] || fail
fi
