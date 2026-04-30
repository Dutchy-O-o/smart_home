"""Show recent access_log entries for the test home."""

import os
import psycopg2

HOME_ID = "757bfcc9-a80b-4886-a8cd-854392454caf"


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
            SELECT card_uid, card_label, result, scanned_at
            FROM access_log
            WHERE homeid = %s
            ORDER BY scanned_at DESC
            LIMIT 10
            """,
            (HOME_ID,),
        )
        rows = cur.fetchall()
        return {
            "status": "ok",
            "recent_scans": [
                {
                    "card_uid": r[0],
                    "label": r[1],
                    "result": r[2],
                    "scanned_at": r[3].isoformat() if r[3] else None,
                }
                for r in rows
            ],
        }
    except Exception as e:
        return {"status": "error", "reason": str(e)}
    finally:
        if conn is not None:
            conn.close()
