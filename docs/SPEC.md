# LeetCode Pattern Trainer — Project Spec for Claude Code

## Your role and how to work

You are helping me (Grish, a CS student) build a personal LeetCode practice system. I am strong in Python, FastAPI, async code and Git. I am actively learning Docker, pytest, CI/CD and pgvector, so when you make a non-obvious choice in those areas, explain it briefly in your phase summary.

Working rules:

1. Build one phase at a time (see "Build phases"). Before writing code for a phase, give me a short plan: files you will create or change, new dependencies and why, and any decision I need to make. Wait for my go-ahead.
2. Every phase ends with passing tests, `ruff` clean, and a short summary of what was built, what was deferred, and how to run it. Then stop and wait for review.
3. Do not add dependencies beyond those listed here without stating why.
4. Never commit secrets. All keys and tokens come from environment variables, with a `.env.example` documenting them.
5. Keep all LeetCode-specific scraping and DOM selectors isolated in one module each, because LeetCode changes them without notice.
6. Prefer pure functions for business logic (scheduler, session summary, snapshot building, insight validation) so they are easy to test without a database.
7. When the spec is ambiguous, ask instead of guessing.

## What the product does

A spaced-repetition trainer for LeetCode organized around patterns (sliding window, monotonic stack, union-find, etc.), not just problems.

- Practice on LeetCode as usual. A browser extension times the session and records what happened (active time, phases, hints, failed submissions).
- When a problem is accepted, the extension shows a one-tap confirmation of how it went. A server-side sync with LeetCode catches anything the extension missed.
- A scheduler decides when each problem should be re-solved. A daily web push notification lists what is due.
- A web dashboard shows stats per pattern, and an AI pipeline turns the data into grounded insights, mistake profiles and practice recommendations.

Single user (me). Public on the internet behind login.

## Stack

| Layer | Choice |
|---|---|
| Backend | Python 3.12, Django 5, Django REST Framework (token auth for the extension) |
| Database | PostgreSQL 16 with the pgvector extension (image `pgvector/pgvector:pg16`) |
| Background jobs | Procrastinate (Postgres-backed queue, periodic tasks; no Redis) |
| Frontend | Django templates, HTMX, Chart.js; served with WhiteNoise |
| Push | PWA manifest + service worker + `pywebpush` with VAPID keys |
| Extension | Chrome Manifest V3, TypeScript, bundled with esbuild, loaded unpacked |
| LLM | Provider-agnostic client over an OpenAI-compatible chat API (local Ollama by default) |
| Tooling | `uv`, `pytest`, `pytest-django`, `ruff`, Docker Compose, GitHub Actions |
| Deploy (later) | Caddy (automatic HTTPS) in front of Gunicorn on a small VPS |

## Repository layout

```
.
├── backend/
│   ├── config/              # settings (base, dev, test, prod), urls, wsgi
│   ├── problems/            # Problem, Pattern, ProblemPattern
│   ├── practice/            # Attempt, ReviewState, scheduler (pure), views
│   ├── sessions_app/        # PracticeSession, SessionEvent, summarize_session (pure)
│   ├── sync/                # LeetCode client (isolated) + sync task
│   ├── notifications/       # PushSubscription, send service, subscribe views
│   ├── stats/               # aggregation queries + dashboard views
│   ├── insights/            # LLM client, analysis, snapshot, insights, coach
│   ├── api/                 # DRF endpoints for the extension
│   ├── templates/  static/
│   └── tests/
├── extension/
│   ├── src/ (content.ts, page-hook.ts, background.ts, popup.ts, selectors.ts, types.ts)
│   ├── manifest.json  build.mjs  package.json
├── docker-compose.yml  Dockerfile  .env.example
└── .github/workflows/ci.yml
```

## Data model

Attempts and session events are append-only logs. Anything derived from them (review state, session metrics) can be recomputed by replaying history.

**Problem**: `slug` (unique), `title`, `url`, `difficulty` (easy/medium/hard), `leetcode_tags` (JSON list), `statement` (text, nullable, for the AI pipeline).

