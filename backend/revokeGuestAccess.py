"""revokeGuestAccess Lambda

Removes a single guest (or any non-admin user) from a home. Used by the
Flutter Profile > Guest Management screen. Admins cannot be removed by
this endpoint — that requires a separate ownership-transfer flow.

Endpoint:
    DELETE /prod/{homeID}/members/{userID}   (Cognito-authorized)

Response (200):
    { "removed": true, "user_id": "<uuid>" }

Errors:
    401 — caller is not authenticated
    403 — caller is not an admin of this home OR target user is also an admin
    404 — target user is not a member of this home
    400 — caller is trying to remove themselves
    409 — target is the home's last admin (only relevant if you later allow
          removing admins via a different flow; safe guard kept here)

Auth model:
    * Caller must be authenticated via Cognito (sub claim required).
    * Caller MUST have role='admin' in user_homes for this home.
    * Caller cannot remove themselves (use a dedicated leave-home flow).
    * Cannot remove another admin via this endpoint — guests only.

Side effects:
    * Best-effort FCM push to the removed user telling them their access
      was revoked. Failures are logged but never block the revoke — the
      delete is the source of truth, the notification is informational.

Required env vars:
    DB_HOST, DB_NAME, DB_USER, DB_PASSWORD
"""
import json
import logging
import os
import psycopg2

DB_HOST = os.environ.get('DB_HOST')
DB_NAME = os.environ.get('DB_NAME')
DB_USER = os.environ.get('DB_USER')
DB_PASSWORD = os.environ.get('DB_PASSWORD')
DB_PORT = os.environ.get('DB_PORT', '5432')

CORS_HEADERS = {
    'Access-Control-Allow-Origin': '*',
    'Content-Type': 'application/json',
}

logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Lazy Firebase init — only when the FCM layer is actually present in the
# deployment, so the Lambda still works in environments without push set
# up (local tests, future redeploys without the layer, etc).
_fcm_ready = False
try:
    import firebase_admin
    from firebase_admin import credentials, messaging
    if not firebase_admin._apps:
        firebase_admin.initialize_app(
            credentials.Certificate("firebase-service-account.json")
        )
    _fcm_ready = True
except Exception as _e:
    logger.warning("FCM disabled (firebase_admin not configured): %s", _e)


def _notify_revoked(target_user_id, home_name):
    """Best-effort push: tell the removed user their access was revoked.
    Never raises — logs and returns. The revoke itself has already
    committed by the time we're called.
    """
    if not _fcm_ready or not target_user_id:
        return
    conn = None
    try:
        conn = psycopg2.connect(
            host=DB_HOST, database=DB_NAME, user=DB_USER,
            password=DB_PASSWORD, port=DB_PORT, connect_timeout=5,
        )
        cur = conn.cursor()
        # Schema (from pushAlertNotificationstoUsers): users.fcm_token
        # joined to user_homes.userid via users.uid.
        cur.execute(
            'SELECT fcm_token FROM users WHERE "uid" = %s AND fcm_token IS NOT NULL',
            (target_user_id,),
        )
        row = cur.fetchone()
        if not row or not row[0]:
            logger.info("No FCM token for user %s — skipping push.", target_user_id)
            return
        token = row[0]
        title = "Access revoked"
        body = f'Your access to "{home_name}" was revoked by the admin.'
        message = messaging.Message(
            notification=messaging.Notification(title=title, body=body),
            android=messaging.AndroidConfig(
                priority="high",
                notification=messaging.AndroidNotification(
                    title=title,
                    body=body,
                    channel_id="high_importance_channel",
                    sound="default",
                ),
            ),
            apns=messaging.APNSConfig(
                headers={"apns-priority": "10"},
                payload=messaging.APNSPayload(
                    aps=messaging.Aps(
                        alert=messaging.ApsAlert(title=title, body=body),
                        sound="default",
                    ),
                ),
            ),
            data={
                "event": "access_revoked",
                "home_name": home_name or "",
            },
            token=token,
        )
        messaging.send(message)
        logger.info("Revoke push sent to %s", target_user_id)
    except Exception as e:
        logger.warning("Revoke push failed for %s: %s", target_user_id, e)
    finally:
        if conn:
            try:
                cur.close()
            except Exception:
                pass
            conn.close()


