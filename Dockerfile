FROM python:3.12-slim

# uv from its official image, the same version as on the host.
COPY --from=ghcr.io/astral-sh/uv:0.13.1 /uv /bin/

# UV_PYTHON_DOWNLOADS=never makes uv use this image's Python instead of fetching one.
# UV_LINK_MODE=copy: the cache mount below is a separate filesystem, so uv can't hardlink from it.
# The venv's bin/ goes first on PATH, so `python` means the project's venv.
ENV PYTHONUNBUFFERED=1 \
    UV_PYTHON_DOWNLOADS=never \
    UV_LINK_MODE=copy \
    PATH="/app/.venv/bin:$PATH"

WORKDIR /app

# Dependencies first, so code edits reuse this cached layer instead of reinstalling.
# The BuildKit cache mount keeps uv's download cache out of the image and reuses it
# across builds when the dependencies change.
COPY pyproject.toml uv.lock .python-version ./
RUN --mount=type=cache,target=/root/.cache/uv \
    uv sync --locked --no-dev

COPY backend ./backend
WORKDIR /app/backend

CMD ["python", "manage.py", "runserver", "0.0.0.0:8000"]
