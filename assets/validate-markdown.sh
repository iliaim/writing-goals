#!/usr/bin/env bash
# Validate the small repository-owned OKF surface. This command is deliberately
# non-mutating and dependency-free so it can run in a fresh host checkout.
set -u

fail() {
  printf 'ERROR: %s\n' "$*" >&2
  return 1
}

repo_root="$(cd "$(dirname "$0")/.." && pwd -P)"

is_host_owned() {
  case "$1" in
    claude/SKILL.md|codex/SKILL.md|.github/PULL_REQUEST_TEMPLATE.md) return 0 ;;
    claude/agents/*)
      name="${1#claude/agents/}"
      [ "$name" = "${name##*/}" ] && printf '%s\n' "$name" | grep -Eq '^writing-goals-[A-Za-z0-9._-]+\.md$'
      return
      ;;
    assets/roles/*)
      name="${1#assets/roles/}"
      [ "$name" = "${name##*/}" ] && printf '%s\n' "$name" | grep -Eq '^writing-goals-[A-Za-z0-9._-]+\.md$'
      return
      ;;
    *) return 1 ;;
  esac
}

is_reserved_index() {
  case "$1" in
    index.md|plans/p*/index.md|plans/revisions.md|plans/revisions.json|objective.md|.writing-goals/*/plans/p*/index.md|.writing-goals/*/plans/revisions.md|.writing-goals/*/plans/revisions.json|.writing-goals/*/objective.md) return 0 ;;
    *) return 1 ;;
  esac
}

frontmatter_value() {
  awk -v key="$2" '
    NR == 1 { if ($0 != "---") exit 2; next }
    $0 == "---" { exit }
    $0 ~ "^" key ":[[:space:]]*" {
      sub("^" key ":[[:space:]]*", "")
      print
      exit
    }
  ' "$1"
}

validate_workspace_path() {
  workspace="$1"
  workspace="${workspace#.writing-goals/}"
  workspace="${workspace%%/*}"
  if ! printf '%s\n' "$workspace" | grep -Eq '^[0-9]{8}-[0-9A-HJKMNP-TV-Z]{6}--[a-z0-9][a-z0-9-]{0,31}$'; then
    fail "$1: invalid objective workspace identity"
    return
  fi
  case "$1" in
    */plans/p*) printf '%s\n' "$1" | grep -Eq '/plans/p[0-9][0-9](/|$)' || { fail "$1: invalid plan revision"; return; } ;;
    */r*) printf '%s\n' "$1" | grep -Eq '/r[0-9][0-9](/|$)' || { fail "$1: invalid receipt revision"; return; } ;;
  esac
}

