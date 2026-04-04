import json
import os
import psycopg2 

def lambda_handler(event, context):
    print("Gelen Event:", json.dumps(event))

    # 1. API Gateway + Cognito Authorizer'dan userId'yi (sub) çıkar
    user_id = None
    
    # Authorizer üzerinden claim deneme
    if event.get("requestContext") and event["requestContext"].get("authorizer") and event["requestContext"]["authorizer"].get("claims"):
        user_id = event["requestContext"]["authorizer"]["claims"].get("sub")
    # Postman vs. test amaçlı queryString
    elif event.get("queryStringParameters") and event["queryStringParameters"].get("userId"):
        user_id = event["queryStringParameters"]["userId"]

    if not user_id:
        return {
            "statusCode": 400,
            "headers": {
                "Access-Control-Allow-Origin": "*",
                "Access-Control-Allow-Credentials": True
            },
            "body": json.dumps({"error": "Unauthorized veya Eksik User ID tespit edildi."})
        }

    # 2. Ortam Değişkenleri (Environment Variables)
    db_host = os.environ.get("DB_HOST")
    db_user = os.environ.get("DB_USER")
    db_password = os.environ.get("DB_PASSWORD")
    db_name = os.environ.get("DB_NAME")
    db_port = os.environ.get("DB_PORT", "5432")

    connection = None
    
    try:
        # 3. PostgreSQL'e bağlan (AWS RDS, Neon, Supabase fark etmez)
        connection = psycopg2.connect(
            host=db_host,
            user=db_user,
            password=db_password,
            dbname=db_name,
            port=db_port,
            sslmode='require' # Çoğu modern Postgres sunucusu ssl gerektirir
        )
        
        cursor = connection.cursor()

        query = "SELECT * FROM get_user_homes(%s);"
        cursor.execute(query, (user_id,))
        
        rows = cursor.fetchall()
        
        colnames = [desc[0] for desc in cursor.description]
        
        homes_list = []
        for row in rows:
            homes_list.append(dict(zip(colnames, row)))

        cursor.close()
        
        return {
            "statusCode": 200,
            "headers": {
                "Access-Control-Allow-Origin": "*",
                "Access-Control-Allow-Credentials": True,
                "Content-Type": "application/json"
            },
            "body": json.dumps({
                "success": True,
                "userId": user_id,
                "homes": homes_list
            })
        }

    except Exception as e:
        print("Veritabanı VEYA İşlem Hatası:", e)
        return {
            "statusCode": 500,
            "headers": {
                "Access-Control-Allow-Origin": "*"
            },
            "body": json.dumps({
                "error": "Sunucu hatası, evler listelenemedi.",
                "details": str(e)
            })
        }
    finally:
        if connection:
            connection.close()
