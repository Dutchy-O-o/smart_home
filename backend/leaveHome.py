"""leaveHome Lambda

Lets a user remove themselves from a home they joined. Symmetric to the
admin-driven revokeGuestAccess: this is the user-driven path.

Endpoint:
    DELETE /prod/{homeID}/leave   (Cognito-authorized)

Response (200):
    { "left": true, "home_id": "<uuid>" }

Errors:
    401 — not authenticated
    403 — not a member of this home
    409 — caller is the last admin (would leave the home admin-less)

Auth model:
    * Caller must be authenticated.
    * Caller can only delete *their own* membership row.
    * If the caller is the only admin, we refuse — they need to promote
      someone first (E feature) or use a separate ownership-transfer flow.

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
        if not home_id:
            return {
                'statusCode': 400,
                'headers': CORS_HEADERS,
                'body': json.dumps({'error': 'homeID path parameter missing.'}),
            }

        conn = psycopg2.connect(
            host=DB_HOST, database=DB_NAME, user=DB_USER,
            password=DB_PASSWORD, port=DB_PORT, connect_timeout=5,
        )
        cur = conn.cursor()

        # 1) Caller must be a member.
        cur.execute(
            "SELECT role FROM user_homes WHERE userid = %s AND homeid = %s",
            (caller_id, home_id),
        )
        row = cur.fetchone()
        if not row:
            return {
                'statusCode': 403,
                'headers': CORS_HEADERS,
                'body': json.dumps({'error': 'You are not a member of this home.'}),
            }

        caller_role = (row[0] or '').lower()

        # 2) If caller is admin, make sure there will still be an admin
        # afterwards. Otherwise refuse — they must promote someone or
        # use an ownership-transfer flow.
        if caller_role == 'admin':
            cur.execute(
                "SELECT COUNT(*) FROM user_homes WHERE homeid = %s AND LOWER(role) = 'admin'",
                (home_id,),
            )
            admin_count = cur.fetchone()[0]
            if admin_count <= 1:
                return {
                    'statusCode': 409,
                    'headers': CORS_HEADERS,
                    'body': json.dumps({
                        'error': "You're the only admin. Promote someone else first or delete the home.",
                    }),
                }

        # 3) Delete membership.
        cur.execute(
            "DELETE FROM user_homes WHERE userid = %s AND homeid = %s",
            (caller_id, home_id),
        )
        conn.commit()

        return {
            'statusCode': 200,
            'headers': CORS_HEADERS,
            'body': json.dumps({'left': True, 'home_id': home_id}),
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