**Pattern**: `slug` (unique), `name`, `description`. Seed about 20 via a data migration: two-pointers, sliding-window, binary-search, prefix-sum, hashmap-counting, monotonic-stack, heap-top-k, intervals, linked-list-pointers, tree-dfs, tree-bfs, graph-bfs, graph-dfs, topological-sort, union-find, backtracking, greedy, dynamic-programming-1d, dynamic-programming-2d, trie, bit-manipulation, design.

**ProblemPattern** (through model): `problem`, `pattern`, `source` (user / llm), `confidence` (float, nullable). Unique on (problem, pattern, source).

**Attempt**: `problem`, `attempted_at`, `status` (pending / confirmed), `outcome` (clean / used_hints / needed_solution / not_solved, nullable while pending), `active_seconds`, `language`, `code` (text), `notes`, `leetcode_submission_id` (unique, nullable), `session` (nullable FK), `pattern_guess` (nullable FK to Pattern), `source` (extension / sync / manual).

**ReviewState**: one per Problem. `due_date`, `interval_days`, `ease`, `repetitions`, `last_reviewed_at`. Always produced by the scheduler function, never edited by hand.

**PracticeSession**: `id` (UUID generated by the extension), `problem`, `started_at`, `ended_at`, `metrics` (JSON output of `summarize_session`), `suggested_outcome`.

**SessionEvent**: `id` (UUID generated by the extension, unique, for dedupe), `session`, `type`, `ts`, `payload` (JSON). Event types: `problem_opened`, `tab_hidden`, `tab_visible`, `idle`, `active`, `first_keystroke`, `hints_opened`, `editorial_opened`, `solutions_opened`, `pattern_guessed`, `submission_result` (payload: status, submission_id, runtime), `session_ended`.

**PushSubscription**: `endpoint` (unique), `p256dh`, `auth`, `user_agent`, `created_at`.

**AttemptAnalysis**: `attempt` (one-to-one), `model`, `prompt_version`, `result` (JSON matching the analysis schema), `created_at`.

**Insight**: `period_start`, `period_end`, `kind`, `title`, `finding`, `recommendation`, `severity`, `metric_keys` (JSON list), `model`, `prompt_version`, `created_at`. **InsightFeedback**: `insight`, `helpful` (bool), `created_at`.

Later (phase 11): embedding columns via `pgvector` on notes and analysis summaries.

## Core logic

### Scheduler (`practice/scheduler.py`)

Pure function: `compute_review_state(attempts: list[AttemptLike], today: date) -> ReviewStateData`. Start with SM-2. Map outcomes to quality: clean and faster than my personal median for that difficulty → 5, clean → 4, used_hints → 3, needed_solution → 1, not_solved → 0. Quality below 3 resets the interval to 1 day. Design the interface so FSRS (the `fsrs` package) can replace SM-2 later by replaying history. Tests: first clean solve, repeated clean solves growing the interval, a failure resetting it, and replay determinism.

### Session summary (`sessions_app/summary.py`)

Pure function: `summarize_session(events: list[EventLike], idle_threshold_s=300) -> SessionMetrics` returning: `active_seconds` (visible and not idle), `think_seconds` (open → first keystroke), `code_seconds` (first keystroke → first submission), `debug_seconds` (first failed submission → accepted), `failed_submissions` by status, `hints_opened`, `editorial_opened`, `solutions_opened`, `accepted`, `pattern_guess`. Suggested outcome rules: editorial or solutions opened → needed_solution; hints opened → used_hints; accepted with neither → clean; never accepted → not_solved. Tests use fixture event lists: clean fast solve, solve with a 20-minute break, two wrong answers then accepted, editorial opened, out-of-order event timestamps.

### Ingest and dedupe

- Extension events are posted in batches; duplicates by event `id` are ignored (`bulk_create(ignore_conflicts=True)`).
- Attempts are upserted on `leetcode_submission_id`, so the extension and the sync never create duplicates.

## Web app screens

