#!/usr/bin/env bash
# Structural plan validation only: this does not judge semantic quality or prose.
set -u

usage() { printf '%s\n' 'usage: plan-lint.sh --plan PLAN --manifest MANIFEST --index INDEX' >&2; exit 2; }
fail() { printf 'plan-lint: %s\n' "$1" >&2; exit 1; }

plan= manifest= index=
while [ "$#" -gt 0 ]; do
  case "$1" in
    --plan|--manifest|--index)
      [ "$#" -ge 2 ] || usage
      case "$1" in --plan) plan=$2 ;; --manifest) manifest=$2 ;; --index) index=$2 ;; esac
      shift 2 ;;
    *) usage ;;
  esac
done
[ -n "$plan" ] && [ -n "$manifest" ] && [ -n "$index" ] || usage
[ -f "$plan" ] && [ -f "$manifest" ] && [ -f "$index" ] || fail 'canonical inputs must be files'

contains() { grep -Eq -- "$1" "$plan"; }
contains 'TODO|TBD|<[^>]+>' && fail 'placeholders are not permitted'
grep -Eq '"schema"[[:space:]]*:[[:space:]]*"writing-goals-plan-manifest/v1"' "$manifest" || fail 'invalid manifest schema'
manifest_digest=$(sed -nE 's/.*"plan_digest"[[:space:]]*:[[:space:]]*"sha256:([0-9a-f]{64})".*/\1/p' "$manifest" | head -n 1)
[ -n "$manifest_digest" ] || fail 'missing manifest digest'
if command -v shasum >/dev/null 2>&1; then
  plan_digest=$(shasum -a 256 "$plan" | awk '{print $1}')
else
  plan_digest=$(sha256sum "$plan" | awk '{print $1}')
fi
[ "$manifest_digest" = "$plan_digest" ] || fail 'manifest digest does not bind the exact plan'

contains '^id:[[:space:]]*[^[:space:]]+' || fail 'missing id'
contains '^task_class:[[:space:]]*(behavioral_code|docs_config|refactor|research_design)[[:space:]]*$' || fail 'unsupported task class'
contains '^requirements:[[:space:]]*\[[^]]+\]' || fail 'missing requirement routes'
contains '^objective_acceptance:[[:space:]]*\[[^]]+\]' || fail 'missing acceptance routes'
contains '^execution_recipe:' || fail 'missing execution recipe'
for field in inputs outputs maker_paths oracle_paths evidence handoff fan_in_owner risks stop_conditions; do
  contains "^[[:space:]]*$field:" || fail "missing recipe field: $field"
done
contains 'argv:[[:space:]]*\[[^]]+\]' || fail 'evidence command must bind exact argv'
contains 'expected_exit:[[:space:]]*[0-9]+' || fail 'evidence command must bind expected exit'

maker_paths=$(sed -nE 's/.*maker_paths:[[:space:]]*\[([^]]*)\].*/\1/p' "$plan" | head -n 1)
oracle_paths=$(sed -nE 's/.*oracle_paths:[[:space:]]*\[([^]]*)\].*/\1/p' "$plan" | head -n 1)
[ -n "$maker_paths" ] && [ -n "$oracle_paths" ] || fail 'write paths must be explicit lists'
for path in $(printf '%s' "$maker_paths" | tr ',' ' '); do
  case " $oracle_paths " in *" $path "*) fail 'maker and oracle paths collide' ;; esac
done

contains '^dag:' || fail 'missing dependency dag'
dag_records=$(awk '
  function trim(value) { sub(/^[[:space:]]+/, "", value); sub(/[[:space:]]+$/, "", value); return value }
  function emit(record, node, deps) {
    node = record; sub(/^.*id:[[:space:]]*/, "", node); sub(/[[:space:],}].*$/, "", node)
    deps = record; sub(/^.*depends_on:[[:space:]]*\[/, "", deps); sub(/\].*$/, "", deps)
    print trim(node) "\t" trim(deps)
  }
  {
    line = $0
    while (match(line, /\{id:[^}]*depends_on:[^}]*\}/)) {
      emit(substr(line, RSTART, RLENGTH))
      line = substr(line, RSTART + RLENGTH)
    }
    if ($0 ~ /^[[:space:]]*-[[:space:]]*id:[[:space:]]*/) {
      if (pending_seen) exit 2
      pending = $0; sub(/^[[:space:]]*-[[:space:]]*id:[[:space:]]*/, "", pending); pending = trim(pending)
      if (pending !~ /^[A-Za-z0-9_-]+$/) exit 2
      pending_seen = 1
      next
    }
    if (pending_seen && $0 ~ /^[[:space:]]*depends_on:[[:space:]]*\[/) {
      deps = $0; sub(/^[[:space:]]*depends_on:[[:space:]]*\[/, "", deps); sub(/\].*$/, "", deps)
      print pending "\t" trim(deps)
      pending = ""
      pending_seen = 0
    }
  }
  END { if (pending_seen) exit 2 }
' "$plan")
dag_parse_status=$?
[ "$dag_parse_status" -eq 0 ] || fail 'expanded dag node lacks depends_on'
node_ids=$(printf '%s\n' "$dag_records" | sed -nE 's/^[[:space:]]*([A-Za-z0-9_-]+)[[:space:]]*.*/\1/p')
[ -n "$node_ids" ] || fail 'dag has no nodes'
dupes=$(printf '%s\n' "$node_ids" | sort | uniq -d)
[ -z "$dupes" ] || fail 'dag node ids must be unique'
while IFS=$'\t' read -r node dependencies; do
  [ -n "$node" ] || continue
  for dependency in $(printf '%s' "$dependencies" | tr ',' ' '); do
    printf '%s\n' "$node_ids" | grep -Fx -- "$dependency" >/dev/null || fail "dag dependency is unknown: $dependency"
  done
done <<EOF
$dag_records
EOF
# Remove ready nodes until nothing remains. If no node can be removed, the DAG has a cycle.
remaining="$node_ids"
while [ -n "$remaining" ]; do
  progressed=false
  next_remaining=
  while IFS= read -r node; do
    [ -n "$node" ] || continue
    dependencies=$(printf '%s\n' "$dag_records" | awk -F '\t' -v wanted="$node" '$1 == wanted { print $2; exit }')
    blocked=false
    for dependency in $(printf '%s' "$dependencies" | tr ',' ' '); do
      if printf '%s\n' "$remaining" | grep -Fx -- "$dependency" >/dev/null; then blocked=true; break; fi
    done
    if [ "$blocked" = true ]; then
      next_remaining="${next_remaining}${next_remaining:+\n}$node"
    else
      progressed=true
    fi
  done <<EOF
$remaining
EOF
  [ "$progressed" = true ] || fail 'dag is cyclic'
  remaining=$(printf '%b' "$next_remaining")
done
contains '^workflow:[[:space:]]*\[discover,[[:space:]]*author,[[:space:]]*lint,[[:space:]]*challenge,[[:space:]]*freeze\][[:space:]]*$' || fail 'workflow must lint before challenge and freeze'

if grep -Eqi '^[[:space:]]*(task_class|execution_recipe|stop_rules)[[:space:]]*:' "$index"; then
  fail 'navigation index must not duplicate plan policy'
fi

printf '%s\n' 'plan-lint: structural validation passed'