validate_manifest() {
  manifest="$1"
  objective="$(dirname "$manifest")/objective.md"
  plan_root="$(dirname "$manifest")"
  state="$(jq -r '.state // empty' "$manifest" 2>/dev/null)"
  expected="$(jq -r '.objective_snapshot.frozen_sha256 // empty' "$manifest" 2>/dev/null)"
  [ "$state" = frozen_approved ] || { fail "$manifest: plan revision is not frozen_approved"; return; }
  [ -f "$objective" ] || { fail "$manifest: objective snapshot is missing"; return; }
  actual="$(shasum -a 256 "$objective" | awk '{print $1}')"
  [ "$expected" = "$actual" ] || { fail "$manifest: objective snapshot digest mismatch"; return; }
  payload_expected="$(jq -r '.plan_payload.frozen_sha256 // empty' "$manifest" 2>/dev/null)"
  [ -n "$payload_expected" ] || { fail "$manifest: frozen plan payload digest is missing"; return; }
  payload_actual="$({
    { printf '%s\n' objective.md index.md; find "$plan_root/goals" -type f -name '*.md' -print 2>/dev/null | sed "s#^$plan_root/##"; } | LC_ALL=C sort | while IFS= read -r relative; do
      content="$plan_root/$relative"
      path_bytes="$(LC_ALL=C printf '%s' "$relative" | wc -c | tr -d ' ')"
      content_bytes="$(wc -c < "$content" | tr -d ' ')"
      emit_u64 "$path_bytes"
      printf '%s' "$relative"
      emit_u64 "$content_bytes"
      cat "$content"
    done
  } | shasum -a 256 | awk '{print $1}')"
  [ "$payload_expected" = "$payload_actual" ] || { fail "$manifest: plan payload digest mismatch"; return; }
  for goal in "$plan_root"/goals/*.md; do
    [ -f "$goal" ] || continue
    grep -Eq '^    manifest_ref: "\.\./revision\.json"$' "$goal" || { fail "$goal: goal must bind the local revision manifest"; return; }
    grep -Eq '^    required_state_at_activation: frozen_approved$' "$goal" || { fail "$goal: goal must require frozen approval"; return; }
    grep -Eq '^    algorithm: sha256$' "$goal" || { fail "$goal: goal must bind with sha256"; return; }
  done
}

emit_u64() {
  value="$1"
  printf '\000\000\000\000'
  for divisor in 16777216 65536 256 1; do
    byte=$((value / divisor % 256))
    printf "\\$(printf '%03o' "$byte")"
  done
}

workspace_root_for() {
  candidate="$1"
  while [ "$candidate" != / ]; do
    if printf '%s\n' "$(basename "$candidate")" | grep -Eq '^[0-9]{8}-[0-9A-HJKMNP-TV-Z]{6}--[a-z0-9][a-z0-9-]{0,31}$'; then
      printf '%s\n' "$candidate"
      return 0
    fi
    candidate="$(dirname "$candidate")"
  done
  return 1
}

validate_owned_markdown() {
  file="$1"
  relative="${file#"$validation_root"/}"

  if is_host_owned "$relative"; then
    return 0
  fi
  if [ "$(sed -n '1p' "$file")" != '---' ]; then
    fail "$relative: missing or invalid OKF version (frontmatter required)"
    return
  fi
  if ! awk 'NR > 1 && $0 == "---" { found=1; exit } END { exit(found ? 0 : 1) }' "$file"; then
    fail "$relative: unterminated OKF frontmatter"
    return
  fi
  version="$(frontmatter_value "$file" okf_version)" || { fail "$relative: malformed frontmatter"; return; }
  if ! printf '%s\n' "$version" | grep -Eq '^"?0\.2"?$'; then
    fail "$relative: missing or invalid OKF version"
    return
  fi
  if is_reserved_index "$relative"; then
    if grep -Eq '^type:' "$file"; then
      fail "$relative: reserved index must remain navigation-only"
      return
    fi
    if awk 'BEGIN { delimiters=0; bad=0 } $0 == "---" { delimiters++; next } delimiters >= 2 && ($0 ~ /(^|[^[:alpha:]])(MUST|SHALL|must|shall|lifecycle|moves from)([^[:alpha:]]|$)/) { bad=1 } END { exit(bad ? 0 : 1) }' "$file"; then
      fail "$relative: reserved index contains normative or lifecycle policy"
      return
    fi
    return 0
  fi

  case "$relative" in
    plans/p[0-9][0-9]/goals/*.md|plans/p[0-9][0-9]/objective.md)
      id="$(frontmatter_value "$file" id)"
      kind="$(frontmatter_value "$file" type)"
      if [ -z "$id" ] || ! printf '%s\n' "$id" | grep -Eq '^[A-Za-z0-9][A-Za-z0-9._-]*$'; then
        fail "$relative: missing or invalid OKF id"
        return
      fi
      if [ -z "$kind" ] || ! printf '%s\n' "$kind" | grep -Eq '^[A-Za-z0-9][A-Za-z0-9._-]*$'; then
        fail "$relative: missing or invalid OKF type"
        return
      fi
      ;;
  esac
  if grep -Eq '^writing_goals:[[:space:]]*$' "$file" && ! grep -Eq '^  profile:[[:space:]]*"?0\.1"?[[:space:]]*$' "$file"; then
    fail "$relative: writing_goals profile must be 0.1"
    return
  fi
  case "$relative" in
    plans/p[0-9][0-9]/goals/*.md)
      grep -Eq '^  kind: goal$' "$file" && grep -Eq '^  objective_binding:$' "$file" && grep -Eq '^    manifest_ref: "\.\./revision\.json"$' "$file" && grep -Eq '^    required_state_at_activation: frozen_approved$' "$file" && grep -Eq '^    algorithm: sha256$' "$file" || { fail "$relative: incomplete writing_goals goal profile"; return; }
      ;;
  esac
}

validate_path() {
  path="$1"
  if [ -L "$path" ]; then
    fail "$path: symlink input is not supported"
    return
  fi
  if [ -d "$path" ]; then
    validation_root="$(cd "$path" && pwd -P)"
    validate_workspace_path "$(basename "$validation_root")" || return
    found=0
    while IFS= read -r file; do
      found=1
      validate_owned_markdown "$file" || return
    done <<EOF
$(find "$validation_root" -type f -name '*.md' -print | LC_ALL=C sort)
EOF
    if [ -d "$validation_root/plans" ]; then
      while IFS= read -r revision_dir; do
        revision_name="$(basename "$revision_dir")"
        if ! printf '%s\n' "$revision_name" | grep -Eq '^p[0-9][0-9]$'; then
          fail "$revision_dir: invalid plan revision"
          return
        fi
        [ -f "$revision_dir/revision.json" ] || { fail "$revision_dir: revision manifest is missing"; return; }
        validate_manifest "$revision_dir/revision.json" || return
      done <<EOF
$(find "$validation_root/plans" -mindepth 1 -maxdepth 1 -type d -print | LC_ALL=C sort)
EOF
    fi
    [ "$found" -eq 1 ] || { fail "$path: no Markdown files found"; return; }
    return
  fi
  [ -f "$path" ] || { fail "$path: expected a regular file or directory"; return; }
  validation_root="$(workspace_root_for "$(cd "$(dirname "$path")" && pwd -P)")" || { fail "$path: no objective workspace root found"; return; }
  validate_workspace_path "$(basename "$validation_root")" || return
  file="$(cd "$(dirname "$path")" && pwd -P)/$(basename "$path")"
  validate_owned_markdown "$file" || return
  relative="${file#"$validation_root"/}"
  case "$relative" in
    plans/p[0-9][0-9]/goals/*.md|plans/p[0-9][0-9]/objective.md|plans/p[0-9][0-9]/index.md)
      plan_root="$validation_root/${relative%/goals/*}"
      case "$relative" in
        plans/p[0-9][0-9]/objective.md|plans/p[0-9][0-9]/index.md) plan_root="$(dirname "$validation_root/$relative")" ;;
      esac
      [ -f "$plan_root/revision.json" ] || { fail "$file: enclosing revision manifest is missing"; return; }
      validate_manifest "$plan_root/revision.json" || return
      ;;
  esac
}

[ "$#" -gt 0 ] || { printf 'usage: %s <Markdown file or directory> [...]\n' "$0" >&2; exit 2; }
status=0
for path in "$@"; do
  validate_path "$path" || status=1
done
exit "$status"
