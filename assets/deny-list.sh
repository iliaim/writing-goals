#!/usr/bin/env bash
# ============================================================================
# deny-list.sh — a deterministic Claude Code *PreToolUse* safety hook.
#
# HONEST SCOPE — READ THIS FIRST
# ------------------------------------------------------------------------
# This hook is a BEST-EFFORT, DEFENSE-IN-DEPTH BACKSTOP against naive or
# accidental footguns by a *cooperative* agent — it is NOT a security
# boundary against an *adversarial* agent. It matches strings in a shell
# command, and a determined agent CAN defeat string-based matching
# (obfuscation, novel tools, its own written scripts, encodings we don't
# model). Do not rely on it as your only control.
#
# The REAL tier-4 boundary is OS-level sandboxing:
#   * a container / VM the run cannot escape,
#   * read-only mounts everywhere outside the repo, non-root user,
#   * NO ambient network egress (or an allowlist proxy that inspects payloads).
# This script exists to catch obvious mistakes early and to make the
# common dangerous shapes fail closed. It deliberately over-blocks
# ("deny-first"): a false block is cheap; an unattended tier-4 action is not.
#
# WHY IT EXISTS: unattended runs use bypass mode
# (--dangerously-skip-permissions), which turns interactive approval prompts
# OFF. A PreToolUse `deny` beats both the allowlist and bypass mode, so the
# few shapes we DO recognize get blocked by code, not by the model's promise.
#
# CONTRACT (Claude PreToolUse):
#   * stdin = JSON with `tool_name` and `tool_input`.
#   * To DENY, emit permissionDecision "deny" on stdout and exit 0:
#       {"hookSpecificOutput":{"hookEventName":"PreToolUse",
#        "permissionDecision":"deny","permissionDecisionReason":"..."}}
#     (exit 2 + stderr is the non-JSON fallback that also blocks — used when
#      jq is unavailable, since we cannot emit valid JSON safely without it.)
#   * To ALLOW, exit 0 with no decision -> normal permission flow proceeds.
#
# DESIGN RULES enforced below:
#   * jq is REQUIRED. No lossy sed parser (a single `"` defeats it). If jq is
#     missing OR the JSON can't be parsed -> DENY.
#   * The command is NORMALIZED (backslash-newline and newlines -> spaces)
#     before any matching, so a line-continuation can't split a pattern.
#   * "Un-reasonable" constructs we cannot analyze soundly -> DENY (fail
#     closed): inline-code interpreters, eval, command/process substitution,
#     base64, /dev/tcp, pipe-to-shell.
#   * Writes/deletes are judged by the RESOLVED ABSOLUTE TARGET PATH (~, $HOME,
#     .., symlinks resolved), not by verb+shape. Target outside the repo -> DENY.
#   * Recognized outbound network senders are DENIED by default (egress control
#     belongs at the proxy layer, not here).
#
# SCOPE: this hook inspects SHELL commands (the Bash tool). File-write dangers
# from the Edit/Write tools are covered by directory scoping, not here.
#
# WIRING: .claude/settings.json -> hooks.PreToolUse[] with matcher "Bash":
#   {"matcher":"Bash","hooks":[{"type":"command","command":".../deny-list.sh"}]}
# ============================================================================

set -u

HOMEDIR="${HOME:-}"

# ---- deny primitive (jq for stdout JSON; exit-2 fallback if jq absent) ------
deny() {
  local reason="$1"
  if command -v jq >/dev/null 2>&1; then
    jq -cn --arg r "$reason" \
      '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
    echo "deny-list: BLOCKED — $reason" >&2
    exit 0
  else
    # No jq -> cannot build valid JSON on an arbitrary reason. exit 2 + stderr
    # is the contract's non-JSON block form, so we still fail CLOSED.
    echo "deny-list: BLOCKED (jq unavailable) — $reason" >&2
    exit 2
  fi
}

# ---- 0) require jq + a parseable payload (no lossy fallback) ----------------
if ! command -v jq >/dev/null 2>&1; then
  deny "jq is required to parse the tool call safely; refusing to evaluate with a lossy parser."
