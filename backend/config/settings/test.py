"""pytest settings, selected in pyproject.toml."""

import os

from .base import *  # noqa: F403

# Local-only fallback so tests run without a .env. An empty value counts as unset.
SECRET_KEY = os.environ.get("DJANGO_SECRET_KEY") or "django-insecure-test-only"
