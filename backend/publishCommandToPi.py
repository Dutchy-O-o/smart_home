import json
import boto3
import os

def get_iot_client():
    env_endpoint = os.environ.get('IOT_ENDPOINT')
    if not env_endpoint:
        raise ValueError("IOT_ENDPOINT ortam degiskeni (environment variable) ayarlanamadı! Lutfen Lambda ayarlarina ekleyin.")
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
                'body': json.dumps({'error': 'Eksik parametre: homeID, deviceID veya commands bulunamadı.'})
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
            'body': json.dumps({'status': 'success', 'message': 'Komut Raspberry Pi cihazina iletildi.'})
        }
        
    except json.JSONDecodeError:
        return {
            'statusCode': 400,
            'headers': {'Access-Control-Allow-Origin': '*'},
            'body': json.dumps({'error': 'Geçersiz JSON formatı.'})
        }
    except Exception as e:
        print(f"Hata oluştu: {str(e)}")
        return {
            'statusCode': 500,
            'headers': {'Access-Control-Allow-Origin': '*'},
            'body': json.dumps({'error': 'Sunucu içi hata.', 'details': str(e)})
        }
