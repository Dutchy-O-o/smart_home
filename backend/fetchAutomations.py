import json
import os
import psycopg2
from psycopg2.extras import RealDictCursor

def lambda_handler(event, context):
    try:
        path_parameters = event.get('pathParameters') or {}
        home_id = path_parameters.get('homeID')
        
        if not home_id:
            return {'statusCode': 400, 'body': json.dumps({'error': 'Missing parameter: homeID'})}

        conn = psycopg2.connect(
            host=os.environ.get('DB_HOST'),
            database=os.environ.get('DB_NAME'),
            user=os.environ.get('DB_USER'),
            password=os.environ.get('DB_PASSWORD'),
            port=os.environ.get('DB_PORT', '5432')
        )
        cur = conn.cursor(cursor_factory=RealDictCursor)
        
        # 1. Fetch Rules
        cur.execute("""
            SELECT ruleid, rule_name, trigger_condition, is_enabled
            FROM automation_rules
            WHERE homeid = %s
            ORDER BY rule_name ASC;
        """, (home_id,))
        rules = cur.fetchall()
        
        automations = []
        
        for rule in rules:
            rule_id = rule['ruleid']
            # Fetch actions for this rule
            cur.execute("""
                SELECT a.actionid, a.deviceid, d.device_name
                FROM rule_actions a
                LEFT JOIN devices d ON a.deviceid = d.deviceid
                WHERE a.ruleid = %s;
            """, (rule_id,))
            actions = cur.fetchall()
            
            actions_list = []
            for action in actions:
                action_id = action['actionid']
                # Fetch action details
                cur.execute("""
                    SELECT ap.property_name, ad.target_value
                    FROM action_details ad
                    JOIN actuator_properties ap ON ad.propertyid = ap.propertyid
                    WHERE ad.actionid = %s;
                """, (action_id,))
                details_rows = cur.fetchall()
                
                # Convert details to dict
                details_dict = {}
                for dr in details_rows:
                    details_dict[dr['property_name']] = dr['target_value']
                
                actions_list.append({
                    "device_id": str(action['deviceid']),
                    "device_name": action['device_name'],
                    "details": details_dict
                })
                
            automations.append({
                "rule_id": str(rule_id),
                "rule_name": rule['rule_name'],
                "trigger_condition": rule['trigger_condition'],
                "is_enabled": rule['is_enabled'],
                "actions": actions_list
            })
            
        cur.close()
        conn.close()
        
        return {
            'statusCode': 200,
            'headers': {'Access-Control-Allow-Origin': '*'},
            'body': json.dumps({'automations': automations})
        }
        
    except Exception as e:
        print(f"Error occurred: {str(e)}")
        return {
            'statusCode': 500,
            'headers': {'Access-Control-Allow-Origin': '*'},
            'body': json.dumps({'error': 'Internal server error.', 'details': str(e)})
        }
