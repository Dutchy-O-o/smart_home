# Raspberry Pi — RFID + Servo Bariyer Sürücüsü

> Mevcut `alert.py`'a yeni `RfidDriver` + `ServoDriver` ekleyeceğiz.
> Bulut tarafı (verifyRfidAccess Lambda + IoT Rule + DB tabloları) zaten
> hazır ve test edildi. Bu brief sadece Raspi yazılım tarafıdır.

---

## Bulut tarafından doğrulanan (zaten çalışıyor)

| Kaynak | Konum | Durum |
|---|---|---|
| `authorized_cards` tablosu | RDS Postgres | ✅ var |
| `access_log` tablosu | RDS Postgres | ✅ var |
| `verifyRfidAccess` Lambda | AWS Lambda | ✅ canlı |
| IoT Rule `rfidAccessCheck` | `homes/+/rfid_check` topic | ✅ aktif |
| Push bildirim (denied) | `pushAlertNotificationstoUsers` | ✅ test edildi, FCM gönderiyor |
| Test kartı | `TEST_AUTH_001` (label="Test Card 1") | ✅ authorized olarak DB'de |

---

## Topic schema (PiPolicy zaten yetki veriyor)

| Yön | Topic | Anlamı |
|---|---|---|
| **Publish** | `homes/{HOME_ID}/rfid_check` | Kart okunduğunda UID buraya gönder |
| **Subscribe** | `homes/{HOME_ID}/rfid_result` | verifyRfidAccess Lambda'nın cevabı buraya düşer |
| **Publish** | `homes/{HOME_ID}/state` | Bariyer/last_scan state güncellemeleri (mevcut akış) |

QoS 1 kullan, mevcut MQTT bağlantısını paylaş (yeni connection açma).

### Payload formatları

**`rfid_check` (sen yayınlıyorsun)**:
```json
{
  "homeID":   "757bfcc9-a80b-4886-a8cd-854392454caf",
  "card_uid": "AB12CD34"
}
```

**`rfid_result` (sen alıyorsun)**:
```json
{
  "card_uid": "AB12CD34",
  "result":   "authorized",   // veya "denied"
  "label":    "Test Card 1"   // authorized ise dolu, denied ise null
}
```

**RFID device state report** (mevcut state akışını kullan):
```json
{
  "deviceID": "18f122ab-b9d3-499c-b068-0f6cb7aef8fb",
  "states": [
    { "property_name": "last_scan", "current_value": "AB12CD34" },
    { "property_name": "status",    "current_value": "active" },
    { "property_name": "barrier",   "current_value": "open" }
  ]
}
```

> Not: `actuator_properties` tablosunda RFID Reader için bu üç property
> kayıtlı değil. State publish edilirse `UpdateActuatorState` Lambda
> "property bulunamadı" diye log'a düşüp atlar — sorun değil, ileride
> property row'ları eklenecek. Yine de state publish et ki ileride hazır olsun.

---

## Donanım

### MFRC522 (RFID okuyucu) — SPI

| MFRC522 pin | Raspi BCM | Fiziksel pin |
|---|---|---|
| SDA / SS | GPIO8 (CE0) | 24 |
| SCK | GPIO11 | 23 |
| MOSI | GPIO10 | 19 |
| MISO | GPIO9 | 21 |
| RST | GPIO25 | 22 |
| GND | GND | 6 veya 9 |
| 3.3V | 3.3V | 1 veya 17 |
| IRQ | bağlama | — |

**SPI etkin olmalı**: `sudo raspi-config` → Interfaces → SPI → Enable
(zaten açık olabilir, kontrol et)

### SG90 servo (bariyer) — PWM

| SG90 tel | Raspi pin | Not |
|---|---|---|
| Sarı (Signal) | GPIO12 (BCM, fiziksel pin 32) | Hardware PWM |
| Kırmızı (VCC) | 5V (pin 2 veya 4) ya da harici 5V supply | ~150mA pik |
| Kahverengi (GND) | GND, ortak | — |

Servo açıları (kullanıcı manuel test edecek, hangi açı kapalı/açık
ise koda yansıt):
- **0° = bariyer KAPALI** (kol yatay, geçiş yok)
- **90° = bariyer AÇIK** (kol dik yukarı, geçiş serbest)
- Otomatik kapanma süresi: **5 saniye** açık kaldıktan sonra 0°'ye dön

