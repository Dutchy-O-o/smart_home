"""
GET /prod/{homeID}/sensor-history?hours=12&types=temperature,humidity

Returns sensor readings for the home over the last N hours, joining
SENSOR_DATA with the home's devices. Powers the dashboard's 12-hour
temperature / humidity sparkline so users see real history pulled
from RDS instead of waiting for local polling to fill the buffer.

Deployment notes:
  - Lambda runtime: Python 3.11+
  - IAM: same role as recordSensorData / getLatestEmotion (psycopg2
    layer + RDS access, ideally inside the same VPC subnet).
  - Env vars: DB_HOST, DB_NAME, DB_USER, DB_PASSWORD
  - API Gateway: GET /{homeID}/sensor-history
      - Authorization: Cognito User Pool authorizer
      - Query string: hours (optional 1-72, default 12),
                      types (optional comma list, default temperature,humidity)

Response shape:
  {
    "hours": 12,
    "readings": [
      {"timestamp": "2026-05-08T17:30:00Z", "temperature": 22.4, "humidity": 47.0},
      ...
    ]
  }
"""
import os
import json
from collections import defaultdict
import psycopg2


def lambda_handler(event, context):
    try:
        path_parameters = event.get('pathParameters') or {}
        home_id = path_parameters.get('homeID')
        if not home_id:
            return _resp(400, {"error": "Missing homeID in path."})

        qs = event.get('queryStringParameters') or {}
        try:
            hours = int(qs.get('hours', '12'))
        except (TypeError, ValueError):
            hours = 12
        hours = max(1, min(72, hours))

        types_raw = qs.get('types', 'temperature,humidity')
        sensor_types = [t.strip() for t in types_raw.split(',') if t.strip()]
        if not sensor_types:
            sensor_types = ['temperature', 'humidity']

        conn = psycopg2.connect(
            host=os.environ['DB_HOST'],
            user=os.environ['DB_USER'],
            password=os.environ['DB_PASSWORD'],
            dbname=os.environ['DB_NAME'],
            connect_timeout=5,
        )
        cur = conn.cursor()

        # Pull all rows for this home's devices in the window, then
        # bucket them client-side by 1-minute intervals so the response
        # is small and the chart stays smooth even over long ranges.
        # NOTE: assumes a `devices` table with `homeid` and `deviceid`.
        # Adjust the join if your schema names are different.
        placeholders = ','.join(['%s'] * len(sensor_types))
        query = f"""
            SELECT sd.timestamp, sd.sensor_type, sd.value
            FROM SENSOR_DATA sd
            JOIN devices d ON d.deviceid = sd.deviceid
            WHERE d.homeid = %s
              AND sd.sensor_type IN ({placeholders})
              AND sd.timestamp >= NOW() - make_interval(hours => %s)
            ORDER BY sd.timestamp ASC
        """
        cur.execute(query, (home_id, *sensor_types, hours))
        rows = cur.fetchall()

        cur.close()
        conn.close()

        # Group by minute bucket, average duplicate readings so multiple
        # sensors don't produce noisy spikes. Appending 'Z' marks the
        # timestamp as UTC so the client doesn't reinterpret it as
        # local time and drift the chart by the timezone offset.
        buckets = defaultdict(lambda: defaultdict(list))
        for ts, stype, val in rows:
            minute = ts.replace(second=0, microsecond=0).isoformat() + "Z"
            try:
                v = float(val)
            except (TypeError, ValueError):
                continue
            buckets[minute][stype].append(v)

        readings = []
        for minute in sorted(buckets.keys()):
            entry = {"timestamp": minute}
            for stype in sensor_types:
                vals = buckets[minute].get(stype) or []
                if vals:
                    entry[stype] = sum(vals) / len(vals)
            readings.append(entry)

        return _resp(200, {
            "hours": hours,
            "types": sensor_types,
            "readings": readings,
        })

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