fi
INPUT="$(cat)"
if ! printf '%s' "$INPUT" | jq -e . >/dev/null 2>&1; then
  deny "hook stdin is not valid JSON; cannot reason about the command — failing closed."
fi
TOOL="$(printf '%s' "$INPUT" | jq -r '.tool_name // ""')"
CMD_RAW="$(printf '%s' "$INPUT" | jq -r '.tool_input.command // ""')"
PAYLOAD_CWD="$(printf '%s' "$INPUT" | jq -r '.cwd // ""')"

# Only shell tools and Codex apply_patch are in scope. Anything else -> allow.
case "$TOOL" in
  Bash|bash|shell|Shell|apply_patch) : ;;
  *) exit 0 ;;
esac

# The bounded shell parser below is intentionally single-line. Failing closed
# is safer than erasing command boundaries or pretending to understand quoted
# newlines. Multiline apply_patch programs are validated separately.
case "$TOOL" in
  Bash|bash|shell|Shell)
    case "$CMD_RAW" in
      *$'\n'*|*$'\r'*) deny "multiline shell commands are outside the bounded parser contract — failing closed." ;;
    esac
    ;;
esac

# ---- 1) normalize: join backslash-newline, newlines/tabs -> spaces ----------
# A `\`+newline (line continuation) or a raw newline would otherwise split a
# command across "lines" and defeat every single-line pattern below.
CMD="$(printf '%s' "$CMD_RAW" | awk 'BEGIN{RS="\1"} {
  gsub(/\\\n/, " ");   # line continuation
  gsub(/\n/,  " ");
  gsub(/\r/,  " ");
  gsub(/\t/,  " ");
  gsub(/  +/, " ");     # squeeze runs of spaces
  print
}')"

# small helper: does the normalized command match this ERE?
has() { printf '%s' "$CMD" | grep -Eq -- "$1"; }

