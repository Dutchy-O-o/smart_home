"""updateMemberRole Lambda

Lets an admin change a member's role: promote a guest to admin, or demote
an admin back to guest. Used by the Guest Management screen.

Endpoint:
    PATCH /prod/{homeID}/members/{userID}
    body: {"role": "admin" | "guest"}

Response (200):
    { "updated": true, "user_id": "...", "role": "admin" }

Errors:
    400 — invalid role / missing body
    401 — not authenticated
    403 — caller is not admin / target self-demotion when alone
    404 — target not in this home
    409 — would leave the home admin-less

Auth model:
    * Caller must be an admin of this home.
    * Caller can demote themselves ONLY if another admin remains in the home.
    * Role value must be exactly 'admin' or 'guest' (case-insensitive).

Required env vars: DB_HOST, DB_NAME, DB_USER, DB_PASSWORD
"""
import json
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

VALID_ROLES = {'admin', 'guest'}


def _resp(code, body):
    return {'statusCode': code, 'headers': CORS_HEADERS, 'body': json.dumps(body)}


def lambda_handler(event, context):
    conn = None
    try:
        claims = event.get('requestContext', {}).get('authorizer', {}).get('claims', {})
        caller_id = claims.get('sub')
        if not caller_id:
            return _resp(401, {'error': 'Unauthorized.'})

        path = event.get('pathParameters') or {}
        home_id = path.get('homeID')
        target_id = path.get('userID')
        if not home_id or not target_id:
            return _resp(400, {'error': 'homeID and userID path parameters required.'})

        # Parse desired role from body.
        try:
            body = json.loads(event.get('body') or '{}')
        except json.JSONDecodeError:
            return _resp(400, {'error': 'Body must be valid JSON.'})

        new_role = (body.get('role') or '').strip().lower()
        if new_role not in VALID_ROLES:
            return _resp(400, {'error': "role must be 'admin' or 'guest'."})

        conn = psycopg2.connect(
            host=DB_HOST, database=DB_NAME, user=DB_USER,
            password=DB_PASSWORD, port=DB_PORT, connect_timeout=5,
        )
        cur = conn.cursor()

        # Caller must be admin.
        cur.execute(
            "SELECT role FROM user_homes WHERE userid = %s AND homeid = %s",
            (caller_id, home_id),
        )
        caller_row = cur.fetchone()
        if not caller_row or (caller_row[0] or '').lower() != 'admin':
            return _resp(403, {'error': 'Only admins can change member roles.'})

        # Target must exist.
        cur.execute(
            "SELECT role FROM user_homes WHERE userid = %s AND homeid = %s",
            (target_id, home_id),
        )
        target_row = cur.fetchone()
        if not target_row:
            return _resp(404, {'error': 'User is not a member of this home.'})
        current_role = (target_row[0] or '').lower()

        if current_role == new_role:
            return _resp(200, {
                'updated': False,
                'user_id': target_id,
                'role': new_role,
                'note': 'Role unchanged.',
            })

        # Demoting the last admin would lock the home — refuse.
        if current_role == 'admin' and new_role == 'guest':
            cur.execute(
                "SELECT COUNT(*) FROM user_homes WHERE homeid = %s AND LOWER(role) = 'admin'",
                (home_id,),
            )
            admin_count = cur.fetchone()[0]
            if admin_count <= 1:
                return _resp(409, {
                    'error': "Cannot demote the only admin. Promote someone else first.",
                })

        cur.execute(
            "UPDATE user_homes SET role = %s WHERE userid = %s AND homeid = %s",
            (new_role, target_id, home_id),
        )
        conn.commit()

        return _resp(200, {
            'updated': True,
            'user_id': target_id,
            'role': new_role,
        })

    except Exception as e:
        print(f"[ERROR] {e}")
        if conn:
            try:
                conn.rollback()
            except Exception:
                pass
        return _resp(500, {'error': 'Internal server error.', 'details': str(e)})
    finally:
        if conn:
            try:
                cur.close()
            except Exception:
                pass
            conn.close()
