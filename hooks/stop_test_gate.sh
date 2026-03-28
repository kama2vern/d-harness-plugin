#!/usr/bin/env bash
# stop_test_gate.sh - 完了ゲートフック (Stop)
#
# Claude Code が停止しようとする（応答を完了する）際にトリガーされる。
# プロジェクトのテストスイートを実行し、テストが失敗した場合は Claude に作業を続けさせる。
#
# 標準入力: Claude Code フックイベントの JSON
# 標準出力: hookSpecificOutput.additionalContext を含む JSON（失敗時）
# 終了コード 0: 停止を許可
# 終了コード 2: 停止をブロックしてコンテキストを注入（Claude は作業を継続する）

set -euo pipefail

emit_context() {
  local msg="$1"
  printf '{"hookSpecificOutput":{"additionalContext":%s}}' "$(echo "$msg" | jq -Rs .)"
  exit 2  # 停止をブロック — Claude に作業を継続させる
}

# ── プロジェクト種別の検出とテスト実行 ────────────────────────────────────────

PROJECT_ROOT="${CLAUDE_PROJECT_DIR:-$(pwd)}"

RAN_TESTS=false
TEST_OUTPUT=""
TEST_FAILED=false

# TypeScript / Node.js
if [[ -f "$PROJECT_ROOT/package.json" ]]; then
  # テストスクリプトが定義されているか確認
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

# テストが見つからなかった場合 — 停止を許可
if [[ "$RAN_TESTS" == "false" ]]; then
  exit 0
fi

# テスト成功 — 停止を許可
if [[ "$TEST_FAILED" == "false" ]]; then
  exit 0
fi

# テスト失敗 — 停止をブロックして失敗の詳細を注入
emit_context "$(printf 'テストが失敗しました。終了する前に失敗を修正してください。\n\n%s' "$TEST_OUTPUT")"
