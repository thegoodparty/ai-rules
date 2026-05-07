# Skill: PR Description

Generate a well-structured PR description from the current branch's changes.

## When to use

Run when you're ready to open a PR and need a description that follows GoodParty's format.

## Prompt

```
Look at all commits on this branch (compared to the base branch) and generate a PR description with this structure:

## What

One paragraph summarizing the change. Be specific — name the feature, module, or bug being addressed.

## Why

Why this change is needed. Link to the ClickUp task if available.

## How

Bullet list of the key implementation decisions. Focus on choices that a reviewer needs to understand — not a line-by-line diff recap.

## Testing

How this was tested:
- [ ] Unit tests added/updated (name the test files)
- [ ] Manual verification (describe what was checked)
- [ ] Existing tests pass (`npm run verify` or equivalent)

## Notes

Anything a reviewer should pay special attention to, or follow-up work this PR defers.
```

## Notes

- Keep the PR description concise. Reviewers skim — front-load the important information.
- If the PR implements a ClickUp task, include the task URL in the Why section.
- Don't list every file changed — the diff does that. Focus on the _why_ behind the changes.
