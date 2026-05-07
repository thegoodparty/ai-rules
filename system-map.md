# System Map

How GoodParty's services connect. Arrow = "calls / depends on".

```
                        ┌─────────────┐
                        │  gp-webapp  │  Next.js frontend
                        └──────┬──────┘
                               │ REST (JWT cookie)
                               ▼
                        ┌─────────────┐
               ┌───────▶│   gp-api    │◀──── gp-sdk (shared TS package)
               │        └──┬──┬──┬────┘
               │           │  │  │
          SQS FIFO         │  │  │  HTTP (internal)
          (status)         │  │  └──────────────────┐
               │           │  │                     │
               │           │  │ HTTP (internal)     │
               ▼           │  ▼                     ▼
  ┌─────────────────────┐  │ ┌──────────────┐ ┌──────────────┐
  │campaign-plan-service│  │ │ election-api │ │  people-api  │
  └─────────────────────┘  │ └──────────────┘ └──────────────┘
         SQS FIFO ▲        │
         (trigger)         │ HTTP
                           ▼
                   ┌────────────────┐
                   │ gp-ai-projects │
                   └────────────────┘

         ┌──────────────────┐
         │ gp-data-platform │  ETL / shared Postgres
         └──────────────────┘
              ▲ reads from gp-api's DB

         ┌────────────────┐
         │candidate-sites │  Static candidate pages (Next.js)
         └────────────────┘
              ▲ data from gp-api

         ┌──────────┐
         │ ai-rules │  Org-wide AI context & review rules
         └──────────┘
              ▲ git submodule in gp-api (and other repos)
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
| ai-rules | (all repos) | git submodule | — | Review-time critics + context |

## Repo count

10 active repos. Stale repos (Voter-file-ETL, gp-styles, gp-sanity, gp-serve) are out of scope.
