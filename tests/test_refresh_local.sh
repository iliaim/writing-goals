#!/usr/bin/env bash
# G09 protected oracle: local refresh status is exact and read-only.
set -u
. "$(dirname "$0")/testlib.sh"

refresh="$REPO_DIR/scripts/refresh-local.sh"
status_fixture="$TEST_TMP/status-repo"
status_home="$TEST_TMP/status-home"
status_codex="$TEST_TMP/status-codex"
mkdir -p "$status_fixture/scripts" "$status_home" "$status_codex"
cp "$refresh" "$status_fixture/scripts/refresh-local.sh"
status_fixture_physical="$(cd "$status_fixture" && pwd -P)"

snapshot_tree() {
  local root="$1" path metadata
  (
    cd "$root" || exit 1
    find . -print | LC_ALL=C sort | while IFS= read -r path; do
      if metadata="$(stat -f '%HT|%Lp|%m' "$path" 2>/dev/null)"; then
        :
      else
        metadata="$(stat -c '%F|%a|%Y' -- "$path")"
      fi
      printf '%s|%s' "$path" "$metadata"
      if [ -L "$path" ]; then
        printf '|target=%s' "$(readlink "$path")"
      elif [ -f "$path" ]; then
        printf '|sha256=%s' "$(shasum -a 256 "$path" | awk '{print $1}')"
      fi
      printf '\n'
    done
  )
}

snapshot_status_surface() {
  printf '%s\n' '== checkout =='
  snapshot_tree "$status_fixture"
  printf '%s\n' '== HOME =='
  snapshot_tree "$status_home"
  printf '%s\n' '== CODEX_HOME =='
  snapshot_tree "$status_codex"
}

assert_exact_file() {
  local file="$1" expected="$2" label="$3" expected_file
  expected_file="$TEST_TMP/expected-$TEST_COUNT"
  printf '%s' "$expected" >"$expected_file"
  TEST_COUNT=$((TEST_COUNT + 1))
  if cmp -s "$expected_file" "$file"; then
    pass "$label"
  else
    fail "$label (expected and actual byte dumps follow)"
    od -An -tx1 "$expected_file" >&2
    od -An -tx1 "$file" >&2
  fi
}

assert_status_report() {
  local claude="$1" codex="$2" archive="$3" label="$4"
  assert_exact_file "$RUN_OUT" "Claude: $claude
Codex: $codex
Latest archive: $archive
" "$label"
  assert_empty_file "$RUN_ERR" "$label emits no stderr"
}

run_read_only_status() {
  local label="$1"
  shift
  local before after
  before="$(snapshot_status_surface)"
  run_command "$@"
  after="$(snapshot_status_surface)"
  TEST_COUNT=$((TEST_COUNT + 1))
  if [ "$before" = "$after" ]; then
    pass "$label leaves checkout, HOME, and CODEX_HOME unchanged"
  else
    fail "$label mutated the status surface"
  fi
}

TEST_COUNT=$((TEST_COUNT + 1))
if [ -f "$refresh" ] && [ -x "$refresh" ]; then
  pass 'G09_SAFE_REFRESH: refresh command is installed as an executable script'
else
  fail 'G09_SAFE_REFRESH: scripts/refresh-local.sh is missing or not executable'
fi

# Freeze the legacy non-installing parser surface exactly.
legacy_usage="usage: $refresh --install [claude|codex|all]
"
run_command bash "$refresh" --help
assert_status 0 'G09_SAFE_REFRESH: --help retains exit 0'
assert_empty_file "$RUN_OUT" 'G09_SAFE_REFRESH: --help retains empty stdout'
assert_exact_file "$RUN_ERR" "$legacy_usage" 'G09_SAFE_REFRESH: --help retains exact usage stderr'

run_command bash "$refresh" --help ignored
assert_status 0 'G09_SAFE_REFRESH: --help retains its legacy extra-argument parsing'
assert_empty_file "$RUN_OUT" 'G09_SAFE_REFRESH: --help with an extra argument retains empty stdout'
assert_exact_file "$RUN_ERR" "$legacy_usage" 'G09_SAFE_REFRESH: --help with an extra argument retains exact usage stderr'