def lambda_handler(event, context):
    conn = None
    try:
        claims = event.get('requestContext', {}).get('authorizer', {}).get('claims', {})
        caller_id = claims.get('sub')
        if not caller_id:
            return {
                'statusCode': 401,
                'headers': CORS_HEADERS,
                'body': json.dumps({'error': 'Unauthorized.'}),
            }

        path_params = event.get('pathParameters') or {}
        home_id = path_params.get('homeID')
        target_user_id = path_params.get('userID')
        if not home_id or not target_user_id:
            return {
                'statusCode': 400,
                'headers': CORS_HEADERS,
                'body': json.dumps({'error': 'homeID and userID path parameters required.'}),
            }

        if target_user_id == caller_id:
            return {
                'statusCode': 400,
                'headers': CORS_HEADERS,
                'body': json.dumps({'error': 'You cannot remove yourself. Use leave-home instead.'}),
            }

        conn = psycopg2.connect(
            host=DB_HOST, database=DB_NAME, user=DB_USER,
            password=DB_PASSWORD, port=DB_PORT, connect_timeout=5,
        )
        cur = conn.cursor()

        # 1) Caller must be ADMIN of this home.
        cur.execute(
            "SELECT role FROM user_homes WHERE userid = %s AND homeid = %s",
            (caller_id, home_id),
        )
        caller_row = cur.fetchone()
        if not caller_row or (caller_row[0] or '').lower() != 'admin':
            return {
                'statusCode': 403,
                'headers': CORS_HEADERS,
                'body': json.dumps({'error': 'Only admins can remove members from this home.'}),
            }

        # 2) Target must exist in this home and must NOT be another admin.
        cur.execute(
            "SELECT role FROM user_homes WHERE userid = %s AND homeid = %s",
            (target_user_id, home_id),
        )
        target_row = cur.fetchone()
        if not target_row:
            return {
                'statusCode': 404,
                'headers': CORS_HEADERS,
                'body': json.dumps({'error': 'User is not a member of this home.'}),
            }
        if (target_row[0] or '').lower() == 'admin':
            return {
                'statusCode': 403,
                'headers': CORS_HEADERS,
                'body': json.dumps({
                    'error': 'Cannot remove another admin. Demote them first.',
                }),
            }

        # 3) Final safety: never let a home end up with zero admins. (Cannot
        # happen via this endpoint since we only delete non-admins above,
        # but keep the check so the contract holds if a future code path
        # ever broadens this query.)
        cur.execute(
            "SELECT COUNT(*) FROM user_homes WHERE homeid = %s AND LOWER(role) = 'admin'",
            (home_id,),
        )
        admin_count = cur.fetchone()[0]
        if admin_count < 1:
            return {
                'statusCode': 409,
                'headers': CORS_HEADERS,
                'body': json.dumps({'error': 'Refusing to leave the home with no admin.'}),
            }

        # 4) Look up the home name BEFORE the delete so we can include it
        # in the push notification (it's tied to the home, not the
        # membership row, so it survives the delete — but we lift it
        # before the commit anyway to keep both code paths simple).
        cur.execute("SELECT home_name FROM homes WHERE homeid = %s", (home_id,))
        home_row = cur.fetchone()
        home_name = home_row[0] if home_row else 'this home'

        # 5) Delete the membership row.
        cur.execute(
            "DELETE FROM user_homes WHERE userid = %s AND homeid = %s",
            (target_user_id, home_id),
        )
        conn.commit()

        # 6) Best-effort FCM push to the removed user. Runs AFTER commit so
        # a notification failure can never block the revoke.
        _notify_revoked(target_user_id, home_name)

        return {
            'statusCode': 200,
            'headers': CORS_HEADERS,
            'body': json.dumps({'removed': True, 'user_id': target_user_id}),
        }

    except Exception as e:
        print(f"[ERROR] {e}")
        if conn:
            try:
                conn.rollback()
            except Exception:
                pass
        return {
            'statusCode': 500,
            'headers': CORS_HEADERS,
            'body': json.dumps({'error': 'Internal server error.', 'details': str(e)}),
        }
    finally:
        if conn:
            try:
                cur.close()
            except Exception:
                pass
            conn.close()
