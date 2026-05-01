<!-- v1 — 2026-04-30 -->
# Work on a ClickUp Task

Pull a ClickUp task (typically one created by `/clickup-epic-create`), load its Epic-level plan if available, set up a focused working context, and start implementing. Designed to feel like "open a ticket and just go" — but with the safety nets of a clear scope confirmation, todo list seeded from acceptance criteria, and explicit verification before claiming done.

## Arguments
- `$ARGUMENTS`: Optional. A ClickUp task ID, full URL (`https://app.clickup.com/t/abc123`), or empty (will prompt).

## Configuration

| Variable             | Default                    | Description                                            |
| -------------------- | -------------------------- | ------------------------------------------------------ |
| `CLICKUP_API_KEY`    | _(required)_               | Personal API token                                     |
| `CLICKUP_PLANS_DIR`  | `~/.claude/plans`          | Where Epic-level plans live (created by epic-create)   |

## Instructions

### Resolve Configuration

Read env vars and apply defaults. If `CLICKUP_API_KEY` is unset, stop. **Never** echo the key.

---

### Phase 1: Load the Task

1. **Parse the task ID** from `$ARGUMENTS`. Accept raw IDs (`abc123`) and full URLs (`https://app.clickup.com/t/abc123`). If missing, ask: "Which ClickUp task? (paste an ID or URL)".

2. **Fetch the task** with markdown body and parent context:
   ```bash
   curl -s -H "Authorization: $CLICKUP_API_KEY" \
     "https://api.clickup.com/api/v2/task/$TASK_ID?include_markdown_description=true"
   ```
   Capture: `name`, `status`, `priority`, `markdown_description`, `parent`, `list.id`, `assignees`, `tags`, `url`.

