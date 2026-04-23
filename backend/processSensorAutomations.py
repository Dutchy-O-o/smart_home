import json
import psycopg2
import boto3
import uuid
import re
import os
from datetime import datetime

# Veritabanı bağlantı bilgileri (Lambda Environment Variables'dan çekilir)
DB_HOST = os.environ.get('DB_HOST')
DB_NAME = os.environ.get('DB_NAME')
DB_USER = os.environ.get('DB_USER')
DB_PASS = os.environ.get('DB_PASSWORD')

# IoT Endpoint'ini Environment Variables'dan çek ve güvenli hale getir
raw_endpoint = os.environ.get('IOT_ENDPOINT')
if raw_endpoint and not raw_endpoint.startswith('https://'):
    IOT_ENDPOINT_URL = f"https://{raw_endpoint}"
else:
    IOT_ENDPOINT_URL = raw_endpoint

# IoT Client'ı açık bir şekilde (Explicitly) endpoint ile başlatıyoruz (Global)
IOT_CLIENT = boto3.client('iot-data', endpoint_url=IOT_ENDPOINT_URL)

# --- WARM START OPTİMİZASYONU ---
# Bağlantıyı global değişkende tutarak her Lambda tetiklemesinde 3 saniye beklemeyi önlüyoruz
conn = None

def get_connection():
    global conn
    if conn is None or conn.closed != 0:
        conn = psycopg2.connect(host=DB_HOST, database=DB_NAME, user=DB_USER, password=DB_PASS)
    return conn


def parse_trigger_condition(condition_str):
    if not condition_str:
        return None
    # Duygu kurallarini atla (emotion == 'happy' vb.) — Bu Lambda sadece sensor kurallarini degerlendirir
    if 'emotion' in condition_str.lower():
        return None
    # "temperature >= 28" formatini parse et
    match = re.match(r'(\w+)\s*(>=|<=|==|!=|>|<)\s*([\d.]+)', condition_str.strip())
    if match:
        sensor_type = match.group(1)
        operator    = match.group(2)
        threshold   = float(match.group(3))
        return (sensor_type, operator, threshold)
    return None


def evaluate_condition(actual_value, operator, threshold):
    try:
        val = float(actual_value)
    except (ValueError, TypeError):
        return False
    if operator == '>=': return val >= threshold
    if operator == '<=': return val <= threshold
    if operator == '>':  return val > threshold
    if operator == '<':  return val < threshold
    if operator == '==': return val == threshold
    if operator == '!=': return val != threshold
    return False


def lambda_handler(event, context):
    try:
        print(f"1. Gelen Event: {json.dumps(event)}")

        # --- IoT Core Rule SQL'inden gelen verileri yakala ---
        # SQL: SELECT *, topic(2) as home_id FROM 'homes/+/sensor'
        home_id   = event.get('home_id')
        device_id = event.get('deviceID')
        raw_data  = event.get('data', {})

        if not home_id or not raw_data:
            print("UYARI: home_id veya data bulunamadi, cikiliyor.")
            return

        # Sensor verilerini duz bir dict'e cevir
        # Pi iki formatta yollayabilir:
        #   Format A: {"temperature": 29.5, "humidity": 45}
        #   Format B: {"temperature": {"value": "29.5", "unit": "C"}, ...}
        sensor_values = {}
        for key, val in raw_data.items():
            if isinstance(val, dict):
                sensor_values[key] = val.get('value', val)
            else:
                sensor_values[key] = val

        print(f"2. Parse edildi -> homeID={home_id}, deviceID={device_id}, sensorler={sensor_values}")

        # --- Global DB Baglantisini Al (Sicak Baslangic) ---
        db_conn = get_connection()
        cur = db_conn.cursor()

        # --- ADIM 1: Bu eve ait aktif sensor kurallarini cek ---
        cur.execute("""
            SELECT ruleid, rule_name, trigger_condition
            FROM AUTOMATION_RULES
            WHERE homeid = %s AND is_enabled = true
        """, (home_id,))
        rules = cur.fetchall()

        if not rules:
            print(f"3. Bu ev icin aktif kural bulunamadi (homeID={home_id}).")
            cur.close()
            return

        print(f"3. {len(rules)} adet aktif kural bulundu. Degerlendirme basliyor...")

        # --- ADIM 2: Her kurali degerlendir ---
        for rule in rules:
            rule_id, rule_name, trigger_condition = rule

            parsed = parse_trigger_condition(trigger_condition)
            if parsed is None:
                continue  # Duygu kurali veya parse edilemeyen kural -> atla

            sensor_type, operator, threshold = parsed

            # Bu sensor tipi gelen veride var mi?
            if sensor_type not in sensor_values:
                continue

            actual_value = sensor_values[sensor_type]

            # --- ADIM 3: EVALUATION - Kosul saglaniyor mu? ---
            if not evaluate_condition(actual_value, operator, threshold):
                continue  # Esik asilmadi -> bir sonraki kurala gec

            print(f"4. KOSUL SAGLANDI! Kural: '{rule_name}' ({trigger_condition}), Gelen deger: {actual_value}")

            # --- ADIM 4: automation_executions'a "Pending" kaydi ac ---
            execution_id = str(uuid.uuid4())
            timestamp = datetime.utcnow()

            cur.execute("""
                INSERT INTO AUTOMATION_EXECUTIONS (executionid, ruleid, executed_at, result)
                VALUES (%s, %s, %s, %s)
            """, (execution_id, rule_id, timestamp, 'Pending'))

            print(f"5. Execution kaydi acildi: {execution_id} (Pending)")

            # --- ADIM 5: Bu kuralin aksiyonlarini cek (hangi cihaza ne komut gidecek) ---
            cur.execute("""
                SELECT ra.deviceid, ap.property_name, ad.target_value
                FROM RULE_ACTIONS ra
                JOIN ACTION_DETAILS ad ON ra.actionid = ad.actionid
                JOIN ACTUATOR_PROPERTIES ap ON ad.propertyid = ap.propertyid
                WHERE ra.ruleid = %s
            """, (rule_id,))
            actions = cur.fetchall()

            if not actions:
                print(f"UYARI: Kural '{rule_name}' icin aksiyon bulunamadi, atlaniyor.")
                continue

            # Aksiyonlari cihaz bazli grupla
            device_commands = {}
            for dev_id, prop, val in actions:
                if dev_id not in device_commands:
                    device_commands[dev_id] = []
                device_commands[dev_id].append({"property_name": prop, "value": val})

            # --- ADIM 6: Her cihaz icin MQTT komutu publish et ---
            print("6. IoT Core'a MQTT mesaji firlatmaya calisiyorum...")
            for dev_id, commands in device_commands.items():
                mqtt_payload = {
                    "deviceID": dev_id,
                    "executionID": execution_id,
                    "commands": commands
                }

                topic = f"homes/{home_id}/command"
                IOT_CLIENT.publish(
                    topic=topic,
                    qos=1,
                    payload=json.dumps(mqtt_payload)
                )
                print(f"7. MQTT Publish -> topic={topic}, cihaz={dev_id}, komutlar={commands}")

        # DB Degisikliklerini Onayla
        db_conn.commit()

        # SADECE CURSOR'U KAPAT. BAGLANTI (db_conn) ACIK KALSIN!
        cur.close()

        print("8. Islem tamamlandi.")

    except Exception as e:
        if 'db_conn' in locals() and db_conn and db_conn.closed == 0:
            db_conn.rollback()
        print(f"HATA: {e}")
        raise e
