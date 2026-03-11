# ai-rules

Focused rule files for AI coding assistants (Claude Code, Cursor, etc.). Each file targets a specific engineering concern so critic agents can enforce standards without context overload.

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
| `ts-engineer.md` | TypeScript type safety: prove types through narrowing, canonical types, boundary validation |

## Design Principles

- **One concern per file** — Each rule file covers a single engineering discipline
- **Actionable, not aspirational** — Rules should let an agent give a clear pass/fail verdict on a piece of code
- **Opinionated** — Generic advice ("write good tests") is useless. These rules take a stance.

## Roadmap

- More rule files (security, error handling, API design)
- `postinstall` script or CLAUDE.md integration for automatic inclusion
- Publish as installable package across thegoodparty projects
