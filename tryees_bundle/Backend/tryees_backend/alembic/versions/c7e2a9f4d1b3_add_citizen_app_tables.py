"""add citizen app tables, citizen event type, park radius

Revision ID: c7e2a9f4d1b3
Revises: a1b2c3d4e5f6
Create Date: 2026-10-28 00:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'c7e2a9f4d1b3'
down_revision: Union[str, Sequence[str], None] = 'a1b2c3d4e5f6'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    op.execute("ALTER TYPE type_event ADD VALUE IF NOT EXISTS 'citizen'")
    # Gli eventi 'citizen' non hanno un device
    op.alter_column('event', 'mac_address', existing_type=sa.String(), nullable=True)
    op.add_column('park', sa.Column('radius_m', sa.Float(), nullable=True))

    op.create_table('citizen',
    sa.Column('id', sa.Integer(), nullable=False),
    sa.Column('public_id', sa.String(), nullable=False),
    sa.Column('install_hash', sa.String(length=64), nullable=False),
    sa.Column('platform', sa.String(), nullable=True),
    sa.Column('app_version', sa.String(), nullable=True),
    sa.Column('blocked', sa.Boolean(), nullable=False),
    sa.Column('created_at', sa.DateTime(timezone=True), nullable=True),
    sa.Column('last_seen_at', sa.DateTime(timezone=True), nullable=True),
    sa.PrimaryKeyConstraint('id')
    )
    op.create_index(op.f('ix_citizen_id'), 'citizen', ['id'], unique=False)
    op.create_index(op.f('ix_citizen_public_id'), 'citizen', ['public_id'], unique=True)
    op.create_index(op.f('ix_citizen_install_hash'), 'citizen', ['install_hash'], unique=True)

    op.create_table('citizen_category',
    sa.Column('code', sa.String(), nullable=False),
    sa.Column('label', sa.String(), nullable=False),
    sa.Column('icon', sa.String(), nullable=True),
    sa.Column('kinds', sa.String(), nullable=False),
    sa.Column('practice_category', sa.String(), nullable=False),
    sa.Column('merge_types', sa.String(), nullable=True),
    sa.Column('sort_order', sa.Integer(), nullable=False),
    sa.Column('active', sa.Boolean(), nullable=False),
    sa.PrimaryKeyConstraint('code')
    )

    op.create_table('citizen_report',
    sa.Column('id', sa.Integer(), nullable=False),
    sa.Column('citizen_id', sa.Integer(), nullable=False),
    sa.Column('park_id', sa.Integer(), nullable=False),
    sa.Column('kind', sa.String(), nullable=False),
    sa.Column('category', sa.String(), nullable=True),
    sa.Column('description', sa.String(length=1000), nullable=False),
    sa.Column('priority', sa.String(), nullable=True),
    sa.Column('lat', sa.Float(), nullable=True),
    sa.Column('lon', sa.Float(), nullable=True),
    sa.Column('rating', sa.Integer(), nullable=True),
    sa.Column('photo_path', sa.String(), nullable=True),
    sa.Column('client_ref', sa.String(length=36), nullable=False),
    sa.Column('status', sa.String(), nullable=False),
    sa.Column('practice_id', sa.Integer(), nullable=True),
    sa.Column('event_id', sa.Integer(), nullable=True),
    sa.Column('created_at', sa.DateTime(timezone=True), nullable=True),
    sa.Column('updated_at', sa.DateTime(timezone=True), nullable=True),
    sa.ForeignKeyConstraint(['citizen_id'], ['citizen.id'], ondelete='CASCADE'),
    sa.ForeignKeyConstraint(['park_id'], ['park.id'], ),
    sa.ForeignKeyConstraint(['category'], ['citizen_category.code'], ),
    sa.ForeignKeyConstraint(['practice_id'], ['practice.id'], ondelete='SET NULL'),
    sa.ForeignKeyConstraint(['event_id'], ['event.id'], ondelete='SET NULL'),
    sa.PrimaryKeyConstraint('id'),
    sa.UniqueConstraint('citizen_id', 'client_ref', name='uq_citizen_report_client_ref')
    )
    op.create_index(op.f('ix_citizen_report_id'), 'citizen_report', ['id'], unique=False)
    op.create_index(op.f('ix_citizen_report_practice_id'), 'citizen_report', ['practice_id'], unique=False)
    op.create_index('ix_citizen_report_citizen_created', 'citizen_report', ['citizen_id', 'created_at'], unique=False)

    op.create_table('citizen_report_history',
    sa.Column('id', sa.Integer(), nullable=False),
    sa.Column('report_id', sa.Integer(), nullable=False),
    sa.Column('status', sa.String(), nullable=False),
    sa.Column('note', sa.String(), nullable=True),
    sa.Column('at', sa.DateTime(timezone=True), nullable=True),
    sa.ForeignKeyConstraint(['report_id'], ['citizen_report.id'], ondelete='CASCADE'),
    sa.PrimaryKeyConstraint('id')
    )
    op.create_index(op.f('ix_citizen_report_history_id'), 'citizen_report_history', ['id'], unique=False)
    op.create_index(op.f('ix_citizen_report_history_report_id'), 'citizen_report_history', ['report_id'], unique=False)

    op.create_table('park_notice',
    sa.Column('id', sa.Integer(), nullable=False),
    sa.Column('park_id', sa.Integer(), nullable=False),
    sa.Column('title', sa.String(length=120), nullable=False),
    sa.Column('body', sa.String(length=1000), nullable=False),
    sa.Column('level', sa.String(), nullable=False),
    sa.Column('starts_at', sa.DateTime(timezone=True), nullable=False),
    sa.Column('ends_at', sa.DateTime(timezone=True), nullable=True),
    sa.Column('created_by', sa.Integer(), nullable=True),
    sa.Column('created_at', sa.DateTime(timezone=True), nullable=True),
    sa.ForeignKeyConstraint(['park_id'], ['park.id'], ),
    sa.ForeignKeyConstraint(['created_by'], ['app_user.id'], ondelete='SET NULL'),
    sa.PrimaryKeyConstraint('id')
    )
    op.create_index(op.f('ix_park_notice_id'), 'park_notice', ['id'], unique=False)
    op.create_index(op.f('ix_park_notice_park_id'), 'park_notice', ['park_id'], unique=False)

    op.create_table('event_citizen',
    sa.Column('event_id', sa.Integer(), nullable=False),
    sa.Column('report_id', sa.Integer(), nullable=True),
    sa.Column('lat', sa.Float(), nullable=True),
    sa.Column('lon', sa.Float(), nullable=True),
    sa.Column('category', sa.String(), nullable=True),
    sa.Column('priority', sa.String(), nullable=True),
    sa.ForeignKeyConstraint(['event_id'], ['event.id'], ondelete='CASCADE'),
    sa.ForeignKeyConstraint(['report_id'], ['citizen_report.id'], ondelete='SET NULL'),
    sa.PrimaryKeyConstraint('event_id')
    )


def downgrade() -> None:
    """Downgrade schema."""
    op.drop_table('event_citizen')
    op.drop_index(op.f('ix_park_notice_park_id'), table_name='park_notice')
    op.drop_index(op.f('ix_park_notice_id'), table_name='park_notice')
    op.drop_table('park_notice')
    op.drop_index(op.f('ix_citizen_report_history_report_id'), table_name='citizen_report_history')
    op.drop_index(op.f('ix_citizen_report_history_id'), table_name='citizen_report_history')
    op.drop_table('citizen_report_history')
    op.drop_index('ix_citizen_report_citizen_created', table_name='citizen_report')
    op.drop_index(op.f('ix_citizen_report_practice_id'), table_name='citizen_report')
    op.drop_index(op.f('ix_citizen_report_id'), table_name='citizen_report')
    op.drop_table('citizen_report')
    op.drop_table('citizen_category')
    op.drop_index(op.f('ix_citizen_install_hash'), table_name='citizen')
    op.drop_index(op.f('ix_citizen_public_id'), table_name='citizen')
    op.drop_index(op.f('ix_citizen_id'), table_name='citizen')
    op.drop_table('citizen')
    op.drop_column('park', 'radius_m')
    # Senza device gli eventi 'citizen' non possono restare con mac_address NOT NULL.
    # Il valore 'citizen' resta nel tipo type_event: PostgreSQL non permette di toglierlo.
    op.execute("DELETE FROM event WHERE mac_address IS NULL")
    op.alter_column('event', 'mac_address', existing_type=sa.String(), nullable=False)
