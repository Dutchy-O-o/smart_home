import json
import os
import psycopg2
from psycopg2.extras import RealDictCursor
from datetime import datetime

class DateTimeEncoder(json.JSONEncoder):
    def default(self, obj):
        if isinstance(obj, datetime):
            return obj.isoformat()
        return super(DateTimeEncoder, self).default(obj)

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
        
        # Fetch successful executions for rules in the specified home
        cur.execute("""
            SELECT e.executionid, e.executed_at, r.rule_name
            FROM automation_executions e
            JOIN automation_rules r ON e.ruleid = r.ruleid
            WHERE r.homeid = %s AND LOWER(e.result) = 'success'
            ORDER BY e.executed_at DESC
            LIMIT 50;
        """, (home_id,))
        
        history_rows = cur.fetchall()
        
        cur.close()
        conn.close()
        
        return {
            'statusCode': 200,
            'headers': {'Access-Control-Allow-Origin': '*'},
            # Use custom encoder to handle datetime objects correctly
            'body': json.dumps({'history': history_rows}, cls=DateTimeEncoder)
        }
        
    except Exception as e:
        print(f"Error occurred: {str(e)}")
        return {
            'statusCode': 500,
            'headers': {'Access-Control-Allow-Origin': '*'},
            'body': json.dumps({'error': 'Internal server error.', 'details': str(e)})
        }
