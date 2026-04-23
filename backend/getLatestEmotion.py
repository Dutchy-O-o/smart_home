import os
import json
import psycopg2

def lambda_handler(event, context):
    try:
        path_parameters = event.get('pathParameters') or {}
        home_id = path_parameters.get('homeID')
        
        if not home_id:
            return _resp(400, {"error": "Missing homeID in path."})

        # --- 1. KULLANICI ID'SİNİ TOKEN'DAN ÇEKME ---
        try:
            user_id = event.get('requestContext', {}).get('authorizer', {}).get('claims', {}).get('sub')
            if not user_id:
                raise ValueError("User ID (sub) not found in token.")
        except Exception as e:
            return _resp(401, {"error": "Unauthorized: Missing or invalid token. " + str(e)})

        conn = psycopg2.connect(
            host=os.environ['DB_HOST'],
            user=os.environ['DB_USER'],
            password=os.environ['DB_PASSWORD'],
            dbname=os.environ['DB_NAME'],
            connect_timeout=5
        )
        cur = conn.cursor()
        
        # --- 2. GÜNCELLENMİŞ SQL SORGUSU ---
        # ER diyagramındaki "timestamp" alanına göre en güncel kaydı getiriyoruz
        query = """
            SELECT detected_emotion, confidence_score 
            FROM ai_analyses 
            WHERE homeid = %s AND userid = %s
            ORDER BY timestamp DESC 
            LIMIT 1
        """
        cur.execute(query, (home_id, user_id))
        row = cur.fetchone()
        
        cur.close()
        conn.close()

        if row:
            emotion = row[0]
            confidence = float(row[1]) if row[1] else 0.0
            
            return _resp(200, {
                "emotion": emotion,
                "confidence": confidence
            })
        else:
            # Kullanıcının o evde henüz kaydedilmiş bir duygusu yok
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