"""Read current actuator state for our 3 target devices, post-test."""

import os
import psycopg2

TARGETS = {
    "16cb9159-69d5-408c-80a3-9a7ca388db47": "AC",
    "238a35b9-f593-4c30-89a2-f43d0141a4f9": "Oven",
    "5d1fd81d-6eb6-4a94-a152-f3acf0fb466c": "TV",
}


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
            SELECT d.deviceid, d.device_name, ap.property_name,
                   acs.current_value, acs.last_updated
            FROM devices d
            JOIN actuator_properties ap ON ap.deviceid = d.deviceid
            LEFT JOIN actuator_current_states acs ON acs.propertyid = ap.propertyid
            WHERE d.deviceid = ANY(%s::uuid[])
            ORDER BY d.device_name, ap.property_name
            """,
            (list(TARGETS.keys()),),
        )
        rows = cur.fetchall()
        return {
            "status": "ok",
            "rows": [
                {
                    "device": TARGETS.get(r[0], r[0]),
                    "deviceid": r[0],
                    "device_name": r[1],
                    "property": r[2],
                    "value": r[3],
                    "last_updated": r[4].isoformat() if r[4] else None,
                }
                for r in rows
            ],
        }
    except Exception as e:
        return {"status": "error", "reason": str(e)}
    finally:
        if conn is not None:
            conn.close()
