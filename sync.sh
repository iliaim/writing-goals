#!/usr/bin/env bash
# Install writing-goals into agent skill trees via SYMLINKS.
# Single source of truth = this build folder; edits here propagate live.
# Usage: ./sync.sh [claude|codex|all]   (default: all)
set -euo pipefail
BD="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# link SRC -> DST as a symlink, but first remove any REAL (non-symlink) file or
# directory sitting at DST. Without this, `ln -sfn shared $dest/shared` when a
# real `shared/` dir already exists silently nests a link at
# `$dest/shared/shared` and still reports success (the silent half-install).
link() {
  local src="$1" dst="$2"
  if [ ! -e "$src" ] && [ ! -L "$src" ]; then
    echo "ERROR: link source missing: $src" >&2; exit 1
  fi
  # -L catches symlinks (even broken ones); ln -sfn safely replaces those.
  # Only a REAL existing path needs an explicit rm first.
  if [ -e "$dst" ] && [ ! -L "$dst" ]; then
    rm -rf -- "$dst" || { echo "ERROR: cannot remove real path at $dst" >&2; exit 1; }
  fi
  ln -sfn "$src" "$dst"
  # Verify we ended up with a symlink pointing at src — catch any nesting.
  if [ ! -L "$dst" ]; then
    echo "ERROR: expected a symlink at $dst but found something else" >&2; exit 1
  fi
  local got
  got="$(readlink "$dst")"
  if [ "$got" != "$src" ]; then
    echo "ERROR: $dst points at '$got', expected '$src'" >&2; exit 1
  fi
}

install_claude() {
  local dest="$HOME/.claude/skills/writing-goals"
  mkdir -p "$dest"
  link "$BD/claude/SKILL.md" "$dest/SKILL.md"   # centerpiece
  link "$BD/shared"          "$dest/shared"      # neutral core (referenced on demand)
  link "$BD/assets"          "$dest/assets"      # gate hook, deny-list, .goals template
  echo "Claude  -> $dest  (invoke as /writing-goals)"
}

install_codex() {
  # Codex adapter is a later phase; only install if it exists.
  [ -f "$BD/codex/SKILL.md" ] || { echo "Codex   -> adapter not built yet, skipping"; return 0; }
  local dest="$HOME/.agents/skills/writing-goals"   # canonical Codex/agent-skills location
  mkdir -p "$dest"
  link "$BD/codex/SKILL.md" "$dest/SKILL.md"
  if [ -f "$BD/codex/agents/openai.yaml" ]; then
    mkdir -p "$dest/agents"; link "$BD/codex/agents/openai.yaml" "$dest/agents/openai.yaml"
  fi
  link "$BD/shared"  "$dest/shared"
  link "$BD/assets"  "$dest/assets"
  echo "Codex   -> $dest  (invoke as \$writing-goals / /skills picker)"
}

case "${1:-all}" in
  claude) install_claude ;;
  codex)  install_codex ;;
  all)    install_claude; install_codex ;;
  *) echo "usage: $0 [claude|codex|all]"; exit 1 ;;
esac
