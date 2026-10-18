# LeetCode Pattern Trainer

A personal, single-user spaced-repetition trainer for LeetCode, organized around patterns (sliding window, monotonic stack, union-find, and so on) rather than just individual problems. A scheduler decides when each problem should be re-solved. A browser extension, daily push reminders, a stats dashboard and AI insights come in later phases.

**Status: Phase 0, the scaffold** (Docker Compose stack, settings split, `uv`, pytest, ruff, CI). There are no app features yet. See [`docs/SPEC.md`](docs/SPEC.md) for the full spec and the phase list.

## Prerequisites

- Docker with Compose v2.24 or newer, which the optional `.env` file needs (Docker Desktop or Colima).
- uv (`brew install uv`). On first run, uv downloads Python 3.12 and the dependencies itself.

## Run the stack

All configuration comes from environment variables documented in `.env.example`. Copying it to `.env` is optional, because the defaults work without one. Never commit `.env`.

```sh
cp .env.example .env
```

Build the image and start the stack, then open http://127.0.0.1:8000/admin/:

```sh
docker compose up --build
```

Create an admin user. `run --rm` starts a one-off container from the `web` service and removes it when the command exits:

```sh
docker compose run --rm web python manage.py createsuperuser
```

Stop the stack. The database volume is kept:

```sh
docker compose down
```

Stop it and also wipe the database volume. Postgres reads `POSTGRES_*` only when it first creates the volume, so after changing those values you need this:

```sh
docker compose down -v
```

## Services

| Service | Role |
|---|---|
| `db` | PostgreSQL 16 with pgvector (`pgvector/pgvector:pg16`). Published on host port **5433**, not 5432, so it doesn't clash with another Postgres you may already run. |
| `migrate` | One-shot: applies Django and Procrastinate migrations, then exits. `web` and `worker` start only after it succeeds. |
| `web` | Django dev server at 127.0.0.1:8000. Reloads on code changes, because `./backend` is mounted into the container. |
| `worker` | Procrastinate background-job worker (Procrastinate is a Postgres-backed job queue). Same image as `web`. It does **not** auto-reload: run `docker compose restart worker` after changing task code. |

All ports bind to 127.0.0.1 only.

## Tests and lint

Run these on the host, the same way CI does. The tests need Postgres, so start only the `db` service in the background (`-d`) first. They use the `config.settings.test` settings and connect to Postgres on localhost:5433. `uv run` runs a command inside the project's virtual environment, creating or updating it first.

```sh
docker compose up -d db
uv run pytest
```

Lint and format with ruff. The `--check` form only verifies formatting and changes nothing:

```sh
uv run ruff check .
uv run ruff format .
uv run ruff format --check .
```

Any manage.py command also runs on the host and talks to the Compose `db` on localhost:5433:

```sh
uv run python backend/manage.py <command>
```

## CI

GitHub Actions (`.github/workflows/ci.yml`) runs on every push:

1. `uv sync --locked`, which installs exactly what `uv.lock` pins and fails if the lockfile is out of date.
2. ruff check.
3. ruff format check.
4. pytest, against a `pgvector/pgvector:pg16` service container (the same image as the local `db`).

## Layout

```
backend/
  config/            settings (base, dev, test), urls, wsgi
  tests/             pytest tests
  manage.py
docs/SPEC.md         full spec and build phases
Dockerfile  docker-compose.yml  .env.example
pyproject.toml  uv.lock          deps + ruff + pytest config
.github/workflows/ci.yml
```
