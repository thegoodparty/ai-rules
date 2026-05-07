# Skill: Security Check

Focused security review for any GoodParty repo. Complements `ai-rules/security.md` with an actionable prompt.

## When to use

Run before merging any PR that touches auth, user input handling, external service calls, or secret management.

## Prompt

```
Perform a security review of the code I changed. Check for:

1. **Injection**: SQL injection, NoSQL injection, command injection, template injection
2. **Auth & access control**: missing auth checks, privilege escalation, broken access control
3. **Secrets**: hardcoded secrets, secrets in logs, secrets in error messages
4. **Input validation**: missing validation, permissive schemas (.passthrough()), type coercion issues
5. **SSRF**: user-controlled URLs passed to fetch/HTTP clients without allowlist
6. **Dependencies**: known vulnerable packages, unnecessary dependencies
7. **Data exposure**: PII in logs, overly broad API responses, missing field filtering

For each finding:
- Severity: CRITICAL / HIGH / MEDIUM / LOW
- Quote the code
- Explain the attack vector
- Provide the fix

If no issues found, state "No security issues identified" with a brief summary of what was checked.
```

## Notes

- For a deeper, rule-by-rule review, read `ai-rules/security.md` and apply each rule individually.
- Pay special attention to S2S auth boundaries (e.g., `PEOPLE_API_S2S_SECRET`).
