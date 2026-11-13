import os
import unittest
from datetime import datetime, timedelta, timezone
from uuid import uuid4

os.environ.setdefault("SECRET_KEY", "citizen-reports-test-secret")
os.environ.setdefault("BASE_URL", "http://localhost")
os.environ.setdefault("POSTGRES_USER", "test")
os.environ.setdefault("POSTGRES_PASSWORD", "test")
os.environ.setdefault("POSTGRES_DB", "test")
os.environ["POSTGRES_HOST"] = "127.0.0.1"
os.environ["POSTGRES_PORT"] = "1"
os.environ.setdefault("MQTT_BROKER_HOST", "127.0.0.1")
os.environ.setdefault("MQTT_BROKER_PORT", "1883")

from fastapi import FastAPI
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from app.api.dependencies import get_db
from app.api.routers import citizen as citizen_router
from app.core.security import CITIZEN_SCOPE, create_access_token
from app.db.database import Base
from app.db.models import Citizen, CitizenReport


class CitizenReportsApiTests(unittest.TestCase):
    def setUp(self):
        self.engine = create_engine(
            "sqlite://",
            connect_args={"check_same_thread": False},
            poolclass=StaticPool,
        )
        Base.metadata.create_all(
            self.engine,
            tables=[Citizen.__table__, CitizenReport.__table__],
        )
        self.session_factory = sessionmaker(bind=self.engine, autoflush=False)

        with self.session_factory() as db:
            self.citizen = Citizen(
                public_id="c_testuser",
                install_hash="a" * 64,
                blocked=False,
            )
            other_citizen = Citizen(
                public_id="c_otheruser",
                install_hash="b" * 64,
                blocked=False,
            )
            db.add_all([self.citizen, other_citizen])
            db.flush()

            base_time = datetime(2026, 1, 1, tzinfo=timezone.utc)
            self.old_problem = self._add_report(
                db, self.citizen.id, "problem", base_time, "Problema precedente"
            )
            self.recent_problem = self._add_report(
                db, self.citizen.id, "problem", base_time + timedelta(days=1), "Problema recente"
            )
            self.suggestion = self._add_report(
                db, self.citizen.id, "suggestion", base_time + timedelta(days=2), "Una nuova idea"
            )
            self.other_problem = self._add_report(
                db, other_citizen.id, "problem", base_time + timedelta(days=3), "Problema altrui"
            )
            db.commit()
            self.citizen_public_id = self.citizen.public_id

        app = FastAPI()
        app.include_router(citizen_router.router, prefix="/citizen")

        def override_get_db():
            with self.session_factory() as db:
                yield db

        app.dependency_overrides[get_db] = override_get_db
        token = create_access_token(
            data={"sub": f"citizen:{self.citizen_public_id}", "scope": CITIZEN_SCOPE},
            expires_delta=timedelta(minutes=5),
        )
        self.client = TestClient(app)
        self.headers = {"Authorization": f"Bearer {token}"}

    def tearDown(self):
        self.client.close()
        self.engine.dispose()

    @staticmethod
    def _add_report(db, citizen_id, kind, created_at, description):
        report = CitizenReport(
            citizen_id=citizen_id,
            park_id=1,
            kind=kind,
            description=description,
            client_ref=str(uuid4()),
            status="received",
            created_at=created_at,
            updated_at=created_at,
        )
        db.add(report)
        db.flush()
        return report.id

    def test_list_reports_filters_kind_and_citizen_before_pagination(self):
        response = self.client.get(
            "/citizen/reports?kind=problem&limit=1",
            headers=self.headers,
        )
        self.assertEqual(response.status_code, 200)
        page = response.json()
        self.assertEqual(set(page), {"items", "total"})
        self.assertEqual(page["total"], 2)
        self.assertEqual([item["id"] for item in page["items"]], [self.recent_problem])
        self.assertNotIn(self.suggestion, [item["id"] for item in page["items"]])
        self.assertNotIn(self.other_problem, [item["id"] for item in page["items"]])

        item = page["items"][0]
        self.assertTrue(
            {"id", "code", "summary", "status_label", "created_at"}.issubset(item)
        )
        self.assertEqual(item["kind"], "problem")
        self.assertEqual(item["code"], f"SEG-2026-{self.recent_problem:06d}")
        self.assertEqual(item["summary"], "Problema recente")
        self.assertEqual(item["status_label"], "Ricevuta")
        self.assertEqual(
            datetime.fromisoformat(item["created_at"].replace("Z", "+00:00")),
            datetime(2026, 1, 2, tzinfo=timezone.utc),
        )

        response = self.client.get(
            "/citizen/reports?kind=problem",
            headers=self.headers,
        )
        self.assertEqual(response.status_code, 200)
        problem_page = response.json()
        self.assertEqual(problem_page["total"], 2)
        self.assertEqual(
            [item["id"] for item in problem_page["items"]],
            [self.recent_problem, self.old_problem],
        )
        self.assertNotIn(self.other_problem, [item["id"] for item in problem_page["items"]])

        response = self.client.get("/citizen/reports", headers=self.headers)
        self.assertEqual(response.status_code, 200)
        all_page = response.json()
        self.assertEqual(all_page["total"], 3)
        self.assertEqual(
            {item["id"] for item in all_page["items"]},
            {self.old_problem, self.recent_problem, self.suggestion},
        )
        self.assertNotIn(self.other_problem, [item["id"] for item in all_page["items"]])


if __name__ == "__main__":
    unittest.main()
