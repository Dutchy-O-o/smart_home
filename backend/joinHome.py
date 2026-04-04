import json
import psycopg2
import os
import time
import hmac
import hashlib
import base64

# Veritabanı Değişkenleri
DB_HOST = os.environ.get('DB_HOST')
DB_NAME = os.environ.get('DB_NAME')
DB_USER = os.environ.get('DB_USER')
DB_PASSWORD = os.environ.get('DB_PASSWORD')

# YENİ: KRİPTOGRAFİK MÜHÜR ANAHTARI (Environment Variables'a eklenecek!)
# AWS'de bu fonksiyona 'INVITE_SECRET_KEY' adında bir çevre değişkeni ekle.
SECRET_KEY = os.environ.get('INVITE_SECRET_KEY', 'benim_staj_projemin_gizli_anahtari_123').encode('utf-8')

def verify_secure_token(token):
    """Gelen QR token'ının mührünü ve süresini kontrol eder."""
    try:
        # Token'ı veriler ve imza olarak ikiye böl
        parts = token.split('.')
        if len(parts) != 2:
            return None, "Geçersiz QR Kod formatı."
            
        payload_b64, signature = parts[0], parts[1]
        
        # 1. MÜHÜR KONTROLÜ (Biri veriyi hacklemeye çalışmış mı?)
        expected_signature = hmac.new(SECRET_KEY, payload_b64.encode('utf-8'), hashlib.sha256).hexdigest()
        if not hmac.compare_digest(expected_signature, signature):
            return None, "Güvenlik İhlali: Sahte veya değiştirilmiş QR kod!"
            
        # 2. SÜRE KONTROLÜ (5 dakika geçmiş mi?)
        # Base64 eksik padding'lerini onar ve çöz
        padding = 4 - (len(payload_b64) % 4)
        payload_json = base64.b64decode(payload_b64 + ("=" * padding)).decode('utf-8')
        payload = json.loads(payload_json)
        
        if int(time.time()) > payload.get('exp', 0):
            return None, "Bu davetiyenin süresi dolmuş (5 dk sınırı)."
            
        return payload.get('home_id'), None
        
    except Exception as e:
        print(f"Token çözme hatası: {e}")
        return None, "QR kod okunamadı veya bozuk."

def lambda_handler(event, context):
    print(f"Gelen İstek: {json.dumps(event)}")
    conn = None
    try:
        # Cognito'dan kimliği al
        claims = event.get('requestContext', {}).get('authorizer', {}).get('claims', {})
        user_id = claims.get('sub')
        
        if not user_id:
            return {'statusCode': 401, 'body': json.dumps("Yetkisiz işlem.")}

        body = json.loads(event.get('body', '{}'))
        if isinstance(body, str):
            body = json.loads(body)
            
        # Artık düz home_id değil, şifreli token bekliyoruz!
        secure_token = body.get('secure_token')
        
        if not secure_token:
            return {'statusCode': 400, 'body': json.dumps("QR kod verisi (secure_token) eksik.")}

        # --- GÜVENLİK FİLTRESİNDEN GEÇİR ---
        home_id, error_msg = verify_secure_token(secure_token)
        if error_msg:
            return {'statusCode': 403, 'body': json.dumps(error_msg)}

        # --- BUNDAN SONRASI VERİTABANI İŞLEMLERİ (Eskisiyle aynı) ---
        conn = psycopg2.connect(host=DB_HOST, database=DB_NAME, user=DB_USER, password=DB_PASSWORD, connect_timeout=5)
        cur = conn.cursor()

        cur.execute("SELECT role FROM user_homes WHERE userid = %s AND homeid = %s", (user_id, home_id))
        if cur.fetchone():
            return {'statusCode': 400, 'body': json.dumps('Zaten bu eve daha önceden katıldınız!')}

        cur.execute("INSERT INTO user_homes (userid, homeid, role) VALUES (%s, %s, 'guest')", (user_id, home_id))
        conn.commit()

        return {'statusCode': 200, 'body': json.dumps('Eve başarıyla katıldınız!')}

    except Exception as e:
        print(f"❌ HATA: {str(e)}")
        if conn:
            conn.rollback()
        return {'statusCode': 500, 'body': json.dumps(f"Sunucu hatası: {str(e)}")}
    finally:
        if conn:
            cur.close()
            conn.close()