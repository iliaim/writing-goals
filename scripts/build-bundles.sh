#!/usr/bin/env bash
# Produce a portable, self-contained writing-goals distribution bundle.
set -euo pipefail

usage() {
  printf 'usage: %s OUTPUT_DIRECTORY\n' "$0" >&2
  exit 2
}

[ "$#" -eq 1 ] || usage

source_root="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
output="$1"
parent="$(dirname -- "$output")"
name="$(basename -- "$output")"

[ -d "$parent" ] || { printf 'ERROR: output parent does not exist: %s\n' "$parent" >&2; exit 1; }
[ ! -e "$output" ] && [ ! -L "$output" ] || { printf 'ERROR: output already exists: %s\n' "$output" >&2; exit 1; }

stage="$(mktemp -d "$parent/.${name}.writing-goals.XXXXXX")"
cleanup() { rm -rf -- "$stage"; }
trap cleanup EXIT HUP INT TERM

# -L deliberately resolves the source tree's development-only codex links.
for entry in claude codex shared assets; do
  cp -RL "$source_root/$entry" "$stage/$entry"
done
cp -p "$source_root/install.sh" "$stage/install.sh"

# Bundles are reproducible across checkouts: directory and file permissions do
# not inherit a caller's umask, and the manifest is traversed in byte order.
find "$stage" -type d -exec chmod 755 {} +
find "$stage" -type f -exec chmod 644 {} +
find "$stage/assets" -type f -name '*.sh' -exec chmod 755 {} +
chmod 755 "$stage/install.sh"

if find "$stage" -type l -print -quit | grep -q .; then
  printf 'ERROR: bundle source contains a symbolic link\n' >&2
  exit 1
fi

(
  cd "$stage"
  LC_ALL=C find . -type f ! -name MANIFEST.sha256 -print | LC_ALL=C sort |
    while IFS= read -r file; do shasum -a 256 "$file"; done > MANIFEST.sha256
)

mv -- "$stage" "$output"
trap - EXIT HUP INT TERM
