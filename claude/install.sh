#!/usr/bin/env bash
# Install the Claude Code integration for neovim-plan-review.
#
# Symlinks the ExitPlanMode hook and the launcher into ~/.claude so Claude
# Code opens every plan in Neovim for review before asking for approval.
# Symlinks (the default) stay in sync with `git pull`; pass --copy to copy.
#
# Usage:
#   claude/install.sh            # symlink into ~/.claude
#   claude/install.sh --copy     # copy instead of symlink
#
# The hook entry in ~/.claude/settings.json is printed at the end; add it by
# hand (or with the update-config skill) so this script never edits your
# settings.

set -euo pipefail

mode="symlink"
if [ "${1:-}" = "--copy" ]; then
  mode="copy"
fi

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

hook_src="$root/scripts/plan-review-hook"
launch_src="$root/scripts/plan-review-launch"
hook_dst="$HOME/.claude/hooks/plan-review-hook"
launch_dst="$HOME/.claude/scripts/plan-review-launch"

for f in "$hook_src" "$launch_src"; do
  if [ ! -f "$f" ]; then
    printf 'install: missing source file: %s\n' "$f" >&2
    exit 1
  fi
done

mkdir -p "$HOME/.claude/hooks" "$HOME/.claude/scripts"
chmod +x "$hook_src" "$launch_src"

link_or_copy() {
  local src="$1" dst="$2"
  if [ "$mode" = "copy" ]; then
    cp "$src" "$dst"
  else
    ln -sf "$src" "$dst"
  fi
  printf '  %s -> %s\n' "$dst" "$src"
}

printf 'Installing the plan-review Claude integration (%s):\n' "$mode"
link_or_copy "$hook_src" "$hook_dst"
link_or_copy "$launch_src" "$launch_dst"

cat <<'EOF'

Add this to "hooks" -> "PreToolUse" in ~/.claude/settings.json:

  {
    "matcher": "ExitPlanMode",
    "hooks": [
      {
        "type": "command",
        "command": "~/.claude/hooks/plan-review-hook",
        "timeout": 7200
      }
    ]
  }

Opt out any time with CLAUDE_PLAN_REVIEW=off or `touch ~/.claude/plan-review.off`.
EOF