Visual direction: clean developer-tool look. IBM Plex Sans for text and IBM Plex Mono for numbers and pattern slugs. Ground `#F4F6F8`, surfaces white, ink `#12161C`, muted text `#4A5563`, borders `#DCE1E7`, action blue `#2F5BEA` (soft `#E8EEFD` / text `#1F3FB0`), weak-spot orange `#E8742B`. Responsive down to phone width. Top nav: Due today, Log attempt, Stats, Problems.

1. **Due today** (landing): "Synced from LeetCode" box of pending attempts with one-tap outcome buttons (HTMX); review queue cards showing title, difficulty, pattern, last outcome and when, overdue tag, "Open on LeetCode" and "Log result"; sidebar with this week's counts, three weakest patterns, reminder status; insight cards once phase 9 exists.
2. **Log attempt**: fallback and edit form (problem search, outcome, patterns, minutes, language, code, notes) with a live "next review" preview from the scheduler and the problem's past attempts.
3. **Problem detail**: attempt history, session metrics, AI analysis.
4. **Stats**: 30 / 90 day / all-time toggle; headline numbers; clean-solve rate by pattern (orange under 60%); think / code / debug time split per pattern (stacked bars); weekly trend; activity heatmap; pattern-guess accuracy and common confusions; error profile (WA vs TLE vs RE); clean rate grouped by review interval; full pattern table with improving / steady / slipping.
5. **Settings**: enable notifications button, LeetCode username, optional session cookie, API token for the extension.
6. **Coach** (phase 11): chat page.

All views require login. Compute stats live with ORM aggregation; no precomputed tables yet.

## Web push

- `manifest.json` and `sw.js` served from the site root (`/sw.js`, via a view or root static mapping) so the worker's scope covers the whole site.
- Service worker handles `push` (show notification with title, body, URL) and `notificationclick` (focus or open the URL).
- Subscribe flow: permission is requested only from a button tap; `pushManager.subscribe` with the VAPID public key; POST the subscription to Django.
- `notifications.services.send_push(...)` wraps `pywebpush`; delete subscriptions on 404 or 410.
- Env: `VAPID_PUBLIC_KEY`, `VAPID_PRIVATE_KEY`, `VAPID_SUBJECT` (mailto:). A management command generates keys.
- Note in docs: iPhone requires Add to Home Screen first.

## Background jobs (Procrastinate)

All schedules in `America/New_York`.

| Task | Trigger |
|---|---|
| `send_daily_reminder` | periodic, 8:00 |
| `sync_leetcode` | periodic, every 30 minutes |
| `summarize_and_suggest(session_id)` | on `session_ended` |
| `analyze_attempt(attempt_id)` | on attempt confirmed (phase 8) |
| `build_weekly_insights` | periodic, Sunday 18:00 (phase 9) |
| `send_weekly_digest` | after weekly insights |

Tasks must be idempotent and safe to retry. Run the worker as its own Compose service using the same image.

## LeetCode sync (`sync/leetcode_client.py`, isolated)

- Uses LeetCode's unofficial GraphQL endpoint. Public mode: recent accepted submissions for a username (title, slug, timestamp, submission id). Optional cookie mode (`LEETCODE_SESSION`, `csrftoken` from env or settings): full submission history including code and failed submissions.
- Also fetch problem metadata (difficulty, topic tags, statement) and cache it on Problem.
- New accepted submissions become `pending` Attempts and trigger a push: "You solved X — how did it go?" linking to the confirm screen.
- Tests use saved JSON fixtures, never live calls. Handle schema changes gracefully: log and skip, never crash the task.

## Extension (Manifest V3, TypeScript)

- **content.ts** on `https://leetcode.com/problems/*`: timer overlay, detects first keystroke in the editor, hints / editorial / solutions clicks, pattern-guess prompt before starting, accepted confirmation panel, "last time" banner for problems in my review queue, optional interview mode (hides difficulty, tags, acceptance rate; shows a countdown).
- **page-hook.ts**: injected into the page's main world; wraps `fetch` to observe submission check responses and posts results to the content script. This is more robust than reading the result DOM.
- **selectors.ts**: every LeetCode DOM selector lives here and nowhere else.
- **background.ts**: owns session state in `chrome.storage.local` (survives page reloads), uses `chrome.idle`, buffers events and flushes in batches to the API with retries, shows the due count as the icon badge.
- **popup.ts**: server URL and API token setup, due count, interview mode toggle.
- Host permissions: leetcode.com plus the configured server (localhost in dev).
- Installed via `chrome://extensions` → Developer mode → Load unpacked. Document this in the README.