# ===========================================================================
# ALLOWLIST / EXTENSION SECTION — tune policy for your repo here.
#
#   EXTRA_DENY_PATTERNS : add project-specific tier-4 ERE fragments; any match
#                         hard-blocks. Keep it DENY-FIRST (when in doubt, deny).
#   DEV_WRITE_OK        : write targets that are safe despite being outside the
#                         repo (character devices, not files). Extend with care.
#   NOTE ON SENDERS: there is intentionally NO host allowlist. A POST body to an
#   "allowlisted" host still exfiltrates, so treating a host as trusted does not
#   make an arbitrary payload safe. Recognized senders are denied outright and
#   egress control is delegated to the sandbox/proxy layer. If you must permit a
#   specific fetch, do it at the proxy, not by weakening this hook.
# ===========================================================================
EXTRA_DENY_PATTERNS=(
  # 'my-prod-cli[[:space:]]+deploy'
)
# Standard character-device write targets (safe; not real files):
dev_write_ok() {
  case "$1" in
    /dev/null|/dev/stdout|/dev/stderr|/dev/tty|/dev/fd/*) return 0 ;;
    *) return 1 ;;
  esac
}

# ---- path helpers (used by the write/delete target check) ------------------
REPO_ROOT=""
for root_candidate in "$PAYLOAD_CWD" "${CLAUDE_PROJECT_DIR:-}" "${PWD:-}"; do
  if [ -n "$root_candidate" ] && [ -d "$root_candidate" ]; then
    REPO_ROOT="$root_candidate"
    break
  fi
done
if [ -n "$REPO_ROOT" ]; then
  REPO_PHYS="$(cd -P "$REPO_ROOT" 2>/dev/null && pwd -P)" || REPO_PHYS=""
else
  REPO_PHYS=""
fi

# Resolve each existing component without relying on GNU-only `readlink -f`.
# Dangling links are rejected; nonexistent ordinary tails remain valid writes.
resolve_phys() {
  local p pending part rest resolved="" candidate target depth=0
  p="$1"
  pending="${p#/}"

  while [ -n "$pending" ]; do
    case "$pending" in
      */*) part="${pending%%/*}"; rest="${pending#*/}" ;;
      *) part="$pending"; rest="" ;;
    esac
    case "$part" in
      ''|.)
        pending="$rest"
        continue
        ;;
      ..)
        resolved="$(dirname "${resolved:-/}")"
        pending="$rest"
        continue
        ;;
    esac
    if [ -z "$resolved" ] || [ "$resolved" = "/" ]; then
      candidate="/$part"
    else
      candidate="$resolved/$part"
    fi

    if [ -L "$candidate" ]; then
      depth=$((depth + 1))
      [ "$depth" -le 40 ] || return 1
      target="$(readlink "$candidate" 2>/dev/null)" || return 1
      case "$target" in
        /*)
          [ -e "$target" ] || [ -L "$target" ] || return 1
          pending="${target#/}"
          resolved=""
          ;;
        *)
          target="${resolved:-/}/$target"
          [ -e "$target" ] || [ -L "$target" ] || return 1
          pending="$target"
          resolved=""
          ;;
      esac
      [ -n "$rest" ] && pending="$pending/$rest"
      continue
    fi

    if [ -e "$candidate" ]; then
      [ -z "$rest" ] || [ -d "$candidate" ] || return 1
      resolved="$candidate"
      pending="$rest"
      continue
    fi

    resolved="$candidate"
    pending="$rest"
  done

  printf '%s' "${resolved:-/}"
}

is_inside() {
  local t="$1"
  [ "$t" = "$REPO_PHYS" ] && return 0
  case "$t" in "$REPO_PHYS"/*) return 0 ;; esac
  return 1
}

# Resolve one candidate write/delete target and DENY if it escapes the repo.
check_target() {
  local t="$1"
  if [ -z "$REPO_PHYS" ]; then
    deny "no valid repository root is available; cannot prove the mutation stays in-repo — failing closed."
  fi
  # strip one layer of surrounding quotes
  case "$t" in
    \"*\") t="${t#\"}"; t="${t%\"}" ;;
    \'*\') t="${t#\'}"; t="${t%\'}" ;;
  esac
  [ -z "$t" ] && return 0
  dev_write_ok "$t" && return 0
  # expand a leading ~
  case "$t" in
    "~") t="$HOMEDIR" ;;
    \~/*) t="$HOMEDIR/${t#\~/}" ;;
  esac
  # expand ${HOME} and $HOME anywhere
  t="$(printf '%s' "$t" | sed -e "s#\${HOME}#${HOMEDIR}#g" -e "s#\$HOME#${HOMEDIR}#g")"
  # an unresolved variable (or leftover $()) means we CANNOT prove it stays
  # in-repo -> fail closed.
  case "$t" in
    *'$'*) deny "write/delete target has an unresolved variable ('$t'); cannot prove it stays in-repo — failing closed." ;;
  esac
  # reduce a glob to its literal directory prefix, then judge that directory
  case "$t" in
    *'*'*|*'?'*|*'['*)
      t="${t%%\**}"; t="${t%%\?*}"; t="${t%%\[*}"
      case "$t" in */*) t="${t%/*}" ;; *) t="" ;; esac
      [ -z "$t" ] && t="."
      ;;
  esac
  # make absolute (relative paths resolve against the repo root)
  case "$t" in
    /*) : ;;
    *) t="$REPO_PHYS/$t" ;;
  esac
  if ! t="$(resolve_phys "$t")"; then
    deny "write/delete target crosses a dangling, cyclic, or non-traversable path ('$t') — failing closed."
  fi
  if ! is_inside "$t"; then
    deny "write/delete target resolves OUTSIDE the repo root ('$t' not under '$REPO_PHYS')."
  fi
}

# Codex supplies the complete apply_patch program in tool_input.command. Treat
# its framing and operation headers as a small language rather than guessing
# from paths that happen to occur in the payload.
if [ "$TOOL" = "apply_patch" ]; then
  [ -n "$REPO_PHYS" ] || deny "no valid repository root is available; cannot validate apply_patch targets."

  patch_line_no=0
  patch_operations=0
  patch_ended=0
  patch_current_operation=""
  while IFS= read -r patch_line || [ -n "$patch_line" ]; do
    patch_line_no=$((patch_line_no + 1))

    if [ "$patch_line_no" -eq 1 ]; then
      [ "$patch_line" = "*** Begin Patch" ] || deny "apply_patch payload is missing the exact Begin Patch boundary."
      continue
    fi
    [ "$patch_ended" -eq 0 ] || deny "apply_patch payload contains content after End Patch."

    case "$patch_line" in
      '*** End Patch')
        patch_ended=1
        patch_current_operation=""
        ;;
      '*** Add File: '*)
        patch_target="${patch_line#*** Add File: }"
        [ -n "$patch_target" ] || deny "apply_patch Add File operation has no target."
        check_target "$patch_target"
        patch_operations=$((patch_operations + 1))
        patch_current_operation="Add"
        ;;
      '*** Update File: '*)
        patch_target="${patch_line#*** Update File: }"
        [ -n "$patch_target" ] || deny "apply_patch Update File operation has no target."
        check_target "$patch_target"
        patch_operations=$((patch_operations + 1))
        patch_current_operation="Update"
        ;;
      '*** Delete File: '*)
        patch_target="${patch_line#*** Delete File: }"
        [ -n "$patch_target" ] || deny "apply_patch Delete File operation has no target."
        check_target "$patch_target"
        patch_operations=$((patch_operations + 1))
        patch_current_operation="Delete"
        ;;
      '*** Move to: '*)
        patch_target="${patch_line#*** Move to: }"
        [ "$patch_current_operation" = "Update" ] || deny "apply_patch Move to must belong to an Update File operation."
        [ -n "$patch_target" ] || deny "apply_patch Move to operation has no destination."
        check_target "$patch_target"
        ;;
      '--- '*|'+++ '*)
        deny "legacy diff headers are not a supported apply_patch operation."
        ;;
      '*** Begin Patch'|'*** Add File:'|'*** Update File:'|'*** Delete File:'|'*** Move to:')
        deny "apply_patch contains a malformed boundary or operation header."
        ;;
      '*** Add '*|'*** Update '*|'*** Delete '*|'*** Move '*|'*** Begin '*|'*** End '*)
        deny "apply_patch contains a malformed boundary or operation header."
        ;;
      '*** '*' File: '*)
        deny "apply_patch contains an unrecognized operation header."
        ;;
      '*** Rename:'*|'*** Rename File:'*|'*** Copy:'*|'*** Copy File:'*|'*** Create File:'*|'*** Remove File:'*)
        deny "apply_patch contains an unrecognized operation header."
        ;;
      *)
        # Hunk content is intentionally opaque. In particular, a legitimate
        # content line may itself begin with "*** ".
        ;;
    esac
  done <<< "$CMD_RAW"

  [ "$patch_ended" -eq 1 ] || deny "apply_patch payload is missing the exact End Patch boundary."
  [ "$patch_operations" -gt 0 ] || deny "apply_patch payload contains no recognized file operation."
  exit 0
fi

# A supported mutation needs a trustworthy root even if its particular parser
# below would otherwise find no path argument.
if [ -z "$REPO_PHYS" ] && {
  has '(^|[[:space:];|&(/])(touch|mkdir|rm|rmdir|unlink|shred|cp|mv|tee|truncate|ln)([[:space:]]|$)' ||
  has '(^|[[:space:];|&(/])sed[[:space:]]+-[^[:space:]]*i[^[:space:]]*([[:space:]]|$)' ||
  has '(^|[[:space:]])(>|>>)([[:space:]]|$)' ||
  has '(^|[[:space:]])of=' ||
  { has '(^|[[:space:];|&(/])find([[:space:]]|$)' && has '(^|[[:space:]])(-delete|-exec|-execdir)([[:space:]]|$)'; }
}; then
  deny "no valid repository root is available; cannot prove the mutation stays in-repo — failing closed."
fi

# ===========================================================================
# DENY CHECKS — deny-first order. The FIRST match wins.
# ===========================================================================

# ---- 2) un-reasonable constructs (we can't analyze these soundly) ----------
# Inline-code interpreters, eval, command/process substitution, base64,
# /dev/tcp, and pipe-to-shell all let a payload we can't inspect run. DENY.
CONSTRUCT_PATTERNS=(
  # inline code. The flag must appear in the LEADING option cluster (after the
  # interpreter, before any script/subcommand), so an app flag deeper in the
  # argv (e.g. `python3 manage.py test -e prod`) does NOT trip it.
  #   python: only -c (inline) / bare - (stdin script) — python has no -e.
  '(^|[[:space:];|&(/])(python[0-9.]*)[[:space:]]+(-[^[:space:]]+[[:space:]]+)*(-c|-)([[:space:]]|$)'
  #   node/perl/ruby/php: -c / -e / bare -
  '(^|[[:space:];|&(/])(perl|node|nodejs|ruby|php)[[:space:]]+(-[^[:space:]]+[[:space:]]+)*(-c|-e|-)([[:space:]]|$)'
  # a shell asked to run an inline string: sh/bash/zsh/dash/ksh -c ...
  '(^|[[:space:];|&(/])(ba|z|da|k)?sh[[:space:]]+(-[^[:space:]]+[[:space:]]+)*-c([[:space:]]|$)'
  'eval([[:space:]]|$)'                       # eval <string>
  '\$\('                                       # $( command substitution )
  '`'                                          # `command substitution`
  '[<>]\('                                     # <( ) / >( ) process substitution
  '(^|[[:space:];|&(=/])base64([[:space:]]|$)' # base64 encode/decode of a payload
  '/dev/(tcp|udp)/'                            # bash pseudo-network device
  '\|[[:space:]]*(sudo[[:space:]]+)?(ba|z|da|k)?sh([[:space:]]|$)'  # ... | sh / | bash
)
for pat in "${CONSTRUCT_PATTERNS[@]}"; do
  if has "$pat"; then
    deny "un-analyzable construct blocked (matched: ${pat}). Cooperative agents don't need inline-eval / command-substitution / base64 / raw sockets in an unattended run."
  fi
done

# ---- 3) outbound network senders (default DENY; egress = proxy's job) -------
NET_SENDERS='(curl|wget|nc|ncat|netcat|scp|sftp|rsync|ssh|telnet|ftp|tftp|mail|mailx|sendmail)'
if has "(^|[[:space:];|&(/])${NET_SENDERS}([[:space:]]|\$)"; then
  deny "outbound network sender detected. Even a POST to an allowlisted host can exfiltrate; egress control belongs at the sandbox/proxy layer, so senders are denied here by default."
fi

# ---- 4) package installs (default-deny package managers as a class) --------
PKG_PATTERNS=(
  '(^|[[:space:];|&(/])pip[0-9]*[[:space:]]+install'
  '(^|[[:space:];|&(/])pipx[[:space:]]+'
  '(^|[[:space:];|&(/])uv[[:space:]]+(pip[[:space:]]+install|add|sync|tool[[:space:]]+install)'
  '(^|[[:space:];|&(/])(npm|pnpm|yarn)[[:space:]]+(install|i|add|ci|dlx)([[:space:]]|$)'
  '(^|[[:space:];|&(/])npx([[:space:]]|$)'
  '(^|[[:space:];|&(/])(gem[[:space:]]+install|cargo[[:space:]]+install|go[[:space:]]+(install|get)|poetry[[:space:]]+add|bundle[[:space:]]+(install|add)|composer[[:space:]]+(install|require|update))'
  '(^|[[:space:];|&(/])(apt|apt-get|brew|dnf|yum|apk|pacman|zypper)[[:space:]]+(install|add|-S)'
)
for pat in "${PKG_PATTERNS[@]}"; do
  if has "$pat"; then
    deny "package install blocked (matched: ${pat}). Installing arbitrary deps in an unattended run is tier-4; vendor/pin deps beforehand."
  fi
done

# ---- 5) destructive git (force-push / history rewrite) ---------------------
# Tolerant of -C <dir>, --git-dir=..., and interleaved options after
# normalization: we require the tokens `git` AND `push` AND a force/mirror flag
# to co-occur, regardless of order.
if has '(^|[[:space:];|&(/])git([[:space:]]|$)'; then
  if has '(^|[[:space:]])push([[:space:]]|$)' && \
     has '(--force([[:space:]]|=|$)|--force-with-lease|(^|[[:space:]])-f([[:space:]]|$)|--mirror)'; then
    deny "destructive git push (force / force-with-lease / mirror) blocked."
  fi
  if has 'filter-branch' || has 'filter-repo' || \
     { has '(^|[[:space:]])reflog([[:space:]]|$)' && has 'expire'; } || \
     has '(^|[[:space:]])update-ref[[:space:]]+-d'; then
    deny "git history rewrite (filter-branch/filter-repo/reflog expire/update-ref -d) blocked."
  fi
fi

# ---- 6) secrets: read/transmit credentials --------------------------------
# READER + SECRET TARGET must co-occur (so a plain `grep foo src.py` is fine).
# NOTE: this reader/secret list is NON-EXHAUSTIVE by nature — new tools and new
# secret filenames will always slip past a string list. Treat it as a backstop.
READERS='(cat|less|more|head|tail|bat|tac|rev|nl|od|xxd|hexdump|strings|cut|tr|grep|egrep|fgrep|awk|sed|sort|uniq|wc|dd|cp|mv|tee|xargs|printenv|env)'
# NOTE: bare words (credentials/authorized_keys) are anchored to a path/filename
# context ([./] or a leading /) so a search *pattern* like `grep -r credentials
# ./src` is NOT mistaken for reading a credentials file.
SECRETS="(\\.env([[:space:]./\"'=:]|\$)|\\.envrc|id_rsa|id_ed25519|id_dsa|id_ecdsa|\\.pem([[:space:]./\"']|\$)|\\.p12|\\.key([[:space:]./\"']|\$)|[./]credentials|secrets?\\.(json|ya?ml|txt|env)|\\.ssh/|/authorized_keys|\\.aws/|\\.npmrc|\\.netrc|\\.pgpass|\\.git-credentials|\\.docker/config)"
if has "(^|[[:space:];|&(/])${READERS}[[:space:]].*${SECRETS}"; then
  deny "reads or transmits secrets (credentials / keys / .env). Blocked."
fi
if has '(^|[[:space:];|&(/])(printenv|env|set)[[:space:]]*(\||>|;|&&)'; then
  deny "dumping the environment onward (env|printenv piped/redirected) is a secrets-exfil shape. Blocked."
fi

# ---- 7) writes/deletes by RESOLVED target path -----------------------------
# We tokenize the command, then check every redirect target and every path
# argument of a destructive command. Any resolved target outside the repo -> DENY.
#
# Pad redirect operators and separators so they become their own tokens.
PADDED="$(printf '%s' "$CMD" | awk '{
  gsub(/>>/, "\002");            # protect >>
  gsub(/>/,  " > ");
  gsub(/\002/, " >> ");
  gsub(/;/,  " ; ");
  gsub(/\|/, " | ");
  gsub(/&/,  " & ");
  print
}')"

# shellcheck disable=SC2162
read -ra TOKENS <<< "$PADDED"
NTOK=${#TOKENS[@]}

is_sep() { case "$1" in ';'|'|'|'&'|'('|')') return 0 ;; *) return 1 ;; esac; }
strip_token_quotes() {
  local value="$1"
  case "$value" in
    \"*\") value="${value#\"}"; value="${value%\"}" ;;
    \'*\') value="${value#\'}"; value="${value%\'}" ;;
  esac
  printf '%s' "$value"
}

is_assignment_token() {
  local value="$1" name
  case "$value" in *=*) name="${value%%=*}" ;; *) return 1 ;; esac
  printf '%s' "$name" | grep -Eq '^[A-Za-z_][A-Za-z0-9_]*$'
}

# Locate the executable in one ordinary command segment. Only common
# transparent wrappers are understood; this deliberately is not a shell parser.
find_command_index() {
  local pos="$1" end="$2" value base
  COMMAND_INDEX=-1
  while [ "$pos" -lt "$end" ]; do
    value="$(strip_token_quotes "${TOKENS[$pos]}")"
    if is_assignment_token "$value"; then pos=$((pos + 1)); continue; fi
    base="${value##*/}"
    case "$base" in
      env)
        pos=$((pos + 1))
        while [ "$pos" -lt "$end" ]; do
          value="$(strip_token_quotes "${TOKENS[$pos]}")"
          if is_assignment_token "$value"; then pos=$((pos + 1)); continue; fi
          case "$value" in
            -u|--unset|-C|--chdir) pos=$((pos + 2)) ;;
            --chdir=*) pos=$((pos + 1)) ;;
            -*) pos=$((pos + 1)) ;;
            *) break ;;
          esac
        done
        ;;
      command|builtin|nohup)
        pos=$((pos + 1))
        while [ "$pos" -lt "$end" ]; do
          value="$(strip_token_quotes "${TOKENS[$pos]}")"
          case "$value" in -*) pos=$((pos + 1)) ;; *) break ;; esac
        done
        ;;
      exec)
        pos=$((pos + 1))
        while [ "$pos" -lt "$end" ]; do
          value="$(strip_token_quotes "${TOKENS[$pos]}")"
          case "$value" in
            -a) pos=$((pos + 2)) ;;
            -*) pos=$((pos + 1)) ;;
            *) break ;;
          esac
        done
        ;;
      sudo)
        pos=$((pos + 1))
        while [ "$pos" -lt "$end" ]; do
          value="$(strip_token_quotes "${TOKENS[$pos]}")"
          case "$value" in
            -u|-g|-h|-p|-C|-T) pos=$((pos + 2)) ;;
            -*) pos=$((pos + 1)) ;;
            *) break ;;
          esac
        done
        ;;
      *)
        COMMAND_INDEX="$pos"
        return 0
        ;;
    esac
  done
}

