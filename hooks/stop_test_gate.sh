#!/usr/bin/env bash
# stop_test_gate.sh - Completion Gate Hook (Stop)
#
# Triggered when Claude Code is about to stop (complete its response).
# Runs the project's test suite and forces Claude to continue if tests fail.
#
# Stdin: JSON from Claude Code hook event
# Stdout: JSON with hookSpecificOutput.additionalContext (on failure)
# Exit 0: allow stop
# Exit 2: block stop and inject context (Claude will continue working)

set -euo pipefail

emit_context() {
  local msg="$1"
  printf '{"hookSpecificOutput":{"additionalContext":%s}}' "$(echo "$msg" | jq -Rs .)"
  exit 2  # block stop — force Claude to continue
}

# ── Detect project type and run tests ────────────────────────────────────────

PROJECT_ROOT="${CLAUDE_PROJECT_DIR:-$(pwd)}"

RAN_TESTS=false
TEST_OUTPUT=""
TEST_FAILED=false

# TypeScript / Node.js
if [[ -f "$PROJECT_ROOT/package.json" ]]; then
  # Check if a test script is defined
  HAS_TEST=$(jq -r '.scripts.test // empty' "$PROJECT_ROOT/package.json" 2>/dev/null || true)

  if [[ -n "$HAS_TEST" ]] && [[ "$HAS_TEST" != "echo \"Error: no test specified\" && exit 1" ]]; then
    RAN_TESTS=true
    cd "$PROJECT_ROOT"
    TEST_OUTPUT=$(npm test --silent 2>&1) && true
    TEST_EXIT=${PIPESTATUS[0]:-$?}
    [[ $TEST_EXIT -ne 0 ]] && TEST_FAILED=true
  fi
fi

# Python
if [[ "$RAN_TESTS" == "false" ]]; then
  HAS_PYTEST=false

  if [[ -f "$PROJECT_ROOT/pytest.ini" ]] || \
     [[ -f "$PROJECT_ROOT/pyproject.toml" ]] && grep -q '\[tool.pytest' "$PROJECT_ROOT/pyproject.toml" 2>/dev/null || \
     [[ -f "$PROJECT_ROOT/setup.cfg" ]] && grep -q '\[tool:pytest\]' "$PROJECT_ROOT/setup.cfg" 2>/dev/null; then
    HAS_PYTEST=true
  fi

  if [[ "$HAS_PYTEST" == "true" ]] && command -v pytest &>/dev/null; then
    RAN_TESTS=true
    cd "$PROJECT_ROOT"
    TEST_OUTPUT=$(pytest --tb=short -q 2>&1) && true
    TEST_EXIT=${PIPESTATUS[0]:-$?}
    [[ $TEST_EXIT -ne 0 ]] && TEST_FAILED=true
  fi
fi

# No tests found — allow stop
if [[ "$RAN_TESTS" == "false" ]]; then
  exit 0
fi

# Tests passed — allow stop
if [[ "$TEST_FAILED" == "false" ]]; then
  exit 0
fi

# Tests failed — block stop and inject failure details
emit_context "$(printf 'Tests failed. Please fix the failures before finishing.\n\n%s' "$TEST_OUTPUT")"
