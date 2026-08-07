#!/usr/bin/env bash
#
# agents-md-sync.sh — enforce AGENTS.md as the single source of truth for agent
# context docs, with CLAUDE.md as a symlink pointing at it.
#
# Invariant, for every directory carrying an agent doc:
#
#   AGENTS.md   regular file (mode 100644) — holds the content
#   CLAUDE.md   symlink (mode 120000) whose target is exactly "AGENTS.md"
#
# Usage:
#   agents-md-sync.sh --check    report violations, exit 1 if any (this is what CI runs)
#   agents-md-sync.sh --fix      convert in place and stage the result; idempotent
#
# --check reads the git index rather than the working tree, so a CLAUDE.md that got
# committed as a plain file (e.g. from a machine with core.symlinks=false) is still
# caught even though it looks fine locally.
#
# Submodules are gitlinks, so a parent repo's run never descends into them; each
# repo that vendors ai-rules checks only its own files.

set -euo pipefail

MODE=""

usage() {
  cat <<'EOF'
usage: agents-md-sync.sh (--check | --fix)

  --check   Report every place where AGENTS.md is not the source of truth or
            CLAUDE.md is not a symlink to it. Exits 1 if anything is wrong.
  --fix     Rewrite the repo to satisfy the invariant and stage the changes.
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --check) MODE=check ;;
    --fix) MODE=fix ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      echo "agents-md-sync: unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

if [ -z "$MODE" ]; then
  echo "agents-md-sync: pass --check or --fix" >&2
  usage >&2
  exit 2
fi

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

# Every tracked CLAUDE.md / AGENTS.md, emitted as "<mode><TAB><path>".
# git ls-files -s prints "<mode> <sha> <stage><TAB><path>", so the tab split gives
# us the path intact even when it contains spaces.
list_docs() {
  git ls-files -s | awk -F'\t' '
    $2 ~ /(^|\/)(CLAUDE|AGENTS)\.md$/ { split($1, f, " "); print f[1] "\t" $2 }
  '
}

# Field 1 is the mode, field 2 the blob sha, for one exact path. Empty if untracked.
idx_field() {
  git ls-files -s -- "$1" 2>/dev/null |
    awk -F'\t' -v n="$2" '{ split($1, f, " "); print f[n]; exit }'
}

join_path() {
  if [ "$1" = "." ]; then echo "$2"; else echo "$1/$2"; fi
}

symlink_target() {
  local sha
  sha="$(idx_field "$1" 2)"
  [ -n "$sha" ] && git cat-file blob "$sha"
}

doc_dirs() {
  list_docs | awk -F'\t' '{ print $2 }' | while IFS= read -r p; do
    dirname "$p"
  done | sort -u
}

check() {
  local bad=0 mode path dir base sibling target
  # Collected up front rather than piped in from a process substitution: under
  # `set -e` a failure inside `< <(...)` is invisible to the parent shell, so a
  # broken index would yield an empty loop and a false "OK". A plain assignment
  # propagates the failure and aborts.
  local docs
  docs="$(list_docs)"
  while IFS="$(printf '\t')" read -r mode path; do
    [ -n "${path:-}" ] || continue
    dir="$(dirname "$path")"
    base="$(basename "$path")"

    if [ "$base" = "AGENTS.md" ]; then
      if [ "$mode" = "120000" ]; then
        echo "  $path: AGENTS.md is the source of truth and must be a regular file, not a symlink"
        bad=$((bad + 1))
      fi
      sibling="$(join_path "$dir" CLAUDE.md)"
      if [ -z "$(idx_field "$sibling" 1)" ]; then
        echo "  $path: no CLAUDE.md symlink beside it"
        bad=$((bad + 1))
      fi
    else
      if [ "$mode" != "120000" ]; then
        echo "  $path: CLAUDE.md must be a symlink to AGENTS.md, found a regular file"
        bad=$((bad + 1))
      else
        target="$(symlink_target "$path")"
        if [ "$target" != "AGENTS.md" ]; then
          echo "  $path: CLAUDE.md symlink must target \"AGENTS.md\", found \"$target\""
          bad=$((bad + 1))
        fi
      fi
      sibling="$(join_path "$dir" AGENTS.md)"
      if [ -z "$(idx_field "$sibling" 1)" ]; then
        echo "  $path: no AGENTS.md beside it"
        bad=$((bad + 1))
      fi
    fi
  done <<<"$docs"

  if [ "$bad" -gt 0 ]; then
    echo
    echo "agents-md-sync: $bad problem(s). Run 'agents-md-sync.sh --fix' and commit the result."
    return 1
  fi

  echo "agents-md-sync: OK — AGENTS.md is the source of truth everywhere."
}

