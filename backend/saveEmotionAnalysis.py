import os
import json
import psycopg2
import uuid

def lambda_handler(event, context):
    try:
        # API Gateway path from /{homeID}/emotion
        path_parameters = event.get('pathParameters') or {}
        home_id = path_parameters.get('homeID')
        
        if not home_id:
            return _resp(400, {"error": "Missing homeID in path."})

        # Body parse
        body = event.get('body')
        if not body:
            return _resp(400, {"error": "Empty body."})
            
        payload = json.loads(body)
        emotion = payload.get('emotion')
        confidence = payload.get('confidence', 0.0)
        
        # Kullanıcı ID'sini token'dan alma (opsiyonel tutalım)
        user_id = None
        if event.get("requestContext") and event["requestContext"].get("authorizer") and event["requestContext"]["authorizer"].get("claims"):
            user_id = event["requestContext"]["authorizer"]["claims"].get("sub")
        
        if not emotion:
            return _resp(400, {"error": "Missing emotion in body."})

        conn = psycopg2.connect(
            host=os.environ['DB_HOST'],
            user=os.environ['DB_USER'],
            password=os.environ['DB_PASSWORD'],
            dbname=os.environ['DB_NAME'],
            connect_timeout=5
        )
        cur = conn.cursor()
        
        analysis_id = str(uuid.uuid4())
        
        # ai_analyses tablosuna yazma işlemi
        query = """
            INSERT INTO ai_analyses (analysis_id, homeid, userid, emotion, confidence, analyzed_at) 
            VALUES (%s, %s, %s, %s, %s, NOW())
        """
        cur.execute(query, (analysis_id, home_id, user_id, emotion, confidence))
        conn.commit()
        
        cur.close()
        conn.close()

        return _resp(200, {"message": "Emotion saved to ai_analyses successfully.", "analysis_id": analysis_id})

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
