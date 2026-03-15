import os
import json
import psycopg2
from psycopg2.extras import RealDictCursor
from datetime import datetime

# WARM START: Database connection
db_conn = None

def get_connection():
    global db_conn
    if db_conn is None or db_conn.closed != 0:
        db_conn = psycopg2.connect(
            host=os.environ.get('DB_HOST'),
            user=os.environ.get('DB_USER'),
            password=os.environ.get('DB_PASSWORD'),
            dbname=os.environ.get('DB_NAME'),
            connect_timeout=5
        )
    return db_conn

def datetime_converter(o):
    if isinstance(o, datetime):
        return o.isoformat()

def lambda_handler(event, context):
    try:
        home_id = event['pathParameters']['homeID']
        user_id = event['requestContext']['authorizer']['claims']['sub']
        
        conn = get_connection()
        cursor = conn.cursor(cursor_factory=RealDictCursor)
        
        # 1. AUTHORIZATION CHECK
        auth_query = 'SELECT role FROM user_homes WHERE "userid" = %s AND "homeid" = %s'
        cursor.execute(auth_query, (user_id, home_id))
        if not cursor.fetchone():
            return {
                'statusCode': 403,
                'body': json.dumps({"error": "You do not have permission to read data for this home."})
            }

        # 2. FETCH LATEST DATA (Based on New Table Structure)
        # Gets the latest value for each sensor type per device.
        sensor_query = """
            SELECT DISTINCT ON (sd.deviceid, sd.sensor_type) 
                d."deviceid", 
                sd.value, 
                sd.sensor_type,
                sd.unit,
                sd.timestamp
            FROM devices d
            JOIN sensor_data sd ON d."deviceid" = sd.deviceid
            WHERE d."homeid" = %s
            ORDER BY sd.deviceid, sd.sensor_type, sd.timestamp DESC;
        """
        cursor.execute(sensor_query, (home_id,))
        records = cursor.fetchall()
        
        # 3. FORMAT DATA TO JSON EXPECTED BY FLUTTER
        sensors_output = {}
        
        for row in records:
            dev_id = str(row['deviceid'])
            s_type = row['sensor_type'] 
            val = row['value']          
            ts = row['timestamp']
            
            # Create dict for device if not exists
            if dev_id not in sensors_output:
                sensors_output[dev_id] = {}
            
            # Map sensor type as key
            sensors_output[dev_id][s_type] = val
            
            # Set latest update time
            if 'last_updated' not in sensors_output[dev_id] or ts > sensors_output[dev_id]['last_updated']:
                sensors_output[dev_id]['last_updated'] = ts

        # Connection remains open for warm starts
        return {
            'statusCode': 200,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({
                "homeid": home_id,
                "sensors": sensors_output
            }, default=datetime_converter)
        }

    except KeyError as e:
        return {'statusCode': 400, 'body': json.dumps({"error": f"Missing parameter: {str(e)}"})}
    except Exception as e:
        print(f"Server Error: {e}")
        return {'statusCode': 500, 'body': json.dumps({"error": "Internal server error"})}