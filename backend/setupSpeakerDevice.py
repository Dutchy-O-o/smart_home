"""Device admin Lambda. Supports actions:

  {"action": "inspect",     "home_id": "<uuid>"}   → list speakers + properties
  {"action": "inspect_all", "home_id": "<uuid>"}   → list ALL devices + properties
  {"action": "rollback",    "home_id": "<uuid>"}   → delete the seeded speaker
        (deterministic uuid5 device id) — legacy cleanup.
  {"action": "delete_device", "device_id": "<uuid>"} → delete a device row +
        its actuator_properties + actuator_current_states (cascades manually).

Used as a one-shot admin tool from the workstation; no end-user invocation."""
import json
import os
import uuid
import psycopg2
from psycopg2.extras import RealDictCursor

NAMESPACE_DEVICE = uuid.UUID('5a1c8b3e-3f4a-4d2c-9b6e-2d1f7a8c4b5d')

conn = None

def get_conn():
    global conn
    if conn is None or conn.closed != 0:
        conn = psycopg2.connect(
            host=os.environ['DB_HOST'],
            user=os.environ['DB_USER'],
            password=os.environ['DB_PASSWORD'],
            dbname=os.environ['DB_NAME'],
            port=os.environ.get('DB_PORT', '5432'),
            connect_timeout=5,
        )
    return conn

_DEVICES_QUERY_TPL = """
    SELECT d.deviceid, d.device_type, d.device_name,
           COALESCE(json_agg(
               json_build_object(
                   'property_name', ap.property_name,
                   'current_value', acs.current_value
               )
           ) FILTER (WHERE ap.property_name IS NOT NULL), '[]'::json) AS properties
    FROM devices d
    LEFT JOIN actuator_properties ap ON ap.deviceid = d.deviceid
    LEFT JOIN actuator_current_states acs ON acs.propertyid = ap.propertyid
    WHERE d.homeid = %s {extra_filter}
    GROUP BY d.deviceid, d.device_type, d.device_name
    ORDER BY d.device_type, d.device_name
"""


def _query_devices(cur, home_id, extra_filter, params):
    cur.execute(_DEVICES_QUERY_TPL.format(extra_filter=extra_filter), params)
    return [{
        'deviceid': str(r['deviceid']),
        'device_type': r['device_type'],
        'device_name': r['device_name'],
        'properties': r['properties'],
    } for r in cur.fetchall()]


def inspect(cur, home_id):
    return _query_devices(cur, home_id, "AND d.device_type = 'speaker'", (home_id,))


def inspect_all(cur, home_id):
    return _query_devices(cur, home_id, "", (home_id,))


def delete_device(cur, device_id):
    """Removes a device row plus its property + state rows. Idempotent."""
    cur.execute(
        """DELETE FROM actuator_current_states
           WHERE propertyid IN (
               SELECT propertyid FROM actuator_properties WHERE deviceid = %s
           )""",
        (device_id,),
    )
    states_deleted = cur.rowcount
    cur.execute("DELETE FROM actuator_properties WHERE deviceid = %s", (device_id,))
    props_deleted = cur.rowcount
    cur.execute("DELETE FROM devices WHERE deviceid = %s", (device_id,))
    devs_deleted = cur.rowcount
    return {
        'device_id': device_id,
        'devices_deleted': devs_deleted,
        'properties_deleted': props_deleted,
        'states_deleted': states_deleted,
    }

def rollback(cur, home_id):
    seeded_id = str(uuid.uuid5(NAMESPACE_DEVICE, home_id))
    cur.execute("""DELETE FROM actuator_current_states
                   WHERE propertyid IN (
                       SELECT propertyid FROM actuator_properties WHERE deviceid = %s
                   )""", (seeded_id,))
    states_deleted = cur.rowcount
    cur.execute("DELETE FROM actuator_properties WHERE deviceid = %s", (seeded_id,))
    props_deleted = cur.rowcount
    cur.execute("DELETE FROM devices WHERE deviceid = %s", (seeded_id,))
    devs_deleted = cur.rowcount
    return {
        'deleted_device_id': seeded_id,
        'devices_deleted': devs_deleted,
        'properties_deleted': props_deleted,
        'states_deleted': states_deleted,
    }

def lambda_handler(event, context):
    action = event.get('action', 'inspect')
    home_id = event.get('home_id')
    device_id = event.get('device_id')

    db = get_conn()
    cur = db.cursor(cursor_factory=RealDictCursor)
    try:
        if action == 'inspect':
            if not home_id:
                return {'statusCode': 400, 'body': json.dumps({'error': 'home_id required'})}
            return {'statusCode': 200, 'body': json.dumps({
                'home_id': home_id, 'speakers': inspect(cur, home_id),
            }, default=str)}

        if action == 'inspect_all':
            if not home_id:
                return {'statusCode': 400, 'body': json.dumps({'error': 'home_id required'})}
            return {'statusCode': 200, 'body': json.dumps({
                'home_id': home_id, 'devices': inspect_all(cur, home_id),
            }, default=str)}

        if action == 'rollback':
            if not home_id:
                return {'statusCode': 400, 'body': json.dumps({'error': 'home_id required'})}
            result = rollback(cur, home_id)
            db.commit()
            return {'statusCode': 200, 'body': json.dumps({
                'home_id': home_id,
                'rollback': result,
                'speakers_after': inspect(cur, home_id),
            }, default=str)}

        if action == 'delete_device':
            if not device_id:
                return {'statusCode': 400, 'body': json.dumps({'error': 'device_id required'})}
            result = delete_device(cur, device_id)
            db.commit()
            return {'statusCode': 200, 'body': json.dumps(result, default=str)}

        return {'statusCode': 400, 'body': json.dumps({'error': f'unknown action {action}'})}
    except Exception as e:
        db.rollback()
        return {'statusCode': 500, 'body': json.dumps({'error': str(e)})}
    finally:
        cur.close()
