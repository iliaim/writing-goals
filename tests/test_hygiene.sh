#!/usr/bin/env bash
# G02 contract: retire legacy .goals policy without preserving its run history
# or leaving a live compatibility surface.
set -u
. "$(dirname "$0")/testlib.sh"

fixture_dir="$REPO_DIR/tests/fixtures/legacy-goals"
durable_rules="$fixture_dir/durable-rules.tsv"
history_patterns="$fixture_dir/history-patterns.txt"
compat_patterns="$fixture_dir/legacy-compat-patterns.txt"
legacy_method_patterns="$fixture_dir/legacy-method-patterns.txt"

g02_durable_files() {
  local relative
  for relative in \
    LICENSE shared/method.md shared/autonomy.md shared/chaining.md shared/modes.md \
    README.md CONTRIBUTING.md SECURITY.md SUPPORT.md CODE_OF_CONDUCT.md \
    docs/quickstart.md docs/examples.md; do
    printf '%s\n' "$REPO_DIR/$relative"
  done
}

fail_fast() {
  fail "$1"
  finish_tests
  exit 1
}

# Keep this first: the protected red receipt is specifically about tracked
# legacy policy, not an unrelated baseline or an allowlisted fixture.
tracked_goals="$(git -C "$REPO_DIR" ls-files -- .goals 2>/dev/null || true)"
if [ -n "$tracked_goals" ]; then
  TEST_COUNT=$((TEST_COUNT + 1))
  fail_fast 'G02_TRACKED_GOALS_REMAIN: tracked legacy .goals policy must be deleted'
fi

TEST_COUNT=$((TEST_COUNT + 1))
if [ ! -e "$REPO_DIR/.goals" ] && [ ! -L "$REPO_DIR/.goals" ]; then
  pass 'G02_LEGACY_MIGRATION_COMPLETE: legacy .goals directory is absent'
else
  fail 'G02_LEGACY_MIGRATION_COMPLETE: legacy .goals directory remains in the worktree'
fi

assert_file_contains "$REPO_DIR/.gitignore" '^/\.goals/$' \
  'G02_LEGACY_MIGRATION_COMPLETE: retired .goals path is ignored'

# Every durable legacy rule has one canonical home.  The fixture is deliberately
# small and maps each source-inventory item to its destination rather than
# treating historical prose as policy.
while IFS=$'\t' read -r rule_id relative_path pattern; do
  case "$rule_id" in
    ''|'#'*) continue ;;
  esac
  target="$REPO_DIR/$relative_path"
  TEST_COUNT=$((TEST_COUNT + 1))
  if [ ! -f "$target" ]; then
    fail "$rule_id: canonical destination is missing ($relative_path)"
    continue
  fi
  matches="$(grep -Eic -- "$pattern" "$target" 2>/dev/null || true)"
  total_matches="$(g02_durable_files | xargs grep -Eih -- "$pattern" 2>/dev/null | wc -l | tr -d '[:space:]')"
  if [ "$matches" -eq 1 ] && [ "$total_matches" -eq 1 ]; then
    pass "$rule_id: durable rule appears exactly once in $relative_path"
  else
    fail "$rule_id: expected one canonical occurrence in $relative_path and one total occurrence, found canonical=$matches total=$total_matches"
  fi
done < "$durable_rules"

g02_live_files() {
  local relative
  for relative in \
    shared/method.md shared/autonomy.md shared/chaining.md shared/modes.md \
    README.md CONTRIBUTING.md SECURITY.md SUPPORT.md CODE_OF_CONDUCT.md \
    docs/quickstart.md docs/examples.md; do
    printf '%s\n' "$REPO_DIR/$relative"
  done
  for relative in assets claude codex; do
    find "$REPO_DIR/$relative" -type f -print 2>/dev/null
  done
  find "$REPO_DIR" -maxdepth 1 -type f -perm -111 -print 2>/dev/null
}

live_files="$(g02_live_files)"

# Completed-run status, assumptions, and narration are evidence, not durable
# product rules.  Do not scan CHANGELOG/ADR/private-plan history here.
while IFS= read -r pattern; do
  case "$pattern" in ''|'#'*) continue ;; esac
  TEST_COUNT=$((TEST_COUNT + 1))
  if printf '%s\n' "$live_files" | xargs grep -EIn -- "$pattern" >/dev/null 2>&1; then
    fail "G02_HISTORY_NOT_MIGRATED: execution-history pattern remains live ($pattern)"
  else
    pass "G02_HISTORY_NOT_MIGRATED: execution-history pattern is absent ($pattern)"
  fi
done < "$history_patterns"

while IFS= read -r pattern; do
  case "$pattern" in ''|'#'*) continue ;; esac
  TEST_COUNT=$((TEST_COUNT + 1))
  if printf '%s\n' "$live_files" | xargs grep -EIn -- "$pattern" >/dev/null 2>&1; then
    fail "G02_LIVE_COMPAT_ZERO: retired compatibility terminology remains live ($pattern)"
  else
    pass "G02_LIVE_COMPAT_ZERO: retired compatibility terminology is absent ($pattern)"
  fi
done < "$compat_patterns"

while IFS= read -r pattern; do
  case "$pattern" in ''|'#'*) continue ;; esac
  TEST_COUNT=$((TEST_COUNT + 1))
  if grep -Ein -- "$pattern" "$REPO_DIR/shared/method.md" >/dev/null 2>&1; then
    fail "G02_LEGACY_MIGRATION_COMPLETE: legacy generic budget wording remains ($pattern)"
  else
    pass "G02_LEGACY_MIGRATION_COMPLETE: legacy generic budget wording is absent ($pattern)"
  fi
done < "$legacy_method_patterns"

finish_tests
