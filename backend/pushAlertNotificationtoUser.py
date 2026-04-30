import os
import json
import logging
import psycopg2
import firebase_admin
from firebase_admin import credentials, messaging

logger = logging.getLogger()
logger.setLevel(logging.INFO)

if not firebase_admin._apps:
    cred = credentials.Certificate("firebase-service-account.json")
    firebase_admin.initialize_app(cred)


# Map of event_type -> (title, body_template). Body may contain "{message}" which
# is replaced by the dynamic alert_message coming from the IoT rule payload.
EVENT_TITLES = {
    "gas_leak": (
        "🚨 DİKKAT: GAZ KAÇAĞI!",
        "Evde yüksek seviyede gaz tespit edildi. Lütfen derhal evi havalandırın.",
    ),
    "earthquake": (
        "⚠️ DEPREM ALARMI!",
        "Sarsıntı tespit edildi. Lütfen güvenli bir yere geçin.",
    ),
    "emotion_change": (
        "🧠 Duygu Değişimi",
        "Yeni duygu tespit edildi: {message}",
    ),
    "rfid_unauthorized": (
        "🔒 Yetkisiz Giriş Denemesi",
        "Tanınmayan bir RFID kart tespit edildi. Güvenlik kayıtlarını kontrol edin.",
    ),
    "rfid_authorized": (
        "✅ Kapı Açıldı",
        "Yetkili giriş kaydedildi: {message}",
    ),
    "stove_left_on": (
        "🔥 Ocak Açık Unutuldu",
        "Evde kimse yokken ocak açık. Lütfen kontrol edin.",
    ),
    "tv_idle_long": (
        "📺 TV Açık Kaldı",
        "TV uzun süredir kullanılmıyor. Otomatik kapatmak ister misiniz?",
    ),
    "ac_running_window_open": (
        "❄️ Klima Açık, Pencere Açık",
        "Pencere açıkken klima çalışıyor. Enerji israfını önlemek için kontrol edin.",
    ),
    "device_offline": (
        "📡 Cihaz Bağlantısı Kesildi",
        "Cihaz çevrimdışı: {message}",
    ),
}

DEFAULT_TITLE = "🔔 Akıllı Ev Bildirimi"
DEFAULT_BODY = "Evinizde bir olay tespit edildi: {message}"


def _resolve_title_body(event_type: str, alert_message: str):
    title, body_template = EVENT_TITLES.get(
        event_type, (DEFAULT_TITLE, DEFAULT_BODY)
    )
    body = body_template.format(message=alert_message or "Detay yok")
    return title, body


def _get_tokens(home_id: str):
    conn = None
    cursor = None
    try:
        conn = psycopg2.connect(
            host=os.environ["DB_HOST"],
            user=os.environ["DB_USER"],
            password=os.environ["DB_PASSWORD"],
            dbname=os.environ["DB_NAME"],
            connect_timeout=5,
        )
        cursor = conn.cursor()
        cursor.execute(
            """
            SELECT DISTINCT u.fcm_token
            FROM users u
            JOIN user_homes uh ON u."uid" = uh."userid"
            WHERE uh."homeid" = %s AND u.fcm_token IS NOT NULL
            """,
            (home_id,),
        )
        return [row[0] for row in cursor.fetchall() if row[0]]
    finally:
        if cursor is not None:
            cursor.close()
        if conn is not None:
            conn.close()


def lambda_handler(event, context):
    try:
        home_id = event.get("homeID")
        alert_message = event.get("message", "")
        event_type = event.get("event_type", "alert")

        logger.info(
            "Push request: home_id=%s event_type=%s message=%s",
            home_id, event_type, alert_message,
        )

        if not home_id:
            return {"status": "error", "reason": "homeID missing"}

        tokens = _get_tokens(home_id)
        if not tokens:
            logger.info("No FCM tokens registered for home %s", home_id)
            return {"status": "no_tokens"}

        title, body = _resolve_title_body(event_type, alert_message)

        message = messaging.MulticastMessage(
            notification=messaging.Notification(title=title, body=body),
            data={
                "event": event_type,
                "title": title,
                "body": body,
                "message": alert_message or "",
            },
            tokens=tokens,
        )

        response = messaging.send_each_for_multicast(message)
        logger.info(
            "FCM result: success=%d failure=%d",
            response.success_count, response.failure_count,
        )

        if response.failure_count > 0:
            for idx, resp in enumerate(response.responses):
                if not resp.success:
                    logger.warning(
                        "FCM failed token_idx=%d error=%s", idx, resp.exception
                    )

        return {
            "status": "ok",
            "event_type": event_type,
            "sent": response.success_count,
            "failed": response.failure_count,
        }

    except Exception as e:
        logger.exception("Push notification handler failed")
        return {"status": "error", "reason": str(e)}