### Kırmızı LED (denied feedback) — opsiyonel ama önerilen

Bir GPIO pini boş seç (örn. GPIO5), 220-330Ω direnç ile LED bağla.
Yetkisiz kart okutulunca 2 saniye yansın.

---

## Yapılacaklar (Raspi'deki Claude Code için)

### 1. Bağımlılıkları kur

```bash
sudo apt update
sudo apt install -y python3-spidev
source /home/ramazan/led-env/bin/activate
pip install mfrc522 spidev
```

### 2. `alert.py` içine yeni driver'lar

`LedStripDriver`'ın yanına ekle:

```python
import threading
from mfrc522 import SimpleMFRC522

# RFID device ID — bulut tarafında kayıtlı
RFID_DEVICE_ID = "18f122ab-b9d3-499c-b068-0f6cb7aef8fb"
SERVO_PIN      = 12     # BCM
LED_DENIED_PIN = 5      # BCM (varsa, yoksa None geç)
SERVO_OPEN_DEG  = 90
SERVO_CLOSED_DEG = 0
BARRIER_OPEN_SEC = 5

class ServoDriver:
    def __init__(self, pin=SERVO_PIN):
        self.pin = pin
        GPIO.setup(self.pin, GPIO.OUT)
        self.pwm = GPIO.PWM(self.pin, 50)  # 50Hz
        self.pwm.start(0)
        self._barrier = "closed"
        self.set_angle(SERVO_CLOSED_DEG)

    def set_angle(self, angle):
        duty = 2 + (angle / 18.0)
        self.pwm.ChangeDutyCycle(duty)
        time.sleep(0.5)
        self.pwm.ChangeDutyCycle(0)  # jitter'ı kapat

    def open_for(self, seconds=BARRIER_OPEN_SEC):
        self.set_angle(SERVO_OPEN_DEG)
        self._barrier = "open"
        # Auto-close in background
        def close_later():
            time.sleep(seconds)
            self.set_angle(SERVO_CLOSED_DEG)
            self._barrier = "closed"
        threading.Thread(target=close_later, daemon=True).start()

    @property
    def barrier(self):
        return self._barrier


class RfidDriver:
    """Read loop runs in its own thread; publishes UIDs to AWS for verification."""
    def __init__(self, mqtt_publish, home_id, servo, denied_led_pin=LED_DENIED_PIN):
        self.reader = SimpleMFRC522()
        self.mqtt_publish = mqtt_publish   # callable: (topic, payload_dict) -> None
        self.home_id = home_id
        self.servo = servo
        self.denied_led_pin = denied_led_pin
        if denied_led_pin is not None:
            GPIO.setup(denied_led_pin, GPIO.OUT)
            GPIO.output(denied_led_pin, GPIO.LOW)
        self._last_uid = None
        self._last_seen = 0
        self._cooldown = 2.0   # aynı kartı 2 sn içinde tekrar okuma

    def start(self):
        threading.Thread(target=self._loop, daemon=True).start()

    def _loop(self):
        while True:
            try:
                uid_int, _text = self.reader.read_no_block()
                if uid_int is None:
                    time.sleep(0.2)
                    continue
                uid = format(uid_int, 'X')
                now = time.time()
                if uid == self._last_uid and (now - self._last_seen) < self._cooldown:
                    time.sleep(0.2)
                    continue
                self._last_uid = uid
                self._last_seen = now
                print(f"[RFID] card scanned: {uid}")

                # Publish state (last_scan + status=active)
                self.mqtt_publish(f"homes/{self.home_id}/state", {
                    "deviceID": RFID_DEVICE_ID,
                    "states": [
                        {"property_name": "last_scan", "current_value": uid},
                        {"property_name": "status",    "current_value": "active"},
                    ],
                })

                # Publish to verifyRfidAccess
                self.mqtt_publish(f"homes/{self.home_id}/rfid_check", {
                    "homeID":   self.home_id,
                    "card_uid": uid,
                })

                time.sleep(0.5)
            except Exception as e:
                print(f"[RFID] read error: {e}")
                time.sleep(1)

    def handle_result(self, payload):
        """Called when an rfid_result message arrives."""
        result = payload.get("result")
        label = payload.get("label")
        uid = payload.get("card_uid")
        print(f"[RFID] verify result for {uid}: {result} ({label})")

        if result == "authorized":
            print(f"[RFID] -> opening barrier")
            self.servo.open_for()
            self.mqtt_publish(f"homes/{self.home_id}/state", {
                "deviceID": RFID_DEVICE_ID,
                "states": [
                    {"property_name": "barrier", "current_value": "open"},
                ],
            })
        else:
            print(f"[RFID] -> denied")
            if self.denied_led_pin is not None:
                GPIO.output(self.denied_led_pin, GPIO.HIGH)
                threading.Timer(2.0, lambda: GPIO.output(self.denied_led_pin, GPIO.LOW)).start()
```

