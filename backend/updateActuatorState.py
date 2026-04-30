import json
import psycopg2
import os
import uuid

# --- WARM START OPTİMİZASYONU ---
# Bağlantıyı globalde tutarak 3 saniyelik timeout riskini ortadan kaldırıyoruz
conn = None

def get_connection():
    global conn
    if conn is None or conn.closed != 0:
        conn = psycopg2.connect(
            host=os.environ.get('DB_HOST'),
            database=os.environ.get('DB_NAME'),
            user=os.environ.get('DB_USER'),
            password=os.environ.get('DB_PASSWORD'),
            port=os.environ.get('DB_PORT', '5432')
        )
    return conn

def lambda_handler(event, context):
    try:
        print("Gelen Event (IoT Payload):", json.dumps(event))

        device_id = event.get('deviceID')
        states = event.get('states', [])

        # --- YANKI (ECHO) MEKANİZMASI İÇİN ID YAKALAMA ---
        # Eğer manuel işlemse null/None dönecek, otomasyonsa UUID gelecek
        execution_id = event.get('executionID')

        if not device_id or not states:
            print("HATA: deviceID veya states bulunamadı.")
            return

        db_conn = get_connection()
        cur = db_conn.cursor()

        # --- 1. AŞAMA: CİHAZIN ANLIK DURUMUNU GÜNCELLEME ---
        for state in states:
            prop_name = state.get('property_name')
            current_val = state.get('current_value')

            # Önce bu property_name ve deviceID ikilisine sahip propertyID'yi bul
            get_prop_query = """
                SELECT propertyid FROM actuator_properties
                WHERE deviceid = %s AND property_name = %s LIMIT 1;
            """
            cur.execute(get_prop_query, (device_id, prop_name))
            prop_result = cur.fetchone()

            if not prop_result:
                print(f"HATA: {device_id} cihazi icin {prop_name} ozelligi actuator_properties tablosunda bulunamadi!")
                continue

            property_id = prop_result[0]

            # Bulunan propertyID ile actuator_current_states tablosuna kayıt yap veya güncelle
            check_query = "SELECT stateid FROM actuator_current_states WHERE propertyid = %s LIMIT 1;"
            cur.execute(check_query, (property_id,))
            state_row = cur.fetchone()

            if state_row:
                # Varsa Güncelle (UPDATE)
                update_query = """
                    UPDATE actuator_current_states
                    SET current_value = %s, last_updated = CURRENT_TIMESTAMP
                    WHERE propertyid = %s;
                """
                cur.execute(update_query, (str(current_val), property_id))
            else:
                # Yoksa Yeni Ekle (INSERT)
                new_state_id = str(uuid.uuid4())
                insert_query = """
                    INSERT INTO actuator_current_states (stateid, propertyid, current_value, last_updated)
                    VALUES (%s, %s, %s, CURRENT_TIMESTAMP);
                """
                cur.execute(insert_query, (new_state_id, property_id, str(current_val)))

        # --- 2. AŞAMA: OTOMASYON GEÇMİŞİNİ (EXECUTION) BAŞARILI YAPMA ---
        if execution_id:
            print(f"Otomasyon yankısı algılandı: {execution_id}. Execution tablosu güncelleniyor...")
            update_exec_query = """
                UPDATE automation_executions
                SET result = 'Success'
                WHERE executionid = %s;
            """
            cur.execute(update_exec_query, (execution_id,))

        db_conn.commit()

        # Cursor'u kapatıyoruz ama Warm-Start için DB bağlantısını açık bırakıyoruz
        cur.close()

        print(f"Basariyla guncellendi: {device_id} | ExecutionID: {execution_id}")
        return True

    except Exception as e:
        if 'db_conn' in locals() and db_conn and db_conn.closed == 0:
            db_conn.rollback()
        print(f"HATA olustu: {str(e)}")
        raise e
