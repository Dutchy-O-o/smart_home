import os
import json
import psycopg2

def lambda_handler(event, context):
    try:
        path_parameters = event.get('pathParameters') or {}
        home_id = path_parameters.get('homeID')
        
        if not home_id:
            return _resp(400, {"error": "Missing homeID in path."})

        conn = psycopg2.connect(
            host=os.environ['DB_HOST'],
            user=os.environ['DB_USER'],
            password=os.environ['DB_PASSWORD'],
            dbname=os.environ['DB_NAME'],
            connect_timeout=5
        )
        cur = conn.cursor()
        
        # get the latest emotion
        # ai_analyses (analysis_id, homeid, emotion, analyzed_at)
        query = """
            SELECT emotion, confidence, analyzed_at 
            FROM ai_analyses 
            WHERE homeid = %s 
            ORDER BY analyzed_at DESC 
            LIMIT 1
        """
        cur.execute(query, (home_id,))
        row = cur.fetchone()
        
        cur.close()
        conn.close()

        if row:
            emotion = row[0]
            confidence = float(row[1]) if row[1] else 0.0
            analyzed_at = str(row[2])
            return _resp(200, {
                "emotion": emotion,
                "confidence": confidence,
                "analyzed_at": analyzed_at
            })
        else:
            # no historical emotion recorded yet
            return _resp(200, {"emotion": None})

    except Exception as e:
        print(f"Error: {e}")
        return _resp(500, {"error": str(e)})

def _resp(code, body):
    return {
        'statusCode': code,
        'headers': {
            'Content-Type': 'application/json',
            'Access-Control-Allow-Origin': '*'
        },
        'body': json.dumps(body)
    }