## API (DRF, token auth)

- `POST /api/sessions/` create session
- `POST /api/sessions/{id}/events/` batch of events (deduped)
- `POST /api/sessions/{id}/confirm/` outcome (+ optional pattern) → creates or updates the Attempt
- `GET /api/problems/{slug}/` my history and review state for the "last time" banner
- `GET /api/due/` due count for the badge
- CORS limited to the extension origin.

## AI insights pipeline

Principle: code computes every number; the model labels, interprets and recommends. Every model output is structured JSON validated with Pydantic, and anything that fails validation is retried once with the error message, then dropped and logged.

### LLM client (`insights/llm.py`)

- One small interface: `complete_json(role, system, user, schema) -> dict`.
- Roles map to config: `LLM_LABELER_*` (frequent, narrow tasks) and `LLM_SYNTH_*` (weekly synthesis, coach), each with `BASE_URL`, `MODEL`, `API_KEY` (may be empty). Both target OpenAI-compatible chat completions so the same code works with local Ollama (`http://localhost:11434/v1`), Gemini's OpenAI-compatible endpoint, or my Go LLM gateway in front of either.
- Request JSON output; always validate locally regardless of provider support. Timeouts and limited retries with backoff. Record model and prompt version on every stored result.
- Prompts live as versioned files in `insights/prompts/` (for example `attempt_analysis_v1.md`).
- Defaults for my machine (16 GB Apple Silicon Mac), documented in `.env.example`:
  - Labeler: Ollama `qwen3.5:9b` at `http://host.docker.internal:11434/v1` (Ollama runs natively on macOS, not in Docker, so it can use the Mac GPU; containers reach it through `host.docker.internal`). Fallback `qwen3.5:4b` if memory is tight. Request a context of about 16K tokens, which fits the problem statement plus a few submissions.
  - Synthesizer: Gemini Flash on the free tier via its OpenAI-compatible endpoint, `GEMINI_API_KEY` from env. Handle HTTP 429 with backoff and retry the task later rather than failing.
  - Embeddings (phase 11): a small local Ollama embedding model such as `nomic-embed-text`.
  - The analysis worker processes one job at a time (no concurrency) to keep memory use predictable.
  - Preferred routing: both roles go through my Go LLM gateway (running on the Mac next to the worker), which routes by URL prefix and passes request bodies through unchanged. The labeler's `BASE_URL` is the gateway's `/ollama/v1` route; the synthesizer's is the gateway's Gemini route pointing at Gemini's OpenAI-compatible endpoint. The gateway handles fallback (Ollama → Groq free tier, rewriting only the `model` field) when Ollama times out or is unreachable. The Django code does not need to know which provider served a request; it stores the model name returned in the response.
- Tests mock the client entirely.

### Per-attempt analysis (phase 8)

Input: problem statement, accepted code, and up to three failed submissions' code with their statuses. Output schema:

```json
{
  "technique": "string, short",
  "pattern_slugs": ["must be from the Pattern table"],
  "time_complexity": "O(...)",
  "space_complexity": "O(...)",
  "better_complexity_exists": true,
  "optimal_time_complexity": "O(...) or null",
  "mistakes": [
    {"category": "one of the fixed taxonomy", "description": "one sentence", "submission": "failed_1 | accepted"}
  ],
  "fix_summary": "what changed between the last failed and the accepted submission, or null",
  "confidence": 0.0
}
```

Fixed mistake taxonomy (Python enum; the model may not invent categories): `off_by_one`, `loop_bounds`, `edge_empty_input`, `edge_single_element`, `edge_duplicates`, `edge_negative_or_zero`, `integer_overflow`, `wrong_base_case`, `state_not_reset`, `wrong_data_structure`, `suboptimal_complexity`, `unnecessary_extra_pass`, `wrong_pattern_choice`, `misread_problem`, `recursion_or_stack_issue`, `comparator_or_sorting_error`, `other`.

