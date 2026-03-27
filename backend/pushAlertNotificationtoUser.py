import os
import json
import psycopg2
import firebase_admin
from firebase_admin import credentials, messaging

if not firebase_admin._apps:
    cred = credentials.Certificate("firebase-service-account.json")
    firebase_admin.initialize_app(cred)

def lambda_handler(event, context):
    try:
        # IoT Core Rule'dan gelen payload
        home_id = event.get('homeID')
        alert_message = event.get('message', 'Acil Durum!')
        event_type = event.get('event_type', 'alert')
        
        print(home_id, alert_message, event_type)
        conn = psycopg2.connect(
            host=os.environ['DB_HOST'], user=os.environ['DB_USER'],
            password=os.environ['DB_PASSWORD'], dbname=os.environ['DB_NAME']
        )
        cursor = conn.cursor()
        
        # O evde yaşayanların token'larını bul
        query = """
            SELECT distinct u.fcm_token FROM users u
            JOIN user_homes uh ON u."uid" = uh."userid"
            WHERE uh."homeid" = %s AND u.fcm_token IS NOT NULL;
        """
        cursor.execute(query, (home_id,))
        tokens = [row[0] for row in cursor.fetchall() if row[0]]
        
        if not tokens:
            return {"status": "No tokens found"}
            
        print(tokens)
        if event_type == "gas_leak":
            title = "🚨 DİKKAT: GAZ KAÇAĞI!"
            body = "Evde yüksek seviyede gaz tespit edildi. Lütfen derhal evi havalandırın."
        elif event_type == "earthquake":
            title = "⚠️ DEPREM ALARMI!"
            body = "Sarsıntı tespit edildi. Lütfen güvenli bir yere geçin."
  
  
         # Bildirim objesini oluştur
        message = messaging.MulticastMessage(
            notification=messaging.Notification(
                title=title,
                body=body
            ),
            data={"event": event_type},
            tokens=tokens
        )
        
        # YENİ FONKSİYON İLE GÖNDER
        response = messaging.send_each_for_multicast(message)
        print(f"Başarılı: {response.success_count}, Hatalı: {response.failure_count}")
        
        return {"status": "Push notification sent"}
    except Exception as e:
        print(f"Hata: {e}")
        return {"error": str(e)}