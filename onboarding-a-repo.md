# Onboarding a Repo

Step-by-step checklist for making a GoodParty repo Claude-friendly. Use the templates in this directory.

## Checklist

### 1. Root CLAUDE.md

- [ ] Create `CLAUDE.md` at repo root using `claude-md-template.md`
- [ ] Fill in all `{{placeholders}}` with repo-specific values
- [ ] Verify commands section — run each command to confirm they work
- [ ] Add repo-specific pointer table rows

### 2. Architecture doc

- [ ] Create `docs/architecture.md` using `architecture-md-template.md`
- [ ] Document the stack, module shape, auth, and cross-service edges
- [ ] Add at least one reference module for agents to copy from

### 3. Nested CLAUDE.md files

- [ ] Identify the top 3-5 most-edited directories (use `git log --format= --name-only | head -500 | xargs dirname | sort | uniq -c | sort -rn`)
- [ ] Create `CLAUDE.md` in each using `nested-claude-md-template.md`
- [ ] Keep each under 80 lines

### 4. ADR directory

- [ ] Create `docs/adr/` if it doesn't exist
- [ ] Add at least one ADR for the repo's most non-obvious decision
- [ ] Use `adr-template.md` for the format

### 5. ai-rules submodule

- [ ] Add ai-rules as a git submodule: `git submodule add https://github.com/thegoodparty/ai-rules.git ai-rules`
- [ ] Add a `postinstall` script to auto-init: `"postinstall": "git submodule update --init --recursive"`
- [ ] Reference ai-rules in CLAUDE.md's pointer table

### 6. Skills directory

- [ ] Create `.claude/skills/` if using Claude Code
- [ ] Decide which skills apply — use the decision tree below
- [ ] Copy applicable org-wide skills from `ai-rules/skills/`
- [ ] Add repo-specific skills as needed

### 7. AGENTS.md (conditional)

- [ ] **Only if** this repo is used with Cursor, Codex, or other AI tools besides Claude Code
- [ ] Create `AGENTS.md` at repo root listing which tools are configured and how

## Skill Placement Decision Tree

```
Is this skill useful in every repo regardless of stack?
├── YES → Put it in ai-rules/skills/ (org-wide)
│         Examples: code-review, security-check, pr-description
└── NO
    ├── Is it stack-specific? (e.g., TypeScript, Python, Next.js)
    │   ├── YES → Put it in each repo of that stack (.claude/skills/)
    │   │         Examples: typescript-developer, nestjs-patterns
    │   └── NO
    │       └── Is it specific to one repo's domain?
    │           └── YES → Put it in that repo only (.claude/skills/)
    │                     Examples: prisma-migration, voter-file-query
```

## Verification

After completing the checklist:

1. Run `cat CLAUDE.md` and verify it reads well as a standalone onboarding doc
2. Ask Claude Code: "What does this repo do and how do I run the tests?" — it should answer correctly from CLAUDE.md alone
3. Verify `ai-rules/` submodule is populated: `ls ai-rules/`
4. Check line counts: `wc -l CLAUDE.md docs/architecture.md src/*/CLAUDE.md`
