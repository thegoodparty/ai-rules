<!-- v1 — 2026-04-30 -->
# Edit an Existing ClickUp Epic

Make structured changes to an existing Epic and its child tasks: edit content, add or remove tasks, change priorities or dependencies. Same drafts-then-apply pattern as `/clickup-epic-create` so you can review the full diff before anything hits ClickUp.

## Arguments
- `$ARGUMENTS`: Optional. Either:
  - A ClickUp task ID or URL (e.g., `abc123` or `https://app.clickup.com/t/abc123`) — load that Epic
  - `resume` — list staged edit drafts and pick one to continue
  - `resume <slug>` — resume a specific staged edit draft (partial match OK)

## Configuration

Same env vars as `/clickup-epic-create`. Required: `CLICKUP_API_KEY`. Defaults: `CLICKUP_DRAFTS_DIR=~/.claude/drafts/clickup`, `CLICKUP_PLANS_DIR=~/.claude/plans`, `CLICKUP_EDITOR=code`.

## Instructions

### Resolve Configuration

Read env vars and apply defaults exactly as in `/clickup-epic-create`. If `CLICKUP_API_KEY` is unset, stop and tell the user.

---

### Phase 0: Resume or Load

1. **If `$ARGUMENTS` starts with `resume`:** find matching `*/epic.md` under `$CLICKUP_DRAFTS_DIR` whose frontmatter has `mode: edit`. Load it (epic.md, tasks/*.md, plan.md, plus the snapshot dir described in step 4). **Skip to Phase 3 (Review Loop).**

2. **Otherwise**, parse `$ARGUMENTS` for a task ID. Accept raw IDs and full ClickUp URLs (`https://app.clickup.com/t/<id>` → `<id>`). If missing, ask.

---

### Phase 1: Fetch Current State

3. **Fetch the Epic with subtasks.** Use `include_subtasks=true` and `include_markdown_description=true` so we get the markdown source, not the rendered HTML:

   ```bash
   curl -s -H "Authorization: $CLICKUP_API_KEY" \
     "https://api.clickup.com/api/v2/task/$EPIC_TASK_ID?include_subtasks=true&include_markdown_description=true"
   ```

   Verify the response is actually an Epic (or at minimum a parent task with children). If `parent` is non-null, warn the user — they may have given you a child task ID by mistake — and offer to switch to its parent.

4. **Stage current state as a snapshot + working drafts.** The snapshot lets us diff later; the working drafts are what the user edits.

   ```bash
   slug="<derived from epic title>"
   # Brace expansion does NOT happen inside quotes — keep braces unquoted.
   mkdir -p "$CLICKUP_DRAFTS_DIR/$slug-edit"/{snapshot/tasks,tasks}
   ```

   Write **both** versions (identical at first):
   - `snapshot/epic.md`, `snapshot/tasks/<NN>-<task-slug>.md` — frozen baseline, do not edit
   - `epic.md`, `tasks/<NN>-<task-slug>.md` — the user's working copy

   The snapshot file frontmatter must include the live ClickUp `id` for each task and the Epic, so we can match files to server records during apply:

   ```markdown
   ---
   type: epic
   mode: edit
   slug: <slug>
   clickupId: <epic id>
   clickupListId: <list id>
   originalName: <name as fetched>
   loadedAt: <ISO timestamp>
   ---
   ```

   For each subtask, frontmatter mirrors the create command's task format **plus** `clickupId: <task id>` and `originalOrder: <position from server>`.

   Bodies are the `markdown_description` returned by the API. If it doesn't have the standard sections (`## Context`, `## Implementation Details`, etc.), preserve whatever's there — don't fabricate sections to match the template. Just note in the user-facing summary that the existing tasks use a different format.

5. **Load the local plan if it exists.** Look for `$CLICKUP_PLANS_DIR/<EPIC_TASK_ID>-plan.md` and copy it to `plan.md` in the draft directory. If absent, create a stub from what we know.

6. **Show the user the loaded state:** Epic title, child task count, list/space, link to ClickUp, and one-line summary per task. Then explain the options in Phase 2.

---

### Phase 2: Edit

7. **Open the draft directory in the editor:**
   ```bash
   "$CLICKUP_EDITOR" "$CLICKUP_DRAFTS_DIR/<slug>-edit"
   ```

8. **Ask the user what to do.** Common operations — pick or combine:
   - **Edit existing task content** → user edits `tasks/<NN>-*.md` directly (or asks you to)
   - **Edit Epic body** → user edits `epic.md`
   - **Add a new task** → create a new file `tasks/<NN>-<slug>.md` with frontmatter `clickupId:` empty (it's a new record). Use the next free order number.
   - **Remove a task** → delete the file from `tasks/`. Don't touch the snapshot.
   - **Reorder tasks** → only changes display order in the local plan; ClickUp doesn't have a reliable subtask order field, so we won't try to reorder server-side. Mention this if the user asks.
   - **Change priority/tags/dependencies** → edit the frontmatter
   - **Bulk operation** → e.g., "raise all priorities one level," "add tag `auth-redesign` to every task" — apply to all working files and confirm

   For substantive content changes, follow the same Quality Bar from `/clickup-epic-create` (self-contained, real-not-invented, atomic, testable, honest).

---

### Phase 3: Review Loop

9. **Present options:**

   > Edited Epic `<id>` — '<title>'. Working drafts at `$CLICKUP_DRAFTS_DIR/<slug>-edit/`. When ready:
   >
   > - **`good`** — apply the diff to ClickUp
   > - **`edit`** — keep editing
   > - **`investigate`** — fetch more context (related tasks, design doc, repo)
   > - **`stage`** — save and resume later via `/clickup-epic-edit resume <slug>`
   > - **`abandon`** — discard all changes and remove the draft directory

10. **If `edit` / `investigate` / `stage` / `abandon`:** behave the same way as in `/clickup-epic-create`. For `abandon`, `rm -rf` the draft dir after explicit user confirmation.

11. **If `good`:** **re-read every working file from disk.**

---

### Phase 4: Compute the Diff

12. **Diff snapshot vs. working files** to produce three lists:
    - **Updated**: files present in both snapshot and working dir, but with content (body or relevant frontmatter fields) changed
    - **Created**: files in working dir with empty `clickupId` (new tasks)
    - **Deleted**: files in snapshot/tasks/ that don't have a matching `clickupId` in any working file

    Also flag the Epic itself if `epic.md` body or name changed vs. snapshot.

13. **Show the user the diff plan** as a numbered list, e.g.:
    ```
    Apply plan:
      1. UPDATE Epic abc123 (name + description)
      2. UPDATE task abc456 (description)
      3. UPDATE task abc789 (priority normal → high)
      4. CREATE new task "Add rate limiting middleware" (no deps)
      5. ARCHIVE task abc999 (default for removals; confirm before destructive delete)
    ```

    For any removal, ask explicitly: "Remove `<id>` — '<title>'? (`archive` (default) / `delete` / `keep`)". **Default to `archive`** (`{archived: true}` PUT) if the user is unsure or just says yes — archived tasks are trivially restorable; deleted ones aren't.

---

### Phase 5: Apply

> **JSON safety.** Same rule as `/clickup-epic-create`: build every payload with `jq -n --arg`, never template values into a JSON string. Bodies will contain quotes, newlines, and backticks.

14. **Update the Epic** if changed:
    ```bash
    EPIC_BODY="$(awk '/^---$/{n++; next} n>=2' epic.md)"
    PAYLOAD="$(jq -n --arg name "$EPIC_NAME" --arg desc "$EPIC_BODY" \
      '{name: $name, markdown_description: $desc}')"
    curl -s -X PUT \
      -H "Authorization: $CLICKUP_API_KEY" \
      -H "Content-Type: application/json" \
      -d "$PAYLOAD" \
      "https://api.clickup.com/api/v2/task/$EPIC_TASK_ID"
    ```

15. **Update each changed task:**
    ```bash
    TASK_BODY="$(awk '/^---$/{n++; next} n>=2' "tasks/$file")"
    PAYLOAD="$(
      jq -n \
        --arg name "$TASK_TITLE" \
        --arg desc "$TASK_BODY" \
        --argjson priority "${TASK_PRIORITY:-null}" \
        '{name: $name, markdown_description: $desc}
         + (if $priority == null then {} else {priority: $priority} end)'
    )"
    curl -s -X PUT \
      -H "Authorization: $CLICKUP_API_KEY" \
      -H "Content-Type: application/json" \
      -d "$PAYLOAD" \
      "https://api.clickup.com/api/v2/task/$TASK_ID"
    ```

    Tags use a separate per-tag endpoint:
    ```bash
    # Add:
    curl -s -X POST -H "Authorization: $CLICKUP_API_KEY" \
      "https://api.clickup.com/api/v2/task/$TASK_ID/tag/$(jq -rn --arg t "$TAG" '$t|@uri')"
    # Remove:
    curl -s -X DELETE -H "Authorization: $CLICKUP_API_KEY" \
      "https://api.clickup.com/api/v2/task/$TASK_ID/tag/$(jq -rn --arg t "$TAG" '$t|@uri')"
    ```
    Diff old vs. new tags and call accordingly.

16. **Create each new task** as a subtask of the Epic (same `jq -n` payload shape as `/clickup-epic-create` Phase 6 step 21, with `parent: $EPIC_TASK_ID`). Capture the new `id` and write it back into the working file's frontmatter so a re-run picks up the new state. Then attach tags via step 15's per-tag endpoint.

17. **Remove tasks** — default to **archive**, only delete on explicit `yes`:

    ```bash
    # ARCHIVE (recommended; non-destructive — task hides from default views, easy to restore):
    PAYLOAD="$(jq -n '{archived: true}')"
    curl -s -X PUT -H "Authorization: $CLICKUP_API_KEY" \
      -H "Content-Type: application/json" \
      -d "$PAYLOAD" \
      "https://api.clickup.com/api/v2/task/$TASK_ID"

    # DELETE (destructive — only on explicit user confirmation):
    curl -s -X DELETE -H "Authorization: $CLICKUP_API_KEY" \
      "https://api.clickup.com/api/v2/task/$TASK_ID"
    ```

    Note: "archive" (`archived: true`) is **not** the same as "close" (status change to a `closed` status). Archive is universal; closing depends on the list having a closed-type status, which not all do.

18. **Reconcile dependencies.** Use the snapshot's `dependencies` (from the original GET response under `.dependencies`) as the baseline, not a fresh API fetch. For each task whose dep set changed:

    ```bash
    # Add:
    PAYLOAD="$(jq -n --arg dep "$NEW_DEP_ID" '{depends_on: $dep}')"
    curl -s -X POST -H "Authorization: $CLICKUP_API_KEY" \
      -H "Content-Type: application/json" \
      -d "$PAYLOAD" \
      "https://api.clickup.com/api/v2/task/$TASK_ID/dependency"

    # Remove:
    curl -s -X DELETE -H "Authorization: $CLICKUP_API_KEY" \
      "https://api.clickup.com/api/v2/task/$TASK_ID/dependency?depends_on=$DROPPED_DEP_ID"
    ```

19. **Track partial failures.** If any call fails, keep going for non-fatal cases (dependency wiring) but stop for fatal cases (Epic update failed) and report what was applied vs. pending.

---

### Phase 6: Update Local Plan and Clean Up

20. **Update the local plan** at `$CLICKUP_PLANS_DIR/<EPIC_TASK_ID>-plan.md`:
    - Refresh the `tasks:` list in frontmatter to reflect current state
    - Update the body if `plan.md` in the draft was edited
    - Bump a `lastEdited: <YYYY-MM-DD>` field

21. **Clean up the draft directory:**
    ```bash
    rm -rf "$CLICKUP_DRAFTS_DIR/<slug>-edit"
    ```

22. **Report.** Print the apply plan again with status per item (✓ applied / ✗ failed / — skipped), the Epic URL, and any follow-up needed. If new tasks were created or substantive task descriptions changed, remind the user: "Run `/work-on-clickup <task_id>` to pick one up." For deleted/archived tasks, note that any local work in flight on those tasks should stop.

---

## Important Notes

- **Always work via the snapshot/working diff.** Never compute "changed?" by re-fetching from ClickUp during apply — that races with concurrent edits and may overwrite someone else's changes silently. Snapshot is the contract.
- **Default to archive over delete** for removed tasks unless the user explicitly chose `yes` to delete. Use the `archived: true` field on PUT — that's true archive (works on any list), not the same as setting `status: closed` (which only works if the list has a `closed`-type status).
- **Use `include_markdown_description=true`** on the GET. The non-markdown `description` field returns HTML, which is lossy if the user roundtrips through this command.
- **`markdown_description`** is also the field to write on PUT/POST.
- **Don't echo `CLICKUP_API_KEY`** anywhere.
- The repo path / design doc may have changed since the Epic was created. If the user wants a re-scan during edit (e.g., "we renamed the auth module"), do it via `investigate` and update file path references in tasks before applying.
