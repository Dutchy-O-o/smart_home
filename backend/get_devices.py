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
        # Extract homeID from Path Parameters
        path_parameters = event.get('pathParameters') or {}
        home_id = path_parameters.get('homeID')
        
        # Extract cognito user ID to check permissions
        request_context = event.get('requestContext', {})
        authorizer = request_context.get('authorizer', {})
        claims = authorizer.get('claims', {})
        user_id = claims.get('sub')
        
        if not home_id or not user_id:
            return {
                'statusCode': 400,
                'headers': {
                    'Access-Control-Allow-Origin': '*',
                    'Access-Control-Allow-Credentials': True
                },
                'body': json.dumps({"error": "Missing homeID or Authorization token."})
            }
        
        conn = get_connection()
        cursor = conn.cursor(cursor_factory=RealDictCursor)
        
        # 1. AUTHORIZATION CHECK
        auth_query = 'SELECT role FROM user_homes WHERE "userid" = %s AND "homeid" = %s'
        cursor.execute(auth_query, (user_id, home_id))
        if not cursor.fetchone():
            return {
                'statusCode': 403,
                'headers': {
                    'Access-Control-Allow-Origin': '*',
                    'Access-Control-Allow-Credentials': True
                },
                'body': json.dumps({"error": "You do not have permission to read devices for this home."})
            }

        # 2. FETCH DEVICES AND THEIR LATEST STATES
        # We join devices with actuator_properties and actuator_current_states
        device_query = """
            SELECT 
                d.deviceid, 
                d.device_type, 
                d.device_name,
                COALESCE(
                    json_agg(
                        json_build_object(
                            'property_name', ap.property_name,
                            'current_value', acs.current_value,
                            'last_updated', acs.last_updated
                        )
                    ) FILTER (WHERE ap.property_name IS NOT NULL), 
                    '[]'::json
                ) AS properties
            FROM devices d
            LEFT JOIN actuator_properties ap ON d.deviceid = ap.deviceid
            LEFT JOIN actuator_current_states acs ON ap.propertyid = acs.propertyid
            WHERE d."homeid" = %s AND d.device_type != 'sensor'
            GROUP BY d.deviceid, d.device_type, d.device_name
            ORDER BY d.device_name ASC;
        """
        cursor.execute(device_query, (home_id,))
        records = cursor.fetchall()
        
        # Format response correctly handling datetimes
        devices_output = []
        for row in records:
            props_raw = row['properties']
            if isinstance(props_raw, str):
                props_raw = json.loads(props_raw)
                
            dev = {
                "deviceid": str(row['deviceid']),
                "device_type": row['device_type'],
                "device_name": row['device_name'],
                "properties": props_raw
            }
            # Clean out None values inside properties if join results were empty in current states
            cleaned_props = []
            for prop in dev['properties']:
                if isinstance(prop, dict) and prop.get('property_name'):
                    if 'last_updated' in prop and isinstance(prop['last_updated'], datetime):
                        prop['last_updated'] = prop['last_updated'].isoformat()
                    cleaned_props.append(prop)
            dev['properties'] = cleaned_props
            devices_output.append(dev)

        return {
            'statusCode': 200,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*',
                'Access-Control-Allow-Credentials': True
            },
            'body': json.dumps({"devices": devices_output}, default=datetime_converter)
        }

    except Exception as e:
        print(f"Error fetching devices: {str(e)}")
        return {
            'statusCode': 500,
            'headers': {
                'Access-Control-Allow-Origin': '*',
                'Access-Control-Allow-Credentials': True
            },
            'body': json.dumps({"error": "Internal Server Error", "details": str(e)})
        }