inspect_sed_segment() {
  local command_index="$1" end="$2" pos value
  local in_place=0 explicit_program=0 options=1
  pos=$((command_index + 1))

  while [ "$pos" -lt "$end" ] && [ "$options" -eq 1 ]; do
    value="$(strip_token_quotes "${TOKENS[$pos]}")"
    case "$value" in
      --)
        options=0
        pos=$((pos + 1))
        ;;
      -e|--expression)
        explicit_program=1
        pos=$((pos + 2))
        ;;
      -e?*|--expression=*)
        explicit_program=1
        pos=$((pos + 1))
        ;;
      -f|--file)
        explicit_program=1
        pos=$((pos + 2))
        ;;
      -f?*|--file=*)
        explicit_program=1
        pos=$((pos + 1))
        ;;
      -l|--line-length)
        pos=$((pos + 2))
        ;;
      --line-length=*)
        pos=$((pos + 1))
        ;;
      -i|--in-place)
        in_place=1
        pos=$((pos + 1))
        if [ "$pos" -lt "$end" ]; then
          value="${TOKENS[$pos]}"
          case "$value" in "''"|'""'|.*) pos=$((pos + 1)) ;; esac
        fi
        ;;
      --in-place=*|-i?*|-[A-Za-z]*i*)
        in_place=1
        pos=$((pos + 1))
        if [ "$pos" -lt "$end" ]; then
          value="${TOKENS[$pos]}"
          case "$value" in "''"|'""') pos=$((pos + 1)) ;; esac
        fi
        ;;
      -*) pos=$((pos + 1)) ;;
      *) options=0 ;;
    esac
  done

  [ "$in_place" -eq 1 ] || return 0
  [ -n "$REPO_PHYS" ] || deny "no valid repository root is available; cannot validate in-place sed targets."

  # Without -e/-f, the first non-option operand is the edit program.
  if [ "$explicit_program" -eq 0 ] && [ "$pos" -lt "$end" ]; then
    pos=$((pos + 1))
  fi
  while [ "$pos" -lt "$end" ]; do
    value="$(strip_token_quotes "${TOKENS[$pos]}")"
    [ "$value" = "--" ] || check_target "$value"
    pos=$((pos + 1))
  done
}

