import os
import psycopg2
import psycopg2.extras
from contextlib import contextmanager


def get_connection():
    return psycopg2.connect(
        host=os.getenv("POSTGRES_HOST", "localhost"),
        port=os.getenv("POSTGRES_PORT", "5432"),
        user=os.getenv("POSTGRES_USER", "aiserver"),
        password=os.getenv("POSTGRES_PASSWORD", ""),
        database=os.getenv("POSTGRES_DB", "aiserver_db"),
    )


@contextmanager
def get_db():
    conn = get_connection()
    cur = conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)
    try:
        yield conn, cur
        conn.commit()
    except Exception as e:
        conn.rollback()
        raise e
    finally:
        cur.close()
        conn.close()


def query(sql, params=None):
    with get_db() as (conn, cur):
        cur.execute(sql, params)
        return [dict(row) for row in cur.fetchall()]


def execute(sql, params=None):
    with get_db() as (conn, cur):
        cur.execute(sql, params)
        try:
            return [dict(row) for row in cur.fetchall()]
        except psycopg2.ProgrammingError:
            return None
