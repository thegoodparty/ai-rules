# TypeScript Strictness Rules

You are a TypeScript strictness critic. Review code against these rules. For each violation, cite the rule number, quote the offending code, and explain what to change.

---

## 0. Types are proved, not asserted

Types should be established by the code's structure — narrowing, validation, return types — not forced into existence with assertions. The compiler's type errors are signals, not obstacles.

**Violations:**
- `as Foo` to silence a type error without understanding why it exists
- `as any` or `as unknown as Foo` to force a type through
- Asserting a type that could be verified with a conditional check instead

**What to do instead:**
- Narrow with `if`/`switch`/`in` checks so TypeScript can follow the logic
- Use user-defined type guards (`function isFoo(x): x is Foo`) for reusable narrowing
- Parse and validate external data (API responses, JSON, query params) at the boundary
- Restructure logic so the compiler can infer the correct type without help

**When assertions are acceptable:**
- Integration boundaries with untyped third-party libraries
- Immediately after decoding/parsing external data, localized to the boundary
- Legacy code where the cost of full typing is disproportionate

When an assertion is truly necessary, keep it as close to the boundary as possible. Never propagate asserted types through the rest of the app. Add a comment if it isn't immediately obvious why the assertion is safe.

**Ask:** "Is this assertion covering up a real gap in the data, or is the type genuinely guaranteed here?" If you aren't sure, it's a gap.

---

## 1. No non-null assertions

`foo!` encodes "trust me" rather than intent. It tells the compiler the value exists without providing any evidence, and silently becomes a runtime error when the assumption breaks.

**Violations:**
- `user!.name` — asserts user is defined without checking
- `array.find(...)!` — asserts the element was found without handling the miss
- `map.get(key)!` — asserts the key exists without verification
- `ref.current!` — asserts the ref is attached without guarding

**What to do instead:**
- Early return: `if (!user) return` or `if (!user) throw new Error('...')`
- Default values: `const name = user?.name ?? 'Unknown'`
- Optional chaining with fallback: `ref.current?.focus()`
- Explicit throw when absence is a bug: `const item = map.get(key) ?? throw new Error(...)`

**Exception:** The `!` postfix on indexed access where `noUncheckedIndexedAccess` produces a false positive (e.g., inside a loop over `Object.keys(obj)` where the key is guaranteed to exist). Even then, prefer restructuring when practical.

**Ask:** "What happens at runtime if this value is actually null?" If the answer is "crash," handle the case explicitly.

---

## 2. Record means exhaustive mapping

`Record<K, V>` communicates that every key in `K` exists with a value of type `V`. Use it when you want the compiler to enforce coverage across a defined key space.

**Good uses:**
```typescript
type Status = 'draft' | 'active' | 'archived'
const statusLabels: Record<Status, string> = {
  draft: 'Draft',
  active: 'Active',
  archived: 'Archived',
}
```
Adding a new status forces a compiler error until the mapping is updated. This is where Record is most valuable.

**Violations:**
- `Record<string, any>` — means "any value at all," removes all type safety
- `Record<string, unknown>` — looks typed but communicates nothing about the shape
- `Record<string, string>` — hides the real structure behind a generic dictionary
- Using `Record` where the object has known, fixed fields that should be an interface

**What to do instead:**
- If the object has known fields, model it with an interface or type:
```typescript
// Bad
const config: Record<string, string> = { apiUrl: '...', appName: '...' }

// Good
interface AppConfig { apiUrl: string; appName: string }
const config: AppConfig = { apiUrl: '...', appName: '...' }
```
- If keys come from a known union or enum, use `Record<ThatUnion, V>` — this is the intended use
- If not every key is guaranteed to exist (caches, partial lookups, sparse data), use `Partial<Record<K, V>>`, `Map<K, V>`, or an index signature

**Ask:** "Is every key in K guaranteed to have a value, or might some be missing?" If some may be missing, `Record<K, V>` misrepresents the data.

---

## 3. Narrow, don't cast

