#!/usr/bin/env bash
# ============================================================================
# deny-list.sh — a deterministic Claude Code *PreToolUse* safety hook.
#
# WHY: unattended runs use bypass mode (--dangerously-skip-permissions), which
# turns the interactive approval prompts OFF. So tier-4 ("prohibited") actions
# must be blocked by CODE, not by the model's promise. This hook is DENY-FIRST:
# a match hard-blocks the tool call, and a PreToolUse `deny` beats both the
# allowlist and bypass mode.
#
# CONTRACT (Claude PreToolUse):
#   * stdin = JSON with `tool_name` and `tool_input`.
#   * To DENY, emit permissionDecision "deny" on stdout and exit 0:
#       {"hookSpecificOutput":{"hookEventName":"PreToolUse",
#        "permissionDecision":"deny","permissionDecisionReason":"..."}}
#     (exit 2 + stderr is the non-JSON fallback that also blocks.)
#   * To ALLOW, exit 0 with no decision -> normal permission flow proceeds.
#
# SCOPE: this hook inspects SHELL commands (the Bash tool). File-write dangers
# from Edit/Write are covered by directory scoping, not here.
# NOTE: on Codex, PreToolUse intercepts SHELL ONLY (not Edit/Write) — so on
# Codex, pair this with workspace/dir scoping to cover file dangers too.
#
# WIRING: .claude/settings.json -> hooks.PreToolUse[] with matcher "Bash":
#   {"matcher":"Bash","hooks":[{"type":"command","command":".../deny-list.sh"}]}
# ============================================================================

set -u

# ---- read stdin ------------------------------------------------------------
INPUT="$(cat)"
if command -v jq >/dev/null 2>&1; then
  TOOL="$(printf '%s' "$INPUT"  | jq -r '.tool_name // ""')"
  CMD="$(printf '%s' "$INPUT"   | jq -r '.tool_input.command // ""')"
else
  TOOL="$(printf '%s' "$INPUT"  | sed -n 's/.*"tool_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
  CMD="$(printf '%s' "$INPUT"   | sed -n 's/.*"command"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
fi

# Only shell tools are in scope. Anything else -> allow (exit 0, no output).
case "$TOOL" in
  Bash|bash|shell|Shell) : ;;
  *) exit 0 ;;
esac

# ===========================================================================
# EXTENSION POINT — edit these two lists to tune policy for your repo.
#
#   ALLOWLIST_HOSTS : hosts curl/wget/etc. MAY reach. A network-send command
#                     whose target host is NOT here is denied.
#   DENY_PATTERNS   : extended-regex fragments; a command matching ANY of them
#                     is hard-blocked. Add project-specific tier-4 actions here.
# Keep it DENY-FIRST: when in doubt, deny — a false block is cheap, an
# unattended tier-4 action is not.
# ===========================================================================
ALLOWLIST_HOSTS='localhost|127\.0\.0\.1|github\.com|raw\.githubusercontent\.com|api\.github\.com|registry\.npmjs\.org|pypi\.org|files\.pythonhosted\.org'