3. **If `parent` is non-null**, this is a subtask of an Epic. Fetch the Epic too (same endpoint with parent's ID) so the user gets a one-line "this task lives under '<epic title>'" context.

4. **Load the local plan**, if present, at `$CLICKUP_PLANS_DIR/<parent_id>-plan.md` (or `$CLICKUP_PLANS_DIR/<task_id>-plan.md` if the task is itself the Epic). The plan often has architecture notes and a dependency graph that aren't in the individual task ticket.

   If no plan exists, that's fine — proceed without it, but mention to the user. The task itself should be self-contained per the Quality Bar.

---

### Phase 2: Orient

5. **Print a focused brief** to the user:
   ```
   Task: <task title>  (<priority>, <status>)
   Epic: <epic title>  (if applicable)
   List: <list name>
   URL:  https://app.clickup.com/t/<task_id>

   Acceptance criteria:
     [ ] ...
     [ ] ...

   Test plan:
     - <one-line summary of unit/integration/manual>

   Implementation snapshot:
     Files to touch: <files listed in the task body>
     Dependencies on other tasks: <ids if listed>

   Plan loaded? <yes from $CLICKUP_PLANS_DIR/...-plan.md  |  no — proceeding from task body alone>
   ```

   Pull this directly from the task's `markdown_description` if it follows the standard format. If the task uses a different format (e.g., it predates `/clickup-epic-create`), summarize what *is* there and explicitly note "this ticket doesn't follow our standard sections — I'll work from what's available."

6. **Verify the working repo.** Look for the design doc / repo references in the loaded plan or task body. If a repo path is named, confirm it exists locally:
   ```bash
   [ -d "<repo path>" ] && echo "Repo present" || echo "Missing — clone or cd to the right project first"
   ```
   If we're not in the right repo (`pwd` ≠ the named repo path), tell the user and offer to `cd` there before continuing. Don't start editing files in the wrong place.

7. **Check task dependencies.** Source of truth is the **API response's `.dependencies`** array (frontmatter is stripped before tasks are POSTed to ClickUp, so the body in ClickUp will not contain a `dependencies:` block). For each `task_id` in `.dependencies[].depends_on`, fetch its status:

   ```bash
   for dep in $(jq -r '.dependencies[].depends_on' <<<"$TASK_JSON"); do
     curl -s -H "Authorization: $CLICKUP_API_KEY" \
       "https://api.clickup.com/api/v2/task/$dep" \
     | jq -r '"\(.id)\t\(.status.status)\t\(.name)"'
   done
   ```

   If any are not in a `closed` / `done`-type status, warn the user — they may want to do those first or accept that this task may be blocked partway through.

8. **Confirm scope with the user** before doing any work. Present the brief plus four explicit options — don't ask an open-ended "anything to adjust?" — most users won't know which levers exist:

   > Going to:
   > - Implement: <one-line summary>
   > - Touching: <list of files>
   > - Verifying via: <test plan summary>
   >
   > How would you like to proceed?
   > - **`go`** — implement the plan as written
   > - **`plan`** — review or update the implementation approach first (we'll iterate before any code changes)
   > - **`focus <part>`** — implement just one part of the task (e.g., `focus tests`, `focus migration`)
   > - **`split`** — this task is too big; help me break it into smaller pieces (no ClickUp changes yet, just the breakdown)

   Wait for an explicit choice. Don't proceed silently.

   - **`go`** → continue to Phase 3.
   - **`plan`** → walk the implementation details with the user, edit the loaded plan file in memory, then re-confirm.
   - **`focus <part>`** → restrict the todo list to the named slice of AC. Note in the final report that the rest is deferred.
   - **`split`** → produce a proposed breakdown (titles + one-line scope per piece) and offer to feed it into `/clickup-epic-edit` to add the new subtasks. **Do not** create tickets directly here — that's what `/clickup-epic-edit` is for.

---

### Phase 3: Plan and Implement

9. **Seed a todo list from the acceptance criteria.** Each AC checkbox becomes a todo. Add prep todos at the front (e.g., "scan files X, Y to confirm current pattern") and verification todos at the back (e.g., "run unit tests", "manual verification per task body"). Update todos as you go — never batch.

10. **Follow the implementation details from the task body.** They were drafted to be enough; if they aren't, that's a real signal — surface the gap to the user rather than papering over it with guessing. Common moves:
    - Read the referenced files first; confirm the pattern the ticket says to follow actually exists.
    - If a file path in the ticket is wrong (renamed/moved/deleted), fix it as you go and mention this to the user — the ticket may need a small correction back in ClickUp.
    - Stick to the scope. New ideas / nice-to-haves go in `Notes / Gotchas` for later, not into this PR.

11. **Run the test plan as written.** If unit tests exist for the touched code, run only those for fast feedback during development; run the broader suite once you think you're done. Don't claim "tests pass" without seeing the actual command output.

---

### Phase 4: Verify and Wrap

12. **Walk the acceptance criteria** as a checklist before declaring done:
    - For each `[ ]`, demonstrate it's met (test output, manual run, or the code change itself).
    - If any AC can't be met as written, stop and ask the user — either revise the AC, split out a follow-up, or rethink the approach. Don't silently downgrade.

13. **Offer to update ClickUp** with progress / completion. Don't update silently — the user may want to control timing / phrasing:

    > Want me to:
    > - Post a comment summarizing the work? (recommended — links the PR / commit, lists what was done)
    > - Move the task to status `<next status>`? (e.g., `in review`, `done`)
    > - Tick any of the AC checkboxes in the description?

    Build payloads with `jq -n` (comment text and status names contain user-supplied content):

    ```bash
    # Comment:
    PAYLOAD="$(jq -n --arg text "$COMMENT_TEXT" \
      '{comment_text: $text, notify_all: false}')"
    curl -s -X POST \
      -H "Authorization: $CLICKUP_API_KEY" \
      -H "Content-Type: application/json" \
      -d "$PAYLOAD" \
      "https://api.clickup.com/api/v2/task/$TASK_ID/comment"
    ```

    For status changes, **don't hardcode the status name** — different lists have different status sets. Fetch the list's available statuses, present them to the user, then PUT the chosen one:

    ```bash
    # Discover valid statuses:
    curl -s -H "Authorization: $CLICKUP_API_KEY" \
      "https://api.clickup.com/api/v2/list/$LIST_ID" \
    | jq -r '.statuses[].status'

    # Apply the user's choice:
    PAYLOAD="$(jq -n --arg status "$CHOSEN_STATUS" '{status: $status}')"
    curl -s -X PUT \
      -H "Authorization: $CLICKUP_API_KEY" \
      -H "Content-Type: application/json" \
      -d "$PAYLOAD" \
      "https://api.clickup.com/api/v2/task/$TASK_ID"
    ```

14. **Offer to update the local Epic plan** — the plan is a living document, not a one-shot artifact. If a plan was loaded from `$CLICKUP_PLANS_DIR/...`, ask whether to refresh it now:

    > Want me to update `<plan path>` to reflect what we did?
    > - Mark this task's AC as completed in the plan's task list
    > - Note any deviations from the plan (we did X instead of Y because Z)
    > - Update the **Open Questions** section (resolved → drop; new ones surfaced → add)
    > - Bump `lastEdited:` in the frontmatter

    If yes, edit the plan file directly. Keep deviations honest — if we worked around something, say so. The next person picking up an adjacent task in this Epic will read the plan first; bad info there poisons the whole flow.

    If no plan was loaded (the task wasn't created via `/clickup-epic-create`), skip this step.

15. **Final report.**
    - Files changed (one line each)
    - Tests run + result
    - AC status (✓ all met, or list the unmet ones)
    - ClickUp updates applied (if any)
    - Plan file updates (if any)
    - Suggested next step: "Open a PR?" / "Move on to task `<next id>` (next in dep graph)?" / "Run `/clickup-epic-edit <epic id>` to update the Epic if scope shifted" — pick what's actually applicable, not all three.

---

## Important Notes

- **Don't commit or push** unless the user explicitly asks. Many users (per personal preference) commit themselves.
- **Don't claim AC are met without verification.** Run the actual tests, do the actual manual check. Evidence before assertions.
- **Don't expand scope** mid-implementation. If the task body is wrong or incomplete, tell the user and let them decide whether to expand the ticket or split a follow-up.
- **Don't post to ClickUp silently** — always offer the option and let the user pick.
- **Use `markdown_description` (not `description`)** when reading the task body via the API. The plain `description` returns HTML.
- If the loaded task doesn't follow the standard `/clickup-epic-create` format, that's OK — work from what's there, but tell the user up front so they're not surprised when the brief looks thinner than usual.
