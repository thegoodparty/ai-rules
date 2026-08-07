# ai-rules

Two things: (1) review-time critics that enforce engineering standards, and (2) the org-wide AI context layer — system map, repo index, templates, and shared skills for onboarding repos to be Claude-friendly.

## Context Layer

Org-wide AI context that helps agents understand GoodParty's architecture before touching code.

| File | Purpose |
|------|---------|
| `system-map.md` | How all 10 active repos connect (ASCII diagram + edge table) |
| `repo-index.md` | Every repo at a glance — language, role, doc links |
| `cross-repo-flows.md` | Multi-repo sequences (onboarding, plan generation, outreach, etc.) |
| `agents-md-template.md` | Template for root `AGENTS.md` in any repo |
| `architecture-md-template.md` | Template for `docs/architecture.md` |
| `nested-agents-md-template.md` | Template for subdirectory `AGENTS.md` files (≤80 lines) |
| `adr-template.md` | Template for Architecture Decision Records |
| `onboarding-a-repo.md` | Step-by-step checklist for making a repo Claude-friendly |
| `scripts/agents-md-sync.sh` | Enforces AGENTS.md as the source of truth (`--check` / `--fix`) |
| `skills/` | Org-wide skills usable in any repo (code-review, security-check, pr-description) |

## AGENTS.md is the source of truth

Agent context docs live in `AGENTS.md`. Claude Code looks for `CLAUDE.md`, so every
directory with an `AGENTS.md` also carries a `CLAUDE.md` **symlink** pointing at it.
One file, one copy, no drift — and every tool reads the same content.

```
AGENTS.md    regular file, holds the content
CLAUDE.md -> AGENTS.md
```

Never create `CLAUDE.md` by copying. Let the script do it:

```bash
ai-rules/scripts/agents-md-sync.sh --check   # CI runs this; exits 1 on violations
ai-rules/scripts/agents-md-sync.sh --fix     # converts in place, idempotent
```

`--check` inspects the git index rather than the working tree, so a `CLAUDE.md`
committed as a plain file from a machine without symlink support is still caught.

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

### AGENTS.md integration

Reference rule files from your project's `AGENTS.md` so they're always loaded:

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
| `performance.md` | Performance: real CPU cycles and roundtrips over Big-O, latency-adds, cache locality, allocations, render/network budgets |
| `performance-tools.md` | Performance tooling cookbook: copy-paste commands for hyperfine, autocannon, `node --prof`, `EXPLAIN ANALYZE`, Lighthouse, bundle analysis |
| `security.md` | Security: injection prevention, auth, secrets, dependencies, SSRF, cryptography |
| `ts-engineer.md` | TypeScript type safety: prove types through narrowing, canonical types, boundary validation |

## Design Principles

- **One concern per file** — Each rule file covers a single engineering discipline
- **Actionable, not aspirational** — Rules should let an agent give a clear pass/fail verdict on a piece of code
- **Opinionated** — Generic advice ("write good tests") is useless. These rules take a stance.

## Roadmap

- More rule files (error handling, API design)
- Publish as installable package across thegoodparty projects
- Additional org-wide skills as patterns emerge
