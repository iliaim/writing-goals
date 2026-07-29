#!/usr/bin/env bash
# Run the portable contract suite without requiring Bats, Python, or Node.
set -u

root="$(cd "$(dirname "$0")/.." && pwd)"
status=0
for test in test_sync.sh test_gates.sh test_deny_list.sh test_docs.sh test_okf.sh; do
  printf '\n==> %s\n' "$test"
  if ! bash "$root/tests/$test"; then
    status=1
  fi
done
exit "$status"
