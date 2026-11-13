"""add incident_id to practice for cross-zone correlation

Revision ID: a1b2c3d4e5f6
Revises: 9665f22103bf
Create Date: 2026-09-30 00:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'a1b2c3d4e5f6'
down_revision: Union[str, Sequence[str], None] = '9665f22103bf'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    op.add_column('practice', sa.Column('incident_id', sa.String(), nullable=True))
    op.create_index('ix_practice_incident_id', 'practice', ['incident_id'])


def downgrade() -> None:
    """Downgrade schema."""
    op.drop_index('ix_practice_incident_id', table_name='practice')
    op.drop_column('practice', 'incident_id')
