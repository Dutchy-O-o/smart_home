"""verifyRfidAccess Lambda

Triggered by AWS IoT Rule on topic homes/+/rfid_check.
Decides whether a card UID is authorized for a given home, writes an
audit log row, and publishes the result back so Raspi can act on it.

Expected event payload:
    {
      "homeID":   "<uuid>",
      "card_uid": "AB12CD34"
    }

Side effects:
    - INSERT into access_log
    - publish to homes/{homeID}/rfid_result with {result, label, card_uid}
    - if denied, also publish to homes/{homeID}/alert with event_type=rfid_unauthorized
      (existing pushAlertNotificationstoUsers Lambda will pick that up and send FCM)
"""

import json
import logging
import os

import boto3
import psycopg2

logger = logging.getLogger()
logger.setLevel(logging.INFO)


def _get_iot_client():
    endpoint = os.environ.get("IOT_ENDPOINT")
    if not endpoint:
        raise RuntimeError("IOT_ENDPOINT env var missing")
    return boto3.client("iot-data", endpoint_url=f"https://{endpoint}")


def _lookup_card(home_id: str, card_uid: str):
    """Returns (result, label) tuple. result is one of: authorized, denied."""
    conn = None
    cur = None
    try:
        conn = psycopg2.connect(
            host=os.environ["DB_HOST"],
            user=os.environ["DB_USER"],
            password=os.environ["DB_PASSWORD"],
            dbname=os.environ["DB_NAME"],
            connect_timeout=5,
        )
        cur = conn.cursor()
        cur.execute(
            """
            SELECT label
            FROM authorized_cards
            WHERE homeid = %s
              AND card_uid = %s
              AND is_active = true
              AND (expires_at IS NULL OR expires_at > NOW())
            LIMIT 1
            """,
            (home_id, card_uid),
        )
        row = cur.fetchone()

        if row is not None:
            label = row[0]
            result = "authorized"
        else:
            label = None
            result = "denied"

        cur.execute(
            """
            INSERT INTO access_log (homeid, card_uid, card_label, result)
            VALUES (%s, %s, %s, %s)
            """,
            (home_id, card_uid, label, result),
        )
        conn.commit()
        return result, label
    finally:
        if cur is not None:
            cur.close()
        if conn is not None:
            conn.close()


def lambda_handler(event, context):
    home_id = event.get("homeID")
    card_uid = event.get("card_uid")

    logger.info(
        "RFID verify request: home_id=%s card_uid=%s", home_id, card_uid
    )

    if not home_id or not card_uid:
        logger.warning("Missing homeID or card_uid")
        return {"status": "error", "reason": "missing homeID or card_uid"}

    try:
        result, label = _lookup_card(home_id, card_uid)
    except Exception as e:
        logger.exception("DB lookup failed")
        return {"status": "error", "reason": str(e)}

    iot = _get_iot_client()

    if result == "denied":
        try:
            iot.publish(
                topic=f"homes/{home_id}/alert",
                qos=1,
                payload=json.dumps(
                    {
                        "homeID": home_id,
                        "event_type": "rfid_unauthorized",
                        "message": f"Bilinmeyen kart: {card_uid}",
                    }
                ),
            )
        except Exception:
            logger.exception("Failed to publish alert (non-fatal)")

    try:
        iot.publish(
            topic=f"homes/{home_id}/rfid_result",
            qos=1,
            payload=json.dumps(
                {
                    "card_uid": card_uid,
                    "result": result,
                    "label": label,
                }
            ),
        )
    except Exception as e:
        logger.exception("Failed to publish rfid_result")
        return {"status": "error", "reason": str(e), "result": result}

    logger.info("RFID verify done: %s (%s)", result, label or "-")
    return {"status": "ok", "result": result, "label": label}
