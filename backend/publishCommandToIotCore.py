import json
import boto3

# Initialize IoT Data Client 
iot_client = boto3.client('iot-data', region_name='us-east-1') 

def lambda_handler(event, context):
    try:
        # API Gateway "Proxy Integration" provides body as string
        body = json.loads(event.get('body', '{}'))
        device_id = body.get('device_id')
        action = body.get('action') 
        value = body.get('value') 
        
        print(f"Received command: {action}")
        
        if not device_id or not action:
            return {
                'statusCode': 400, 
                'body': json.dumps('Missing parameter: device_id and action are required.')
            }

        # Subscribed MQTT topic for Raspberry Pi
        topic = f"/komut"

        # Publish message to IoT Core
        iot_client.publish(
            topic=topic,
            qos=1,
            payload=json.dumps({'komut': action,"value":value})
        )

        return {
            'statusCode': 200,
            'body': json.dumps({'status': 'Success', 'message': f'Command sent to device {device_id}.'})
        }

    except Exception as e:
        print("Error:", e)
        return {
            'statusCode': 500, 
            'body': json.dumps('An error occurred on the server.')
        }