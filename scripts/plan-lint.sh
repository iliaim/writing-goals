#!/usr/bin/env bash
# Structural validation for full protected plans. It deliberately does not
# decide whether the prose, alternatives, or approval are semantically sound; it is not semantic
# approval.
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
contains '^objective_acceptance:[[:space:]]*\[[^]]+\]' || fail 'missing top-level acceptance routes'
contains '^alternatives:' || fail 'missing alternatives record'
alternatives_check=$(awk '
  /^alternatives:[[:space:]]*\[\][[:space:]]*$/ { empty=1; next }
  /^alternatives:/ { active=1; next }
  active && /^dag:/ { active=0 }
  active && /^  - option:[[:space:]]*[^[:space:]]+/ { options++; pending=1; next }
  active && pending && /^    rejected_because:[[:space:]]*[^[:space:]]+/ { reasons++; pending=0; next }
  END {
    if (empty) { print "empty"; exit }
    if (options == 0) { print "missing-options"; exit }
    if (pending || reasons != options) { print "missing-reason"; exit }
    print "ok"
  }
' "$plan")
case "$alternatives_check" in
  ok) ;;
  empty) contains '^no_credible_alternative_reason:[[:space:]]*[^[:space:]]+' || fail 'empty alternatives need an explicit reason' ;;
  missing-reason) fail 'each alternative needs a rejection reason' ;;
  *) fail 'alternatives need at least one option or an explicit empty reason' ;;
esac
contains '^dag:' || fail 'missing dependency dag'

# Canonical full plans use expanded nodes so a node owns its task class,
# requirement/objective routes, execution recipe, and dependency declaration.
dag_records=$(awk '
  function trim(value) { sub(/^[[:space:]]+/, "", value); sub(/[[:space:]]+$/, "", value); return value }
  function required_value(value) { return value == "" ? "!" : value }
  function emit() {
    if (!active) return
    if (evidence_item && !evidence_incomplete && evidence_argv && evidence_exit) evidence_valid="yes"
    dependency_value = (deps == "" ? "-" : deps)
    dependency_seen_value = (deps_seen == "" ? "no" : deps_seen)
    evidence_valid_value = (evidence_valid == "" ? "no" : evidence_valid)
    print required_value(id) "\t" required_value(task) "\t" required_value(route) "\t" required_value(requirements) "\t" required_value(objective) "\t" required_value(recipe) "\t" required_value(inputs) "\t" required_value(outputs) "\t" required_value(maker) "\t" required_value(oracle) "\t" required_value(evidence) "\t" evidence_valid_value "\t" required_value(handoff) "\t" required_value(fanin) "\t" required_value(risks) "\t" required_value(stops) "\t" dependency_seen_value "\t" dependency_value "\t" required_value(argv) "\t" required_value(expected_exit)
  }
  /^  - id:/ {
    emit(); active=1
    id=$0; sub(/^  - id:[[:space:]]*/, "", id); id=trim(id)
    task=route=requirements=objective=recipe=inputs=outputs=maker=oracle=evidence=evidence_valid=handoff=fanin=risks=stops=deps_seen=deps=argv=expected_exit=evidence_item=evidence_argv=evidence_exit=evidence_incomplete=""
    next
  }
  active && /^    task_class:/ { task=$0; sub(/^    task_class:[[:space:]]*/, "", task); task=trim(task); next }
  active && /^    evidence_route:/ { route=$0; sub(/^    evidence_route:[[:space:]]*/, "", route); route=trim(route); next }
  active && /^    requirements:/ { requirements=$0; sub(/^    requirements:[[:space:]]*/, "", requirements); requirements=trim(requirements); next }
  active && /^    objective_acceptance:/ { objective=$0; sub(/^    objective_acceptance:[[:space:]]*/, "", objective); objective=trim(objective); next }
  active && /^    execution_recipe:/ { recipe="yes"; next }
  active && /^      inputs:/ { evidence_section=""; inputs="yes"; next }
  active && /^      outputs:/ { evidence_section=""; outputs="yes"; next }
  active && /^      maker_paths:/ { evidence_section=""; maker=$0; sub(/^      maker_paths:[[:space:]]*/, "", maker); maker=trim(maker); next }
  active && /^      oracle_paths:/ { evidence_section=""; oracle=$0; sub(/^      oracle_paths:[[:space:]]*/, "", oracle); oracle=trim(oracle); next }
  active && /^      evidence:/ { evidence="yes"; evidence_section="yes"; evidence_item=evidence_argv=evidence_exit=""; next }
  active && /^        - order:[[:space:]]*[0-9]+/ {
    if (evidence_item && (!evidence_argv || !evidence_exit)) evidence_incomplete="yes"
    evidence_item="yes"; evidence_argv=evidence_exit=""; next
  }
  active && /^      handoff:/ { evidence_section=""; handoff="yes"; next }
  active && /^      fan_in_owner:/ { evidence_section=""; fanin="yes"; next }
  active && /^      risks:/ { evidence_section=""; risks="yes"; next }
  active && /^      stop_conditions:/ { evidence_section=""; stops="yes"; next }
  active && /^      [A-Za-z_][A-Za-z0-9_-]*:/ { evidence_section=""; next }
  active && /^    depends_on:/ { evidence_section=""; deps_seen="yes"; deps=$0; sub(/^    depends_on:[[:space:]]*\[/, "", deps); sub(/\].*$/, "", deps); deps=trim(deps); next }
  active && evidence_section && evidence_item && /^          argv:[[:space:]]*\[[^]]+\]/ { argv="yes"; evidence_argv="yes"; next }
  active && evidence_section && evidence_item && /^          expected_exit:[[:space:]]*[0-9]+/ { expected_exit="yes"; evidence_exit="yes"; next }
  END { emit() }