Pattern slugs from the model are stored as `ProblemPattern(source="llm")` with the confidence, never overwriting mine. Stats compare my labels with the model's.

### Weekly snapshot and insights (phase 9)

- `build_snapshot(period) -> dict` (pure over query results): a flat dict of stable metric keys, for example `dp.clean_rate_30d`, `dp.clean_rate_delta_30d`, `dp.think_share_30d`, `monotonic_stack.debug_share_30d`, `mistakes.edge_empty_input.count_30d`, `guess.accuracy_30d`, `guess.top_confusion`, `retention.clean_rate_interval_14d_plus`, `speed.medium.median_active_min_30d`.
- The synth model receives the snapshot and returns up to five insights: `{kind, title, finding, recommendation, severity: info|notable|important, metric_keys: [...]}`.
- `validate_insight(insight, snapshot)`: every `metric_keys` entry must exist in the snapshot, and every number appearing in `finding` must match a cited metric value (allow formatting tolerance, such as 0.41 vs 41%). Reject otherwise. This validator needs thorough tests.
- Store valid insights, render them as cards on Due today and Stats with links to the evidence chart, add thumbs up / down, and send a weekly digest push with the top insight.

### Recommendations (phase 10)

Code builds a candidate list from the problem catalog (weak patterns, suitable difficulty, not attempted in the last 30 days, up to 25 candidates). The model may only choose from that list by slug and explains each pick in one sentence. Reject any slug not in the candidates. Show three on Due today.

### Semantic memory and coach (phase 11)

- Embed notes, analysis summaries and short solution summaries into pgvector (embedding model configurable; a local Ollama embedding model by default).
- Coach page: an agent loop using the synth model with read-only tools I define: `get_pattern_stats(pattern, days)`, `get_recent_attempts(pattern, limit)`, `get_mistake_counts(pattern, days)`, `search_notes(query, k)`. No raw SQL from the model. Cap tool calls per question. Show which tools were used under each answer.

### Evaluation

A `insights/eval/` folder with about 25 hand-labeled attempts (expected technique, complexity, mistake categories) and a management command that runs the current prompt and model against them and prints accuracy per field. Run it whenever a prompt or model changes.

## Testing and CI

- `pytest` with `pytest-django`; factories for models; fixtures for LeetCode responses and session event sequences.
- Pure functions get the most tests: scheduler, `summarize_session`, snapshot building, insight validation, sync parsing.
- GitHub Actions on every push: install with `uv`, run `ruff`, run tests against a `pgvector/pgvector:pg16` service container. Extension: `tsc --noEmit` and a build check.

## Build phases

0. **Scaffold**: repo layout, Docker Compose (db, web, worker), settings split, `.env.example`, `uv`, pytest, ruff, CI workflow, README with run instructions.
1. **Core models**: problems, patterns (seeded), attempts, review state, admin, scheduler with tests.
2. **Web UI**: Due today, Log attempt, Problem detail, login, HTMX interactions.
3. **Stats dashboard** (session-based charts appear once data exists).
4. **PWA and web push**: manifest, service worker, subscribe flow, daily reminder task.
5. **LeetCode sync**: client, pending attempts, confirm flow, sync push notification.
6. **API and extension MVP**: token auth, session and event endpoints, timer, submission detection, accepted confirmation panel.
7. **Session intelligence**: `summarize_session`, suggested outcomes, phase timing, hint detection, pattern guess, interview mode, "last time" banner, stats for phases, guesses and errors.
8. **AI per-attempt analysis**: LLM client, analysis task, mistake taxonomy stats, eval command.
9. **Weekly insights**: snapshot, synthesis, validator, insight cards, feedback, digest.
10. **Recommendations**.
11. **pgvector and coach**.
12. **Deploy**: production settings, Caddy, Gunicorn, VPS deploy workflow, backups for the Postgres volume.
