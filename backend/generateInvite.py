import json
import time
import hmac
import hashlib
import base64
import os
import psycopg2

# Gizli Anahtar ve Veritabanı Değişkenleri
SECRET_KEY = os.environ.get('INVITE_SECRET_KEY', 'benim_staj_projemin_gizli_anahtari_123').encode('utf-8')
DB_HOST = os.environ.get('DB_HOST')
DB_NAME = os.environ.get('DB_NAME')
DB_USER = os.environ.get('DB_USER')
DB_PASSWORD = os.environ.get('DB_PASSWORD')

def lambda_handler(event, context):
    print(f"Gelen İstek: {json.dumps(event)}")
    conn = None
    try:
        # 1. Cognito'dan İsteği Yapanın Kimliğini Al
        claims = event.get('requestContext', {}).get('authorizer', {}).get('claims', {})
        user_id = claims.get('sub')
        
        # 2. URL'den (Path Parameters) home_id'yi Al
        path_params = event.get('pathParameters', {}) or {}
        home_id = path_params.get('homeID')
        
        if not user_id:
            return {'statusCode': 401, 'body': json.dumps("Yetkisiz işlem: Token bulunamadı.")}
            
        if not home_id:
            return {'statusCode': 400, 'body': json.dumps("homeID path parametresi eksik!")}

        # 3. Veritabanına Bağlan ve Admin Kontrolü Yap
        conn = psycopg2.connect(host=DB_HOST, database=DB_NAME, user=DB_USER, password=DB_PASSWORD, connect_timeout=5)
        cur = conn.cursor()
        
        cur.execute("""
            SELECT role FROM user_homes 
            WHERE userid = %s AND homeid = %s
        """, (user_id, home_id))
        
        result = cur.fetchone()
        
        if not result:
            return {'statusCode': 403, 'body': json.dumps("Hata: Bu eve erişim izniniz yok.")}
            
        role = result[0].lower()
        if role != 'admin':
            # Kullanıcı evde var ama misafir! Davet oluşturamaz.
            return {'statusCode': 403, 'body': json.dumps("Güvenlik İhlali: Sadece ev sahibi (ADMIN) davet kodu üretebilir.")}

        # 4. Kişi gerçekten ADMIN ise 5 Dakikalık Mühürlü Token'ı Oluştur
        expiration_time = int(time.time()) + 300
        payload = {"home_id": home_id, "exp": expiration_time}
        payload_json = json.dumps(payload, separators=(',', ':'))
        payload_b64 = base64.urlsafe_b64encode(payload_json.encode('utf-8')).decode('utf-8').rstrip('=')
        
        signature = hmac.new(SECRET_KEY, payload_b64.encode('utf-8'), hashlib.sha256).hexdigest()
        secure_token = f"{payload_b64}.{signature}"
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                "secure_token": secure_token,
                "expires_in_seconds": 300
            })
        }

    except Exception as e:
        print(f"HATA: {str(e)}")
        return {'statusCode': 500, 'body': json.dumps(f"Sunucu hatası: {str(e)}")}
    finally:
        if conn:
            cur.close()
            conn.close()