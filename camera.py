import cv2
import requests
import urllib3

# Kendi ürettiğimiz SSL sertifikasını kullandığımız için uyarıları gizliyoruz
urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

# Raspberry Pi'nin API adresi
API_URL = "https://192.168.1.10:8000/predict"

print("Kamera açılıyor... Lütfen kameraya bak.")
cap = cv2.VideoCapture(0)

ret, frame = cap.read()
if ret:
    _, img_encoded = cv2.imencode('.jpg', frame)
    print("Görüntü şifreli (HTTPS) olarak Raspberry Pi'ye gönderiliyor...")
    try:
        response = requests.post(
            API_URL, 
            files={"file": ("test.jpg", img_encoded.tobytes(), "image/jpeg")}, 
            verify=False,
            timeout=15 
        )
        print("\n--- SONUÇ ---")
        if response.status_code == 200:
            print(f"Pi'den Gelen Yanıt: {response.json()}")
        else:
            print(f"Hata Kodu: {response.status_code}\nDetay: {response.text}")
    except Exception as e:
        print(f"\nBağlantı Hatası! Pi'ye ulaşılamadı. Hata: {e}")
else:
    print("Kameradan görüntü alınamadı!")

cap.release()