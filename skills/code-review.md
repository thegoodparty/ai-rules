# Skill: Code Review

Review code changes against GoodParty engineering standards. Use after completing a feature or before opening a PR.

## When to use

Run this skill when you've finished a substantive code change and want a quality check before committing.

## Prompt

```
Review the code I just changed. For each file:

1. Check for correctness: logic errors, off-by-one, null access, async mistakes
2. Check for style: does it match the repo's AGENTS.md code style section?
3. Check for duplication: is there existing code in this repo that does the same thing?
4. Check for security: injection, auth bypass, secret exposure, SSRF
5. Check for test coverage: are the changes tested? Are edge cases covered?

For each issue found:
- Quote the offending code
- Explain what's wrong
- Suggest the fix

End with a verdict: PASS, PASS WITH NOTES, or FAIL.
```

## Notes

- This is a general-purpose review skill. For deeper checks on specific concerns, use the dedicated critic files in `ai-rules/` (security.md, bugs.md, etc.).
- Combine with repo-specific rules from `.cursor/rules/` or AGENTS.md if available.