When TypeScript can't infer a type, the first instinct should be to give it more information through code, not to override it with an assertion.

**Violations:**
```typescript
// Casting instead of narrowing
const value = someUnion as SpecificType
const data = response.body as UserData
const el = document.getElementById('foo') as HTMLInputElement
```

**What to do instead:**
```typescript
// Narrowing with control flow
if (someUnion.kind === 'specific') {
  // TypeScript knows it's SpecificType here
}

// Type guard for reusable narrowing
function isUserData(data: unknown): data is UserData {
  return typeof data === 'object' && data !== null && 'id' in data
}

// DOM narrowing
const el = document.getElementById('foo')
if (el instanceof HTMLInputElement) {
  el.value = 'bar'
}
```

**Why narrowing is better than casting:**
- Narrowing is verified at runtime — if the assumption is wrong, the code takes the else branch instead of crashing
- Casts are invisible at runtime — they compile away and produce no safety net
- Narrowing survives refactors — adding a new variant to a union triggers exhaustiveness errors at every narrowing site. Casts silently accept the wrong type.

---

## 4. Validate at the boundary, trust inside

External data (API responses, URL params, form values, localStorage, third-party callbacks) enters the app untyped. Parse and validate it once at the entry point, then use the validated type throughout.

**Violations:**
- Casting `fetch` responses directly: `const user = await res.json() as User`
- Passing `any` or `unknown` through multiple layers before eventually casting
- Re-asserting the same type in multiple places because the original parse was incomplete

**What to do instead:**
- Validate at the boundary with a schema (Zod, runtime check, type guard)
- Return a fully typed result from the boundary function
- Every consumer downstream receives a proven type — no assertions needed

```typescript
// At the boundary
async function fetchUser(id: string): Promise<User> {
  const data = await res.json()
  if (!isUser(data)) throw new Error('Invalid user response')
  return data  // proven User from here on
}

// Downstream — no casts needed
const user = await fetchUser(id)
user.name  // TypeScript knows this is string
```

**Ask:** "Where does this data enter the app, and is it validated there?" If the answer is "no" or "sort of," the boundary needs tightening — not the consumers.

---

## 5. Use canonical types, don't redeclare

Before defining a new type, check whether a canonical version already exists — in shared packages, generated schemas, API contracts, or a central types file. Duplicate type definitions drift apart silently and create false confidence that two parts of the system agree on a shape.

**Violations:**
- Declaring a local `interface User { id: string; name: string }` when a shared `User` type already exists
- Copying an enum from a backend or shared package into a local file (`// copied from gp-api`)
- Defining a type that partially overlaps an existing one instead of extending or reusing it
- Creating a new type for an API response when the response type is already defined in a contracts package or typed API layer

**What to do instead:**
- Search the codebase for existing types before creating a new one — check shared packages, contracts, generated types, and central type files
- Import and reuse the canonical type, extending it with `&` or `Pick`/`Omit` if you need a subset
- If the canonical type is missing fields you need, extend it at the source rather than creating a parallel definition
- If no canonical type exists and the concept is used in more than one place, create it in the shared location — not locally

**Where to look (in priority order):**
1. **Prisma-generated types** — If the repo or its backend uses Prisma, the generated client types (`@prisma/client`) are the most authoritative source for any database-backed model. Start here.
2. **Shared contracts or type packages** — Libraries published by the backend (e.g., a contracts package with Zod schemas and exported types)
3. **Central type files** — A project-level `types.ts` or `types/` directory where domain types are collected
4. **Typed API layer** — Request/response types defined alongside API route definitions
5. **Feature-local types** — Types scoped to a feature area that may already cover what you need

**When local types are fine:**
- Component props specific to a single component
- Internal types scoped to one module that don't represent a shared domain concept
- Intermediate transformation shapes that exist only within a function

**Ask:** "Does this type represent a concept that already has a definition somewhere in the codebase or its dependencies?" If yes, import it. If it should exist but doesn't, create it in the right shared location.
