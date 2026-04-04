import json
import psycopg2
import os

# Veritabanı bağlantı bilgilerini Çevre Değişkenlerinden (Environment Variables) alıyoruz
DB_HOST = os.environ.get('DB_HOST')
DB_NAME = os.environ.get('DB_NAME')
DB_USER = os.environ.get('DB_USER')
DB_PASSWORD = os.environ.get('DB_PASSWORD')

def lambda_handler(event, context):
    print(f"Gelen Ham Veri: {json.dumps(event)}")
    
    conn = None
    try:
        # 1. JSON'dan ana verileri çek
        device_id = event.get('deviceID')
        timestamp = event.get('timestamp')
        sensor_data_dict = event.get('data', {})
        
        if not device_id or not sensor_data_dict:
            raise Exception("Hata: deviceID veya data objesi bulunamadı!")

        # 2. Veritabanına bağlan
        conn = psycopg2.connect(
            host=DB_HOST,
            database=DB_NAME,
            user=DB_USER,
            password=DB_PASSWORD,
            connect_timeout=5
        )
        cur = conn.cursor()

        # 3. Yeni JSON yapısına göre sensör verilerini ayıkla
        records_to_insert = []
        for sensor_type, sensor_info in sensor_data_dict.items():
            # Artık value ve unit içerideki objeden geliyor
            val = str(sensor_info.get('value', ''))
            unit = str(sensor_info.get('unit', ''))
            
            # dataID'yi çıkardık, veritabanı kendi halledecek
            records_to_insert.append((
                device_id,
                timestamp,
                val,
                sensor_type,
                unit
            ))

        # 4. Toplu Ekleme (dataID sütunu sorgudan çıkarıldı)
        insert_query = """
            INSERT INTO SENSOR_DATA (deviceID, timestamp, value, sensor_type, unit)
            VALUES (%s, %s, %s, %s, %s)
        """
        
        cur.executemany(insert_query, records_to_insert)
        conn.commit()
        
        print(f"✅ Başarılı: {device_id} cihazından gelen {len(records_to_insert)} adet sensör verisi kaydedildi.")
        
        return {
            'statusCode': 200,
            'body': json.dumps('Veriler başarıyla kaydedildi!')
        }

    except Exception as e:
        print(f"❌ HATA: {e}")
        if conn:
            conn.rollback()
        return {
            'statusCode': 500,
            'body': json.dumps(f"Veri yazılamadı: {str(e)}")
        }
    finally:
        if conn:
            cur.close()
            conn.close()