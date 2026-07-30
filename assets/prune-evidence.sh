#!/usr/bin/env bash
# Explicit, deterministic evidence retention.  There is deliberately no mode
# that runs without a complete selector tuple.
set -u
set -o pipefail

die() { printf '%s\n' "prune-evidence: $1" >&2; exit 1; }
valid_timestamp() {
  printf '%s\n' "$1" | grep -Eq '^[0-9]{4}-(0[1-9]|1[0-2])-(0[1-9]|[12][0-9]|3[01])T([01][0-9]|2[0-3]):[0-5][0-9]:[0-5][0-9]Z$' || return 1
  perl -MTime::Piece -e '$t = Time::Piece->strptime($ARGV[0], "%Y-%m-%dT%H:%M:%SZ"); exit($t->strftime("%Y-%m-%dT%H:%M:%SZ") eq $ARGV[0] ? 0 : 1)' "$1" >/dev/null 2>&1
}

records_dir='' identity='' plan='' cutoff='' manifest=''
while [ "$#" -gt 0 ]; do
  case "$1" in
    --records-dir|--identity|--plan|--cutoff|--manifest)
      [ "$#" -ge 2 ] || die "missing value for $1"
      case "$1" in
        --records-dir) records_dir=$2 ;;
        --identity) identity=$2 ;;
        --plan) plan=$2 ;;
        --cutoff) cutoff=$2 ;;
        --manifest) manifest=$2 ;;
      esac
      shift 2 ;;
    *) die "unknown argument: $1" ;;
  esac
done

[ -n "$records_dir" ] && [ -n "$identity" ] && [ -n "$plan" ] && [ -n "$cutoff" ] && [ -n "$manifest" ] || die 'records-dir, identity, plan, cutoff, and manifest are required'
[ -d "$records_dir" ] && [ ! -L "$records_dir" ] || die 'records-dir must be a real directory'
case "$identity" in *[!A-Za-z0-9._:-]*|'') die 'invalid identity' ;; esac
case "$plan" in p[0-9][0-9]) ;; *) die 'invalid plan' ;; esac
valid_timestamp "$cutoff" || die 'cutoff must be canonical RFC3339 UTC'
manifest_parent=$(dirname -- "$manifest")
[ -d "$manifest_parent" ] && [ ! -L "$manifest_parent" ] || die 'manifest parent must be a real directory'
[ ! -e "$manifest" ] && [ ! -L "$manifest" ] || die 'manifest already exists'

files=()
while IFS= read -r -d '' record; do
  name=${record##*/}
  printf '%s\n' "$name" | grep -Eq '^[A-Za-z0-9][A-Za-z0-9._-]*\.receipt$' || die 'unsupported receipt filename'
  [ ! -L "$record" ] || die 'receipt symlinks are not supported'
  files+=("$record")
done < <(find "$records_dir" -type f -name '*.receipt' -print0)

sorted_files=()
if [ "${#files[@]}" -gt 0 ]; then
  while IFS= read -r record; do sorted_files+=("$record"); done < <(printf '%s\n' "${files[@]}" | LC_ALL=C sort)
fi

deletions=()
for record in "${sorted_files[@]-}"; do
  [ -n "$record" ] || continue
  seen_identity=0 seen_plan=0 seen_recorded=0 seen_reference=0
  receipt_identity='' receipt_plan='' recorded_at='' referenced_by=''
  while IFS= read -r line || [ -n "${line:-}" ]; do
    case "$line" in *=*) key=${line%%=*}; value=${line#*=} ;; *) die 'malformed receipt line' ;; esac
    case "$key" in
      identity) [ "$seen_identity" -eq 0 ] || die 'duplicate identity field'; seen_identity=1; receipt_identity=$value ;;
      plan) [ "$seen_plan" -eq 0 ] || die 'duplicate plan field'; seen_plan=1; receipt_plan=$value ;;
      recorded_at) [ "$seen_recorded" -eq 0 ] || die 'duplicate recorded_at field'; seen_recorded=1; recorded_at=$value ;;
      referenced_by) [ "$seen_reference" -eq 0 ] || die 'duplicate referenced_by field'; seen_reference=1; referenced_by=$value ;;
      payload) : ;;
      *) die 'unsupported receipt field' ;;
    esac
  done < "$record"
  [ "$seen_identity" -eq 1 ] && [ "$seen_plan" -eq 1 ] && [ "$seen_recorded" -eq 1 ] && [ "$seen_reference" -eq 1 ] || die 'receipt is missing a required field'
  printf '%s\n' "$receipt_identity" | grep -Eq '^[A-Za-z0-9][A-Za-z0-9._:-]*$' || die 'invalid receipt identity'
  printf '%s\n' "$receipt_plan" | grep -Eq '^p[0-9][0-9]$' || die 'invalid receipt plan'
  valid_timestamp "$recorded_at" || die 'invalid receipt timestamp'
  if [ -n "$referenced_by" ]; then
    printf '%s\n' "$referenced_by" | grep -Eq '^[A-Za-z0-9][A-Za-z0-9._-]*\.receipt$' || die 'invalid authority reference'
    [ -f "$records_dir/$referenced_by" ] && [ ! -L "$records_dir/$referenced_by" ] || die 'authority reference is missing or unsafe'
  fi
  if [ "$receipt_identity" = "$identity" ] && [ "$receipt_plan" = "$plan" ] && [ "$recorded_at" \< "$cutoff" ] && [ -z "$referenced_by" ]; then
    deletions+=("$record")
  fi
done

tmp=''
cleanup() { [ -z "$tmp" ] || rm -f -- "$tmp"; }
trap cleanup EXIT HUP INT TERM
tmp=$(mktemp "$manifest_parent/.prune-evidence.XXXXXX") || die 'cannot create manifest staging file'
for record in "${deletions[@]-}"; do
  [ -n "$record" ] || continue
  printf 'deleted\t%s\n' "${record##*/}" >> "$tmp" || die 'cannot write deletion manifest'
done

for record in "${deletions[@]-}"; do
  [ -n "$record" ] || continue
  rm -f -- "$record" || die 'cannot delete selected receipt'
done
mv -- "$tmp" "$manifest" || die 'cannot publish deletion manifest'
tmp=''
