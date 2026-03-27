import os
import json
import psycopg2

def lambda_handler(event, context):
    try:
        user_id = event['requestContext']['authorizer']['claims']['sub']
        body = json.loads(event['body'])
        new_fcm_token = body.get('fcm_token')
        
        if not new_fcm_token:
            return {'statusCode': 400, 'body': json.dumps({"error": "Token eksik."})}

        conn = psycopg2.connect(
            host=os.environ['DB_HOST'], user=os.environ['DB_USER'],
            password=os.environ['DB_PASSWORD'], dbname=os.environ['DB_NAME']
        )
        cursor = conn.cursor()
        
        # Kullanıcının token sütununu güncelle
        cursor.execute('UPDATE users SET fcm_token = %s WHERE "uid" = %s', (new_fcm_token, user_id))
        conn.commit()
        
        return {'statusCode': 200, 'body': json.dumps({"message": "Token kaydedildi."})}
    except Exception as e:
        return {'statusCode': 500, 'body': json.dumps({"error": str(e)})}