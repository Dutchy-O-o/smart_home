"""Create authorized_cards + access_log tables. Idempotent — safe to run
multiple times."""

import os
import psycopg2

MIGRATION = """
CREATE TABLE IF NOT EXISTS authorized_cards (
    cardid       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    homeid       UUID NOT NULL,
    card_uid     TEXT NOT NULL,
    label        TEXT NOT NULL,
    bound_userid UUID,
    added_by     UUID,
    added_at     TIMESTAMP NOT NULL DEFAULT NOW(),
    expires_at   TIMESTAMP,
    is_active    BOOLEAN NOT NULL DEFAULT true,
    UNIQUE (homeid, card_uid)
);

CREATE INDEX IF NOT EXISTS idx_authorized_cards_home_active
    ON authorized_cards(homeid, is_active);

CREATE TABLE IF NOT EXISTS access_log (
    logid       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    homeid      UUID NOT NULL,
    card_uid    TEXT NOT NULL,
    card_label  TEXT,
    result      TEXT NOT NULL CHECK (result IN ('authorized', 'denied', 'expired')),
    scanned_at  TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_access_log_home_time
    ON access_log(homeid, scanned_at DESC);
"""


def lambda_handler(event, context):
    conn = None
    try:
        conn = psycopg2.connect(
            host=os.environ['DB_HOST'],
            user=os.environ['DB_USER'],
            password=os.environ['DB_PASSWORD'],
            dbname=os.environ['DB_NAME'],
            connect_timeout=10,
        )
        conn.autocommit = False
        cur = conn.cursor()
        cur.execute(MIGRATION)

        cur.execute("""
            SELECT table_name, column_name FROM information_schema.columns
            WHERE table_schema = 'public'
              AND table_name IN ('authorized_cards', 'access_log')
            ORDER BY table_name, ordinal_position
        """)
        cols = cur.fetchall()
        conn.commit()
        return {
            "status": "ok",
            "schema_after": [{"table": r[0], "column": r[1]} for r in cols],
        }
    except Exception as e:
        if conn is not None:
            conn.rollback()
        return {"status": "error", "reason": str(e)}
    finally:
        if conn is not None:
            conn.close()
