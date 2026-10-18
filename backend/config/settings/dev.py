"""Local development: the Compose stack, and manage.py run on the host."""

import os

from .base import *  # noqa: F403

DEBUG = True

# Local-only fallback so the stack runs without a .env. An empty value counts as unset.
SECRET_KEY = os.environ.get("DJANGO_SECRET_KEY") or "django-insecure-dev-only"
