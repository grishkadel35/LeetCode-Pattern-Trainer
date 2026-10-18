FROM python:3.12-slim

# uv from its official image, the same version as on the host.
COPY --from=ghcr.io/astral-sh/uv:0.13.1 /uv /bin/

# UV_PYTHON_DOWNLOADS=never makes uv use this image's Python instead of fetching one.
# The venv's bin/ goes first on PATH, so `python` means the project's venv.
ENV PYTHONUNBUFFERED=1 \
    UV_PYTHON_DOWNLOADS=never \
    PATH="/app/.venv/bin:$PATH"

WORKDIR /app

# Dependencies first, so code edits reuse this cached layer instead of reinstalling.
COPY pyproject.toml uv.lock .python-version ./
RUN uv sync --locked --no-dev

COPY backend ./backend
WORKDIR /app/backend

CMD ["python", "manage.py", "runserver", "0.0.0.0:8000"]
