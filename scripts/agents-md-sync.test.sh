#!/usr/bin/env bash
#
# Regression suite for agents-md-sync.sh.
#
# Each case builds a throwaway git repo in one of the starting states the script
# claims to handle, runs it, and asserts on the resulting index. Cases 4, 7 and 11
# cover bugs that shipped in the first draft and destroyed data or reported a false
# clean; they must keep failing loudly if that behaviour ever comes back.
#
# Usage: scripts/agents-md-sync.test.sh [path/to/agents-md-sync.sh]

set -uo pipefail

SCRIPT="${1:-"$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/agents-md-sync.sh"}"
SCRIPT="$(cd "$(dirname "$SCRIPT")" && pwd)/$(basename "$SCRIPT")"
REAL_GIT="$(command -v git)"

pass=0
fail=0
ok() {
  printf '  PASS %s\n' "$1"
  pass=$((pass + 1))
}
bad() {
  printf '  FAIL %s\n' "$1"
  fail=$((fail + 1))
}
want() { # want <desc> <expected> <actual>
  if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (want '$2', got '$3')"; fi
}

newrepo() {
  cd "$(mktemp -d)" || exit 1
  git init -q .
  git config user.email t@t.t
  git config user.name t
}

mode_of() { git ls-files -s -- "$1" | awk '{print $1; exit}'; }
target_of() { git cat-file blob "$(git ls-files -s -- "$1" | awk '{print $2; exit}')"; }

echo "== 1. only CLAUDE.md -> renamed, symlink left behind =="
newrepo
printf 'content A\n' >CLAUDE.md
git add -A && git commit -qm init
bash "$SCRIPT" --fix >/dev/null
want "AGENTS.md is a regular file" 100644 "$(mode_of AGENTS.md)"
want "CLAUDE.md is a symlink" 120000 "$(mode_of CLAUDE.md)"
want "symlink targets AGENTS.md" "AGENTS.md" "$(target_of CLAUDE.md)"
want "content preserved" "content A" "$(cat AGENTS.md)"
bash "$SCRIPT" --check >/dev/null 2>&1
want "check passes after fix" 0 $?

echo "== 2. only AGENTS.md -> symlink added =="
newrepo
printf 'content B\n' >AGENTS.md
git add -A && git commit -qm init
bash "$SCRIPT" --fix >/dev/null
want "CLAUDE.md symlink created" 120000 "$(mode_of CLAUDE.md)"
want "AGENTS.md untouched" "content B" "$(cat AGENTS.md)"

echo "== 3. backwards symlink AGENTS.md -> CLAUDE.md gets flipped =="
newrepo
printf 'real content\n' >CLAUDE.md
ln -s CLAUDE.md AGENTS.md
git add -A && git commit -qm init
want "precondition: AGENTS.md is the symlink" 120000 "$(mode_of AGENTS.md)"
bash "$SCRIPT" --fix >/dev/null
want "AGENTS.md is now the regular file" 100644 "$(mode_of AGENTS.md)"
want "CLAUDE.md is now the symlink" 120000 "$(mode_of CLAUDE.md)"
want "content survived the flip" "real content" "$(cat AGENTS.md)"

echo "== 4. dangling AGENTS.md symlink, no CLAUDE.md to promote =="
newrepo
printf 'x\n' >CLAUDE.md
ln -s CLAUDE.md AGENTS.md
git add -A && git commit -qm init
git rm -q --cached CLAUDE.md && rm -f CLAUDE.md
git commit -qm "drop CLAUDE.md"
out="$(bash "$SCRIPT" --fix 2>&1)"
rc=$?
want "fix reports failure rather than aborting mid-write" 1 "$rc"
case "$out" in
  *"no CLAUDE.md in the index"*) ok "reports the skip" ;;
  *) bad "no skip message: $out" ;;
esac
want "AGENTS.md not destroyed" 120000 "$(mode_of AGENTS.md)"

echo "== 5. both regular + identical -> collapsed =="
newrepo
printf 'same\n' >AGENTS.md
printf 'same\n' >CLAUDE.md
git add -A && git commit -qm init
bash "$SCRIPT" --fix >/dev/null
want "CLAUDE.md collapsed to a symlink" 120000 "$(mode_of CLAUDE.md)"
want "content kept" "same" "$(cat AGENTS.md)"

echo "== 6. both regular + differing -> refused, nothing destroyed =="
newrepo
printf 'aaa\n' >AGENTS.md
printf 'bbb\n' >CLAUDE.md
git add -A && git commit -qm init
out="$(bash "$SCRIPT" --fix 2>&1)"
rc=$?
want "exits non-zero: the invariant still is not met" 1 "$rc"
case "$out" in
  *"merge them by hand"*) ok "refuses to guess a winner" ;;
  *) bad "expected a refusal: $out" ;;
esac
want "AGENTS.md still a regular file" 100644 "$(mode_of AGENTS.md)"
want "CLAUDE.md still a regular file" 100644 "$(mode_of CLAUDE.md)"
want "AGENTS.md content intact" "aaa" "$(cat AGENTS.md)"
want "CLAUDE.md content intact" "bbb" "$(cat CLAUDE.md)"

