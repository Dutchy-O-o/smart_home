import json
import psycopg2
import boto3
import uuid
import os
from datetime import datetime

# Veritabanı bağlantı bilgileri (Lambda Environment Variables'dan çekilir)
DB_HOST = os.environ.get('DB_HOST')
DB_NAME = os.environ.get('DB_NAME')
DB_USER = os.environ.get('DB_USER')
DB_PASS = os.environ.get('DB_PASSWORD')

# IoT Endpoint'ini Environment Variables'dan çek ve güvenli hale getir
raw_endpoint = os.environ.get('IOT_ENDPOINT')
if raw_endpoint and not raw_endpoint.startswith('https://'):
    IOT_ENDPOINT_URL = f"https://{raw_endpoint}"
else:
    IOT_ENDPOINT_URL = raw_endpoint

# IoT Client'ı açık bir şekilde (Explicitly) endpoint ile başlatıyoruz (Global)
IOT_CLIENT = boto3.client('iot-data', endpoint_url=IOT_ENDPOINT_URL)

# --- WARM START OPTİMİZASYONU ---
# Bağlantıyı global değişkende tutarak her Lambda tetiklemesinde 3 saniye beklemeyi önlüyoruz
conn = None

def get_connection():
    global conn
    # Eğer bağlantı yoksa veya zaman aşımına uğrayıp kapandıysa yeniden aç
    if conn is None or conn.closed != 0:
        conn = psycopg2.connect(host=DB_HOST, database=DB_NAME, user=DB_USER, password=DB_PASS)
    return conn

def lambda_handler(event, context):
    # 1. Girdi Verilerini Yakalama
    home_id = event['pathParameters']['homeID']
    
    body = json.loads(event['body'])
    detected_emotion = body.get('detected_emotion')
    confidence_score = body.get('confidence_score')
    
    # --- GÜVENLİ COGNITO AUTHORIZER KONTROLÜ ---
    # KeyError ve 500 hatası almamak için güvenli (defensive) çekim yapıyoruz
    try:
        user_id = event.get('requestContext', {}).get('authorizer', {}).get('claims', {}).get('sub')
        if not user_id:
            raise ValueError("Yetkilendirme bilgisi (User ID) bulunamadı.")
    except Exception:
        return {
            'statusCode': 401,
            'body': json.dumps({"status": "error", "message": "Yetkisiz erişim veya eksik token."})
        }
    
    try:
        # Global DB Bağlantısını Al (Sıcak Başlangıç)
        print("1. Veritabanına bağlanmayı deniyorum...")
        db_conn = get_connection()
        cur = db_conn.cursor()
        print("2. Veritabanına başarıyla bağlandım! Sorguları atıyorum...")
        # --- ADIM 1: OTOMASYON KURALINI ARA ---
        trigger_search_str = f"emotion == '{detected_emotion}'"
        
        cur.execute("""
            SELECT ruleid FROM AUTOMATION_RULES 
            WHERE homeid = %s AND is_enabled = true AND trigger_condition = %s
            LIMIT 1
        """, (home_id, trigger_search_str))
        
        rule_row = cur.fetchone()
        triggered_rule_id = rule_row[0] if rule_row else None
        
        # --- ADIM 2: AI ANALİZİNİ KAYDET (AI_ANALYSES) ---
        analysis_id = str(uuid.uuid4())
        timestamp = datetime.utcnow()
        
        cur.execute("""
            INSERT INTO AI_ANALYSES (analysisid, userid, homeid, timestamp, detected_emotion, confidence_score, triggered_ruleid)
            VALUES (%s, %s, %s, %s, %s, %s, %s)
        """, (analysis_id, user_id, home_id, timestamp, detected_emotion, confidence_score, triggered_rule_id))
        
        execution_id = None
        
        # --- ADIM 3: EĞER KURAL VARSA AKSİYONLARI TETİKLE ---
        if triggered_rule_id:
            # A. Otomasyon Geçmişine (Execution) "Pending" kaydı at
            execution_id = str(uuid.uuid4())
            cur.execute("""
                INSERT INTO AUTOMATION_EXECUTIONS (executionid, ruleid, executed_at, result)
                VALUES (%s, %s, %s, %s)
            """, (execution_id, triggered_rule_id, timestamp, 'Pending'))
            
            # B. Kuralın aksiyonlarını ve detaylarını çek
            cur.execute("""
                SELECT ra.deviceid, ap.property_name, ad.target_value 
                FROM RULE_ACTIONS ra
                JOIN ACTION_DETAILS ad ON ra.actionid = ad.actionid
                JOIN ACTUATOR_PROPERTIES ap ON ad.propertyid = ap.propertyid
                WHERE ra.ruleid = %s
            """, (triggered_rule_id,))
            
            actions = cur.fetchall()
            
            # C. Aksiyonları cihaz bazlı grupla ve MQTT'ye gönder
            device_commands = {}
            for device_id, prop, val in actions:
                if device_id not in device_commands:
                    device_commands[device_id] = []
                device_commands[device_id].append({"property_name": prop, "value": val})
            
            print("3. IoT Core'a MQTT mesajı fırlatmaya çalışıyorum...")
            for dev_id, commands in device_commands.items():
                mqtt_payload = {
                    "deviceID": dev_id,
                    "executionID": execution_id,
                    "commands": commands
                }
                
                topic = f"homes/{home_id}/command"
                IOT_CLIENT.publish(
                    topic=topic,
                    qos=1,
                    payload=json.dumps(mqtt_payload)
                )
            print("4. MQTT mesajı başarıyla fırlatıldı!")
        # DB Değişikliklerini Onayla
        db_conn.commit()
        
        # SADECE CURSOR'U KAPAT. BAĞLANTI (db_conn) AÇIK KALSIN!
        cur.close()
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                "status": "success",
                "analysisID": analysis_id,
                "triggered_ruleID": triggered_rule_id,
                "executionID": execution_id
            })
        }

    except Exception as e:
        if 'db_conn' in locals() and db_conn and db_conn.closed == 0:
            db_conn.rollback()
        print(f"Error: {e}")
        return {
            'statusCode': 500,
            'body': json.dumps({"status": "error", "message": str(e)})
        }