# Replace CLAUDE.md in $1 with a symlink to its sibling AGENTS.md.
link_claude() {
  local claude
  claude="$(join_path "$1" CLAUDE.md)"
  rm -f "$claude"
  ln -s AGENTS.md "$claude"
  git add "$claude"
}

fix() {
  local changed=0 dir agents claude amode cmode
  # Same reason as in check(): collect before looping so a failure is fatal
  # rather than silently becoming "nothing to do".
  local dirs
  dirs="$(doc_dirs)"
  while IFS= read -r dir; do
    [ -n "${dir:-}" ] || continue
    agents="$(join_path "$dir" AGENTS.md)"
    claude="$(join_path "$dir" CLAUDE.md)"
    amode="$(idx_field "$agents" 1)"
    cmode="$(idx_field "$claude" 1)"

    # Already correct.
    if [ "$amode" = "100644" ] && [ "$cmode" = "120000" ] &&
      [ "$(symlink_target "$claude")" = "AGENTS.md" ]; then
      continue
    fi

    if [ "$amode" = "120000" ]; then
      # Backwards: AGENTS.md -> CLAUDE.md. The content lives in CLAUDE.md, so drop
      # the symlink, promote CLAUDE.md to AGENTS.md, and relink the other way.
      if [ "$(symlink_target "$agents")" != "CLAUDE.md" ]; then
        echo "  SKIP $agents: symlink targets \"$(symlink_target "$agents")\", not CLAUDE.md — resolve by hand"
        continue
      fi
      # A dangling symlink: the CLAUDE.md holding the content is gone, so there is
      # nothing to promote. Bail before the removals below destroy the symlink too.
      if [ -z "$cmode" ]; then
        echo "  SKIP $agents: symlink to CLAUDE.md, but no CLAUDE.md in the index — resolve by hand"
        continue
      fi
      git rm -q --cached "$agents" >/dev/null
      rm -f "$agents"
      git mv "$claude" "$agents"
      link_claude "$dir"
      echo "  flipped $agents (was a symlink to CLAUDE.md)"
      changed=$((changed + 1))
    elif [ -z "$amode" ] && [ -n "$cmode" ]; then
      # Only CLAUDE.md exists: rename it and leave a symlink behind.
      git mv "$claude" "$agents"
      link_claude "$dir"
      echo "  renamed $claude -> $agents"
      changed=$((changed + 1))
    elif [ -n "$amode" ] && [ -z "$cmode" ]; then
      link_claude "$dir"
      echo "  added $claude symlink"
      changed=$((changed + 1))
    elif [ "$amode" = "100644" ] && [ "$cmode" = "100644" ]; then
      # Both are real files. Only safe to collapse when they already agree, judged
      # on the indexed blobs: comparing working-tree files would read stale content
      # under a sparse checkout or a staged-but-not-checked-out change, and
      # collapsing on a false match loses whichever copy differs.
      if [ "$(idx_field "$agents" 2)" = "$(idx_field "$claude" 2)" ]; then
        link_claude "$dir"
        echo "  collapsed duplicate $claude into a symlink"
        changed=$((changed + 1))
      else
        echo "  SKIP $dir: AGENTS.md and CLAUDE.md are both real files with different content — merge them by hand"
      fi
    elif [ "$cmode" = "120000" ]; then
      # Symlink with the wrong target.
      link_claude "$dir"
      echo "  repointed $claude at AGENTS.md"
      changed=$((changed + 1))
    fi
  done <<<"$dirs"

  if [ "$changed" -eq 0 ]; then
    echo "agents-md-sync: nothing to do."
  else
    echo "agents-md-sync: updated $changed director(ies); changes are staged."
  fi
}

case "$MODE" in
  check) check ;;
  fix) fix ;;
esac