### 3. `RfidDriver` ve `ServoDriver`'ı başlat

`alert.py`'da AWS bağlantısı kurulduktan ve `mqtt_connection` hazır
olduktan sonra:

```python
HOME_ID = "757bfcc9-a80b-4886-a8cd-854392454caf"

def mqtt_publish_helper(topic, payload):
    mqtt_connection.publish(
        topic=topic,
        payload=json.dumps(payload),
        qos=mqtt.QoS.AT_LEAST_ONCE,
    )

servo = ServoDriver()
rfid = RfidDriver(mqtt_publish_helper, HOME_ID, servo)
rfid.start()
```

### 4. `rfid_result` topic'ine subscribe

Mevcut `subscribe(homes/{HOME_ID}/command, ...)` çağrısının yanına ekle:

```python
def on_rfid_result(topic, payload, **kwargs):
    try:
        data = json.loads(payload.decode())
        rfid.handle_result(data)
    except Exception as e:
        print(f"[RFID] result parse error: {e}")

mqtt_connection.subscribe(
    topic=f"homes/{HOME_ID}/rfid_result",
    qos=mqtt.QoS.AT_LEAST_ONCE,
    callback=on_rfid_result,
)
```

### 5. systemd servisini restart et

```bash
sudo systemctl restart akilliev.service
sudo journalctl -u akilliev.service -f
```

Beklenen log satırları (boot'ta):
- `[INFO] subscribed to homes/.../rfid_result`
- `RfidDriver` thread başladı (sessiz)
- `ServoDriver` 0°'ye konumlandı

Kart okutulunca:
- `[RFID] card scanned: AB12CD34`
- `[RFID] verify result for AB12CD34: authorized (Test Card 1)`
- `[RFID] -> opening barrier`
- 5 saniye sonra servo otomatik kapanır

### 6. Test

Maketteki RFID okuyucusuna **`TEST_AUTH_001` UID'li bir kart yaklaştır**:
- DB'de kayıtlı, `authorized` dönmeli, servo 90°'ye kalkıp 5 sn sonra inmeli

Bilinmeyen bir kart yaklaştır:
- `denied` dönmeli, kırmızı LED 2 sn yanmalı, telefona "Yetkisiz Giriş" push gelmeli

> **Önemli**: `TEST_AUTH_001` literal string'i DB'de UID olarak kayıtlı.
> Gerçek kartının UID'i farklı olacak. Kullanıcıya kartını okutması ve
> log'da görünen UID'yi söylemesini iste — sonra bulut tarafında o UID
> ile yeni bir authorized_cards row'u eklenecek.

### 7. UID kayıt akışı (geçici, manuel)

Faz 2'de mobil app'ten kart eklenecek. Şimdilik kullanıcı:
1. Kartını okutur
2. Log'da `[RFID] card scanned: <UID>` görür ve UID'i kopyalar
3. Bana yazar ("UID: XXXX")
4. Ben bulut tarafında o UID'yi DB'ye `authorized_cards` row'u olarak eklerim

---

## Tamamlanınca

Bana **"RFID hazır, kart okutuyor"** diye yaz, beraber:
1. Telefonun kartını okutursun
2. Loglarda UID'yi görürüz
3. Ben o UID'yi DB'ye eklerim (script var)
4. Tekrar okutursun → bariyer açılmalı
5. Random bir kart okutursun → bariyer kapalı kalsın + telefonuna push gelsin

End-to-end test böyle olur.
