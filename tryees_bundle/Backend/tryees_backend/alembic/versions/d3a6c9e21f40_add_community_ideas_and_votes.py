"""add community ideas and votes

Revision ID: d3a6c9e21f40
Revises: c7e2a9f4d1b3
Create Date: 2026-11-10
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa

revision: str = "d3a6c9e21f40"
down_revision: Union[str, Sequence[str], None] = "c7e2a9f4d1b3"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column("citizen_report", sa.Column("title", sa.String(length=120), nullable=True))
    op.add_column(
        "citizen_report",
        sa.Column("visibility", sa.String(length=10), server_default="public", nullable=False),
    )
    op.create_table(
        "citizen_idea_vote",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("idea_id", sa.Integer(), nullable=False),
        sa.Column("citizen_id", sa.Integer(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=True),
        sa.ForeignKeyConstraint(["idea_id"], ["citizen_report.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["citizen_id"], ["citizen.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("idea_id", "citizen_id", name="uq_citizen_idea_vote"),
    )
    op.create_index("ix_citizen_idea_vote_id", "citizen_idea_vote", ["id"], unique=False)
    op.create_index("ix_citizen_idea_vote_idea", "citizen_idea_vote", ["idea_id"], unique=False)


def downgrade() -> None:
    op.drop_index("ix_citizen_idea_vote_idea", table_name="citizen_idea_vote")
    op.drop_index("ix_citizen_idea_vote_id", table_name="citizen_idea_vote")
    op.drop_table("citizen_idea_vote")
    op.drop_column("citizen_report", "visibility")
    op.drop_column("citizen_report", "title")
