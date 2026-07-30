#!/usr/bin/env bash
# Protected G11 oracle: deterministic local final-readiness, never publication.
set -u
. "$(dirname "$0")/testlib.sh"

readiness="$REPO_DIR/assets/publish-readiness.sh"
fixtures="$REPO_DIR/tests/fixtures/publication"
missing_contract() { printf '%s\n' 'FAIL: G11_READINESS_MISSING' >&2; exit 1; }
[ -f "$readiness" ] && [ -f "$fixtures/readiness.env" ] || missing_contract
bash -n "$readiness" || missing_contract

. "$fixtures/readiness.env"
fake_bin="$TEST_TMP/fake-bin"
mkdir -p "$fake_bin"
cp "$fixtures/fake-bin/git" "$fake_bin/git"
cp "$fixtures/fake-bin/gh" "$fake_bin/gh"
chmod 500 "$fake_bin/git" "$fake_bin/gh"

run_readiness() {
  scenario=$1; shift
  transcript="$TEST_TMP/$scenario.argv"; : > "$transcript"
  branch="$head"; remote_url="git@github.com:$repository.git"; head_commit="$commit"; head_tree="$tree"
  case "$scenario" in dirty) ;; branch-mismatch) branch=codex/other ;; remote-mismatch) remote_url=git@github.com:acme/other.git ;; commit-mismatch) head_commit=3333333333333333333333333333333333333333 ;; tree-mismatch) head_tree=4444444444444444444444444444444444444444 ;; protected-branch) branch=main ;; esac
  run_command env PATH="$fake_bin:$PATH" FAKE_TRANSCRIPT="$transcript" FAKE_SCENARIO="$scenario" FAKE_BRANCH="$branch" FAKE_REMOTE_URL="$remote_url" FAKE_COMMIT="$head_commit" FAKE_TREE="$head_tree" \
    "$readiness" "$@"
  LAST_TRANSCRIPT="$transcript"
}

args=(--repo "$repository" --remote "$remote" --base "$base" --head "$head" --commit "$commit" --tree "$tree")
assert_local_only() {
  assert_not_contains "$(cat "$LAST_TRANSCRIPT")" '^git <(remote|push|ls-remote|fetch|pull|clone)|^gh| <(merge|deploy|release|tag|delete)>|--force' "$1: no remote query, mutation, or lifecycle command"
}
assert_readiness_packet() {
  assert_file_contains "$RUN_OUT" '^readiness=ready$' 'G11_READINESS_PACKET: status is deterministic'
  assert_file_contains "$RUN_OUT" '^repository=acme/writing-goals$' 'G11_READINESS_PACKET: exact repository'
  assert_file_contains "$RUN_OUT" '^commit=1111111111111111111111111111111111111111$' 'G11_READINESS_PACKET: exact final commit'
  assert_file_contains "$RUN_OUT" '^tree=2222222222222222222222222222222222222222$' 'G11_READINESS_PACKET: exact final tree'
  assert_file_contains "$RUN_OUT" 'human.*(G13|terminal)|(G13|terminal).*human' 'G11_READINESS_PACKET: human-only publication after terminal G13'
  assert_not_contains "$(cat "$RUN_OUT" "$RUN_ERR")" 'ghp_|token=|secret|/protected-' 'G11_READINESS_PACKET: no secret or protected path'
}

run_readiness valid "${args[@]}"
assert_success 'G11_LOCAL_READINESS: exact clean local target is ready'
assert_readiness_packet
assert_file_contains "$LAST_TRANSCRIPT" '^git <show-ref> <--verify> <--quiet> <refs/heads/main>$' 'G11_LOCAL_BASE: base is resolved from a local ref'
assert_file_contains "$LAST_TRANSCRIPT" '^git <merge-base> <--is-ancestor> <main> <HEAD>$' 'G11_LOCAL_BASE: local base ancestry reaches exact HEAD'
assert_local_only 'G11_LOCAL_READINESS'

for scenario in dirty branch-mismatch remote-mismatch commit-mismatch tree-mismatch protected-branch; do
  run_readiness "$scenario" "${args[@]}"
  assert_nonzero "G11_LOCAL_READINESS: $scenario blocks"
  assert_local_only "G11_LOCAL_READINESS: $scenario"
done

# Base must be a local branch and must be an ancestor of the exact HEAD. A
# remote-tracking spelling is not a local readiness base.
for scenario in base-absent base-not-ancestor; do
  run_readiness "$scenario" "${args[@]}"
  assert_nonzero "G11_LOCAL_BASE: $scenario blocks"
  assert_local_only "G11_LOCAL_BASE: $scenario"
done
run_readiness nonlocal-base --repo "$repository" --remote "$remote" --base origin/main --head "$head" --commit "$commit" --tree "$tree"
assert_nonzero 'G11_LOCAL_BASE: remote-tracking base blocks'
assert_local_only 'G11_LOCAL_BASE: remote-tracking base'

for omitted in repo remote base head commit tree; do
  short_args=()
  index=0
  while [ "$index" -lt "${#args[@]}" ]; do
    flag="${args[$index]}"
    if [ "$flag" != "--$omitted" ]; then short_args+=("$flag" "${args[$((index + 1))]}"); fi
    index=$((index + 2))
  done
  run_readiness "missing-$omitted" "${short_args[@]}"
  assert_nonzero "G11_EXPLICIT_TARGET: missing --$omitted blocks"
  assert_local_only "G11_EXPLICIT_TARGET: missing --$omitted"
done

run_readiness forbidden "${args[@]}" --authority /tmp/forged
assert_nonzero 'G11_EXPLICIT_TARGET: forbidden authority argument blocks'
assert_local_only 'G11_EXPLICIT_TARGET: forbidden authority argument'
run_readiness forbidden "${args[@]}" --publish
assert_nonzero 'G11_EXPLICIT_TARGET: publication argument blocks'
assert_local_only 'G11_EXPLICIT_TARGET: publication argument'

# Packet fields are line-oriented. Newlines must be rejected before output so
# no caller-controlled field can forge another packet record.
for newline_field in repo remote base head commit tree; do
  newline_args=()
  index=0
  while [ "$index" -lt "${#args[@]}" ]; do
    flag="${args[$index]}"; value="${args[$((index + 1))]}"
    [ "$flag" != "--$newline_field" ] || value="${value}"$'\n'forged=value
    newline_args+=("$flag" "$value")
    index=$((index + 2))
  done
  run_readiness "newline-$newline_field" "${newline_args[@]}"
  assert_nonzero "G11_PACKET_FIELDS: newline in --$newline_field blocks"
  assert_local_only "G11_PACKET_FIELDS: newline in --$newline_field"
done
finish_tests
