#!/usr/bin/env bash
# Deterministic local-only final-readiness check.  G11 never publishes.
set -u
set -o pipefail

fail() { printf '%s\n' 'readiness refused' >&2; exit 1; }

repository=''
remote=''
base=''
head=''
commit=''
tree=''
seen=''

while [ "$#" -gt 0 ]; do
  case "$1" in
    --repo|--remote|--base|--head|--commit|--tree)
      [ "$#" -ge 2 ] || fail
      key=${1#--}
      case " $seen " in *" $key "*) fail ;; esac
      seen="$seen $key"
      case "$1" in
        --repo) repository=$2 ;;
        --remote) remote=$2 ;;
        --base) base=$2 ;;
        --head) head=$2 ;;
        --commit) commit=$2 ;;
        --tree) tree=$2 ;;
      esac
      shift 2
      ;;
    *) fail ;;
  esac
done

[ -n "$repository" ] && [ -n "$remote" ] && [ -n "$base" ] && [ -n "$head" ] && [ -n "$commit" ] && [ -n "$tree" ] || fail
for field in "$repository" "$remote" "$base" "$head" "$commit" "$tree"; do
  case "$field" in *$'\n'*|*$'\r'*) fail ;; esac
done
[ "$head" != "$base" ] || fail
case "$head" in main|master|release) fail ;; esac
printf '%s' "$repository" | grep -Eq '^[A-Za-z0-9][A-Za-z0-9._-]*/[A-Za-z0-9][A-Za-z0-9._-]*$' || fail
printf '%s' "$remote" | grep -Eq '^[A-Za-z0-9][A-Za-z0-9._-]*$' || fail
printf '%s' "$base" | grep -Eq '^[A-Za-z0-9][A-Za-z0-9._-]*$' || fail
printf '%s' "$head" | grep -Eq '^[A-Za-z0-9][A-Za-z0-9._/-]*$' || fail
printf '%s' "$commit" | grep -Eq '^[0-9a-f]{40}$' || fail
printf '%s' "$tree" | grep -Eq '^[0-9a-f]{40}$' || fail

# These are local repository facts only.  Do not add remote Git or gh calls.
[ -z "$(git status --porcelain)" ] || fail
[ "$(git branch --show-current)" = "$head" ] || fail
remote_url=$(git config --get "remote.$remote.url") || fail
case "$remote_url" in
  "git@github.com:$repository.git"|"https://github.com/$repository.git"|"https://github.com/$repository") ;;
  *) fail ;;
esac
[ "$(git rev-parse HEAD)" = "$commit" ] || fail
[ "$(git rev-parse 'HEAD^{tree}')" = "$tree" ] || fail
git show-ref --verify --quiet "refs/heads/$base" || fail
git merge-base --is-ancestor "$base" HEAD || fail

printf '%s\n' \
  'readiness=ready' \
  "repository=$repository" \
  "remote=$remote" \
  "base=$base" \
  "head=$head" \
  "commit=$commit" \
  "tree=$tree" \
  'publication=human-only after terminal G13'
