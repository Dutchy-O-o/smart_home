import json
import os
import psycopg2
from psycopg2.extras import RealDictCursor

def lambda_handler(event, context):
    try:
        path_parameters = event.get('pathParameters') or {}
        home_id = path_parameters.get('homeID')
        
        query_string_parameters = event.get('queryStringParameters') or {}
        emotion = query_string_parameters.get('emotion')
        
        if not home_id or not emotion:
            return {
                'statusCode': 400,
                'headers': {
                    'Content-Type': 'application/json',
                    'Access-Control-Allow-Origin': '*'
                },
                'body': json.dumps({'error': 'Eksik parametre: homeID veya emotion bulunamadı.'})
            }

        conn = psycopg2.connect(
            host=os.environ.get('DB_HOST'),
            database=os.environ.get('DB_NAME'),
            user=os.environ.get('DB_USER'),
            password=os.environ.get('DB_PASSWORD'),
            port=os.environ.get('DB_PORT', '5432')
        )
        cur = conn.cursor(cursor_factory=RealDictCursor)
        
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
  AND r.trigger_condition = %s 
  AND r.is_enabled = true;
"""
        
        cur.execute(query, (home_id, emotion))
        rows = cur.fetchall()
        
        actions_dict = {}
        rule_name = None
        
        if rows:
            rule_name = rows[0].get('rule_name')

        for row in rows:
            dev_id = row['deviceid']
            if dev_id not in actions_dict:
                actions_dict[dev_id] = {
                    "deviceID": dev_id,
                    "device_name": row['device_name'],
                    "commands": []
                }
            
            actions_dict[dev_id]["commands"].append({
                "property_name": row['property_name'],
                "value": row['target_value']
            })
            
        actions_list = list(actions_dict.values())
        
        response_body = {
            "homeID": home_id,
            "trigger_emotion": emotion,
            "rule_name": rule_name if rule_name else "",
            "actions": actions_list
        }
        
        cur.close()
        conn.close()
        
        return {
            'statusCode': 200,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps(response_body)
        }
        
    except Exception as e:
        print(f"Hata oluştu: {str(e)}")
        return {
            'statusCode': 500,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({'error': 'Sunucu içi hata oluştu.', 'details': str(e)})
        }
