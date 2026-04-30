"""Read-only check: list devices + their actuator properties for the user's
home. Used once to confirm what the Raspi needs to handle. The wrapper
shell script creates a temp Lambda, invokes it, and deletes it."""

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
            SELECT d.deviceid, d.device_name, d.device_type,
                   COALESCE(array_agg(ap.property_name)
                       FILTER (WHERE ap.property_name IS NOT NULL),
                       '{}') AS properties
            FROM devices d
            LEFT JOIN actuator_properties ap ON ap.deviceid = d.deviceid
            WHERE d.homeid = %s
            GROUP BY d.deviceid, d.device_name, d.device_type
            ORDER BY d.device_type, d.device_name;
            """,
            (HOME_ID,),
        )
        rows = cur.fetchall()
        return {
            "status": "ok",
            "home_id": HOME_ID,
            "devices": [
                {
                    "deviceid": r[0],
                    "device_name": r[1],
                    "device_type": r[2],
                    "properties": list(r[3]),
                }
                for r in rows
            ],
        }
    except Exception as e:
        return {"status": "error", "reason": str(e)}
    finally:
        if conn is not None:
            conn.close()
