"""
SQLAlchemy models used by the API and migrations.
"""

from sqlalchemy import Column, Integer, String
from .db import Base


class Person(Base):
    __tablename__ = "person"

    id = Column(Integer, primary_key=True, index=True)
    name = Column(String(255), nullable=False)