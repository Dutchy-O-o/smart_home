import os
import psycopg2

def lambda_handler(event, context):
    # Sadece "Kayıt Onaylandı" tetiklemesinde çalışmasını garantilemek için bir kontrol
    if event.get('triggerSource') == 'PostConfirmation_ConfirmSignUp':
        
        # Cognito'nun bize yolladığı event'in içinden verileri cımbızlıyoruz
        user_sub = event['request']['userAttributes']['sub'] # Senin yeni UID'n (Primary Key)
        email = event['request']['userAttributes'].get('email', '')
        username = event['userName']
        
        try:
            # DB bağlantı ayarları (Environment Variables)
            DB_HOST = os.environ.get('DB_HOST')
            DB_USER = os.environ.get('DB_USER') 
            DB_PASS = os.environ.get('DB_PASSWORD') 
            DB_NAME = os.environ.get('DB_NAME') 

            # DİKKAT 1: psycopg2'de "passwd" yerine "password", "db" yerine "dbname" kullanılır.
            conn = psycopg2.connect(
                host=DB_HOST, 
                user=DB_USER, 
                password=DB_PASS, 
                dbname=DB_NAME, 
                connect_timeout=5
            )
            cursor = conn.cursor()
            
            # DİKKAT 2: PostgreSQL genelde tablo ve sütun isimlerinde küçük harf sever. 
            # Eğer db'de büyük açtıysan "USERS", küçük açtıysan "users" yaz.
            sql = "INSERT INTO users (uid, username, email, created_at) VALUES (%s, %s, %s, NOW())"
            cursor.execute(sql, (user_sub, username, email))
            conn.commit()
            
            print(f"Başarılı: {username} veritabanına eklendi.")
            
        except Exception as e:
            print(f"Veritabanına yazarken hata oluştu: {e}")
            # ÖNEMLİ: Hata olsa bile uygulamayı kitlememek için loglayıp geçiyoruz.
            
        finally:
            # DİKKAT 3: psycopg2'de "conn.open" yoktur. "conn.closed == 0" diye kontrol edilir.
            if 'conn' in locals() and conn.closed == 0:
                conn.close()

    # EN ÖNEMLİ KISIM: Cognito bu event objesini geri döndürmeni bekler. 
    return event