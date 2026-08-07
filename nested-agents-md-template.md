# Nested AGENTS.md Template

Use this template for `AGENTS.md` files inside subdirectories (e.g., `src/users/AGENTS.md`). These give agents module-level context without reading the whole codebase. Keep under 80 lines.

Each nested `AGENTS.md` gets a `CLAUDE.md` symlink beside it, created by `ai-rules/scripts/agents-md-sync.sh --fix`.

---

````markdown
# {{module-name}}

{{one-line purpose of this module}}

## Key files

| File | Role |
|------|------|
| `{{module}}.module.ts` | {{NestJS module definition / entry point}} |
| `{{module}}.controller.ts` | {{HTTP layer — routes and request handling}} |
| `services/{{module}}.service.ts` | {{Business logic}} |
| `schemas/{{action}}{{Entity}}.schema.ts` | {{Validation schemas}} |

## Patterns

- {{pattern 1 — e.g., "Extends `createPrismaBase(MODELS.User)` for DB access"}}
- {{pattern 2 — e.g., "Uses `@Roles(UserRole.ADMIN)` on admin-only routes"}}
- {{pattern 3 — e.g., "Emits SQS messages via `QueueProducerService`"}}

## Data model

{{list the primary Prisma models / DB tables this module owns}}

- `{{Model}}` — {{one-line description}}

## Gotchas

- {{gotcha 1 — e.g., "Soft-deletes: queries must filter on `deletedAt IS NULL`"}}
- {{gotcha 2 — e.g., "The `status` field is an enum — add new values via migration"}}

## Related modules

- `{{related-module}}` — {{why it's related, e.g., "shares the Campaign model"}}
````
