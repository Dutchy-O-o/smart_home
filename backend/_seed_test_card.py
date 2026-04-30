"""Insert a test authorized card so we can verify the authorized path."""

import os
import psycopg2

HOME_ID = "757bfcc9-a80b-4886-a8cd-854392454caf"
TEST_UID = "TEST_AUTH_001"
LABEL = "Test Card 1"


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
        cur = conn.cursor()
        cur.execute(
            """
            INSERT INTO authorized_cards (homeid, card_uid, label)
            VALUES (%s, %s, %s)
            ON CONFLICT (homeid, card_uid) DO UPDATE SET
              label = EXCLUDED.label,
              is_active = true
            RETURNING cardid, label, is_active
            """,
            (HOME_ID, TEST_UID, LABEL),
        )
        row = cur.fetchone()
        conn.commit()
        return {
            "status": "ok",
            "cardid": str(row[0]),
            "label": row[1],
            "is_active": row[2],
        }
    except Exception as e:
        return {"status": "error", "reason": str(e)}
    finally:
        if conn is not None:
            conn.close()
