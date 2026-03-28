#!/usr/bin/env bash
# pre_safety_gate.sh - Safety Gate Hook (PreToolUse)
#
# Triggered before Write/Edit/MultiEdit/Bash tool calls.
# Blocks dangerous operations structurally — no prompt can override this.
#
# Stdin: JSON from Claude Code hook event
# Stdout: reason message (on block)
# Exit 0: allow operation
# Exit 2: block operation (Claude Code treats this as a hard block)

set -euo pipefail

INPUT=$(cat)

TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null || true)

# ── File-based tools: block sensitive file paths ─────────────────────────────
if [[ "$TOOL_NAME" =~ ^(Write|Edit|MultiEdit)$ ]]; then
  FILE_PATH=$(echo "$INPUT" | jq -r '
    .tool_input.file_path //
    .tool_input.path //
    empty
  ' 2>/dev/null || true)

  if [[ -n "$FILE_PATH" ]]; then
    BASENAME=$(basename "$FILE_PATH")
    LOWER=$(echo "$FILE_PATH" | tr '[:upper:]' '[:lower:]')

    # Block sensitive files
    BLOCKED=false
    REASON=""

    if [[ "$BASENAME" =~ ^\.(env|envrc)$ ]] || [[ "$BASENAME" =~ \.env\. ]]; then
      BLOCKED=true
      REASON="Editing .env files is blocked by the safety gate. Use .env.example instead."
    elif [[ "$LOWER" =~ (secret|credential|private_key|id_rsa|id_ed25519) ]]; then
      BLOCKED=true
      REASON="Editing files with sensitive names (secret/credential/key) is blocked by the safety gate."
    elif [[ "$LOWER" =~ \.(pem|key|p12|pfx)$ ]]; then
      BLOCKED=true
      REASON="Editing certificate/key files is blocked by the safety gate."
    fi

    if [[ "$BLOCKED" == "true" ]]; then
      echo "$REASON" >&2
      exit 2
    fi
  fi
fi

# ── Bash tool: block dangerous shell commands ────────────────────────────────
if [[ "$TOOL_NAME" == "Bash" ]]; then
  COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null || true)

  if [[ -n "$COMMAND" ]]; then
    BLOCKED=false
    REASON=""

    # rm -rf on root or home
    if echo "$COMMAND" | grep -qE 'rm\s+-[a-z]*r[a-z]*f[a-z]*\s+(/\s|/\*|~\s|~/\*)'; then
      BLOCKED=true
      REASON="Dangerous rm -rf on root/home directory is blocked by the safety gate."
    # sudo rm -rf
    elif echo "$COMMAND" | grep -qE 'sudo\s+rm\s+-[a-z]*r'; then
      BLOCKED=true
      REASON="sudo rm -rf is blocked by the safety gate."
    # chmod 777 on sensitive dirs
    elif echo "$COMMAND" | grep -qE 'chmod\s+777\s+/'; then
      BLOCKED=true
      REASON="chmod 777 on system directories is blocked by the safety gate."
    # curl/wget piped directly to bash/sh (supply-chain attack vector)
    elif echo "$COMMAND" | grep -qE '(curl|wget).+\|\s*(ba)?sh'; then
      BLOCKED=true
      REASON="Piping curl/wget directly to bash is blocked by the safety gate. Download and inspect scripts first."
    fi

    if [[ "$BLOCKED" == "true" ]]; then
      echo "$REASON" >&2
      exit 2
    fi
  fi
fi

exit 0
