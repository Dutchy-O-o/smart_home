import os
import json
import psycopg2

def lambda_handler(event, context):
    conn = None
    cur = None
    try:
        print(f"[DELETE] Event: {json.dumps(event)}")

        # 1. homeID from path
        path_params = event.get('pathParameters') or {}
        home_id = path_params.get('homeID')
        if not home_id:
            return _resp(400, {"error": "Missing homeID in path."})

        # 2. rule_id from query params or body
        query_params = event.get('queryStringParameters') or {}
        rule_id = query_params.get('rule_id')

        if not rule_id:
            body_raw = event.get('body') or '{}'
            try:
                body = json.loads(body_raw)
            except Exception:
                body = {}
            rule_id = body.get('rule_id')

        if not rule_id:
            return _resp(400, {"error": "Missing rule_id."})

        print(f"[DELETE] home_id={home_id} rule_id={rule_id}")

        # 3. Fresh DB connection
        conn = psycopg2.connect(
            host=os.environ['DB_HOST'],
            user=os.environ['DB_USER'],
            password=os.environ['DB_PASSWORD'],
            dbname=os.environ['DB_NAME'],
            connect_timeout=5
        )
        conn.autocommit = False
        cur = conn.cursor()

        # 4. Verify rule belongs to this home
        cur.execute(
            "SELECT ruleid FROM automation_rules WHERE ruleid = %s AND homeid = %s",
            (rule_id, home_id)
        )
        if not cur.fetchone():
            print(f"[DELETE] Rule not found: {rule_id}")
            return _resp(404, {"error": "Rule not found."})

        # 5. Cascade delete
        cur.execute("""
            DELETE FROM action_details
            WHERE actionid IN (
                SELECT actionid FROM rule_actions WHERE ruleid = %s
            )
        """, (rule_id,))
        print(f"[DELETE] action_details deleted: {cur.rowcount}")

        cur.execute("DELETE FROM rule_actions WHERE ruleid = %s", (rule_id,))
        print(f"[DELETE] rule_actions deleted: {cur.rowcount}")

        cur.execute("DELETE FROM automation_rules WHERE ruleid = %s", (rule_id,))
        print(f"[DELETE] automation_rules deleted: {cur.rowcount}")

        conn.commit()
        print("[DELETE] Commit OK")

        return _resp(200, {"message": "Deleted.", "rule_id": rule_id})

    except Exception as e:
        print(f"[DELETE] ERROR: {str(e)}")
        if conn:
            try: conn.rollback()
            except: pass
        return _resp(500, {"error": str(e)})
    finally:
        if cur:
            try: cur.close()
            except: pass
        if conn:
            try: conn.close()
            except: pass


def _resp(code, body):
    return {
        'statusCode': code,
        'headers': {
            'Content-Type': 'application/json',
            'Access-Control-Allow-Origin': '*',
        },
        'body': json.dumps(body)
    }
