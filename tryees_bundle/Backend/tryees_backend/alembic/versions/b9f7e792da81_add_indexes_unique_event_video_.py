"""add indexes, unique event_video, composite practice index

Revision ID: b9f7e792da81
Revises: 8e4a71d61114
Create Date: 2026-09-17 00:13:51.456856

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'b9f7e792da81'
down_revision: Union[str, Sequence[str], None] = '8e4a71d61114'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    op.execute("CREATE INDEX IF NOT EXISTS ix_event_mac_address ON event (mac_address)")
    op.execute("CREATE INDEX IF NOT EXISTS ix_event_transmission_time ON event (transmission_time)")
    op.execute("CREATE INDEX IF NOT EXISTS ix_event_type ON event (type)")
    op.execute("DROP INDEX IF EXISTS ix_event_video_id_event")
    op.execute("CREATE UNIQUE INDEX ix_event_video_id_event ON event_video (id_event)")
    op.execute("CREATE INDEX IF NOT EXISTS ix_practice_category ON practice (category)")
    op.execute("CREATE INDEX IF NOT EXISTS ix_practice_created_at ON practice (created_at)")
    op.execute("CREATE INDEX IF NOT EXISTS ix_practice_status ON practice (status)")
    op.execute("CREATE INDEX IF NOT EXISTS ix_practice_status_category_created ON practice (status, category, created_at)")


def downgrade() -> None:
    """Downgrade schema."""
    op.execute("DROP INDEX IF EXISTS ix_practice_status_category_created")
    op.execute("DROP INDEX IF EXISTS ix_practice_status")
    op.execute("DROP INDEX IF EXISTS ix_practice_created_at")
    op.execute("DROP INDEX IF EXISTS ix_practice_category")
    op.execute("DROP INDEX IF EXISTS ix_event_video_id_event")
    op.execute("CREATE INDEX IF NOT EXISTS ix_event_video_id_event ON event_video (id_event)")
    op.execute("DROP INDEX IF EXISTS ix_event_type")
    op.execute("DROP INDEX IF EXISTS ix_event_transmission_time")
    op.execute("DROP INDEX IF EXISTS ix_event_mac_address")
