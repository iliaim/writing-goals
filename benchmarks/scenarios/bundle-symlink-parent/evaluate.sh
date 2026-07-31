#!/usr/bin/env bash
# Scenario oracle. It constructs its own symlink and inputs after cloning the
# candidate, so a candidate fixture cannot define the acceptance evidence.
set -euo pipefail

[ "$#" -eq 1 ] || { printf 'usage: %s WORKTREE\n' "$0" >&2; exit 2; }
worktree=$1
[ -d "$worktree" ] || { printf 'missing worktree: %s\n' "$worktree" >&2; exit 2; }
[ -z "$(git -C "$worktree" status --porcelain)" ] || {
  printf '%s\n' 'candidate worktree is dirty; benchmark requires a local commit' >&2
  exit 1
}

scratch="$(mktemp -d "${TMPDIR:-/tmp}/writing-goals-benchmark-oracle.XXXXXX")"
cleanup() { rm -rf -- "$scratch"; }
trap cleanup EXIT HUP INT TERM
candidate="$scratch/candidate"
git clone --quiet --no-local "$worktree" "$candidate"
candidate="$(CDPATH= cd -- "$candidate" && pwd -P)"

outside="$scratch/outside"
redirect="$scratch/redirect"
mkdir "$outside"
ln -s "$outside" "$redirect"
stdout="$scratch/symlink.stdout"
stderr="$scratch/symlink.stderr"
set +e
bash "$candidate/scripts/build-bundles.sh" "$redirect/bundle" > "$stdout" 2> "$stderr"
status=$?
set -e
[ "$status" -ne 0 ] || { printf '%s\n' 'symlink parent was accepted' >&2; exit 1; }
[ ! -s "$stdout" ] || { printf '%s\n' 'symlink parent wrote stdout' >&2; exit 1; }
expected="$scratch/symlink.expected"
printf 'ERROR: output parent must not be a symbolic link: %s\n' "$redirect" > "$expected"
cmp -s "$expected" "$stderr" || {
  printf '%s\n' 'symlink parent stderr did not match the required diagnostic' >&2
  exit 1
}
[ -z "$(find "$outside" -mindepth 1 -print -quit)" ] || {
  printf '%s\n' 'symlink target contains output or staging content' >&2
  exit 1
}

normal_parent="$scratch/normal-parent"
normal_bundle="$normal_parent/bundle"
mkdir "$normal_parent"
bash "$candidate/scripts/build-bundles.sh" "$normal_bundle" > "$scratch/normal.stdout" 2> "$scratch/normal.stderr"
[ ! -s "$scratch/normal.stdout" ] && [ ! -s "$scratch/normal.stderr" ] || {
  printf '%s\n' 'normal real-parent build wrote unexpected output' >&2
  exit 1
}
[ -f "$normal_bundle/MANIFEST.sha256" ] || { printf '%s\n' 'normal build has no manifest' >&2; exit 1; }
[ -z "$(find "$normal_bundle" -type l -print -quit)" ] || {
  printf '%s\n' 'normal bundle contains a symbolic link' >&2
  exit 1
}
(
  cd "$normal_bundle"
  shasum -a 256 -c MANIFEST.sha256 >/dev/null
) || { printf '%s\n' 'normal bundle manifest does not validate' >&2; exit 1; }

bash "$candidate/tests/test_bundles.sh" > "$scratch/candidate-tests.stdout" \
  2> "$scratch/candidate-tests.stderr" || {
  printf '%s\n' 'candidate bundle regression test failed' >&2
  cat "$scratch/candidate-tests.stderr" >&2
  exit 1
}
