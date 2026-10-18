"""Smoke tests: the database, the admin and Procrastinate's schema are wired up."""

import pytest
from django.db import connection


@pytest.mark.django_db
def test_database_answers():
    with connection.cursor() as cursor:
        cursor.execute("SELECT 1")
        assert cursor.fetchone() == (1,)


def test_admin_login_page_loads(client):
    assert client.get("/admin/login/").status_code == 200


@pytest.mark.django_db
def test_procrastinate_schema_is_migrated():
    assert "procrastinate_jobs" in connection.introspection.table_names()
