import json
import os
import psycopg2 

def lambda_handler(event, context):
    print("Received Event:", json.dumps(event))

    # 1. Extract userId (sub) from API Gateway + Cognito Authorizer
    user_id = None
    
    # Try fetching claim via Authorizer
    if event.get("requestContext") and event["requestContext"].get("authorizer") and event["requestContext"]["authorizer"].get("claims"):
        user_id = event["requestContext"]["authorizer"]["claims"].get("sub")
    # Query string for testing via Postman etc.
    elif event.get("queryStringParameters") and event["queryStringParameters"].get("userId"):
        user_id = event["queryStringParameters"]["userId"]

    if not user_id:
        return {
            "statusCode": 400,
            "headers": {
                "Access-Control-Allow-Origin": "*",
                "Access-Control-Allow-Credentials": True
            },
            "body": json.dumps({"error": "Unauthorized or missing User ID."})
        }

    # 2. Environment Variables
    db_host = os.environ.get("DB_HOST")
    db_user = os.environ.get("DB_USER")
    db_password = os.environ.get("DB_PASSWORD")
    db_name = os.environ.get("DB_NAME")
    db_port = os.environ.get("DB_PORT", "5432")

    connection = None
    
    try:
        # 3. Connect to PostgreSQL
        connection = psycopg2.connect(
            host=db_host,
            user=db_user,
            password=db_password,
            dbname=db_name,
            port=db_port,
            sslmode='require' 
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
        print("Database or Processing Error:", e)
        return {
            "statusCode": 500,
            "headers": {
                "Access-Control-Allow-Origin": "*"
            },
            "body": json.dumps({
                "error": "Server error, failed to list homes.",
                "details": str(e)
            })
        }
    finally:
        if connection:
            connection.close()
