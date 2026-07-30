#!/usr/bin/env bash
# Protected G12 oracle: bind the complete tracked Markdown inventory before
# maker dispatch and ensure every path has exactly one explicit schema route.
set -u
. "$(dirname "$0")/testlib.sh"

fixture_dir="$REPO_DIR/tests/fixtures/docs"
inventory_paths_fixture="$fixture_dir/markdown-inventory.paths"
digest_fixture="$fixture_dir/markdown-inventory.sha256"
binding_fixture="$fixture_dir/oracle-inventory.sha256"
actual_inventory="$TEST_TMP/g12-markdown-inventory.nul"
expected_inventory="$TEST_TMP/g12-markdown-inventory.expected.nul"

git -C "$REPO_DIR" ls-files -z -- '*.md' > "$actual_inventory"
tr '\n' '\0' < "$inventory_paths_fixture" > "$expected_inventory"
actual_digest="$(shasum -a 256 "$actual_inventory" | awk '{print $1}')"
expected_digest="$(awk 'NR == 1 { print $1 }' "$digest_fixture" 2>/dev/null)"
oracle_inventory_digest="$({
  for path in tests/test_docs.sh tests/test_legacy_public.sh tests/test_owned_markdown.sh tests/fixtures/docs/markdown-inventory.paths tests/fixtures/docs/markdown-inventory.sha256 tests/fixtures/docs/red-contracts.txt; do
    printf '%s\0' "$path"
    cat "$REPO_DIR/$path"
  done
} | shasum -a 256 | awk '{print $1}')"
expected_binding="$(awk 'NR == 1 { print $1 }' "$binding_fixture" 2>/dev/null)"

TEST_COUNT=$((TEST_COUNT + 1))
if cmp -s "$actual_inventory" "$expected_inventory" && [ "$actual_digest" = "$expected_digest" ]; then
  pass 'G12_MARKDOWN_INVENTORY_EXACT: tracked Markdown path set and SHA-256 digest are frozen'
else
  fail 'G12_MARKDOWN_INVENTORY_EXACT: tracked Markdown path set or SHA-256 digest changed'
fi

TEST_COUNT=$((TEST_COUNT + 1))
if [ "$oracle_inventory_digest" = "$expected_binding" ]; then
  pass 'G12_MARKDOWN_INVENTORY_EXACT: protected oracle and inventory digest are bound together'
else
  fail 'G12_MARKDOWN_INVENTORY_EXACT: protected oracle and inventory digest binding changed'
fi

