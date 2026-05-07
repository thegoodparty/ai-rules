# Cross-Repo Flows

Multi-repo sequences that AI agents need to understand when working on any single repo. Each flow names the trigger, repos involved, sequence, and where the contract lives.

---

## 1. Candidate Onboarding

**Trigger:** User signs up or creates a campaign on gp-webapp.

**Repos:** gp-webapp → gp-api → election-api

**Sequence:**
1. gp-webapp submits signup form via REST to gp-api (auth: JWT cookie).
2. gp-api creates user + campaign records in Postgres.
3. gp-api calls election-api to fetch matching election/candidacy data (internal HTTP).
4. gp-api returns enriched campaign object to gp-webapp.

**Contract:** `@goodparty_org/contracts` in gp-sdk defines shared types between gp-webapp and gp-api. gp-api → election-api uses internal HTTP.

---

## 2. Campaign Plan Generation

**Trigger:** User requests a campaign plan in gp-webapp.

**Repos:** gp-webapp → gp-api → campaign-plan-service (SQS) → gp-api

**Sequence:**
1. gp-webapp calls gp-api endpoint to start plan generation.
2. gp-api publishes a message to the SQS FIFO queue with `QueueType` for plan generation.
3. campaign-plan-service consumes the message, generates the plan (AI-powered), persists `planJson` and tasks to its own Postgres DB.
4. campaign-plan-service publishes a COMPLETED/FAILED status event back to gp-api via SQS.
5. gp-api updates the campaign record; gp-webapp polls or receives the result.

**Contract:** SQS message schema defined in gp-api's `src/queue/` producer. campaign-plan-service consumes the same shape.

---

## 3. Voter Outreach

**Trigger:** Campaign initiates voter outreach via gp-webapp.

**Repos:** gp-webapp → gp-api → people-api

**Sequence:**
1. gp-webapp calls gp-api with outreach parameters.
2. gp-api authenticates via S2S JWT (`PEOPLE_API_S2S_SECRET`) and calls people-api.
3. people-api queries the voter file, returns matching voter records.
4. gp-api processes results and returns to gp-webapp.

**Contract:** S2S JWT signed with `PEOPLE_API_S2S_SECRET`. Request/response shapes in people-api's API surface.

---

## 4. AI Feature Requests

**Trigger:** AI-powered features (content generation, analysis) requested from gp-webapp.

**Repos:** gp-webapp → gp-api → gp-ai-projects

**Sequence:**
1. gp-webapp calls gp-api with AI feature request.
2. gp-api forwards to gp-ai-projects via internal HTTP.
3. gp-ai-projects runs ML/AI logic and returns results.
4. gp-api passes results back to gp-webapp.

**Contract:** Internal HTTP between gp-api and gp-ai-projects.

---

## 5. Data Pipeline / ETL

**Trigger:** Scheduled or event-driven ETL jobs.

**Repos:** gp-data-platform → gp-api (DB)

**Sequence:**
1. gp-data-platform connects directly to gp-api's Postgres database.
2. Reads campaign, user, and election data for analytics/reporting.
3. Transforms and loads into data warehouse or analytics tables.

**Contract:** Direct Postgres access. Schema defined by Prisma migrations in gp-api.

---

## 6. Candidate Sites

**Trigger:** Candidate site pages are built/rendered.

**Repos:** candidate-sites → gp-api

**Sequence:**
1. candidate-sites (Next.js) fetches candidate and campaign data from gp-api at build or request time.
2. Renders static or SSR pages for individual candidates.

**Contract:** REST API from gp-api. Shared types via `@goodparty_org/contracts`.

---

## 7. SDK / Contracts Publishing

**Trigger:** API shape changes in gp-api.

**Repos:** gp-api → gp-sdk → gp-webapp, candidate-sites

**Sequence:**
1. Developer updates API types in gp-api.
2. Contracts are built (`npm run generate` in gp-api) and published via gp-sdk (`@goodparty_org/contracts`).
3. gp-webapp and candidate-sites update the package to consume new types.

**Contract:** `@goodparty_org/contracts` npm package in gp-sdk.
