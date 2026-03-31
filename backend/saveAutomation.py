import json
import os
import psycopg2
import uuid
from psycopg2.extras import RealDictCursor

def lambda_handler(event, context):
    try:
        path_parameters = event.get('pathParameters') or {}
        home_id = path_parameters.get('homeID')
        
        if not event.get('body'):
            return {'statusCode': 400, 'body': json.dumps({'error': 'Missing parameter: request body is empty.'})}
            
        body = json.loads(event['body'])
        
        rule_name = body.get('rule_name')
        trigger_condition = body.get('trigger_condition')
        is_enabled = body.get('is_enabled', True)
        actions = body.get('actions', [])
        
        if not home_id or not rule_name or not trigger_condition:
            return {'statusCode': 400, 'body': json.dumps({'error': 'Missing required parameters.'})}

        conn = psycopg2.connect(
            host=os.environ.get('DB_HOST'),
            database=os.environ.get('DB_NAME'),
            user=os.environ.get('DB_USER'),
            password=os.environ.get('DB_PASSWORD'),
            port=os.environ.get('DB_PORT', '5432')
        )
        cur = conn.cursor(cursor_factory=RealDictCursor)
        
        # 1. Insert into automation_rules
        rule_id = str(uuid.uuid4())
        
        cur.execute("""
            INSERT INTO automation_rules (ruleid, homeid, rule_name, trigger_condition, is_enabled)
            VALUES (%s, %s, %s, %s, %s)
            RETURNING ruleid;
        """, (rule_id, home_id, rule_name, trigger_condition, is_enabled))
        
        for action in actions:
            action_id = str(uuid.uuid4())
            device_id = action.get('device_id') or action.get('deviceID')
            
            # 2. Insert into rule_actions
            cur.execute("""
                INSERT INTO rule_actions (actionid, ruleid, deviceid)
                VALUES (%s, %s, %s)
            """, (action_id, rule_id, device_id))
            
            details = action.get('details', {})
            
            # 3. Insert into action_details
            # details is a dict like {"state": "on", "brightness": 100}
            if isinstance(details, dict):
                for prop_name, target_value in details.items():
                    # Find propertyid from actuator_properties
                    cur.execute("SELECT propertyid FROM actuator_properties WHERE property_name = %s", (prop_name,))
                    prop_row = cur.fetchone()
                    
                    if prop_row:
                        property_id = prop_row['propertyid']
                        detail_id = str(uuid.uuid4())
                        
                        cur.execute("""
                            INSERT INTO action_details (detailid, actionid, propertyid, target_value)
                            VALUES (%s, %s, %s, %s)
                        """, (detail_id, action_id, property_id, str(target_value)))
                    else:
                        print(f"Warning: propertyid not found for '{prop_name}'.")
            elif isinstance(details, list):
                # Fallback if Flutter sends the old format [{"property_name": "...", "target_value": "..."}]
                for detail in details:
                    prop_name = detail.get("property_name")
                    target_value = detail.get("target_value")
                    cur.execute("SELECT propertyid FROM actuator_properties WHERE property_name = %s", (prop_name,))
                    prop_row = cur.fetchone()
                    if prop_row:
                        property_id = prop_row['propertyid']
                        detail_id = str(uuid.uuid4())
                        cur.execute("""
                            INSERT INTO action_details (detailid, actionid, propertyid, target_value)
                            VALUES (%s, %s, %s, %s)
                        """, (detail_id, action_id, property_id, str(target_value)))
        
        conn.commit()
        cur.close()
        conn.close()
        
        return {
            'statusCode': 201,
            'headers': {'Access-Control-Allow-Origin': '*'},
            'body': json.dumps({'message': 'Automation saved successfully!', 'rule_id': rule_id})
        }
        
    except Exception as e:
        print(f"Error occurred: {str(e)}")
        return {
            'statusCode': 500,
            'headers': {'Access-Control-Allow-Origin': '*'},
            'body': json.dumps({'error': 'Internal server error.', 'details': str(e)})
        }