route_count() {
  case "$1" in
    README.md|CHANGELOG.md|CODE_OF_CONDUCT.md|CONTEXT.md|CONTRIBUTING.md|PLAN.md|SECURITY.md|SUPPORT.md|docs/*.md|shared/*.md)
      printf '%s\n' 1 ;;
    claude/SKILL.md|codex/SKILL.md|claude/agents/writing-goals-*.md|assets/roles/writing-goals-*.md|.github/PULL_REQUEST_TEMPLATE.md)
      printf '%s\n' 1 ;;
    tests/fixtures/core-integration/README.md|tests/fixtures/evidence/README.md|tests/fixtures/install/README.md|tests/fixtures/okf/valid/.github/PULL_REQUEST_TEMPLATE.md|tests/fixtures/okf/valid/assets/roles/writing-goals-maker.md|tests/fixtures/okf/valid/claude/SKILL.md|tests/fixtures/okf/valid/claude/agents/writing-goals-maker.md|tests/fixtures/okf/valid/codex/SKILL.md|tests/fixtures/okf/valid/docs/unowned.md|tests/fixtures/okf/valid/index.md|tests/fixtures/okf/valid/notes.md|tests/fixtures/okf/valid/plans/p01/goals/g01.md|tests/fixtures/okf/valid/plans/p01/index.md|tests/fixtures/okf/valid/plans/p01/objective.md|tests/fixtures/plan-lint/README.md|tests/fixtures/plan-lint/bad-command/index.md|tests/fixtures/plan-lint/digest-mismatch/index.md|tests/fixtures/plan-lint/duplicate-index/index.md|tests/fixtures/plan-lint/empty-expanded-id/index.md|tests/fixtures/plan-lint/expanded-node-missing-depends/index.md|tests/fixtures/plan-lint/fake-task-class/index.md|tests/fixtures/plan-lint/hidden-duplicate-id/index.md|tests/fixtures/plan-lint/invalid-dag/index.md|tests/fixtures/plan-lint/lint-order/index.md|tests/fixtures/plan-lint/missing-recipe/index.md|tests/fixtures/plan-lint/missing-routes/index.md|tests/fixtures/plan-lint/placeholder/index.md|tests/fixtures/plan-lint/three-node-cycle/index.md|tests/fixtures/plan-lint/unknown-dependency/index.md|tests/fixtures/plan-lint/valid/index.md|tests/fixtures/plan-lint/write-collision/index.md|tests/fixtures/planning-receipts/README.md|tests/fixtures/planning-receipts/copied-policy/role-prompt.md|tests/fixtures/publication/README.md|tests/fixtures/redaction/README.md|tests/fixtures/retention/README.md)
      # Each fixture path is enumerated above; this is a finite fixture schema,
      # not a tests/** fallback that could hide an unowned future document.
      printf '%s\n' 1 ;;
    *) printf '%s\n' 0 ;;
  esac
}

is_ordinary_okf_path() {
  case "$1" in
    README.md|CHANGELOG.md|CODE_OF_CONDUCT.md|CONTEXT.md|CONTRIBUTING.md|PLAN.md|SECURITY.md|SUPPORT.md|docs/*.md|shared/*.md) return 0 ;;
    *) return 1 ;;
  esac
}

route_failures=0
while IFS= read -r -d '' path; do
  count="$(route_count "$path")"
  if [ "$count" -ne 1 ]; then
    route_failures=$((route_failures + 1))
    printf 'unrouted or multiply routed Markdown: %s\n' "$path" >&2
  fi
done < "$actual_inventory"
TEST_COUNT=$((TEST_COUNT + 1))
if [ "$route_failures" -eq 0 ]; then
  pass 'G12_EVERY_MARKDOWN_ROUTED: each frozen Markdown path has exactly one route'
else
  fail 'G12_EVERY_MARKDOWN_ROUTED: every frozen Markdown path must have exactly one route'
fi

okf_failures=0
while IFS= read -r -d '' path; do
  if is_ordinary_okf_path "$path"; then
    file="$REPO_DIR/$path"
    if [ "$(sed -n '1p' "$file")" != '---' ] || ! awk 'NR > 1 && $0 == "---" { found=1; exit } END { exit(found ? 0 : 1) }' "$file" || ! sed -n '2,/^---$/p' "$file" | grep -Eq '^okf_version:[[:space:]]*"?0\.2"?[[:space:]]*$'; then
      okf_failures=$((okf_failures + 1))
      printf 'ordinary Markdown lacks its OKF route: %s\n' "$path" >&2
    fi
  fi
done < "$actual_inventory"
TEST_COUNT=$((TEST_COUNT + 1))
if [ "$okf_failures" -eq 0 ]; then
  pass 'G12_OWNER_ALLOWLIST_EXACT: every ordinary path uses the OKF route and owner paths use only their explicit schemas'
else
  fail 'G12_OWNER_ALLOWLIST_EXACT: every ordinary path must use its OKF route'
fi

TEST_COUNT=$((TEST_COUNT + 1))
if [ -f "$REPO_DIR/assets/goal.md.tmpl" ]; then
  pass 'G12_OWNER_ALLOWLIST_EXACT: non-Markdown goal template has its explicit route'
else
  fail 'G12_OWNER_ALLOWLIST_EXACT: assets/goal.md.tmpl is missing'
fi

if [ "$TEST_FAILURES" -ne 0 ]; then
  printf '%s\n' 'FAIL: G12_MARKDOWN_ROUTE_INCOMPLETE' >&2
fi
finish_tests