is_destructive() {
  # match on the basename so an absolute path (/bin/rm) is caught too
  case "${1##*/}" in
    rm|rmdir|unlink|shred|cp|mv|tee|truncate|ln|touch|mkdir) return 0 ;;
    *) return 1 ;;
  esac
}

inspect_destructive_segment() {
  local command_index="$1" end="$2" pos value
  pos=$((command_index + 1))
  while [ "$pos" -lt "$end" ]; do
    value="$(strip_token_quotes "${TOKENS[$pos]}")"
    case "$value" in
      -*) : ;;
      *) check_target "$value" ;;
    esac
    pos=$((pos + 1))
  done
}

inspect_find_segment() {
  local command_index="$1" end="$2" pos value mutates=0
  pos=$((command_index + 1))
  while [ "$pos" -lt "$end" ]; do
    value="$(strip_token_quotes "${TOKENS[$pos]}")"
    case "$value" in
      -exec|-execdir|-ok|-okdir)
        deny "nested command execution through find is not safely analyzable."
        ;;
      -delete) mutates=1 ;;
    esac
    pos=$((pos + 1))
  done
  [ "$mutates" -eq 1 ] || return 0

  pos=$((command_index + 1))
  while [ "$pos" -lt "$end" ]; do
    value="$(strip_token_quotes "${TOKENS[$pos]}")"
    case "$value" in
      -*) break ;;
      *) check_target "$value" ;;
    esac
    pos=$((pos + 1))
  done
}

