"""One-shot Lambda that runs the DB cleanup SQL.
Gets deployed, invoked once, then deleted by the surrounding shell script.
SQL is embedded so we don't need to ship a separate file."""

import os
import psycopg2

SQL_SCRIPT = r"""
DELETE FROM actuator_current_states
WHERE propertyid IN (
    SELECT propertyid FROM actuator_properties
    WHERE deviceid IN (
        '69ddf0d3-563a-49fd-ade2-35f929f0bd05',
        'dcab0373-e1b2-4714-8718-49a8d2e9055a'
    )
);

DELETE FROM actuator_properties
WHERE deviceid IN (
    '69ddf0d3-563a-49fd-ade2-35f929f0bd05',
    'dcab0373-e1b2-4714-8718-49a8d2e9055a'
);

DELETE FROM devices
WHERE deviceid IN (
    '69ddf0d3-563a-49fd-ade2-35f929f0bd05',
    'dcab0373-e1b2-4714-8718-49a8d2e9055a'
);

UPDATE devices
SET device_name = 'Oven'
WHERE deviceid = '238a35b9-f593-4c30-89a2-f43d0141a4f9';

DELETE FROM actuator_current_states
WHERE propertyid IN (
    SELECT propertyid FROM actuator_properties
    WHERE deviceid IN (
        '3d35eb4d-fbb8-4ad0-8331-db1ec14fcd91',
        'c608414b-3c92-4c9c-aef9-4921ec3b8234'
    )
);

DELETE FROM actuator_properties
WHERE deviceid IN (
    '3d35eb4d-fbb8-4ad0-8331-db1ec14fcd91',
    'c608414b-3c92-4c9c-aef9-4921ec3b8234'
);

DELETE FROM devices
WHERE deviceid IN (
    '3d35eb4d-fbb8-4ad0-8331-db1ec14fcd91',
    'c608414b-3c92-4c9c-aef9-4921ec3b8234'
);
"""

VERIFY_SQL = """
SELECT deviceid, device_name, device_type FROM devices
WHERE deviceid IN (
    '69ddf0d3-563a-49fd-ade2-35f929f0bd05',
    'dcab0373-e1b2-4714-8718-49a8d2e9055a',
    '3d35eb4d-fbb8-4ad0-8331-db1ec14fcd91',
    'c608414b-3c92-4c9c-aef9-4921ec3b8234',
    '238a35b9-f593-4c30-89a2-f43d0141a4f9'
);
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

        # Run all DDL/DML in a single transaction. psycopg2 starts an
        # implicit transaction; we rely on conn.commit() / rollback() to
        # finalize, so the script does NOT need its own BEGIN/COMMIT.
        cur.execute(SQL_SCRIPT)

        # Verify within the same transaction (before commit) — sanity only.
        cur.execute(VERIFY_SQL)
        remaining = [
            {"deviceid": r[0], "device_name": r[1], "device_type": r[2]}
            for r in cur.fetchall()
        ]

        # Sanity: only the renamed Oven row should still be in the result set.
        only_oven = (
            len(remaining) == 1
            and remaining[0]["deviceid"] == "238a35b9-f593-4c30-89a2-f43d0141a4f9"
            and remaining[0]["device_name"] == "Oven"
        )

        if not only_oven:
            conn.rollback()
            return {
                "status": "error",
                "reason": "verification failed — rolled back",
                "remaining_rows": remaining,
            }

        conn.commit()
        return {
            "status": "ok",
            "verification_after_cleanup": remaining,
        }

    except Exception as e:
        if conn is not None:
            conn.rollback()
        return {"status": "error", "reason": str(e)}
    finally:
        if conn is not None:
            conn.close()
