"""
GET /prod/{homeID}/emotion-history?days=7

Returns the user's mood entries for the last N days (default 7).
Reads from the existing `ai_analyses` table — no schema changes
required, since saveEmotionAnalysis already writes there.

Deployment notes:
  - Lambda runtime: Python 3.11+
  - IAM: same role as getLatestEmotion (psycopg2 layer + RDS access)
  - Env vars: DB_HOST, DB_NAME, DB_USER, DB_PASSWORD
  - API Gateway: GET /{homeID}/emotion-history
      - Authorization: Cognito User Pool authorizer (matches existing routes)
      - Query string: days (optional, integer 1-30, defaults to 7)

Response shape:
  {
    "entries": [
      {"emotion": "happy", "confidence": 0.94, "timestamp": "2026-05-08T17:32:11Z"},
      ...
    ]
  }
"""
import os
import json
import psycopg2


def lambda_handler(event, context):
    try:
        path_parameters = event.get('pathParameters') or {}
        home_id = path_parameters.get('homeID')
        if not home_id:
            return _resp(400, {"error": "Missing homeID in path."})

        # Cognito sub from authorizer claims, mirroring getLatestEmotion.
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

        # Days range, clamped to [1, 30] so a runaway query can't dump
        # the whole table for a malicious caller.
        qs = event.get('queryStringParameters') or {}
        days_raw = qs.get('days', '7')
        try:
            days = int(days_raw)
        except (TypeError, ValueError):
            days = 7
        days = max(1, min(30, days))

        conn = psycopg2.connect(
            host=os.environ['DB_HOST'],
            user=os.environ['DB_USER'],
            password=os.environ['DB_PASSWORD'],
            dbname=os.environ['DB_NAME'],
            connect_timeout=5,
        )
        cur = conn.cursor()

        # Note: column names match getLatestEmotion (detected_emotion,
        # confidence_score, timestamp). make_interval lets us pass the
        # bound `days` integer through psycopg2's parameter binding
        # without manual string concat.
        query = """
            SELECT detected_emotion, confidence_score, timestamp
            FROM ai_analyses
            WHERE homeid = %s
              AND userid = %s
              AND timestamp >= NOW() - make_interval(days => %s)
            ORDER BY timestamp ASC
        """
        cur.execute(query, (home_id, user_id, days))
        rows = cur.fetchall()

        cur.close()
        conn.close()

        # PostgreSQL `timestamp without time zone` columns store UTC on
        # this RDS instance but isoformat() produces a naive string the
        # client would parse as local time — drifting the heatmap by
        # the device's timezone offset. Append 'Z' so the Dart side
        # parses as UTC and converts to local for display.
        entries = [
            {
                "emotion": row[0],
                "confidence": float(row[1]) if row[1] is not None else 0.0,
                "timestamp": row[2].isoformat() + "Z" if row[2] else None,
            }
            for row in rows
        ]

        return _resp(200, {"entries": entries, "days": days})

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
