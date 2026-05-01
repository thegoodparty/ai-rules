# ai-rules

Focused rule files **and** Claude Code slash commands for AI coding assistants. Rule files target specific engineering concerns so critic agents can enforce standards without context overload. Commands wrap recurring workflows (creating ClickUp Epics from design docs, picking up tickets, etc.) so they're one slash away in any repo that uses this submodule.

## Usage

### Manual prompt

The simplest approach — tell your AI assistant to read the rules and apply them:

```
Read ai-rules/test-engineer.md and review my tests against those rules
```

### Subagent / critic

Spawn a dedicated review agent with the rule file as its prompt. In Claude Code:

```
Spawn a code-critic agent with the contents of ai-rules/test-engineer.md as its system prompt.
Review the test files changed in this PR.
```

This keeps the critic focused on one concern without polluting your main conversation context.

### Claude Code hooks

Run a critic automatically on every commit or PR using [Claude Code hooks](https://docs.anthropic.com/en/docs/claude-code/hooks). Add to `.claude/settings.json`:

```json
{
  "hooks": {
    "PostCommit": [
      {
        "command": "claude -p 'Read ai-rules/test-engineer.md. Review the test files in this diff: $(git diff HEAD~1 --name-only | grep test). For each violation, cite the rule number and quote the code.'"
      }
    ]
  }
}
```

### CLAUDE.md integration

Reference rule files from your project's `CLAUDE.md` so they're always loaded:

```markdown
## Code Review Rules
When reviewing or writing tests, follow the rules in `ai-rules/test-engineer.md`.
```

### Custom agent definitions

Create a reusable agent in `.claude/agents/test-critic.md`:

```markdown
You are a test engineer critic.

Read and apply all rules from ai-rules/test-engineer.md to the code under review.
For each violation, cite the rule number, quote the offending code, and explain what to change.
End with a verdict: PASS, PASS WITH NOTES, or FAIL.
```

Then invoke it: `@test-critic review the tests in this PR`

## Rule Files

| File | Focus |
|------|-------|
| `test-engineer.md` | Test quality: behavior-driven tests, unit-first approach, pragmatic edge cases |
| `breaking-changes.md` | Breaking changes: trace callers of changed code, flag incompatible usage |
| `bugs.md` | Bug detection: null access, async mistakes, logic errors, silent failures |
| `code-duplication.md` | Duplication critic: search the codebase for existing code that does the same thing |
| `security.md` | Security: injection prevention, auth, secrets, dependencies, SSRF, cryptography |
| `ts-engineer.md` | TypeScript type safety: prove types through narrowing, canonical types, boundary validation |

## Slash Commands

Markdown prompt-workflows under `commands/`. Each one becomes a `/<name>` slash command in Claude Code once installed.

| Command                | Purpose                                                                       |
| ---------------------- | ----------------------------------------------------------------------------- |
| `clickup-epic-create`  | Generate a ClickUp Epic + Claude-Code-ready subtasks from a design doc + repo |
| `clickup-epic-edit`    | Edit an existing Epic and its subtasks via a snapshot/diff/apply flow         |
| `work-on-clickup`      | Pull a ClickUp task, load its plan, scope-confirm, and start implementation   |

### Install

```bash
# Default: symlink into ~/.claude/commands (user-level, available in every project)
./install.sh

# Copy instead of symlink (no auto-update on `git submodule update`)
./install.sh copy

# Project-level only (./.claude/commands in the current repo)
./install.sh symlink project

# Overwrite an existing non-symlink at the destination
./install.sh --force
```

If `ai-rules` is a submodule, the install path becomes `<project>/ai-rules/install.sh`. Run it once per machine — symlinks pick up updates automatically when the submodule is bumped. Re-runs are idempotent (already-correct symlinks are skipped). If a destination file exists and isn't a symlink we created, the script warns and skips unless you pass `--force`.

#### Multi-profile setups (`CLAUDE_CONFIG_DIR`)

If you run multiple Claude Code profiles via aliases like `CLAUDE_CONFIG_DIR=~/.claude-foo claude`, slash commands must live under that profile's commands dir, not `~/.claude/commands/`. The install script honors `CLAUDE_CONFIG_DIR` when set, so run it under the same env as the profile you're targeting:

```bash
CLAUDE_CONFIG_DIR=~/.claude-foo ./install.sh
# or with an alias that already sets it:
claude-foo-install   # if you alias `CLAUDE_CONFIG_DIR=~/.claude-foo /path/to/install.sh`
```

If you've installed into the wrong dir, just `rm` the stale symlinks (they're harmless but won't do anything for that profile) and re-run with the correct env.

### Prerequisites

The commands shell out to: `bash`, `curl`, `jq`, `ripgrep` (`rg`), `git`. `gh` is optional (only used by `/clickup-epic-create`'s investigate phase). Install on macOS:

```bash
brew install jq ripgrep gh
```

### Required env vars

Set these in your shell profile (`~/.zshrc` / `~/.bashrc`):

```bash
export CLICKUP_API_KEY="pk_..."     # ClickUp → Settings → Apps → API Token
export CLICKUP_TEAM_ID="..."        # optional: skips a prompt
export CLICKUP_LIST_ID="..."        # optional: skips a prompt
```

Optional overrides: `CLICKUP_DRAFTS_DIR` (default `~/.claude/drafts/clickup`), `CLICKUP_PLANS_DIR` (default `~/.claude/plans`), `CLICKUP_REPOS_DIR` (default `~/.claude/repos`), `CLICKUP_EDITOR` (default `code`).

**Never commit your `CLICKUP_API_KEY` or any other secret to this repo.**

## Design Principles

- **One concern per file** — Each rule or command file covers a single engineering discipline or workflow
- **Actionable, not aspirational** — Rules should let an agent give a clear pass/fail verdict; commands should produce a concrete artifact, not advice
- **Opinionated** — Generic advice ("write good tests") is useless. These files take a stance.

## Roadmap

- More rule files (error handling, API design)
- More commands (PR review automation, test scaffolding, plan execution)
- `postinstall` hook or CLAUDE.md integration so submodule update auto-installs new commands
