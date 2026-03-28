#!/usr/bin/env bash
# install.sh - d-harness-plugin インストーラ
#
# Usage:
#   bash install.sh [--target-dir <path>] [--settings <path>] [--dry-run]
#
# Defaults:
#   --target-dir  ~/.claude/harness-plugin
#   --settings    ~/.claude/settings.json

set -euo pipefail

# ── Colors ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()    { echo -e "${GREEN}[harness]${NC} $*"; }
warn()    { echo -e "${YELLOW}[harness]${NC} $*"; }
error()   { echo -e "${RED}[harness]${NC} $*" >&2; }

# ── Argument parsing ─────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_DIR="${HOME}/.claude/harness-plugin"
SETTINGS_FILE="${HOME}/.claude/settings.json"
DRY_RUN=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --target-dir) TARGET_DIR="$2"; shift 2 ;;
    --settings)   SETTINGS_FILE="$2"; shift 2 ;;
    --dry-run)    DRY_RUN=true; shift ;;
    *) error "Unknown option: $1"; exit 1 ;;
  esac
done

info "Installing d-harness-plugin..."
info "  Source:   $SCRIPT_DIR"
info "  Target:   $TARGET_DIR"
info "  Settings: $SETTINGS_FILE"
[[ "$DRY_RUN" == "true" ]] && warn "  (dry-run mode — no files will be written)"

# ── Dependency check ─────────────────────────────────────────────────────────
check_dep() {
  local cmd="$1" install_hint="$2"
  if command -v "$cmd" &>/dev/null; then
    info "  ✓ $cmd"
  else
    warn "  ✗ $cmd not found — $install_hint"
  fi
}

echo ""
info "Checking dependencies:"
check_dep jq    "apt install jq  /  brew install jq"
check_dep biome "npm install -g @biomejs/biome  (TypeScript linting)"
check_dep ruff  "pip install ruff  (Python linting)"
check_dep pytest "pip install pytest  (Python tests)"
echo ""

# ── Copy hook scripts ─────────────────────────────────────────────────────────
if [[ "$DRY_RUN" == "false" ]]; then
  mkdir -p "$TARGET_DIR/hooks"
  cp "$SCRIPT_DIR/hooks/post_edit_lint.sh"  "$TARGET_DIR/hooks/"
  cp "$SCRIPT_DIR/hooks/pre_safety_gate.sh" "$TARGET_DIR/hooks/"
  cp "$SCRIPT_DIR/hooks/stop_test_gate.sh"  "$TARGET_DIR/hooks/"
  chmod +x "$TARGET_DIR/hooks/"*.sh
  info "Hook scripts copied to $TARGET_DIR/hooks/"
else
  info "[dry-run] Would copy hooks to $TARGET_DIR/hooks/"
fi

# ── Merge settings.json ───────────────────────────────────────────────────────
PLUGIN_SETTINGS=$(sed "s|__HARNESS_DIR__|${TARGET_DIR}|g" "$SCRIPT_DIR/settings.json")

if [[ "$DRY_RUN" == "false" ]]; then
  # Create settings.json if it doesn't exist
  if [[ ! -f "$SETTINGS_FILE" ]]; then
    mkdir -p "$(dirname "$SETTINGS_FILE")"
    echo '{}' > "$SETTINGS_FILE"
  fi

  CURRENT=$(cat "$SETTINGS_FILE")

  # Deep merge: merge hooks arrays, preserving existing entries
  MERGED=$(echo "$CURRENT" "$PLUGIN_SETTINGS" | jq -s '
    .[0] as $existing |
    .[1] as $new |
    $existing | . + {
      "hooks": (
        ($existing.hooks // {}) as $eh |
        ($new.hooks // {}) as $nh |
        {
          "PreToolUse":  (($eh.PreToolUse  // []) + ($nh.PreToolUse  // []) | unique_by(.hooks[0].command)),
          "PostToolUse": (($eh.PostToolUse // []) + ($nh.PostToolUse // []) | unique_by(.hooks[0].command)),
          "Stop":        (($eh.Stop        // []) + ($nh.Stop        // []) | unique_by(.hooks[0].command))
        }
      )
    }
  ')

  echo "$MERGED" > "$SETTINGS_FILE"
  info "Merged hooks into $SETTINGS_FILE"
else
  info "[dry-run] Would merge hooks into $SETTINGS_FILE"
  echo ""
  info "Merged result preview:"
  DUMMY_CURRENT='{}'
  echo "$DUMMY_CURRENT" "$PLUGIN_SETTINGS" | jq -s '.[0] * .[1]'
fi

echo ""
info "Installation complete!"
info "Restart Claude Code to activate the harness."
