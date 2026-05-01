#!/usr/bin/env bash
# install.sh — Install ai-rules slash commands into a Claude Code commands dir.
#
# ai-rules is typically a git submodule of each project repo. Installing user-level
# (default) makes commands available in every project; project-level scopes them
# to a single repo.

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: install.sh [symlink|copy] [user|project] [--force] [-h|--help]

  symlink   (default) Symlink each command into the destination — picks up
            updates automatically when the submodule is bumped.
  copy      Copy each command. No auto-update.

  user      (default) Install into $CLAUDE_CONFIG_DIR/commands if set, else
            ~/.claude/commands. Available in every project for that profile.
  project   Install into ./.claude/commands (current repo only).

  --force   Overwrite existing files even if they aren't symlinks managed by us.
  -h        Show this help.

Notes:
  Claude Code resolves slash commands from $CLAUDE_CONFIG_DIR/commands when
  that env var is set (used by setups that run multiple Claude profiles via
  aliases like `CLAUDE_CONFIG_DIR=~/.claude-gp claude`). If your shell sets
  CLAUDE_CONFIG_DIR for the profile you intend to use, run this script under
  that same env so it installs into the right place.

Examples:
  ./install.sh                        # symlink, user-level (honors CLAUDE_CONFIG_DIR)
  ./install.sh copy                   # copy, user-level
  ./install.sh symlink project        # symlink into ./.claude/commands
  CLAUDE_CONFIG_DIR=~/.claude-gp ./install.sh   # explicit profile
EOF
}

MODE="symlink"
SCOPE="user"
FORCE=0

for arg in "$@"; do
  case "$arg" in
    -h|--help)        usage; exit 0 ;;
    --force)          FORCE=1 ;;
    symlink|copy)     MODE="$arg" ;;
    user|project)     SCOPE="$arg" ;;
    *)                echo "Unknown argument: $arg" >&2; usage >&2; exit 1 ;;
  esac
done

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/commands" && pwd)"

case "$SCOPE" in
  user)    DEST="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/commands" ;;
  project) DEST="$(pwd)/.claude/commands" ;;
esac

if [ ! -d "$SRC" ] || ! ls "$SRC"/*.md >/dev/null 2>&1; then
  echo "No command files found in $SRC" >&2
  exit 1
fi

mkdir -p "$DEST"

linked=0
copied=0
skipped=0
clobbered=0

for f in "$SRC"/*.md; do
  name="$(basename "$f")"
  target="$DEST/$name"

  if [ -L "$target" ]; then
    # Already a symlink — replace silently if pointing elsewhere; skip if same.
    current="$(readlink "$target")"
    if [ "$MODE" = "symlink" ] && [ "$current" = "$f" ]; then
      printf '  ok      %s (already linked)\n' "$name"
      skipped=$((skipped + 1)); continue
    fi
    rm "$target"
  elif [ -e "$target" ]; then
    if [ "$FORCE" -eq 0 ]; then
      printf '  WARN    %s exists and is not managed by this script — skipping. Re-run with --force to overwrite.\n' "$name" >&2
      skipped=$((skipped + 1)); continue
    fi
    rm "$target"
    clobbered=$((clobbered + 1))
  fi

  case "$MODE" in
    symlink) ln -s "$f" "$target"; printf '  linked  %-32s -> %s\n' "$name" "$f"; linked=$((linked + 1)) ;;
    copy)    cp    "$f" "$target"; printf '  copied  %s\n' "$name"; copied=$((copied + 1)) ;;
  esac
done

echo
echo "Done. linked=$linked copied=$copied skipped=$skipped clobbered=$clobbered  (dest: $DEST)"
echo
echo "Available commands:"
for f in "$SRC"/*.md; do
  printf '  /%s\n' "$(basename "$f" .md)"
done
echo
echo "Required env vars (set these in your shell profile):"
echo "  export CLICKUP_API_KEY=\"pk_...\"      # ClickUp -> Settings -> Apps -> API Token"
echo "  export CLICKUP_TEAM_ID=\"...\"         # optional: skips a prompt"
echo "  export CLICKUP_LIST_ID=\"...\"         # optional: skips a prompt"
echo
echo "Prerequisites: bash, curl, jq, ripgrep (rg), git. Optional: gh."
