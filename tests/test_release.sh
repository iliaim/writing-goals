#!/usr/bin/env bash
# Protected G13 oracle: release evidence is exact, detached, local, and hermetic.
set -u
. "$(dirname "$0")/testlib.sh"

ci="$REPO_DIR/.github/workflows/ci.yml"
fixture="$REPO_DIR/tests/fixtures/conformance/release.env"
red() { printf '%s\n' "FAIL: G13_RELEASE_CONTRACT_INCOMPLETE${1:+: $1}" >&2; exit 1; }

[ -f "$ci" ] && [ -f "$fixture" ] || red 'release fixture or CI workflow missing'
. "$fixture"
grep -q -- 'shellcheck' "$ci" && grep -q -- "$required_ci_status" "$ci" || red 'authoritative CI ShellCheck status missing'
grep -q -- "$required_ci_os" "$ci" || red 'Linux CI matrix route missing'
grep -q -- 'persist-credentials: false' "$ci" || red 'credential-free checkout missing'
grep -q -- 'contents: read' "$ci" || red 'read-only CI permissions missing'

git -C "$REPO_DIR" diff --quiet --ignore-submodules -- || red 'source worktree is dirty'
[ -z "$(git -C "$REPO_DIR" status --porcelain)" ] || red 'source status is dirty'
commit="$(git -C "$REPO_DIR" rev-parse HEAD)" || red 'cannot resolve candidate commit'
tree="$(git -C "$REPO_DIR" rev-parse "$commit^{tree}")" || red 'cannot resolve candidate tree'
checkout="$TEST_TMP/detached-candidate"
home="$TEST_TMP/home"; codex_home="$TEST_TMP/codex-home"
mkdir -p "$home" "$codex_home"
run_command git clone --quiet --no-local "$REPO_DIR" "$checkout"
assert_success 'G13_CLEAN_EXACT_CHECKOUT: local exact candidate clone succeeds'
run_command git -C "$checkout" checkout --quiet --detach "$commit"
assert_success 'G13_CLEAN_EXACT_CHECKOUT: checkout is detached at the exact candidate commit'
[ "$(git -C "$checkout" rev-parse HEAD)" = "$commit" ] || red 'detached commit drift'
[ "$(git -C "$checkout" rev-parse HEAD^{tree}")" = "$tree" ] || red 'detached tree drift'
[ -z "$(git -C "$checkout" status --porcelain)" ] || red 'detached checkout is dirty'
pass 'G13_CLEAN_EXACT_CHECKOUT: commit/tree and worktree are exact and clean'

run_command env HOME="$home" CODEX_HOME="$codex_home" bash "$checkout/tests/test_conformance.sh"
assert_success 'G13_RELEASE_MATRIX_COMPLETE: detached clean checkout passes conformance with temporary homes'
assert_not_contains "$(cat "$RUN_OUT" "$RUN_ERR")" "$REPO_DIR|$HOME" 'G13_RELEASE_MATRIX_COMPLETE: detached verification does not expose ambient source/home paths'

if command -v shellcheck >/dev/null 2>&1; then
  run_command bash -c 'set --; for f in sync.sh install.sh assets/*.sh scripts/*.sh tests/*.sh; do test -f "$f" && set -- "$@" "$f"; done; shellcheck --exclude=SC2294 "$@" && printf "%s\\n" SHELLCHECK_STATUS=PASSED' bash
  assert_success 'G13_LINUX_SHELLCHECK_PASSED: available ShellCheck passes the release script surface'
  assert_file_contains "$RUN_OUT" '^SHELLCHECK_STATUS=PASSED$' 'G13_LINUX_SHELLCHECK_PASSED: local authoritative tool status is explicit'
else
  printf '%s\n' 'SHELLCHECK_STATUS=NOT_AVAILABLE'
  pass 'G13_LINUX_SHELLCHECK_PASSED: local unavailable status is non-authoritative; CI must pass'
fi
finish_tests
