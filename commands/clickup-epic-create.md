<!-- v1 — 2026-04-30 -->
# Create a ClickUp Epic from a Design Doc

Take a design doc plus the relevant repo, scan the codebase, and break the work into a coherent **Epic with N well-scoped subtasks**. Each subtask ships with its own context, implementation details, acceptance criteria, and test plan — so any single one can be handed straight to Claude Code and produce high-quality code without further excavation.

This is deliberately an **Epic-orchestration** command, not a single-ticket command. The whole point is the breakdown: turning a design doc into a structured set of Claude-Code-ready tasks with explicit dependencies. For one-off tickets, just use ClickUp directly — the ceremony here only earns its keep when there are multiple tasks to coordinate. (Pair with `/clickup-epic-edit` to revise an existing Epic and `/work-on-clickup` to pick up a single subtask once the Epic is created.)

## Arguments
- `$ARGUMENTS`: Optional. Can be:
  - Free-text initial context (e.g., `~/docs/auth-redesign.md https://github.com/acme/api`)
  - `resume` — list staged drafts and pick one to continue
  - `resume <slug>` — resume a specific staged draft by slug (partial match OK)

## Configuration

These environment variables can be set to override defaults:

| Variable             | Default                    | Description                                                |
| -------------------- | -------------------------- | ---------------------------------------------------------- |
| `CLICKUP_API_KEY`    | _(required)_               | Personal API token (ClickUp → Settings → Apps)             |
| `CLICKUP_TEAM_ID`    | _(prompted if unset)_      | Workspace (team) ID                                        |
| `CLICKUP_LIST_ID`    | _(prompted if unset)_      | Default List ID where the Epic will be created             |
| `CLICKUP_DRAFTS_DIR` | `~/.claude/drafts/clickup` | Where draft directories are staged                         |
| `CLICKUP_PLANS_DIR`  | `~/.claude/plans`          | Where Epic-level plans are saved after creation            |
| `CLICKUP_REPOS_DIR`  | `~/.claude/repos`          | Where public repos are cloned for analysis                 |
| `CLICKUP_EDITOR`     | `code`                     | Command used to open draft files for review                |

## Instructions

### Resolve Configuration

Before doing anything else, read the environment variables and apply defaults. Run:

```bash
echo "CLICKUP_DRAFTS_DIR=${CLICKUP_DRAFTS_DIR:-$HOME/.claude/drafts/clickup}"
echo "CLICKUP_PLANS_DIR=${CLICKUP_PLANS_DIR:-$HOME/.claude/plans}"
echo "CLICKUP_REPOS_DIR=${CLICKUP_REPOS_DIR:-$HOME/.claude/repos}"
echo "CLICKUP_EDITOR=${CLICKUP_EDITOR:-code}"
echo "CLICKUP_API_KEY is ${CLICKUP_API_KEY:+set}${CLICKUP_API_KEY:-NOT SET}"
echo "CLICKUP_TEAM_ID=${CLICKUP_TEAM_ID:-<unset>}"
echo "CLICKUP_LIST_ID=${CLICKUP_LIST_ID:-<unset>}"
```

If `CLICKUP_API_KEY` is not set, stop and tell the user to export it before continuing. **Never** echo the key value itself or include it in any draft file.

Use the resolved values for all paths and commands throughout this workflow.

---

### Phase 0: Check for Staged Drafts

1. **If `$ARGUMENTS` starts with `resume`:**
   - List directories under `$CLICKUP_DRAFTS_DIR` that contain an `epic.md`.
   - If a slug was given (e.g., `resume auth-redesign`), match against directory names (partial match OK).
   - If multiple matches or no slug, show the user a table of available drafts (slug, epic title, target list, staged date — pulled from each `epic.md` frontmatter) and ask which one to load.
   - Read the chosen draft directory: `epic.md`, every `tasks/*.md`, and `plan.md`.
   - **Skip to Phase 5 (Review Loop)** with the loaded content.
   - If no staged drafts exist, say so and proceed to Phase 1.

