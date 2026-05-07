# Architecture Template

Use this template when creating `docs/architecture.md` for any GoodParty repo. Replace `{{placeholders}}` with repo-specific values. Delete sections that don't apply.

---

````markdown
# Architecture

A pointer-heavy doc. Detailed conventions live in `CLAUDE.md` and repo-specific rule files.

## Stack

- {{framework and version}}
- {{ORM / data layer}}
- {{validation approach}}
- {{async / queue system, if any}}
- {{observability stack}}
- {{infra / deploy tooling}}

## Module shape

{{describe the standard directory layout for a feature/module}}

```
{{directory tree example}}
```

`{{reference-module}}` is a clean reference module — start there if you need a pattern to copy.

## Auth

{{describe the auth chain — guards, decorators, token types}}

## Cross-service edges

{{list all services this repo talks to or is called by}}

| Direction | Service | Protocol | Auth |
|-----------|---------|----------|------|
| {{inbound/outbound}} | {{service}} | {{HTTP/SQS/DB}} | {{auth method}} |

Shared types flow through `{{contracts package or mechanism}}`.

## Bootstrap

{{describe how the app starts — entry point, global config, middleware}}

## Key patterns

{{list 2-5 patterns unique to this repo that an agent needs to know}}

- {{pattern 1}}: {{one-line explanation + pointer to docs/adr}}
- {{pattern 2}}: {{one-line explanation}}

## ADRs

See `docs/adr/` for non-obvious decisions.
````