DENY_PATTERNS=(
  # -- deletes / writes outside the repo (absolute paths, ~, parent-escape) ---
  # NOTE: a repo-local `rm -rf ./build` stays ALLOWED (tier-2, in-workspace);
  # we only block rm whose target escapes CWD (leading /, ~, $HOME, or ../).
  'rm[[:space:]]+(-{1,2}[a-zA-Z-]*[[:space:]]+)*(/|~|\.\./|\$HOME|\$\{HOME\})'
  '>[[:space:]]*/(etc|usr|bin|sbin|System|Library|var|opt)/' # redirect-write into system dirs
  '(cp|mv|dd|tee|truncate)[[:space:]]+[^|;&]*[[:space:]]/(etc|usr|bin|sbin|System|Library|var|opt)/'

  # -- git force-push / history rewrite / remote-add -------------------------
  'git[[:space:]]+push[[:space:]]+.*(--force([^-]|$)|--force-with-lease|-f([[:space:]]|$))'
  'git[[:space:]]+(filter-branch|filter-repo)'
  'git[[:space:]]+push[[:space:]]+.*--mirror'
  'git[[:space:]]+update-ref[[:space:]]+-d'
  'git[[:space:]]+reflog[[:space:]]+expire'
  'git[[:space:]]+remote[[:space:]]+add'

  # -- package installs of arbitrary deps -----------------------------------
  '(pip[0-9]?|pip3|uv[[:space:]]+pip)[[:space:]]+install'
  'npm[[:space:]]+(install|i|add)[[:space:]]+[^-]'          # npm install <pkg> (bare `npm i` handled by caller policy)
  '(yarn[[:space:]]+add|pnpm[[:space:]]+add)'
  '(gem[[:space:]]+install|cargo[[:space:]]+install|go[[:space:]]+install|go[[:space:]]+get)'
  '(apt|apt-get|brew|dnf|yum|apk|pacman)[[:space:]]+(install|add)'
  'poetry[[:space:]]+add'
  'curl[[:space:]]+[^|]*\|[[:space:]]*(sudo[[:space:]]+)?(sh|bash)'   # curl | sh installers

  # -- obvious spend / purchase ---------------------------------------------
  'stripe[[:space:]]+(charges|payment_intents|checkout)'
  '(aws|gcloud|az)[[:space:]]+[^|;&]*(purchase|reserved-instances|buy)'
  '(buy|checkout|place-order|--confirm-purchase|pay-now)'

  # -- secrets exfiltration (print or transmit .env / keys) -----------------
  '(cat|less|head|tail|bat|xxd|base64)[[:space:]]+[^|;&]*(\.env([[:space:]./]|$)|\.pem|id_rsa|id_ed25519|credentials|secrets?\.(json|ya?ml))'
  '(printenv|env|set)[[:space:]]*(\||>|;|&&).*'            # dumping the environment onward
  '(\.env|id_rsa|id_ed25519|\.pem|credentials)[^|]*\|[[:space:]]*(curl|wget|nc|ncat|mail|sendmail|ssh)'
)

# Network senders whose destination host must be on the allowlist.
NET_SENDERS='curl|wget|nc|ncat|scp|rsync|sftp|ssh|mail|sendmail|telnet'

deny() {
  local reason="$1"
  if command -v jq >/dev/null 2>&1; then
    jq -cn --arg r "$reason" \
      '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
  else
    printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}\n' "$reason"
  fi
  echo "deny-list: BLOCKED — $reason" >&2
  exit 0    # permissionDecision:"deny" is the deterministic block (beats bypass)
}

# ---- 1) explicit deny patterns --------------------------------------------
for pat in "${DENY_PATTERNS[@]}"; do
  if printf '%s' "$CMD" | grep -Eq "$pat"; then
    deny "tier-4 shell action blocked (matched: ${pat}). See deny-list.sh to adjust policy."
  fi
done

# ---- 2) external network sends to non-allowlisted hosts -------------------
# If the command invokes a network sender AND references an http(s) URL whose
# host is not on ALLOWLIST_HOSTS, deny. (No URL + a sender like `mail`/`nc` to
# a bare host is also denied, conservatively.)
if printf '%s' "$CMD" | grep -Eq "(^|[[:space:]|;&(])($NET_SENDERS)([[:space:]]|$)"; then
  # pull every http(s) host referenced
  hosts="$(printf '%s' "$CMD" | grep -Eo 'https?://[^/[:space:]"'\'']+' | sed -E 's#https?://##')"
  if [ -z "$hosts" ]; then
    deny "network sender used with no explicit http(s) URL; cannot verify destination against the allowlist."
  fi
  while IFS= read -r h; do
    [ -z "$h" ] && continue
    if ! printf '%s' "$h" | grep -Eq "^($ALLOWLIST_HOSTS)$"; then
      deny "external send to non-allowlisted host '$h' (allowlist: $ALLOWLIST_HOSTS)."
    fi
  done <<EOF
$hosts
EOF
fi

# ---- default: allow --------------------------------------------------------
# No pattern matched -> stay out of the way; normal permission flow proceeds.
exit 0