---

### Phase 1: Gather Inputs

2. **Get the design doc.** From `$ARGUMENTS` or by asking. Accept any of:
   - **Local file path** → read it (`cat`, or use the file-reading skill for PDFs/DOCX).
   - **URL** → fetch it (web_fetch, or `curl` for Confluence/Notion exports the user has access to).
   - **Pasted text** → use as-is.

   Confirm you have it by summarizing in 2–3 sentences and asking "Did I understand the design correctly?" Don't proceed until the user confirms.

3. **Get the GitHub repo.** From `$ARGUMENTS` or by asking. Accept either:
   - **Local checkout path** (e.g., `~/code/api`) → use directly.
   - **Public repo URL** → clone shallowly into `$CLICKUP_REPOS_DIR/<repo-name>`:
     ```bash
     mkdir -p "$CLICKUP_REPOS_DIR"
     [ -d "$CLICKUP_REPOS_DIR/<repo-name>" ] \
       && (cd "$CLICKUP_REPOS_DIR/<repo-name>" && git pull --ff-only) \
       || git clone --depth 50 <url> "$CLICKUP_REPOS_DIR/<repo-name>"
     ```
   Remember the resolved local path as `$REPO_PATH` for the rest of the workflow.

4. **Resolve ClickUp targets.**
   - If `$CLICKUP_TEAM_ID` is unset, fetch teams and ask the user to pick one:
     ```bash
     curl -s -H "Authorization: $CLICKUP_API_KEY" \
       https://api.clickup.com/api/v2/team
     ```
   - If `$CLICKUP_LIST_ID` is unset, ask the user for the target List ID, or help them navigate Spaces → Folders → Lists via:
     ```bash
     curl -s -H "Authorization: $CLICKUP_API_KEY" \
       "https://api.clickup.com/api/v2/team/$CLICKUP_TEAM_ID/space?archived=false"
     # then for a chosen space:
     curl -s -H "Authorization: $CLICKUP_API_KEY" \
       "https://api.clickup.com/api/v2/space/<space_id>/list?archived=false"
     # and for folders:
     curl -s -H "Authorization: $CLICKUP_API_KEY" \
       "https://api.clickup.com/api/v2/space/<space_id>/folder?archived=false"
     ```
   - **Detect Epic task type.** Some workspaces have a custom task type called "Epic". Check:
     ```bash
     curl -s -H "Authorization: $CLICKUP_API_KEY" \
       "https://api.clickup.com/api/v2/team/$CLICKUP_TEAM_ID/custom_item"
     ```
     If a "Epic" custom item exists, capture its `id` as `$EPIC_CUSTOM_ITEM_ID` for use later. If not, the Epic will be a regular parent task.

---

### Phase 2: Codebase Reconnaissance

5. **Map the design doc to the codebase.** Don't draft tickets blind — spend a few tool calls building a mental model. From the design doc, extract concepts (entities, endpoints, components, flows) and find where they live in `$REPO_PATH`:

   ```bash
   # Lay of the land
   ls "$REPO_PATH"
   cat "$REPO_PATH/README.md" 2>/dev/null | head -100

   # Detect language/framework signals
   ls "$REPO_PATH" | grep -E '^(package\.json|pyproject\.toml|go\.mod|Cargo\.toml|Gemfile|composer\.json|build\.gradle)$'

   # Test framework signals
   rg -n --no-heading -g '!node_modules' '(jest|vitest|pytest|rspec|go test|cargo test)' "$REPO_PATH" | head -20

   # Find each concept from the design doc
   rg -n --no-heading -g '!node_modules' '<concept>' "$REPO_PATH" | head -30
   ```

   Build a short internal map: which files/modules will the work touch? What patterns does the existing code follow (e.g., handler structure, DB access pattern, how new endpoints are wired)? Skim 1–2 representative files per area.

6. **Briefly summarize what you learned to the user** — language, framework, testing setup, where the work will land. This catches misunderstandings early.

