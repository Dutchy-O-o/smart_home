"""getHomeMembers Lambda

Returns the list of users for a given home (admins + guests). Used by the
Flutter Profile > Guest Management screen so the home admin can see who
has access and revoke guests.

Endpoint:
    GET /prod/{homeID}/members   (Cognito-authorized)

Response (200):
    {
        "members": [
            {
                "user_id": "<cognito sub uuid>",
                "role": "admin" | "guest",
                "email": "alex@example.com",     // best-effort from Cognito
                "name":  "Alex Chen",            // best-effort
                "is_you": true | false
            },
            ...
        ]
    }

Auth model:
    * Caller must be authenticated via Cognito (sub claim required).
    * Caller MUST have role='admin' in user_homes for this home, otherwise 403.
    * Cognito lookups (email/name) are best-effort — if the IAM role doesn't
      have `cognito-idp:ListUsers` permission the response still returns
      with `email`/`name` as null so the UI degrades gracefully.

Required env vars:
    DB_HOST, DB_NAME, DB_USER, DB_PASSWORD
    COGNITO_USER_POOL_ID    (e.g. us-east-1_xxxxxxxxx)

IAM (attach to this Lambda's execution role):
    * AWSLambdaBasicExecutionRole (default)
    * RDS / VPC if the DB is private (same as other Lambdas)
    * cognito-idp:ListUsers on the user pool (for email/name enrichment)
"""
import json
import os
import psycopg2
import boto3
from botocore.exceptions import ClientError

DB_HOST = os.environ.get('DB_HOST')
DB_NAME = os.environ.get('DB_NAME')
DB_USER = os.environ.get('DB_USER')
DB_PASSWORD = os.environ.get('DB_PASSWORD')
DB_PORT = os.environ.get('DB_PORT', '5432')
USER_POOL_ID = os.environ.get('COGNITO_USER_POOL_ID')

_cognito = boto3.client('cognito-idp') if USER_POOL_ID else None

CORS_HEADERS = {
    'Access-Control-Allow-Origin': '*',
    'Content-Type': 'application/json',
}


def _enrich_with_cognito(user_ids):
    """Best-effort: fetch email/name attributes from Cognito for each sub.
    Returns {sub: {email, name}}. Failures are silently logged and the
    map is left empty for those users — the UI shows them as just user_id."""
    result = {}
    if not _cognito or not USER_POOL_ID:
        return result
    # ListUsers can be filtered by `sub = "..."` — one call per user.
    # For a typical home (admin + a handful of guests) this is cheap.
    for uid in user_ids:
        try:
            resp = _cognito.list_users(
                UserPoolId=USER_POOL_ID,
                Filter=f'sub = "{uid}"',
                Limit=1,
            )
            users = resp.get('Users') or []
            if not users:
                continue
            attrs = {a['Name']: a['Value'] for a in users[0].get('Attributes', [])}
            result[uid] = {
                'email': attrs.get('email'),
                'name': attrs.get('name') or attrs.get('given_name'),
            }
        except ClientError as e:
            print(f"[WARN] Cognito enrich failed for {uid}: {e}")
        except Exception as e:
            print(f"[WARN] Cognito enrich error for {uid}: {e}")
    return result


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

        # 1) Caller must be ADMIN of this home — guests cannot list members.
        cur.execute(
            "SELECT role FROM user_homes WHERE userid = %s AND homeid = %s",
            (caller_id, home_id),
        )
        row = cur.fetchone()
        if not row:
            return {
                'statusCode': 403,
                'headers': CORS_HEADERS,
                'body': json.dumps({'error': 'You do not have access to this home.'}),
            }
        if (row[0] or '').lower() != 'admin':
            return {
                'statusCode': 403,
                'headers': CORS_HEADERS,
                'body': json.dumps({'error': 'Only admins can list home members.'}),
            }

        # 2) Pull every member of this home, including when they joined.
        # joined_at was added in a 2026-05 migration; older rows got NOW()
        # at migration time so the column is always populated.
        cur.execute(
            "SELECT userid, role, joined_at FROM user_homes WHERE homeid = %s "
            "ORDER BY role DESC, joined_at",
            (home_id,),
        )
        rows = cur.fetchall()

        user_ids = [str(r[0]) for r in rows]
        enrichment = _enrich_with_cognito(user_ids)

        members = []
        for uid, role, joined_at in rows:
            uid_s = str(uid)
            extra = enrichment.get(uid_s, {})
            members.append({
                'user_id': uid_s,
                'role': (role or '').lower(),
                'email': extra.get('email'),
                'name': extra.get('name'),
                'is_you': uid_s == caller_id,
                # ISO-8601 string so the Flutter side can DateTime.parse().
                # Null-safe in case a legacy row somehow has no value.
                'joined_at': joined_at.isoformat() if joined_at else None,
            })

        return {
            'statusCode': 200,
            'headers': CORS_HEADERS,
            'body': json.dumps({'members': members}),
        }

    except Exception as e:
        print(f"[ERROR] {e}")
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
