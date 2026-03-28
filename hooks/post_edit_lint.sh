#!/usr/bin/env bash
# post_edit_lint.sh - Quality Loop Hook (PostToolUse)
#
# Triggered after Write/Edit/MultiEdit tool calls.
# Runs linter on the modified file and injects errors as additionalContext
# so Claude can fix them immediately.
#
# Stdin: JSON from Claude Code hook event
# Stdout: JSON with hookSpecificOutput.additionalContext (on error)
# Exit 0: success (even on lint errors — we report, not block)

set -euo pipefail

# ── Parse stdin ──────────────────────────────────────────────────────────────
INPUT=$(cat)

# Extract file path from tool input (Write/Edit/MultiEdit all have file_path)
FILE_PATH=$(echo "$INPUT" | jq -r '
  .tool_input.file_path //
  .tool_input.path //
  empty
' 2>/dev/null || true)

if [[ -z "$FILE_PATH" ]]; then
  exit 0
fi

# Resolve to absolute path if relative
if [[ "$FILE_PATH" != /* ]]; then
  FILE_PATH="$(pwd)/$FILE_PATH"
fi

# File must exist
if [[ ! -f "$FILE_PATH" ]]; then
  exit 0
fi

# ── Language detection ───────────────────────────────────────────────────────
EXT="${FILE_PATH##*.}"

emit_context() {
  local msg="$1"
  printf '{"hookSpecificOutput":{"additionalContext":%s}}' "$(echo "$msg" | jq -Rs .)"
  exit 0
}

# ── TypeScript / JavaScript ──────────────────────────────────────────────────
if [[ "$EXT" =~ ^(ts|tsx|js|jsx|mts|cts)$ ]]; then
  if ! command -v biome &>/dev/null && ! npx --yes biome --version &>/dev/null 2>&1; then
    exit 0  # biome not available, skip silently
  fi

  BIOME_CMD="biome"
  command -v biome &>/dev/null || BIOME_CMD="npx biome"

  # Step 1: Auto-fix
  $BIOME_CMD check --write "$FILE_PATH" &>/dev/null || true

  # Step 2: Check for remaining errors
  LINT_OUTPUT=$($BIOME_CMD check "$FILE_PATH" 2>&1 || true)

  if echo "$LINT_OUTPUT" | grep -qE '(error|warning)'; then
    # Strip ANSI escape codes for clean output
    CLEAN=$(echo "$LINT_OUTPUT" | sed 's/\x1b\[[0-9;]*m//g')
    emit_context "$(printf 'Biome lint issues in %s:\n\n%s\n\nPlease fix the above issues.' "$FILE_PATH" "$CLEAN")"
  fi

  exit 0
fi

# ── Python ───────────────────────────────────────────────────────────────────
if [[ "$EXT" == "py" ]]; then
  RUFF_CMD=""
  if command -v ruff &>/dev/null; then
    RUFF_CMD="ruff"
  elif command -v uvx &>/dev/null; then
    RUFF_CMD="uvx ruff"
  else
    exit 0  # ruff not available, skip silently
  fi

  # Step 1: Auto-fix (lint + format)
  $RUFF_CMD check --fix "$FILE_PATH" &>/dev/null || true
  $RUFF_CMD format "$FILE_PATH" &>/dev/null || true

  # Step 2: Check for remaining errors
  LINT_OUTPUT=$($RUFF_CMD check "$FILE_PATH" 2>&1 || true)

  if [[ -n "$LINT_OUTPUT" ]] && ! echo "$LINT_OUTPUT" | grep -q "^All checks passed"; then
    emit_context "$(printf 'Ruff lint issues in %s:\n\n%s\n\nPlease fix the above issues.' "$FILE_PATH" "$LINT_OUTPUT")"
  fi

  exit 0
fi

# Other file types: no-op
exit 0
