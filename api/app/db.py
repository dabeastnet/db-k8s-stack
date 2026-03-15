"""
Database configuration and session creation utilities.

This module creates a SQLAlchemy engine and a session factory using
environment variables for configuration. It is imported by both the
application code and the Alembic migration environment.
"""

import os
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker, declarative_base

# Read database connection parameters from environment variables. The
# DATABASE_URL should be in the form:
# postgresql+psycopg2://user:password@host:port/dbname

DATABASE_URL = os.getenv("DATABASE_URL")
if not DATABASE_URL:
    # Fall back to individual environment variables for convenience
    db_user = os.getenv("DB_USER", "postgres")
    db_password = os.getenv("DB_PASSWORD", "postgres")
    db_name = os.getenv("DB_NAME", "postgres")
    db_host = os.getenv("DB_HOST", "localhost")
    db_port = os.getenv("DB_PORT", "5432")
    DATABASE_URL = f"postgresql+psycopg2://{db_user}:{db_password}@{db_host}:{db_port}/{db_name}"

engine = create_engine(
    DATABASE_URL,
    pool_pre_ping=True,
    pool_size=int(os.getenv("DB_POOL_SIZE", "5")),
    max_overflow=int(os.getenv("DB_MAX_OVERFLOW", "10")),
)

# Session factory
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)

# Declarative base for models
Base = declarative_base()