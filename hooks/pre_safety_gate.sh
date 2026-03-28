#!/usr/bin/env bash
# pre_safety_gate.sh - セーフティゲートフック (PreToolUse)
#
# Write/Edit/MultiEdit/Bash ツール呼び出し前にトリガーされる。
# 危険な操作を構造的にブロックする — プロンプトによる上書きは不可。
#
# 標準入力: Claude Code フックイベントの JSON
# 標準出力: 理由メッセージ（ブロック時）
# 終了コード 0: 操作を許可
# 終了コード 2: 操作をブロック（Claude Code はこれをハードブロックとして扱う）

set -euo pipefail

INPUT=$(cat)

TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null || true)

# ── ファイル系ツール: センシティブなファイルパスをブロック ─────────────────────────────
if [[ "$TOOL_NAME" =~ ^(Write|Edit|MultiEdit)$ ]]; then
  FILE_PATH=$(echo "$INPUT" | jq -r '
    .tool_input.file_path //
    .tool_input.path //
    empty
  ' 2>/dev/null || true)

  if [[ -n "$FILE_PATH" ]]; then
    BASENAME=$(basename "$FILE_PATH")
    LOWER=$(echo "$FILE_PATH" | tr '[:upper:]' '[:lower:]')

    # センシティブなファイルをブロック
    BLOCKED=false
    REASON=""

    if [[ "$BASENAME" =~ ^\.(env|envrc)$ ]] || [[ "$BASENAME" =~ \.env\. ]]; then
      BLOCKED=true
      REASON=".env ファイルの編集はセーフティゲートによりブロックされています。代わりに .env.example を使用してください。"
    elif [[ "$LOWER" =~ (secret|credential|private_key|id_rsa|id_ed25519) ]]; then
      BLOCKED=true
      REASON="センシティブな名前（secret/credential/key）を持つファイルの編集はセーフティゲートによりブロックされています。"
    elif [[ "$LOWER" =~ \.(pem|key|p12|pfx)$ ]]; then
      BLOCKED=true
      REASON="証明書/鍵ファイルの編集はセーフティゲートによりブロックされています。"
    fi

    if [[ "$BLOCKED" == "true" ]]; then
      echo "$REASON" >&2
      exit 2
    fi
  fi
fi

# ── Bash ツール: 危険なシェルコマンドをブロック ────────────────────────────────
if [[ "$TOOL_NAME" == "Bash" ]]; then
  COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null || true)

  if [[ -n "$COMMAND" ]]; then
    BLOCKED=false
    REASON=""

    # ルートまたはホームへの rm -rf
    if echo "$COMMAND" | grep -qE 'rm\s+-[a-z]*r[a-z]*f[a-z]*\s+(/\s|/\*|~\s|~/\*)'; then
      BLOCKED=true
      REASON="ルート/ホームディレクトリへの危険な rm -rf はセーフティゲートによりブロックされています。"
    # sudo rm -rf
    elif echo "$COMMAND" | grep -qE 'sudo\s+rm\s+-[a-z]*r'; then
      BLOCKED=true
      REASON="sudo rm -rf はセーフティゲートによりブロックされています。"
    # センシティブなディレクトリへの chmod 777
    elif echo "$COMMAND" | grep -qE 'chmod\s+777\s+/'; then
      BLOCKED=true
      REASON="システムディレクトリへの chmod 777 はセーフティゲートによりブロックされています。"
    # curl/wget を bash/sh に直接パイプ（サプライチェーン攻撃の経路）
    elif echo "$COMMAND" | grep -qE '(curl|wget).+\|\s*(ba)?sh'; then
      BLOCKED=true
      REASON="curl/wget を bash に直接パイプすることはセーフティゲートによりブロックされています。先にスクリプトをダウンロードして内容を確認してください。"
    fi

    if [[ "$BLOCKED" == "true" ]]; then
      echo "$REASON" >&2
      exit 2
    fi
  fi
fi

exit 0