echo "== 7. identical in the working tree, differing in the index =="
newrepo
printf 'aaa\n' >AGENTS.md
printf 'bbb\n' >CLAUDE.md
git add -A && git commit -qm init # index: aaa vs bbb
printf 'aaa\n' >CLAUDE.md         # working tree: now identical
out="$(bash "$SCRIPT" --fix 2>&1)"
case "$out" in
  *"merge them by hand"*) ok "judged on indexed blobs, so it still refuses" ;;
  *) bad "collapsed on a working-tree match while index blobs differ: $out" ;;
esac
want "CLAUDE.md not turned into a symlink" 100644 "$(mode_of CLAUDE.md)"

echo "== 8. symlink with the wrong target -> repointed =="
newrepo
printf 'c\n' >AGENTS.md
ln -s ../elsewhere.md CLAUDE.md
git add -A && git commit -qm init
bash "$SCRIPT" --fix >/dev/null
want "symlink repointed at AGENTS.md" "AGENTS.md" "$(target_of CLAUDE.md)"

echo "== 9. nested dirs, paths with spaces, and idempotence =="
newrepo
mkdir -p a/b "weird dir"
printf 'root\n' >CLAUDE.md
printf 'nested\n' >a/b/CLAUDE.md
printf 'spaced\n' >"weird dir/CLAUDE.md"
git add -A && git commit -qm init
bash "$SCRIPT" --fix >/dev/null
want "nested doc flipped" 120000 "$(mode_of a/b/CLAUDE.md)"
want "path with spaces flipped" 120000 "$(mode_of "weird dir/CLAUDE.md")"
want "spaced content preserved" "spaced" "$(cat "weird dir/AGENTS.md")"
out="$(bash "$SCRIPT" --fix 2>&1)"
case "$out" in
  *"nothing to do"*) ok "a second --fix is a no-op" ;;
  *) bad "not idempotent: $out" ;;
esac

echo "== 10. --check catches a CLAUDE.md committed as a regular file =="
newrepo
printf 'z\n' >AGENTS.md
printf 'z\n' >CLAUDE.md
git add -A && git commit -qm init
bash "$SCRIPT" --check >/dev/null 2>&1
want "check fails on a non-symlink CLAUDE.md" 1 $?

echo "== 12. executable AGENTS.md (mode 100755) is still collapsed, not skipped =="
newrepo
printf 'same\n' >AGENTS.md
printf 'same\n' >CLAUDE.md
chmod +x AGENTS.md
git add -A && git commit -qm init
want "precondition: AGENTS.md indexed as 100755" 100755 "$(mode_of AGENTS.md)"
bash "$SCRIPT" --fix >/dev/null
want "CLAUDE.md became a symlink" 120000 "$(mode_of CLAUDE.md)"
bash "$SCRIPT" --check >/dev/null 2>&1
want "check passes afterwards" 0 $?

echo "== 13. --fix never reports success on a state it cannot handle =="
newrepo
printf 'a\n' >AGENTS.md
printf 'b\n' >CLAUDE.md
chmod +x AGENTS.md
git add -A && git commit -qm init
out="$(bash "$SCRIPT" --fix 2>&1)"
case "$out" in
  *"nothing to do"*) bad "claimed 'nothing to do' while --check still fails" ;;
  *) ok "does not claim a clean result" ;;
esac
case "$out" in
  *"merge them by hand"* | *"resolve by hand"*) ok "emits an actionable diagnostic" ;;
  *) bad "no diagnostic for an unhandled state: $out" ;;
esac

echo "== 11. a git failure must never read as a clean result =="
newrepo
printf 'q\n' >CLAUDE.md
git add -A && git commit -qm init
bash "$SCRIPT" --fix >/dev/null
# Shim a git that fails only on `ls-files`, standing in for a broken index or a
# shallow clone missing objects.
shim="$(mktemp -d)"
cat >"$shim/git" <<STUB
#!/usr/bin/env bash
if [ "\${1:-}" = "ls-files" ]; then
  echo "fatal: simulated index failure" >&2
  exit 128
fi
exec "$REAL_GIT" "\$@"
STUB
chmod +x "$shim/git"
out="$(PATH="$shim:$PATH" bash "$SCRIPT" --check 2>&1)"
rc=$?
want "check exits non-zero" 1 "$([ "$rc" -ne 0 ] && echo 1 || echo 0)"
case "$out" in
  *"OK — AGENTS.md is the source of truth"*) bad "false clean: claimed OK while git was failing" ;;
  *) ok "does not claim OK" ;;
esac
out="$(PATH="$shim:$PATH" bash "$SCRIPT" --fix 2>&1)"
rc=$?
want "fix exits non-zero" 1 "$([ "$rc" -ne 0 ] && echo 1 || echo 0)"
case "$out" in
  *"nothing to do"*) bad "false clean: claimed 'nothing to do' while git was failing" ;;
  *) ok "does not claim 'nothing to do'" ;;
esac

echo
printf '=== %d passed, %d failed ===\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
