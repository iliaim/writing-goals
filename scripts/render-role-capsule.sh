#!/usr/bin/env bash
# Render an ephemeral role view; it neither approves nor dispatches work.
set -u

usage() { printf '%s\n' 'usage: render-role-capsule.sh --plan PLAN --manifest MANIFEST --role ROLE --output FILE' >&2; exit 2; }
fail() { printf 'render-role-capsule: %s\n' "$1" >&2; exit 1; }

plan= manifest= role= output=
while [ "$#" -gt 0 ]; do
  case "$1" in
    --plan|--manifest|--role|--output)
      [ "$#" -ge 2 ] || usage
      case "$1" in --plan) plan=$2 ;; --manifest) manifest=$2 ;; --role) role=$2 ;; --output) output=$2 ;; esac
      shift 2 ;;
    *) usage ;;
  esac
done
[ -n "$plan" ] && [ -n "$manifest" ] && [ -n "$role" ] && [ -n "$output" ] || usage
[ -f "$plan" ] && [ -f "$manifest" ] || fail 'canonical inputs must be files'
case "$role" in writing-goals-planner|writing-goals-challenger|writing-goals-oracle-author|writing-goals-maker|writing-goals-verifier|writing-goals-reviewer|writing-goals-publisher) ;; *) fail 'unknown role' ;; esac
digest=$(sed -nE 's/.*"plan_digest"[[:space:]]*:[[:space:]]*"sha256:([0-9a-f]{64})".*/\1/p' "$manifest" | head -n 1)
[ -n "$digest" ] || fail 'manifest lacks a SHA-256 digest'
if command -v shasum >/dev/null 2>&1; then actual_digest=$(shasum -a 256 "$plan" | awk '{print $1}'); else actual_digest=$(sha256sum "$plan" | awk '{print $1}'); fi
[ "$digest" = "$actual_digest" ] || fail 'manifest digest does not bind the exact plan'
tmp=$(mktemp "${TMPDIR:-/tmp}/writing-goals-capsule.XXXXXX") || exit 1
trap 'rm -f "$tmp"' EXIT HUP INT TERM
printf '{\n  "schema": "writing-goals-role-capsule/v1",\n  "plan_manifest_digest": "sha256:%s",\n  "role": "%s"\n}\n' "$digest" "$role" >"$tmp"
mv "$tmp" "$output"
trap - EXIT HUP INT TERM
