"""
POST /prod/{homeID}/alerts
GET  /prod/{homeID}/alerts?limit=50

Adds a server-side alerts log so the notifications screen can show
the same list across devices instead of only what's been pushed via
FCM to this specific phone.

Schema (create once in RDS — copy/paste in psql or the Lambda console):

  CREATE TABLE IF NOT EXISTS user_alerts (
    alert_id    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    homeid      VARCHAR(64) NOT NULL,
    userid      VARCHAR(64) NOT NULL,
    title       TEXT NOT NULL,
    description TEXT,
    alert_type  VARCHAR(32) NOT NULL,        -- 'security' | 'emotion' | 'device'
    alert_level VARCHAR(16) NOT NULL,        -- 'critical' | 'warning' | 'info'
    is_read     BOOLEAN DEFAULT FALSE,
    created_at  TIMESTAMP NOT NULL DEFAULT NOW()
  );
  CREATE INDEX IF NOT EXISTS idx_user_alerts_owner
    ON user_alerts(homeid, userid, created_at DESC);

Deployment notes:
  - Lambda runtime: Python 3.11+
  - IAM + psycopg2 layer + DB env vars (same as other Lambdas)
  - Two API Gateway routes both point at this Lambda — distinguish by
    event['httpMethod']:
      POST /{homeID}/alerts  → save
      GET  /{homeID}/alerts  → list
  - Both protected by Cognito authorizer.

POST body:
  { "title": "...", "description": "...",
    "alert_type": "device", "alert_level": "info" }

GET response:
  { "alerts": [
      {"id": "...", "title": "...", "description": "...",
       "type": "device", "level": "info", "is_read": false,
       "created_at": "2026-05-08T17:32:11Z"},
      ...
    ]
  }
"""
import os
import json
import uuid
import psycopg2


def lambda_handler(event, context):
    method = event.get('httpMethod', 'GET').upper()
    try:
        path_parameters = event.get('pathParameters') or {}
        home_id = path_parameters.get('homeID')
        if not home_id:
            return _resp(400, {"error": "Missing homeID in path."})

        try:
            user_id = (
                event.get('requestContext', {})
                .get('authorizer', {})
                .get('claims', {})
                .get('sub')
            )
            if not user_id:
                raise ValueError("User ID (sub) not found in token.")
        except Exception as e:
            return _resp(401, {"error": "Unauthorized: " + str(e)})

        conn = psycopg2.connect(
            host=os.environ['DB_HOST'],
            user=os.environ['DB_USER'],
            password=os.environ['DB_PASSWORD'],
            dbname=os.environ['DB_NAME'],
            connect_timeout=5,
        )
        cur = conn.cursor()

        # Idempotent schema bootstrap — runs on first invocation, no-op
        # on every subsequent call. Saves the user from having to open
        # the RDS query editor by hand.
        cur.execute("""
            CREATE TABLE IF NOT EXISTS user_alerts (
              alert_id    VARCHAR(64) PRIMARY KEY,
              homeid      VARCHAR(64) NOT NULL,
              userid      VARCHAR(64) NOT NULL,
              title       TEXT NOT NULL,
              description TEXT,
              alert_type  VARCHAR(32) NOT NULL,
              alert_level VARCHAR(16) NOT NULL,
              is_read     BOOLEAN DEFAULT FALSE,
              created_at  TIMESTAMP NOT NULL DEFAULT NOW()
            )
        """)
        cur.execute("""
            CREATE INDEX IF NOT EXISTS idx_user_alerts_owner
              ON user_alerts(homeid, userid, created_at DESC)
        """)
        conn.commit()

        if method == 'POST':
            body = event.get('body') or '{}'
            payload = json.loads(body)
            title = (payload.get('title') or '').strip()
            description = (payload.get('description') or '').strip()
            alert_type = (payload.get('alert_type') or 'device').lower()
            alert_level = (payload.get('alert_level') or 'info').lower()
            if not title:
                cur.close(); conn.close()
                return _resp(400, {"error": "title is required"})
            if alert_type not in ('security', 'emotion', 'device'):
                alert_type = 'device'
            if alert_level not in ('critical', 'warning', 'info'):
                alert_level = 'info'

            alert_id = str(uuid.uuid4())
            cur.execute(
                """
                INSERT INTO user_alerts
                  (alert_id, homeid, userid, title, description, alert_type, alert_level)
                VALUES (%s, %s, %s, %s, %s, %s, %s)
                """,
                (alert_id, home_id, user_id, title, description, alert_type, alert_level),
            )
            conn.commit()
            cur.close(); conn.close()
            return _resp(200, {"alert_id": alert_id})

        # GET — list recent alerts.
        qs = event.get('queryStringParameters') or {}
        try:
            limit = int(qs.get('limit', '50'))
        except (TypeError, ValueError):
            limit = 50
        limit = max(1, min(200, limit))

        cur.execute(
            """
            SELECT alert_id, title, description, alert_type, alert_level,
                   is_read, created_at
            FROM user_alerts
            WHERE homeid = %s AND userid = %s
            ORDER BY created_at DESC
            LIMIT %s
            """,
            (home_id, user_id, limit),
        )
        rows = cur.fetchall()
        cur.close(); conn.close()

        # Append 'Z' so the client parses this as UTC and converts to
        # local time. Without this, the relative-day grouping in the
        # Notifications screen drifts by the device's timezone offset
        # (Today vs Yesterday slips for entries created near midnight).
        alerts = [
            {
                "id": str(row[0]),
                "title": row[1],
                "description": row[2] or "",
                "type": row[3],
                "level": row[4],
                "is_read": bool(row[5]),
                "created_at": row[6].isoformat() + "Z" if row[6] else None,
            }
            for row in rows
        ]
        return _resp(200, {"alerts": alerts})

    except Exception as e:
        print(f"Error: {e}")
        return _resp(500, {"error": str(e)})


def _resp(code, body):
    return {
        'statusCode': code,
        'headers': {
            'Content-Type': 'application/json',
            'Access-Control-Allow-Origin': '*',
        },
        'body': json.dumps(body),
    }
