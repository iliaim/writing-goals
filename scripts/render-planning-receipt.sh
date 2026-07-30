#!/usr/bin/env bash
# Render a closed, ephemeral receipt from explicit inputs; it does not manage work.
set -u

usage() { printf '%s\n' 'usage: render-planning-receipt.sh --plan PLAN --manifest MANIFEST --role ROLE --status STATUS --findings-ref REF --evidence-ref REF --follow-up-ref REF --output FILE' >&2; exit 2; }
fail() { printf 'render-planning-receipt: %s\n' "$1" >&2; exit 1; }

validate_fixture= plan= manifest= role= status= findings= evidence= follow_up= output=
while [ "$#" -gt 0 ]; do
  case "$1" in
    --validate-fixture) [ "$#" -ge 2 ] || usage; validate_fixture=$2; shift 2 ;;
    --plan|--manifest|--role|--status|--findings-ref|--evidence-ref|--follow-up-ref|--output)
      [ "$#" -ge 2 ] || usage
      case "$1" in --plan) plan=$2 ;; --manifest) manifest=$2 ;; --role) role=$2 ;; --status) status=$2 ;; --findings-ref) findings=$2 ;; --evidence-ref) evidence=$2 ;; --follow-up-ref) follow_up=$2 ;; --output) output=$2 ;; esac
      shift 2 ;;
    *) usage ;;
  esac
done
if [ -n "$validate_fixture" ]; then
  [ -d "$validate_fixture" ] || fail 'fixture must be a directory'
  find "$validate_fixture" -type f -print | grep -Eq '.' || fail 'fixture is empty'
  if find "$validate_fixture" -type f -exec grep -Eqi '(mutable-plan|task_class:|execution_recipe:|semantic_approval|selected_task|dispatch)' {} +; then
    fail 'fixture contains prohibited persistent or generated planning material'
  fi
  fail 'fixture does not prove the prohibited material was rejected'
fi
[ -n "$plan" ] && [ -n "$manifest" ] && [ -n "$role" ] && [ -n "$status" ] && [ -n "$findings" ] && [ -n "$evidence" ] && [ -n "$follow_up" ] && [ -n "$output" ] || usage
[ -f "$plan" ] && [ -f "$manifest" ] || fail 'canonical inputs must be files'
case "$role" in writing-goals-planner|writing-goals-challenger|writing-goals-oracle-author|writing-goals-maker|writing-goals-verifier|writing-goals-reviewer|writing-goals-publisher) ;; *) fail 'unknown role' ;; esac
case "$status" in needs_human|pass|fail) ;; *) fail 'unknown receipt status' ;; esac
safe_ref() { case "$1" in ''|*[!A-Za-z0-9._/@:+=-]*) fail 'references must be single-line safe tokens' ;; esac; }
safe_ref "$findings"; safe_ref "$evidence"; safe_ref "$follow_up"
digest=$(sed -nE 's/.*"plan_digest"[[:space:]]*:[[:space:]]*"sha256:([0-9a-f]{64})".*/\1/p' "$manifest" | head -n 1)
[ -n "$digest" ] || fail 'manifest lacks a SHA-256 digest'
if command -v shasum >/dev/null 2>&1; then actual_digest=$(shasum -a 256 "$plan" | awk '{print $1}'); else actual_digest=$(sha256sum "$plan" | awk '{print $1}'); fi
[ "$digest" = "$actual_digest" ] || fail 'manifest digest does not bind the exact plan'
tmp=$(mktemp "${TMPDIR:-/tmp}/writing-goals-receipt.XXXXXX") || exit 1
trap 'rm -f "$tmp"' EXIT HUP INT TERM
printf '{\n  "schema": "writing-goals-planning-receipt/v1",\n  "plan_manifest_digest": "sha256:%s",\n  "role": "%s",\n  "status": "%s",\n  "findings_ref": "%s",\n  "evidence_ref": "%s",\n  "follow_up_ref": "%s"\n}\n' "$digest" "$role" "$status" "$findings" "$evidence" "$follow_up" >"$tmp"
mv "$tmp" "$output"
trap - EXIT HUP INT TERM