---

### Phase 3: Question Round

7. **Ask focused questions** to fill the gaps the design doc and codebase don't cover. Ask only what you genuinely need — don't interrogate. Typical gaps:
   - **Granularity preference**: "Roughly how many tasks should this break into? (e.g., 3–5 chunky, or 8–15 atomic)"
   - **Sequencing**: "Strict serial dependencies, or parallelizable where possible?"
   - **Out of scope**: "Anything explicitly *not* in scope for this Epic?"
   - **Conventions to honor**: "Any patterns in this codebase I should mimic, or any to avoid?"
   - **Testing expectations**: "What level of test coverage per task — unit only, or integration too? Anything currently untested I shouldn't bother adding tests for?"
   - **Priority/timeline**: "Target completion? Any tasks more urgent than others?"
   - **Reviewers/assignees**: "Anyone specific to assign or @-mention?"

   Skip any question already answered by the design doc, `$ARGUMENTS`, or the codebase scan. Batch the rest into one message.

8. **Confirm the Epic title, then generate a slug.** Don't silently invent a title from the design doc — propose one and let the user correct.

   > Proposed Epic title: **<title>**. OK, or what would you prefer?

   Once confirmed, derive the slug:
   - Lowercase, hyphenate, strip non-alphanumerics, truncate to 50 chars.
   - Example: "User authentication redesign" → `user-authentication-redesign`.

9. **Check for similar existing drafts** in `$CLICKUP_DRAFTS_DIR`:
   - Read the frontmatter of every `*/epic.md`.
   - If any look related (similar title, same target list), ask the user before proceeding: "I found a staged draft that looks related: `<slug>` — '<title>' (staged <date>). Same Epic, or new one?"
   - If same: load it and skip to Phase 5. If new: pick a more specific slug.
   - **Hard collision** (the chosen slug exactly matches an existing draft directory) — append `-2`, `-3`, ... until free, and tell the user which slug was used. Never overwrite a staged draft silently.

---

### Phase 4: Draft the Epic and Tasks

10. **Create the draft directory:**
    ```bash
    mkdir -p "$CLICKUP_DRAFTS_DIR/<slug>/tasks"
    ```

11. **Draft `epic.md`** at `$CLICKUP_DRAFTS_DIR/<slug>/epic.md`. The Epic ticket itself is for humans planning and tracking — it should be readable by a PM. Keep implementation specifics in the task tickets, not the Epic.

    ````markdown
    ---
    type: epic
    slug: <slug>
    title: <Epic title>
    clickupTeamId: <team id>
    clickupListId: <list id>
    epicCustomItemId: <id or empty>
    designDoc: <path or URL>
    githubRepo: <url or path>
    staged: <YYYY-MM-DD>
    ---

    # <Epic title>

    ## Summary
    One paragraph: what this Epic delivers and why.

    ## Goals
    - Concrete, testable outcomes.

    ## Non-Goals
    - Things explicitly out of scope.

    ## Success Metrics
    - How we'll know this worked.

    ## Task Breakdown
    1. **<task title>** — one-line summary
    2. **<task title>** — one-line summary
    ...

    ## Links
    - Design doc: <link>
    - Repo: <link>
    ````

