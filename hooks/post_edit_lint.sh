#!/usr/bin/env bash
# post_edit_lint.sh - 品質ループフック (PostToolUse)
#
# Write/Edit/MultiEdit ツール呼び出し後にトリガーされる。
# 変更されたファイルに対してリンターを実行し、エラーを additionalContext として注入することで
# Claude がすぐに修正できるようにする。
#
# 標準入力: Claude Code フックイベントの JSON
# 標準出力: hookSpecificOutput.additionalContext を含む JSON（エラー時）
# 終了コード 0: 成功（lint エラーがあっても — ブロックせず報告のみ）

set -euo pipefail

# ── 標準入力のパース ──────────────────────────────────────────────────────────────
INPUT=$(cat)

# ツール入力からファイルパスを取得（Write/Edit/MultiEdit はすべて file_path を持つ）
FILE_PATH=$(echo "$INPUT" | jq -r '
  .tool_input.file_path //
  .tool_input.path //
  empty
' 2>/dev/null || true)

if [[ -z "$FILE_PATH" ]]; then
  exit 0
fi

# 相対パスの場合は絶対パスに変換
if [[ "$FILE_PATH" != /* ]]; then
  FILE_PATH="$(pwd)/$FILE_PATH"
fi

# ファイルが存在しなければならない
if [[ ! -f "$FILE_PATH" ]]; then
  exit 0
fi

# ── 言語検出 ───────────────────────────────────────────────────────
EXT="${FILE_PATH##*.}"

emit_context() {
  local msg="$1"
  printf '{"hookSpecificOutput":{"additionalContext":%s}}' "$(echo "$msg" | jq -Rs .)"
  exit 0
}

# ── TypeScript / JavaScript ──────────────────────────────────────────────────
if [[ "$EXT" =~ ^(ts|tsx|js|jsx|mts|cts)$ ]]; then
  if ! command -v biome &>/dev/null && ! npx --yes biome --version &>/dev/null 2>&1; then
    exit 0  # biome が利用不可のため、静かにスキップ
  fi

  BIOME_CMD="biome"
  command -v biome &>/dev/null || BIOME_CMD="npx biome"

  # ステップ1: 自動修正
  $BIOME_CMD check --write "$FILE_PATH" &>/dev/null || true

  # ステップ2: 残存エラーの確認
  LINT_OUTPUT=$($BIOME_CMD check "$FILE_PATH" 2>&1 || true)

  if echo "$LINT_OUTPUT" | grep -qE '(error|warning)'; then
    # クリーンな出力のために ANSI エスケープコードを除去
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
    exit 0  # ruff が利用不可のため、静かにスキップ
  fi

  # ステップ1: 自動修正（lint + フォーマット）
  $RUFF_CMD check --fix "$FILE_PATH" &>/dev/null || true
  $RUFF_CMD format "$FILE_PATH" &>/dev/null || true

  # ステップ2: 残存エラーの確認
  LINT_OUTPUT=$($RUFF_CMD check "$FILE_PATH" 2>&1 || true)

  if [[ -n "$LINT_OUTPUT" ]] && ! echo "$LINT_OUTPUT" | grep -q "^All checks passed"; then
    emit_context "$(printf 'Ruff lint issues in %s:\n\n%s\n\nPlease fix the above issues.' "$FILE_PATH" "$LINT_OUTPUT")"
  fi

  exit 0
fi

# その他のファイル種別: 何もしない
exit 0