run_command bash "$refresh"
assert_status 2 'G09_SAFE_REFRESH: default invocation retains exit 2'
assert_empty_file "$RUN_OUT" 'G09_SAFE_REFRESH: default invocation retains empty stdout'
assert_exact_file "$RUN_ERR" "ERROR: explicit --install is required; no installed copies were changed.
$legacy_usage" 'G09_SAFE_REFRESH: default invocation retains exact refusal stderr'

run_command bash "$refresh" --install invalid
assert_status 2 'G09_SAFE_REFRESH: invalid install selection retains exit 2 without installing'
assert_empty_file "$RUN_OUT" 'G09_SAFE_REFRESH: invalid install selection retains empty stdout'
assert_exact_file "$RUN_ERR" "$legacy_usage" 'G09_SAFE_REFRESH: invalid install selection retains exact usage stderr'

run_command bash "$refresh" --install claude extra
assert_status 2 'G09_SAFE_REFRESH: extra install argument retains exit 2 before installing'
assert_empty_file "$RUN_OUT" 'G09_SAFE_REFRESH: extra install argument retains empty stdout'
assert_exact_file "$RUN_ERR" "$legacy_usage" 'G09_SAFE_REFRESH: extra install argument retains exact usage stderr'

# No archive root and no installed targets.
run_read_only_status 'G09_STATUS_MISSING_ABSENT' \
  env HOME="$status_home" CODEX_HOME="$status_codex" \
  bash "$status_fixture/scripts/refresh-local.sh" --status
assert_status 0 'G09_STATUS_MISSING_ABSENT: status exits 0'
assert_status_report missing missing none \
  'G09_STATUS_MISSING_ABSENT: absent archive and targets produce exactly three ordered lines'

# An existing but empty archive root still reports none.
mkdir -p "$status_fixture/.archive/writing-goals"
run_read_only_status 'G09_STATUS_EMPTY_ARCHIVE' \
  env HOME="$status_home" CODEX_HOME="$status_codex" \
  bash "$status_fixture/scripts/refresh-local.sh" --status
assert_status 0 'G09_STATUS_EMPTY_ARCHIVE: status exits 0'
assert_status_report missing missing none \
  'G09_STATUS_EMPTY_ARCHIVE: empty archive root reports none'

# A hidden immediate child is eligible. A lexically later file is not.
mkdir -p "$status_fixture/.archive/writing-goals/.hidden-archive"
printf '%s\n' 'not a directory' >"$status_fixture/.archive/writing-goals/zzzz-file"
run_read_only_status 'G09_STATUS_HIDDEN_ARCHIVE' \
  env HOME="$status_home" CODEX_HOME="$status_codex" \
  bash "$status_fixture/scripts/refresh-local.sh" --status
assert_status 0 'G09_STATUS_HIDDEN_ARCHIVE: status exits 0'
assert_status_report missing missing \
  "$status_fixture_physical/.archive/writing-goals/.hidden-archive" \
  'G09_STATUS_HIDDEN_ARCHIVE: hidden child is included and non-directory is excluded'

# Lexical ordering is by immediate directory name, not mtime or nested descendants.
mkdir -p "$status_fixture/.archive/writing-goals/20260729" \
  "$status_fixture/.archive/writing-goals/20260730/nested-zzzz"
touch -t 202607300303 "$status_fixture/.archive/writing-goals/20260729"
touch -t 202607290101 "$status_fixture/.archive/writing-goals/20260730"
mkdir -p "$status_home/.claude/skills/writing-goals" "$status_codex/skills"
printf '%s\n' 'Claude copy' >"$status_home/.claude/skills/writing-goals/marker"
ln -s "$status_fixture/absent-codex-target" "$status_codex/skills/writing-goals"
run_read_only_status 'G09_STATUS_OVERRIDE_AND_LEXICAL' \
  env HOME="$status_home" CODEX_HOME="$status_codex" \
  bash "$status_fixture/scripts/refresh-local.sh" --status
assert_status 0 'G09_STATUS_OVERRIDE_AND_LEXICAL: status exits 0'
assert_status_report copy symlink \
  "$status_fixture_physical/.archive/writing-goals/20260730" \
  'G09_STATUS_OVERRIDE_AND_LEXICAL: copy, broken symlink, override, and lexical immediate archive are exact'