12. **Draft each task** as `$CLICKUP_DRAFTS_DIR/<slug>/tasks/<NN>-<task-slug>.md`, where `NN` is a zero-padded order number (`01`, `02`, ...).

    Every task **must** include all six sections below. This is the bar for "Claude-Code-ready":

    ````markdown
    ---
    type: task
    order: <NN>
    title: <Task title>
    priority: <urgent|high|normal|low>
    estimateHours: <number or empty>
    dependencies: [<order numbers of tasks this depends on>]
    tags: [<tag>, <tag>]
    assignee: <username or empty>
    ---

    # <Task title>

    ## Context
    Why this task exists. One short paragraph linking back to the Epic goal it serves. If the design doc has a section that motivates this task, quote the gist (in your own words).

    ## Implementation Details
    The technical *how*. Be specific enough that a competent engineer (or Claude Code) can execute without re-deriving design decisions.

    **Files to touch:**
    - `path/to/file.ext` — what changes here
    - `path/to/another.ext` — what changes here

    **Approach:**
    1. Step-by-step plan, in order.
    2. Reference existing patterns in the repo where applicable (e.g., "follow the pattern in `auth/middleware.go`").
    3. Note specific function signatures, schema changes, API shapes where they're decided.

    **Dependencies / data flow:**
    - New libraries, env vars, config keys.
    - Migration ordering, if any.

    ## Acceptance Criteria
    Checkable, behavioral conditions. Use `- [ ]` checkboxes.

    - [ ] Specific observable outcome 1
    - [ ] Specific observable outcome 2
    - [ ] Edge case X is handled (describe behavior)

    ## Test Plan
    **Unit tests** (in `<test dir>` following `<framework>`):
    - Test case: <what it asserts>
    - Test case: <what it asserts>

    **Integration tests** (if applicable):
    - Scenario: <setup → action → expected result>

    **Manual verification:**
    - Step: <what to do, what to look for>

    ## Notes / Gotchas
    - Edge cases, perf considerations, things easy to get wrong.
    - Open questions (flag explicitly; don't hide them).
    ````

    Quality bar — before moving on, self-check each task:
    - Could a competent engineer who hasn't read the design doc execute this in one sitting? If no, add detail or split it.
    - Are file paths real (verified against the repo scan)? Don't fabricate.
    - Are acceptance criteria observable, not internal? "Feature works" is not acceptance criteria.
    - Is the test plan specific to the project's actual framework, not generic?
    - Does it depend on tasks that will exist? Reference them by `order` number.

13. **Draft `plan.md`** at `$CLICKUP_DRAFTS_DIR/<slug>/plan.md` — the Epic-level technical plan. This is for local reference, not posted to ClickUp:

    ````markdown
    ---
    epic: <slug>
    designDoc: <path or URL>
    githubRepo: <url or path>
    ---

    # Implementation Plan: <Epic title>

    ## Architecture Notes
    Cross-cutting decisions that span multiple tasks. Why we chose X over Y.

    ## Dependency Graph
    Text or ASCII showing task ordering and parallelization opportunities.

    ## Migration / Rollout
    If applicable: backfills, feature flags, deploy ordering.

    ## Open Questions
    Things still unresolved. Flag the task(s) they affect.

    ## Risks
    Things that could go wrong, mitigations.
    ````

---

### Phase 5: Review Loop

14. **Open the draft directory in the editor:**
    ```bash
    "$CLICKUP_EDITOR" "$CLICKUP_DRAFTS_DIR/<slug>"
    ```

15. **Tell the user what's open and present options:**

    > Drafted **1 Epic + N tasks** at `$CLICKUP_DRAFTS_DIR/<slug>/`. Edit the files directly in your editor if you'd like. When ready:
    >
    > - **`good`** — create the Epic and all tasks in ClickUp
    > - **`edit`** — tell me what to change (I'll update the files)
    > - **`investigate`** — I should dig deeper before finalizing (re-scan the repo, fetch related ClickUp tasks, etc.)
    > - **`stage`** — save and resume later via `/clickup-epic-create resume`

16. **If `edit`:** apply the requested changes to whichever files are affected. Re-open the directory if helpful. Loop back to step 15.

17. **If `investigate`:** ask what to dig into. Common useful moves:
    - Re-scan specific files in the repo for missed details.
    - Pull existing ClickUp tasks in the target list to learn naming/format conventions:
      ```bash
      curl -s -H "Authorization: $CLICKUP_API_KEY" \
        "https://api.clickup.com/api/v2/list/$CLICKUP_LIST_ID/task?archived=false&page=0" \
        | head -200
      ```
    - Fetch related design docs the user mentions.
    - Search the repo's PR history if `gh` is available: `gh pr list --search "<query>" --repo <owner/repo>`.
    Update drafts based on findings, then loop back to step 15.

18. **If `stage`:** confirm "Staged as `<slug>`. Resume with `/clickup-epic-create resume <slug>`." and **stop**. Don't create anything in ClickUp.

19. **If `good`:** **re-read every file from disk** before submitting — the user may have edited them in the editor. Parse:
    - `epic.md` frontmatter and body
    - Every `tasks/*.md` in numeric order, frontmatter and body
    - `plan.md` body

---

### Phase 6: Create in ClickUp

> **JSON safety — read before any POST/PUT.** Task and Epic bodies contain quotes, backticks, and newlines. **Never** template values into a JSON heredoc — build every payload with `jq -n` and pipe it into `curl -d @-`. If you find yourself writing `"name": "<title>"` literally, stop and use `jq -n --arg name "$TITLE" '{name: $name}'` instead.

20. **Create the Epic.** POST to the target list. If `epicCustomItemId` is set in the frontmatter, include it; otherwise create a regular task.

    ```bash
    EPIC_BODY="$(awk '/^---$/{n++; next} n>=2' epic.md)"   # strip frontmatter

    PAYLOAD="$(
      jq -n \
        --arg name "$EPIC_TITLE" \
        --arg desc "$EPIC_BODY" \
        --argjson custom "${EPIC_CUSTOM_ITEM_ID:-null}" \
        '{name: $name, markdown_description: $desc}
         + (if $custom == null then {} else {custom_item_id: $custom} end)'
    )"

    EPIC_TASK_ID="$(
      curl -s -X POST \
        -H "Authorization: $CLICKUP_API_KEY" \
        -H "Content-Type: application/json" \
        -d "$PAYLOAD" \
        "https://api.clickup.com/api/v2/list/$CLICKUP_LIST_ID/task" \
      | jq -r '.id // empty'
    )"

    [ -n "$EPIC_TASK_ID" ] || { echo "Epic create failed"; exit 1; }
    ```

    If the call fails (`.id` empty / response has `.err`), surface the raw response to the user and stop — don't create orphan subtasks.

21. **Create each Task** as a subtask of the Epic, in `order` order. Map priority strings to ClickUp's 1–4 scale: `urgent=1`, `high=2`, `normal=3`, `low=4`. **Don't** send `tags` on create — many workspaces silently drop unknown tags via this field. Attach tags in step 22 instead.

    ```bash
    TASK_BODY="$(awk '/^---$/{n++; next} n>=2' "tasks/$file")"

    PAYLOAD="$(
      jq -n \
        --arg name   "$TASK_TITLE" \
        --arg desc   "$TASK_BODY" \
        --arg parent "$EPIC_TASK_ID" \
        --argjson priority   "${TASK_PRIORITY:-null}" \
        --argjson estimateMs "${TASK_ESTIMATE_MS:-null}" \
        '{name: $name, markdown_description: $desc, parent: $parent}
         + (if $priority   == null then {} else {priority: $priority} end)
         + (if $estimateMs == null then {} else {time_estimate: $estimateMs} end)'
    )"

    TASK_ID="$(
      curl -s -X POST \
        -H "Authorization: $CLICKUP_API_KEY" \
        -H "Content-Type: application/json" \
        -d "$PAYLOAD" \
        "https://api.clickup.com/api/v2/list/$CLICKUP_LIST_ID/task" \
      | jq -r '.id // empty'
    )"
    ```

    Capture each returned task `id`, keyed by `order` number, so dependencies and tag attachment can reference real IDs in the next steps.

22. **Attach tags per task.** For each tag in the task's frontmatter, call the per-task tag endpoint (this auto-creates space-level tags if they don't exist):

    ```bash
    for tag in "${TASK_TAGS[@]}"; do
      curl -s -X POST -H "Authorization: $CLICKUP_API_KEY" \
        "https://api.clickup.com/api/v2/task/$TASK_ID/tag/$(jq -rn --arg t "$tag" '$t|@uri')"
    done
    ```

23. **Wire up dependencies.** For each task with a non-empty `dependencies` list in its frontmatter, resolve each `order` number to its real ClickUp ID (from step 21) and POST:

    ```bash
    PAYLOAD="$(jq -n --arg dep "$DEPENDENCY_TASK_ID" '{depends_on: $dep}')"
    curl -s -X POST \
      -H "Authorization: $CLICKUP_API_KEY" \
      -H "Content-Type: application/json" \
      -d "$PAYLOAD" \
      "https://api.clickup.com/api/v2/task/$TASK_ID/dependency"
    ```

    Failures here are non-fatal — log and continue, surface in the final report. ClickUp rate-limits at ~100 req/min on lower tiers; if you see HTTP 429, `sleep 2` and retry once.

---

### Phase 7: Save Plan, Clean Up, Report

24. **Save the Epic-level plan** to `$CLICKUP_PLANS_DIR/<EPIC_TASK_ID>-plan.md`:
    ```bash
    mkdir -p "$CLICKUP_PLANS_DIR"
    ```
    Add frontmatter on top of the `plan.md` body:
    ```markdown
    ---
    epic: <EPIC_TASK_ID>
    epicTitle: <epic title>
    listId: <list id>
    teamId: <team id>
    tasks:
      - { id: <task_id>, order: 01, title: "<...>" }
      - { id: <task_id>, order: 02, title: "<...>" }
    designDoc: <path or URL>
    githubRepo: <url or path>
    created: <YYYY-MM-DD>
    ---
    ```

25. **Clean up the staged draft directory:**
    ```bash
    rm -rf "$CLICKUP_DRAFTS_DIR/<slug>"
    ```

26. **Report to the user:**
    - Epic: `<title>` — `<EPIC_TASK_ID>` — `https://app.clickup.com/t/<EPIC_TASK_ID>`
    - Tasks: bulleted list with `<id>`, title, and link
    - Any dependency-wire failures
    - Plan saved at `$CLICKUP_PLANS_DIR/<EPIC_TASK_ID>-plan.md`
    - Suggest next step: "Hand a task to Claude Code with `/work-on-clickup <task_id>`, or just open the task in ClickUp and copy its description into a fresh Claude Code session."

---

## Quality Bar (read this before drafting)

Tasks that go through this command must clear all of:

1. **Self-contained.** A reader who hasn't seen the design doc or the repo can execute the task from the ticket alone.
2. **Real, not invented.** Every file path, function name, and pattern reference must come from the actual repo scan, not pattern-matched from training data.
3. **Atomic.** A task does one coherent thing. If "and then" appears in the title, split it.
4. **Testable.** Acceptance criteria describe externally observable behavior. The test plan names the actual framework and points at the test directory that exists in this repo.
5. **Honest about uncertainty.** Open questions go in `Notes / Gotchas` explicitly — never papered over.

If any drafted task fails this bar, fix it before opening the editor for the user. Burning a review cycle on obvious gaps is a worse experience than taking one more pass.

---

## Important Notes

- **Never** echo, log, or write `$CLICKUP_API_KEY` to any draft, plan, or output file. It lives only in the env and curl headers.
- **Always** use `markdown_description` (not `description`) in the ClickUp API payload — `description` ignores formatting.
- **Always** re-read the draft files from disk before posting to ClickUp; the user may have edited them in their editor.
- The Epic-level plan (`plan.md`) is for local use only and is **not** posted to ClickUp. Implementation details that *do* belong in ClickUp go inside each task ticket.
- Staged draft directories persist under `$CLICKUP_DRAFTS_DIR` until the Epic is created (then cleaned up) or manually removed.
- If the repo is large, prefer targeted `rg` queries over reading whole directories. The agent's context is finite — spend it on the files that matter.
- If the design doc references endpoints/screens/entities that **don't** exist in the repo, that's a finding worth surfacing to the user before drafting tasks for them.
