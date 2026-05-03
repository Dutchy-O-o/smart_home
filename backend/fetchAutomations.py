import json
import os
import psycopg2
from psycopg2.extras import RealDictCursor

CORS_HEADERS = {
    'Content-Type': 'application/json',
    'Access-Control-Allow-Origin': '*'
}


def _connect():
    return psycopg2.connect(
        host=os.environ.get('DB_HOST'),
        database=os.environ.get('DB_NAME'),
        user=os.environ.get('DB_USER'),
        password=os.environ.get('DB_PASSWORD'),
        port=os.environ.get('DB_PORT', '5432')
    )


def _list_rules(home_id):
    """Default behaviour: full automation list for the home."""
    conn = _connect()
    cur = conn.cursor(cursor_factory=RealDictCursor)
    try:
        cur.execute(
            """
            SELECT ruleid, rule_name, trigger_condition, is_enabled
            FROM automation_rules
            WHERE homeid = %s
            ORDER BY rule_name ASC;
            """,
            (home_id,),
        )
        rules = cur.fetchall()

        automations = []
        for rule in rules:
            rule_id = rule['ruleid']

            cur.execute(
                """
                SELECT a.actionid, a.deviceid, d.device_name
                FROM rule_actions a
                LEFT JOIN devices d ON a.deviceid = d.deviceid
                WHERE a.ruleid = %s;
                """,
                (rule_id,),
            )
            actions = cur.fetchall()

            actions_list = []
            for action in actions:
                cur.execute(
                    """
                    SELECT ap.property_name, ad.target_value
                    FROM action_details ad
                    JOIN actuator_properties ap ON ad.propertyid = ap.propertyid
                    WHERE ad.actionid = %s;
                    """,
                    (action['actionid'],),
                )
                details_dict = {
                    dr['property_name']: dr['target_value']
                    for dr in cur.fetchall()
                }
                actions_list.append({
                    "device_id": str(action['deviceid']),
                    "device_name": action['device_name'],
                    "details": details_dict,
                })

            automations.append({
                "rule_id": str(rule_id),
                "rule_name": rule['rule_name'],
                "trigger_condition": rule['trigger_condition'],
                "is_enabled": rule['is_enabled'],
                "actions": actions_list,
            })

        return {"automations": automations}
    finally:
        cur.close()
        conn.close()


def _by_emotion(home_id, emotion):
    """Branched behaviour when ?emotion=X is supplied: returns the device
    actions for active rules whose trigger_condition matches the emotion.

    Accepts both storage formats:
      - bare emotion (e.g. "happy")
      - app-emitted expression (e.g. "emotion == 'happy'")
    """
    conn = _connect()
    cur = conn.cursor(cursor_factory=RealDictCursor)
    try:
        query = """
            SELECT
                r.rule_name,
                a.deviceid,
                d.device_name,
                ap.property_name,
                ad.target_value
            FROM automation_rules r
            JOIN rule_actions a ON r.ruleid = a.ruleid
            JOIN devices d ON a.deviceid = d.deviceid
            JOIN action_details ad ON a.actionid = ad.actionid
            JOIN actuator_properties ap ON ad.propertyid = ap.propertyid
            WHERE r.homeid = %s
              AND (r.trigger_condition = %s OR r.trigger_condition = %s)
              AND r.is_enabled = true;
        """
        expr_form = "emotion == '{}'".format(emotion)
        cur.execute(query, (home_id, emotion, expr_form))
        rows = cur.fetchall()

        actions_dict = {}
        rule_name = rows[0]['rule_name'] if rows else ""

        for row in rows:
            dev_id = row['deviceid']
            if dev_id not in actions_dict:
                actions_dict[dev_id] = {
                    "deviceID": dev_id,
                    "device_name": row['device_name'],
                    "commands": [],
                }
            actions_dict[dev_id]["commands"].append({
                "property_name": row['property_name'],
                "value": row['target_value'],
            })

        return {
            "homeID": home_id,
            "trigger_emotion": emotion,
            "rule_name": rule_name,
            "actions": list(actions_dict.values()),
        }
    finally:
        cur.close()
        conn.close()


def lambda_handler(event, context):
    try:
        path_parameters = event.get('pathParameters') or {}
        home_id = path_parameters.get('homeID')

        if not home_id:
            return {
                'statusCode': 400,
                'headers': CORS_HEADERS,
                'body': json.dumps({'error': 'Missing parameter: homeID'}),
            }

        qs = event.get('queryStringParameters') or {}
        emotion = qs.get('emotion') if qs else None

        if emotion:
            body = _by_emotion(home_id, emotion)
        else:
            body = _list_rules(home_id)

        return {
            'statusCode': 200,
            'headers': CORS_HEADERS,
            'body': json.dumps(body, default=str),
        }

    except Exception as e:
        print(f"Error occurred: {str(e)}")
        return {
            'statusCode': 500,
            'headers': CORS_HEADERS,
            'body': json.dumps({'error': 'Internal server error.', 'details': str(e)}),
        }