i=0
while [ "$i" -lt "$NTOK" ]; do
  tok="${TOKENS[$i]}"
  # redirect target
  if [ "$tok" = ">" ] || [ "$tok" = ">>" ]; then
    j=$((i+1))
    # a combined redirect (>& / >|) puts a lone '&'/'|' between the operator and
    # the filename after tokenization — skip it so the real target is checked.
    if [ "$j" -lt "$NTOK" ]; then case "${TOKENS[$j]}" in '&'|'|') j=$((j+1)) ;; esac; fi
    if [ "$j" -lt "$NTOK" ]; then check_target "${TOKENS[$j]}"; fi
  # dd of=<path>
  elif case "$tok" in of=*) true ;; *) false ;; esac; then
    check_target "${tok#of=}"
  fi
  i=$((i+1))
done

# Inspect the executable in every ordinary command segment. This keeps gh/glab
# matching out of argument positions and ensures a later in-place sed is not
# skipped after an earlier read-only command.
segment_start=0
i=0
while [ "$i" -le "$NTOK" ]; do
  if [ "$i" -eq "$NTOK" ] || is_sep "${TOKENS[$i]}"; then
    if [ "$segment_start" -lt "$i" ]; then
      find_command_index "$segment_start" "$i"
      if [ "$COMMAND_INDEX" -ge 0 ]; then
        command_token="$(strip_token_quotes "${TOKENS[$COMMAND_INDEX]}")"
        case "${command_token##*/}" in
          gh|glab)
            deny "external repository mutator (gh/glab) is denied in unattended runs."
            ;;
          sed)
            inspect_sed_segment "$COMMAND_INDEX" "$i"
            ;;
          find)
            inspect_find_segment "$COMMAND_INDEX" "$i"
            ;;
          xargs)
            deny "nested command execution through xargs is not safely analyzable."
            ;;
          *)
            if is_destructive "$command_token"; then
              inspect_destructive_segment "$COMMAND_INDEX" "$i"
            fi
            ;;
        esac
      fi
    fi
    segment_start=$((i + 1))
  fi
  i=$((i + 1))
done

# ---- 8) obvious spend / purchase -------------------------------------------
SPEND_PATTERNS=(
  'stripe[[:space:]]+(charges|payment_intents|checkout)'
  '(^|[[:space:]])(aws|gcloud|az)[[:space:]].*(purchase|reserved-instances|buy-)'
  '(--confirm-purchase|place-order|pay-now)'
)
for pat in "${SPEND_PATTERNS[@]}"; do
  if has "$pat"; then
    deny "spend/purchase action blocked (matched: ${pat})."
  fi
done

# ---- 9) operator extension patterns ----------------------------------------
if [ "${#EXTRA_DENY_PATTERNS[@]}" -gt 0 ]; then
  for pat in "${EXTRA_DENY_PATTERNS[@]}"; do
    if has "$pat"; then
      deny "project deny-pattern matched: ${pat}."
    fi
  done
fi

# ---- default: allow --------------------------------------------------------
# Nothing matched -> stay out of the way; normal permission flow proceeds.
exit 0
