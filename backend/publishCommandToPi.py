import json
import boto3
import os

def get_iot_client():
    env_endpoint = os.environ.get('IOT_ENDPOINT')
    if not env_endpoint:
        raise ValueError("IOT_ENDPOINT environment variable is not set. Please add it to the Lambda configuration.")
    return boto3.client('iot-data', endpoint_url=f"https://{env_endpoint}")

client = get_iot_client()

def lambda_handler(event, context):
    try:
        # 1. API Gateway'den homeID'yi al
        path_parameters = event.get('pathParameters') or {}
        home_id = path_parameters.get('homeID')
        
        # 2. Body içinden cihaz ID ve komut listesini al
        body = json.loads(event.get('body', '{}'))
        device_id = body.get('deviceID')
        commands = body.get('commands', [])
        
        if not home_id or not device_id or not commands:
            return {
                'statusCode': 400,
                'headers': {'Access-Control-Allow-Origin': '*'},
                'body': json.dumps({'error': 'Missing parameter: homeID, deviceID or commands not found.'})
            }
        
        # 3. Raspberry Pi'nin anlayacağı JSON payload'ını hazırla
        payload = {
            "deviceID": device_id,
            "commands": commands
        }
        
        # 4. MQTT Topic'i belirle
        topic = f"homes/{home_id}/command"
        
        # 5. Mesajı AWS IoT Core'a Publish et (QoS 0 veya 1 mantığı ile)
        client.publish(
            topic=topic,
            qos=1,  # Mesajın iletildiğinden emin olmak için Quality of Service 1 
            payload=json.dumps(payload)
        )
        
        # 6. Mobil uygulamaya anında "Başarılı" cevabı dön. 
        # (Cihaz henüz işlemi bitirmedi, sadece komut iletildi)
        return {
            'statusCode': 200,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({'status': 'success', 'message': 'Command delivered to the Raspberry Pi.'})
        }
        
    except json.JSONDecodeError:
        return {
            'statusCode': 400,
            'headers': {'Access-Control-Allow-Origin': '*'},
            'body': json.dumps({'error': 'Invalid JSON format.'})
        }
    except Exception as e:
        print(f"An error occurred: {str(e)}")
        return {
            'statusCode': 500,
            'headers': {'Access-Control-Allow-Origin': '*'},
            'body': json.dumps({'error': 'Internal server error.', 'details': str(e)})
        }
