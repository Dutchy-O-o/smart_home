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


# Map a raw event_type into (alert_type, alert_level) for the
# user_alerts table. Mirrors what the Flutter FCM handler does so the
# server log and the local feed agree on classification.
_EVENT_CLASSIFICATION = {
    "gas_leak":              ("security", "critical"),
    "earthquake":            ("security", "critical"),
    "rfid_unauthorized":     ("security", "warning"),
    "rfid_denied":           ("security", "warning"),
    "unauthorized_access":   ("security", "warning"),
    "emotion_change":        ("emotion",  "info"),
    "stove_left_on":         ("device",   "warning"),
    "tv_idle_long":          ("device",   "info"),
    "ac_running_window_open":("device",   "warning"),
    "device_offline":        ("device",   "warning"),
    "rfid_authorized":       ("device",   "info"),
}


def _persist_alert_for_home_users(home_id: str, title: str, body: str,
                                  event_type: str):
    """Write one user_alerts row per user in the home. Best-effort —
    catches its own exceptions so a DB hiccup never blocks FCM delivery.

    Bootstraps the user_alerts table on first call so we don't depend on
    saveAlertEvent having run already.
    """
    import uuid
    conn = None
    cursor = None
    try:
        atype, alevel = _EVENT_CLASSIFICATION.get(event_type, ("device", "info"))
        conn = psycopg2.connect(
            host=os.environ["DB_HOST"],
            user=os.environ["DB_USER"],
            password=os.environ["DB_PASSWORD"],
            dbname=os.environ["DB_NAME"],
            connect_timeout=5,
        )
        cursor = conn.cursor()
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS user_alerts (
              alert_id    VARCHAR(64) PRIMARY KEY,
              homeid      VARCHAR(64) NOT NULL,
              userid      VARCHAR(64) NOT NULL,
              title       TEXT NOT NULL,
              description TEXT,
              alert_type  VARCHAR(32) NOT NULL,
              alert_level VARCHAR(16) NOT NULL,
              is_read     BOOLEAN DEFAULT FALSE,
              created_at  TIMESTAMP NOT NULL DEFAULT NOW()
            )
        """)
        cursor.execute("""
            CREATE INDEX IF NOT EXISTS idx_user_alerts_owner
              ON user_alerts(homeid, userid, created_at DESC)
        """)
        conn.commit()

        cursor.execute(
            'SELECT DISTINCT "userid" FROM user_homes WHERE "homeid" = %s',
            (home_id,),
        )
        user_ids = [row[0] for row in cursor.fetchall() if row[0]]
        if not user_ids:
            return

        rows = [
            (str(uuid.uuid4()), home_id, uid, title, body, atype, alevel)
            for uid in user_ids
        ]
        cursor.executemany(
            """
            INSERT INTO user_alerts
              (alert_id, homeid, userid, title, description, alert_type, alert_level)
            VALUES (%s, %s, %s, %s, %s, %s, %s)
            """,
            rows,
        )
        conn.commit()
        logger.info("Persisted alert to %d user_alerts rows", len(rows))
    except Exception:
        logger.exception("Failed to persist alert (non-fatal)")
        if conn is not None:
            try:
                conn.rollback()
            except Exception:
                pass
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

        title, body = _resolve_title_body(event_type, alert_message)

        # Persist the alert server-side BEFORE checking FCM tokens. We
        # want it to show up in the Notifications screen even when no
        # device is registered for push (or the push fails) — the user
        # can still see the history when they next open the app.
        # Best-effort: failures are logged but never block the push.
        _persist_alert_for_home_users(home_id, title, body, event_type)

        tokens = _get_tokens(home_id)
        if not tokens:
            logger.info("No FCM tokens registered for home %s", home_id)
            return {"status": "no_tokens"}

        # Android-specific config: high priority + channel_id are REQUIRED
        # for the notification to surface in the system tray when the app is
        # in background or killed on Android 8+ / 13+. Without these, FCM
        # delivers the payload but the OS never displays it.
        android_config = messaging.AndroidConfig(
            priority="high",
            notification=messaging.AndroidNotification(
                title=title,
                body=body,
                channel_id="high_importance_channel",
                sound="default",
                default_sound=True,
                default_vibrate_timings=True,
                notification_count=1,
            ),
        )

        # APNS config so iOS shows the alert when the app is backgrounded.
        apns_config = messaging.APNSConfig(
            headers={"apns-priority": "10"},
            payload=messaging.APNSPayload(
                aps=messaging.Aps(
                    alert=messaging.ApsAlert(title=title, body=body),
                    sound="default",
                    content_available=True,
                ),
            ),
        )

        message = messaging.MulticastMessage(
            notification=messaging.Notification(title=title, body=body),
            android=android_config,
            apns=apns_config,
            data={
                "event": event_type,
                "title": title,
                "body": body,
                "message": alert_message or "",
                "click_action": "FLUTTER_NOTIFICATION_CLICK",
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
