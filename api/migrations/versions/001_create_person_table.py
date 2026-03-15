"""Create person table and seed initial data

Revision ID: 001_create_person_table
Revises: 
Create Date: 2026-03-13 00:00:00.000000

"""
from alembic import op
import sqlalchemy as sa

# revision identifiers, used by Alembic.
revision = '001_create_person_table'
down_revision = None
branch_labels = None
depends_on = None


def upgrade() -> None:
    # Create person table
    op.create_table(
        'person',
        sa.Column('id', sa.Integer, primary_key=True, autoincrement=True),
        sa.Column('name', sa.String(length=255), nullable=False),
    )
    # Seed the table with a default name
    op.execute(
        "INSERT INTO person (name) VALUES ('Dieter Beckers')"
    )


def downgrade() -> None:
    op.drop_table('person')