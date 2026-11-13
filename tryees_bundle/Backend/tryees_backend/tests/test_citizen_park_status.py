import os
import unittest
from datetime import datetime, timezone

os.environ.setdefault("SECRET_KEY", "citizen-park-status-test-secret")
os.environ.setdefault("BASE_URL", "http://localhost")
os.environ.setdefault("POSTGRES_USER", "test")
os.environ.setdefault("POSTGRES_PASSWORD", "test")
os.environ.setdefault("POSTGRES_DB", "test")
os.environ["POSTGRES_HOST"] = "127.0.0.1"
os.environ["POSTGRES_PORT"] = "1"
os.environ.setdefault("MQTT_BROKER_HOST", "127.0.0.1")
os.environ.setdefault("MQTT_BROKER_PORT", "1883")

from app.db.models import CitizenCategory, CitizenReport, Practice, PracticeStatus
from app.services.citizen import park_status


class FakeQuery:
    def __init__(self, rows):
        self.rows = rows

    def filter(self, *args, **kwargs):
        return self

    def order_by(self, *args):
        return self

    def all(self):
        return self.rows

    def __iter__(self):
        return iter(self.rows)


class FakeDatabase:
    def __init__(self, practices, report_categories):
        self.practices = practices
        self.report_categories = report_categories

    def query(self, *entities):
        if len(entities) == 1 and entities[0] is Practice:
            return FakeQuery(self.practices)
        if (
            len(entities) == 2
            and entities[0] is CitizenReport.practice_id
            and entities[1] is CitizenReport.category
        ):
            return FakeQuery(self.report_categories)
        if (
            len(entities) == 2
            and entities[0] is CitizenCategory.code
            and entities[1] is CitizenCategory.label
        ):
            return FakeQuery([("waste", "Rifiuti")])
        raise AssertionError(f"Unexpected query: {entities}")


class CitizenParkStatusTests(unittest.TestCase):
    def test_open_problem_changes_park_status_to_warning(self):
        now = datetime(2026, 1, 1, tzinfo=timezone.utc)
        practice = Practice(
            id=1,
            park_id=7,
            status=PracticeStatus.open,
            category="other",
            created_at=now,
            updated_at=now,
        )
        db = FakeDatabase([practice], [(practice.id, "waste")])
        empty_db = FakeDatabase([], [])

        clear_status = park_status(empty_db, 7, now=now, notices=[])
        problem_status = park_status(db, 7, now=now, notices=[])

        self.assertEqual(clear_status["level"], "ok")
        self.assertEqual(problem_status["level"], "warning")
        self.assertEqual(problem_status["open_issues"], 1)
        self.assertEqual(problem_status["highlights"], [
            {"category": "waste", "label": "Rifiuti", "count": 1}
        ])


if __name__ == "__main__":
    unittest.main()
