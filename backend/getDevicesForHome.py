"""getDevicesForHome Lambda

Triggered by AWS IoT Rule `getHomeDevices` on topic `homes/+/devices/get`.
Returns the device list for a home so the Pi can self-configure (find
speaker / RFID / etc deviceIDs) without anything hardcoded in alert.py.

Auth model: scoped by topic (`homes/{HOME}/*`) — Pi's IoT cert (PiPolicy)
already gates which homes it can publish to. No Cognito needed here.

Expected event payload (published by Pi):
    {"home_id": "<uuid>"}            # "action" field optional, ignored

Side effect:
    publish to `homes/{home_id}/devices/response` with `{devices: [...]}`.
"""
import json
import os
import psycopg2
from psycopg2.extras import RealDictCursor
import boto3

iot_client = boto3.client('iot-data')

db_conn = None

def get_connection():
    global db_conn
    if db_conn is None or db_conn.closed != 0:
        db_conn = psycopg2.connect(
            host=os.environ.get('DB_HOST'),
            user=os.environ.get('DB_USER'),
            password=os.environ.get('DB_PASSWORD'),
            dbname=os.environ.get('DB_NAME'),
            connect_timeout=5,
        )
    return db_conn


def lambda_handler(event, context):
    try:
        home_id = event.get('home_id')
        if not home_id:
            print("[ERROR] Payload içinde home_id bulunamadı.")
            return {"status": "error", "message": "Missing home_id"}

        conn = get_connection()
        cursor = conn.cursor(cursor_factory=RealDictCursor)
        cursor.execute(
            'SELECT deviceid, device_type, device_name FROM devices WHERE "homeid" = %s',
            (home_id,),
        )
        records = cursor.fetchall()

        devices_output = [
            {
                "deviceid": str(row['deviceid']),
                "device_type": row['device_type'],
                "device_name": row['device_name'],
            }
            for row in records
        ]

        response_topic = f"homes/{home_id}/devices/response"
        iot_client.publish(
            topic=response_topic,
            qos=1,
            payload=json.dumps({"devices": devices_output}),
        )

        print(f"[SUCCESS] {len(devices_output)} cihaz {response_topic} topiğine gönderildi.")
        return {"status": "success", "device_count": len(devices_output)}

    except Exception as e:
        print(f"[ERROR] İşlem sırasında hata: {str(e)}")
        return {"status": "error", "message": str(e)}
