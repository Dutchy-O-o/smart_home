"""Drop the unused 'source' property from the TV device — UI removed it,
keeping it in DB would let stale state writes happen."""

import os
import psycopg2

TV_DEVICE_ID = "5d1fd81d-6eb6-4a94-a152-f3acf0fb466c"


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

        cur.execute(
            """
            DELETE FROM actuator_current_states
            WHERE propertyid IN (
                SELECT propertyid FROM actuator_properties
                WHERE deviceid = %s AND property_name = 'source'
            )
            """,
            (TV_DEVICE_ID,),
        )
        cur.execute(
            """
            DELETE FROM actuator_properties
            WHERE deviceid = %s AND property_name = 'source'
            """,
            (TV_DEVICE_ID,),
        )

        cur.execute(
            "SELECT property_name FROM actuator_properties WHERE deviceid = %s ORDER BY property_name",
            (TV_DEVICE_ID,),
        )
        remaining = [r[0] for r in cur.fetchall()]

        if 'source' in remaining:
            conn.rollback()
            return {"status": "error", "reason": "source still present", "remaining": remaining}

        conn.commit()
        return {"status": "ok", "tv_properties_after": remaining}

    except Exception as e:
        if conn is not None:
            conn.rollback()
        return {"status": "error", "reason": str(e)}
    finally:
        if conn is not None:
            conn.close()
