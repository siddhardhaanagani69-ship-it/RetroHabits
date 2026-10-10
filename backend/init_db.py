"""Apply schema.sql to the database in DATABASE_URL. Safe to re-run."""
import os
from pathlib import Path

import psycopg
from dotenv import load_dotenv

load_dotenv(Path(__file__).with_name(".env"))
with psycopg.connect(os.environ["DATABASE_URL"]) as conn:
    conn.execute(Path(__file__).with_name("schema.sql").read_text())
print("schema applied")
