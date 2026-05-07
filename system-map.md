# System Map

How GoodParty's services connect. Arrow direction = "calls / depends on". The edge table below is the canonical reference; the diagram is a quick visual.

```
   gp-webapp              ── REST (JWT cookie) ──▶  gp-api
   gp-sdk                 ── shared TS types  ──▶  gp-api  (compile-time only)

   gp-api                 ── HTTP (internal)   ──▶  election-api
   gp-api                 ── HTTP (S2S JWT)    ──▶  people-api
   gp-api                 ── HTTP (internal)   ──▶  gp-ai-projects

   gp-api                 ── SQS FIFO trigger  ──▶  campaign-plan-service
   campaign-plan-service  ── SQS FIFO status   ──▶  gp-api

   gp-data-platform       ── Postgres (read)   ──▶  gp-api DB
   candidate-sites        ── REST              ──▶  gp-api

   ai-rules               ── git submodule     ──▶  gp-api (and repos that opt in)
```

## Key edges

| From | To | Protocol | Auth | Notes |
|------|----|----------|------|-------|
| gp-webapp | gp-api | REST | JWT cookie | All user-facing API calls |
| gp-api | election-api | HTTP | Internal | Election/candidacy data |
| gp-api | people-api | HTTP | S2S JWT (`PEOPLE_API_S2S_SECRET`) | Voter file lookups |
| gp-api | campaign-plan-service | SQS FIFO | IAM | Trigger plan generation |
| campaign-plan-service | gp-api | SQS FIFO | IAM | Status callbacks |
| gp-api | gp-ai-projects | HTTP | Internal | AI/ML features |
| gp-data-platform | gp-api DB | Postgres | Direct | ETL reads |
| gp-sdk | gp-api | — | — | Shared TS types via `@goodparty_org/contracts` |
| candidate-sites | gp-api | REST | — | Fetches candidate data |
| ai-rules | (consumer repos) | git submodule | — | Review-time critics + context; currently gp-api, rolling out to others |

## Repo count

10 active repos. Stale repos (Voter-file-ETL, gp-styles, gp-sanity, gp-serve) are out of scope.