' "$plan")
[ -n "$dag_records" ] || fail 'dag must contain expanded nodes with per-node contracts'

node_ids='' all_maker_paths='' all_oracle_paths=''
while IFS=$'\t' read -r node task route requirements objective recipe inputs outputs maker oracle evidence evidence_valid handoff fanin risks stops deps_seen dependencies argv expected_exit; do
  case "$node" in ''|*[!A-Za-z0-9_-]*) fail 'dag node id is missing or invalid' ;; esac
  case "$task" in behavioral_code|docs_config|refactor|research_design) ;; *) fail "unsupported task class on node: $node" ;; esac
  case "$task:$route" in behavioral_code:red_to_green|behavioral_code:characterization_to_green|docs_config:red_to_green|docs_config:characterization_to_green|refactor:characterization_to_green|research_design:source_and_challenge) ;; *) fail "invalid evidence route on node: $node" ;; esac
  case "$requirements" in \[*\]* ) ;; *) fail "missing requirement routes on node: $node" ;; esac
  case "$objective" in \[*\]* ) ;; *) fail "missing acceptance routes on node: $node" ;; esac
  [ "$recipe" = yes ] || fail "missing execution recipe on node: $node"
  [ "$evidence_valid" = yes ] || fail "evidence command is incomplete on node: $node"
  for field in "$inputs" "$outputs" "$evidence" "$handoff" "$fanin" "$risks" "$stops" "$argv" "$expected_exit"; do
    [ "$field" = yes ] || fail "missing recipe field on node: $node"
  done
  case "$maker" in \[*\]) ;; *) fail "missing recipe field on node: $node" ;; esac
  case "$oracle" in \[*\]) ;; *) fail "missing recipe field on node: $node" ;; esac
  [ "$deps_seen" = yes ] || fail "missing dependency declaration on node: $node"
  for maker_path in $(printf '%s' "$maker" | tr -d '[]' | tr ',' ' '); do all_maker_paths="${all_maker_paths}${all_maker_paths:+ }$maker_path"; done
  for oracle_path in $(printf '%s' "$oracle" | tr -d '[]' | tr ',' ' '); do all_oracle_paths="${all_oracle_paths}${all_oracle_paths:+ }$oracle_path"; done
  node_ids="${node_ids}${node_ids:+\n}$node"
done <<EOF
$dag_records
EOF
for maker_path in $all_maker_paths; do
  case " $all_oracle_paths " in *" $maker_path "*) fail 'maker and oracle paths collide across the dag' ;; esac
done
dupes=$(printf '%b\n' "$node_ids" | sort | uniq -d)
[ -z "$dupes" ] || fail 'dag node ids must be unique'
while IFS=$'\t' read -r node _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ dependencies _ _; do
  for dependency in $(printf '%s' "$dependencies" | tr ',' ' '); do
    [ "$dependency" = - ] && continue
    printf '%b\n' "$node_ids" | grep -Fx -- "$dependency" >/dev/null || fail "dag dependency is unknown: $dependency"
  done
done <<EOF
$dag_records
EOF

# Remove ready nodes until nothing remains. If no node can be removed, the DAG has a cycle.
remaining=$(printf '%b\n' "$node_ids")
while [ -n "$remaining" ]; do
  progressed=false
  next_remaining=''
  while IFS= read -r node; do
    [ -n "$node" ] || continue
    dependencies=$(printf '%s\n' "$dag_records" | awk -F '\t' -v wanted="$node" '$1 == wanted { print $18; exit }')
    blocked=false
    for dependency in $(printf '%s' "$dependencies" | tr ',' ' '); do
      [ "$dependency" = - ] && continue
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
