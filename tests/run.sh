#!/usr/bin/env bash
# Run the portable contract suite without requiring Bats, Python, or Node.
set -u

root="$(cd "$(dirname "$0")/.." && pwd)"
status=0
g13_contract_failed=false
for test in test_adapters.sh test_gates.sh test_deny_list.sh test_host_isolation.sh test_docs.sh test_legacy_public.sh test_owned_markdown.sh test_okf.sh test_hygiene.sh test_roles.sh test_planning.sh test_state.sh test_evidence.sh test_plan_lint.sh test_planning_receipts.sh test_redaction.sh test_retention.sh test_resume.sh test_core_integration.sh test_continuation.sh test_publisher.sh test_bundles.sh test_install.sh test_refresh_local.sh test_benchmark_harness.sh test_skill_structure.sh test_skill_host_contract.sh test_skill_evals.sh test_conformance.sh test_release.sh; do
  printf '\n==> %s\n' "$test"
  if ! bash "$root/tests/$test"; then
    status=1
    case "$test" in test_conformance.sh|test_release.sh) g13_contract_failed=true ;; esac
  fi
done
[ "$g13_contract_failed" = true ] && printf '%s\n' 'FAIL: G13_FULL_SUITE_NEW_CONTRACT_RED' >&2
exit "$status"
