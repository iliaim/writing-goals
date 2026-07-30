#!/usr/bin/env bash
# Redact untrusted evidence before it is allowed onto the filesystem.
set -u
set -o pipefail

die() { printf '%s\n' "redact-stream: $1" >&2; exit 1; }

output='' max_bytes='' max_records=''
while [ "$#" -gt 0 ]; do
  case "$1" in
    --output|--max-bytes|--max-records)
      [ "$#" -ge 2 ] || die "missing value for $1"
      case "$1" in
        --output) output=$2 ;;
        --max-bytes) max_bytes=$2 ;;
        --max-records) max_records=$2 ;;
      esac
      shift 2 ;;
    *) die "unknown argument: $1" ;;
  esac
done

[ -n "$output" ] && [ -n "$max_bytes" ] && [ -n "$max_records" ] || die 'output, max-bytes, and max-records are required'
case "$max_bytes" in ''|0|*[!0-9]*|0*) die 'max-bytes must be a canonical positive integer' ;; esac
case "$max_records" in ''|0|*[!0-9]*|0*) die 'max-records must be a canonical positive integer' ;; esac
[ "${#max_bytes}" -le 9 ] && [ "${#max_records}" -le 9 ] || die 'configured limit is too large'

parent=$(dirname -- "$output")
[ -d "$parent" ] && [ ! -L "$parent" ] || die 'output parent must be a real directory'
[ ! -e "$output" ] && [ ! -L "$output" ] || die 'output already exists'

tmp=''
cleanup() {
  [ -z "$tmp" ] || rm -f -- "$tmp"
}
trap cleanup EXIT HUP INT TERM

# Perl consumes and validates the complete stream before writing its first byte.
# Thus this temporary file can only ever contain the already-sanitized excerpt.
tmp=$(mktemp "$parent/.redact-stream.XXXXXX") || die 'cannot create sanitized staging file'
if ! perl -MEncode=decode,encode,FB_CROAK -e '
  use strict;
  use warnings;
  my ($max_bytes, $max_records) = @ARGV;
  local $/;
  my $raw = <STDIN>;
  $raw = q{} unless defined $raw;
  my $text;
  eval { $text = decode("UTF-8", $raw, FB_CROAK); 1 } or exit 1;
  exit 1 if $text =~ /\x00/;

  my @records = ($text =~ /.*(?:\n|\z)/g);
  pop @records if @records && $records[-1] eq q{};
  my $written = 0;
  my $count = 0;
  for my $record (@records) {
    last if $count >= $max_records;
    # The field-name redactor below deliberately handles only literal JSON
    # property names.  Do not persist JSON-like records whose property names
    # contain escapes: an escape can conceal a credential-bearing key.
    exit 1 if $record =~ /"(?:\\.|[^"\\])*\\.(?:\\.|[^"\\])*"\s*:/;
    # Credential-bearing authorization values and key/value secrets are removed
    # before paths so neither a token nor a local root is persisted.
    $record =~ s{\bauthorization\s*:\s*(?:bearer|token)?\s*[^\s\r\n]+}{q{authorization: [REDACTED]}}egi;
    $record =~ s{\b[[:alnum:]_-]*(?:secret|token|key|password)[[:alnum:]_-]*\s*(?:=|:)\s*[^\s\r\n]+}{q{[REDACTED_SECRET]}}egi;
    # JSON values can be nested or non-scalar.  Without a JSON parser, reject
    # every literal credential-shaped property rather than risk staging it.
    exit 1 if $record =~ /"[^"\\]*(?:secret|token|key|password)[^"\\]*"\s*:/i;
    $record =~ s{("[^"\\]*(?:secret|token|key|password)[^"\\]*"\s*:\s*)"(?:\\.|[^"\\])*"}{$1"[REDACTED_SECRET]"}gi;
    $record =~ s{\b(?:sk_(?:live|test)_[[:alnum:]_-]+|ghp_[[:alnum:]]+)}{q{[REDACTED_SECRET]}}g;
    # Covers raw UNC paths and their JSON-escaped representation (\\\\server\\share).
    $record =~ s{(?<![[:alnum:]_.-])\\{2,}[^\s"\r\n]*}{[REDACTED_PATH]}g;
    $record =~ s{(?<![[:alnum:]_.-])/(?:[[:alnum:]_.~+-]+/?)+}{q{[REDACTED_PATH]}}g;
    $record =~ s{(?<![[:alnum:]_.-])[A-Za-z]:(?:\\+|/)[^\s"\r\n]*}{q{[REDACTED_PATH]}}g;
    my $bytes = encode("UTF-8", $record);
    last if length($bytes) + $written > $max_bytes;
    print $bytes or exit 1;
    $written += length($bytes);
    $count++;
  }
' "$max_bytes" "$max_records" < /dev/stdin > "$tmp"; then
  die 'input cannot be transformed with certainty'
fi

[ ! -e "$output" ] && [ ! -L "$output" ] || die 'output appeared during redaction'
mv -- "$tmp" "$output" || die 'cannot publish sanitized evidence'
tmp=''