TEST_COUNT=$((TEST_COUNT + 1))
case "$status_fixture_physical/.archive/writing-goals/20260730" in
  /*) pass 'G09_STATUS_OVERRIDE_AND_LEXICAL: reported archive expectation is absolute' ;;
  *) fail 'G09_STATUS_OVERRIDE_AND_LEXICAL: reported archive expectation is not absolute' ;;
esac

# Empty and unset CODEX_HOME both fall back to HOME/.codex.
rm -rf "$status_home/.claude/skills/writing-goals"
ln -s "$status_fixture/absent-claude-target" "$status_home/.claude/skills/writing-goals"
mkdir -p "$status_home/.codex/skills/writing-goals"
printf '%s\n' 'Codex copy' >"$status_home/.codex/skills/writing-goals/marker"
run_read_only_status 'G09_STATUS_EMPTY_CODEX_HOME_FALLBACK' \
  env HOME="$status_home" CODEX_HOME= \
  bash "$status_fixture/scripts/refresh-local.sh" --status
assert_status 0 'G09_STATUS_EMPTY_CODEX_HOME_FALLBACK: status exits 0'
assert_status_report symlink copy \
  "$status_fixture_physical/.archive/writing-goals/20260730" \
  'G09_STATUS_EMPTY_CODEX_HOME_FALLBACK: broken Claude symlink and empty CODEX_HOME fallback are exact'

run_read_only_status 'G09_STATUS_UNSET_CODEX_HOME_FALLBACK' \
  env -u CODEX_HOME HOME="$status_home" \
  bash "$status_fixture/scripts/refresh-local.sh" --status
assert_status 0 'G09_STATUS_UNSET_CODEX_HOME_FALLBACK: status exits 0'
assert_status_report symlink copy \
  "$status_fixture_physical/.archive/writing-goals/20260730" \
  'G09_STATUS_UNSET_CODEX_HOME_FALLBACK: unset CODEX_HOME fallback is exact'

# Rejected status arguments produce no report and remain read-only.
run_read_only_status 'G09_STATUS_EXTRA_ARGUMENT' \
  env HOME="$status_home" CODEX_HOME="$status_codex" \
  bash "$status_fixture/scripts/refresh-local.sh" --status extra
assert_status 2 'G09_STATUS_EXTRA_ARGUMENT: extra status argument exits 2'
assert_empty_file "$RUN_OUT" 'G09_STATUS_EXTRA_ARGUMENT: rejected status emits no stdout'
assert_exact_file "$RUN_ERR" "usage: $status_fixture/scripts/refresh-local.sh --install [claude|codex|all]
" 'G09_STATUS_EXTRA_ARGUMENT: rejected status emits exact unchanged usage stderr'

# The benchmark-HOME exception is static-only: never inspect a real user install.
assert_file_contains "$refresh" 'case "\$HOME" in|if \[\[? "\$HOME" =+ "/Users/user" \]\]?' \
  'G09_STATUS_BENCHMARK_HOME: implementation explicitly branches on HOME'
assert_file_contains "$refresh" '/Users/user/\.claude/skills/writing-goals' \
  'G09_STATUS_BENCHMARK_HOME: benchmark HOME maps to the exact fixed Claude target'
assert_file_contains "$refresh" '\$HOME/\.claude/skills/writing-goals' \
  'G09_STATUS_BENCHMARK_HOME: other HOME values map to the HOME-relative Claude target'

assert_file_contains "$refresh" 'bash tests/run\.sh' 'G09_SAFE_REFRESH: refresh verifies the source before installation'
assert_file_contains "$refresh" 'scripts/build-bundles\.sh' 'G09_SAFE_REFRESH: refresh installs a self-contained bundle'
assert_file_contains "$refresh" '\.archive/writing-goals' 'G09_SAFE_REFRESH: refresh preserves replaced targets in the repository archive'
assert_file_contains "$REPO_DIR/.gitignore" '^/dist/$' 'G09_SAFE_REFRESH: generated refresh bundles do not leave the source checkout dirty'
assert_file_contains "$REPO_DIR/.gitignore" '^/\.archive/$' 'G09_SAFE_REFRESH: local backup archives do not dirty the source checkout'

finish_tests
