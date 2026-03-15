import json
import psycopg2
import os

DB_HOST = os.environ.get('DB_HOST')
DB_NAME = os.environ.get('DB_NAME')
DB_USER = os.environ.get('DB_USER')
DB_PASSWORD = os.environ.get('DB_PASSWORD')

def lambda_handler(event, context):

    print("RECEIVED DATA:", event)
    
    try:
        # Read MQTT JSON payload from IoT Core
        device_id = event.get('device_id')
        value = event.get('value')
        sensor_type = event.get('sensor_type')
        unit = event.get('unit', '') 
        
        if not device_id or not value or not sensor_type:
            return {
                'statusCode': 400,
                'body': json.dumps('Error: Missing sensor data parameters!')
            }

        # Connect to PostgreSQL database
        connection = psycopg2.connect(
            host=DB_HOST,
            database=DB_NAME,
            user=DB_USER,
            password=DB_PASSWORD,
            port="5432"
        )
        cursor = connection.cursor()

        # SQL query to insert sensor data into SENSOR_DATA table
        insert_query = """
            INSERT INTO SENSOR_DATA (deviceID, value, sensor_type, unit) 
            VALUES (%s, %s, %s, %s)
        """
        record_to_insert = (device_id, str(value), sensor_type, unit)

        cursor.execute(insert_query, record_to_insert)
        connection.commit()

        print(f"Success: {sensor_type} sensor data added to DB. Value: {value}")

    except (Exception, psycopg2.Error) as error:
        print("Error while inserting data into database:", error)
        return {
            'statusCode': 500,
            'body': json.dumps('Database error')
        }
    finally:
        # Close connection
        if 'connection' in locals() and connection:
            cursor.close()
            connection.close()

    return {
        'statusCode': 200,
        'body': json.dumps('Sensor data saved successfully!')
    }