# AGENTS.md Template

Use this template when creating or upgrading a root `AGENTS.md` for any GoodParty repo. Replace `{{placeholders}}` with repo-specific values. Delete sections that don't apply.

`AGENTS.md` is the single source of truth. Every repo also carries a `CLAUDE.md` symlink beside it so Claude Code picks up the same content — create it with `ai-rules/scripts/agents-md-sync.sh --fix`, never by copying the file.

---

````markdown
# AGENTS.md

Guidance for Claude Code, Cursor, Codex, and other AI agents working in `{{repo-name}}`. Keep this file short — push detail into `docs/`.

## Project

{{one-line description of what this repo is and does, including framework and primary datastore}}

## Commands (most-used first)

```bash
{{dev-server-command}}          # Dev server
{{verify-command}}              # Full verification (lint + typecheck + test)
{{test-command}}                # Tests only
{{single-test-command}}         # Single file test
{{lint-command}}                # Lint
{{lint-fix-command}}            # Auto-fix lint
{{build-command}}               # Production build
```

{{additional commands as needed — migrations, code generation, deploy}}

## Pointer table — when in doubt

| Doing | Read |
|-------|------|
| Adding an endpoint / feature | `docs/architecture.md` |
| Writing or fixing a test | `docs/writing-tests.md` |
| First-time setup | `docs/getting-started.md` |
| Why a thing is the way it is | `docs/adr/` |
| AI rule-by-rule code review | `ai-rules/` (git submodule) |

{{add repo-specific rows as needed}}

## Code style

{{list the key style rules — formatting, linting strictness, naming conventions}}

- {{formatter config reference, e.g. "No semicolons, single quotes, trailing commas (`.prettierrc`)"}}
- {{key lint rules that agents trip on, e.g. "no-explicit-any is an error"}}
- {{path aliases, e.g. "`@/*` → `src/*`"}}
- {{function style preference}}

## Module shape

{{describe the standard directory layout for a feature/module — show the tree}}

```
{{directory tree example}}
```

`{{reference-module}}` is a clean reference to copy.

## Testing

- Framework: **{{test-framework}}**
- Test file pattern: `{{pattern}}`
- {{key testing conventions — env file, mock strategy, patterns}}

Full guide: `docs/writing-tests.md`

## Never

- {{repo-specific prohibitions — list things agents must never do here}}
- {{e.g., "Never edit applied migration files"}}
- {{e.g., "Never disable critical lint rules without justification"}}
- Never edit `CLAUDE.md` directly — it is a symlink to this file.

## Environment

- {{runtime and version, e.g. "Node 22.12.0 (`.nvmrc`)"}}
- {{package manager and version}}
- {{other env notes}}
````
