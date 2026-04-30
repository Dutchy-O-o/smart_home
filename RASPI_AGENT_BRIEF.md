# Raspberry Pi — AWS IoT MQTT Controller (3 cihaz)

> Bu brief, Raspberry Pi üzerinde çalışan Claude Code'a verilecek. Mevcut
> AWS IoT setup'ı keşfedildi, schema'lar netleştirildi, sertifikalar zaten
> Raspi'de hazır kabul ediliyor.

---

## Görev özeti (BU dosyayı Raspi'deki Claude Code'a olduğu gibi yapıştır)

Raspberry Pi'da AWS IoT Core'a MQTT üzerinden bağlanan, ev sahibinin
mobil uygulamasından gelen komutları **TV / Air Conditioner / Oven**
cihazlarına ileten bir Python servisi yazman gerek. Servis aynı zamanda
cihaz state'lerini AWS'ye geri yayınlayacak ki mobil app'teki kart
durumları tutarlı kalsın.

### Bağlantı bilgileri (sabit)

| Parametre | Değer |
|---|---|
| AWS IoT Endpoint | `a1cxjn3ytw2lp0-ats.iot.us-east-1.amazonaws.com` |
| Region | `us-east-1` |
| MQTT Port | `8883` (TLS) |
| Client ID | `757bfcc9-a80b-4886-a8cd-854392454caf` (= homeID, **PiPolicy** bunu zorunlu kılıyor) |
| HOME_ID | `757bfcc9-a80b-4886-a8cd-854392454caf` |

### Sertifikalar (Raspi'de bulunmalı)

Cert ARN: `arn:aws:iot:us-east-1:162803876446:cert/f302e41b5c83be562d7cfdf6fb265f6adb55d090508555eb70e34b2eb09eef50`

Raspi'de muhtemelen şu dosyalar zaten var:
- `*-certificate.pem.crt` (cihaz sertifikası)
- `*-private.pem.key` (özel anahtar)
- `AmazonRootCA1.pem` (Amazon root CA)

`/home/pi/certs/` veya benzeri bir klasörde olduklarını varsay; yoksa
mevcut MQTT bağlantı yapan eski script'lerden konumlarını çıkar (örn.
mevcut sensör publisher kodu varsa). **Yeni cert oluşturma — mevcudu
kullan.**

### Topic schema (PiPolicy yetkisiyle)

PiPolicy şu topic prefix'ine pub/sub yetkisi verir:
`homes/757bfcc9-a80b-4886-a8cd-854392454caf/*`

| Yön | Topic | Anlamı |
|---|---|---|
| **Subscribe** | `homes/{HOME_ID}/command` | Mobil uygulamadan gelen komutlar |
| **Publish** | `homes/{HOME_ID}/state` | Komut başarıyla uygulanınca yeni state'i geri yayınla (DB güncellenir) |

QoS 1 kullan (en az bir kez teslim).

### Komut payload formatı (subscribe — sen alıyorsun)

```json
{
  "deviceID": "16cb9159-69d5-408c-80a3-9a7ca388db47",
  "executionID": "b3c1f4a2-...",
  "commands": [
    { "property_name": "power", "value": "on" }
  ]
}
```

`commands` array'i tek veya çoklu olabilir; hepsini sırayla uygula.

`executionID` **opsiyonel**:
- Otomasyon (emotion/sensor kuralı) tetiklediyse UUID gelir.
- Manuel kullanıcı komutuysa hiç gelmez (veya `null` olur).

Bu ID'yi sakla — state mesajını yayınlarken **birebir geri yansıtacaksın
(echo)**. Backend bu yankıyla `automation_executions` kaydını
`Pending` → `Success`'e çeviriyor.

### State payload formatı (publish — sen yayınlıyorsun)

Komut başarıyla uygulandıktan sonra `homes/{HOME_ID}/state` topic'ine bu
payload'u yayınla:

```json
{
  "deviceID": "16cb9159-69d5-408c-80a3-9a7ca388db47",
  "executionID": "b3c1f4a2-...",
  "states": [
    { "property_name": "power", "current_value": "on" }
  ]
}
```

**`executionID` echo kuralı:**
- Komut payload'unda `executionID` geldiyse → state payload'una **aynı
  ID'yi** koy.
- Komut payload'unda yoksa (manuel komut) → state payload'unda da
  `executionID` alanını **hiç koyma** (veya `null` koy).

Bu payload AWS'deki `saveDeviceState` IoT Rule'una düşer ve
`UpdateActuatorState` Lambda'sı tarafından PostgreSQL'deki
`actuator_current_states` tablosuna yazılır. Mobil app polling ile
buradan okuyor. `executionID` doluysa ayrıca `automation_executions`
tablosundaki ilgili satır `Pending` → `Success`'e geçer.

### Yöneteceğin 3 cihaz

| deviceID | İsim | Tip | Geçerli `property_name`'ler | Geçerli value'lar |
|---|---|---|---|---|
| `16cb9159-69d5-408c-80a3-9a7ca388db47` | Air Conditioner | ac | `power` | `"on"` / `"off"` |
| `238a35b9-f593-4c30-89a2-f43d0141a4f9` | Oven | stove | `power` | `"on"` / `"off"` |
| `5d1fd81d-6eb6-4a94-a152-f3acf0fb466c` | Living Room TV | tv | `power`, `volume`, `channel` | power: `"on"/"off"`, volume: 0-100 (string olarak gelebilir, int'e dönüştür), channel: int |

> Diğer deviceID'ler (Speaker, LED Strip, RFID, sensörler) BU ajanın görevi
> DEĞİL. Tanınmayan deviceID gelirse log'a yaz ve atla — hata atma, çünkü
> kardeş servis(ler) onları yönetiyor olabilir.

### Donanım soyutlaması (önemli karar noktası)

Henüz fiziksel sürücü kodu yazma. Önce `device_drivers.py` adında
**stub'lar (mock'lar)** içeren bir modül oluştur:

```python
class AcDriver:
    def set_power(self, on: bool): ...   # IR LED veya akıllı klima HTTP API'si
class OvenDriver:
    def set_power(self, on: bool): ...   # Röle modülü (GPIO)
class TvDriver:
    def set_power(self, on: bool): ...
    def set_volume(self, level: int): ...
    def channel_up(self): ...
    def channel_down(self): ...
```

Stub'lar şimdilik sadece state'i bellekte tutsun ve `print` ile log atsın.
Gerçek donanım (IR transmit / GPIO röle) **sonra** eklenecek; o kısım
Raspi'nin fiziksel kurulumuna bağlı, ben (bulut tarafındaki ajan) bunu
göremiyorum.

Ama şimdiden düşün:
- **AC ve TV** — büyük ihtimalle IR LED ile (`lirc` veya `pigpio` kullan).
  Her komut için kayıtlı IR signal'i fırlat.
- **Oven (Ocak)** — büyük ihtimalle bir röle modülü (GPIO yüksek/alçak).
  `RPi.GPIO` veya `gpiozero` kullan. **Güvenlik kritik**: gerçek bir ocak
  yerine bir LED veya röle bağla; gerçek mains voltajını sürmek için ek
  donanım gerekir, bu kapsamın dışında.

Channel için TV'de iki seçenek var:
- App `channel: 5` gönderirse: önceki kanaldan farkı al, fark kadar
  CHANNEL_UP / CHANNEL_DOWN butonu fırlat. (Tipik IR pattern.)
- VEYA HDMI-CEC kullanılıyorsa direct channel set.

Volume için: hedef level - mevcut level farkı kadar VOLUME_UP /
VOLUME_DOWN tetikle, veya HDMI-CEC. Stub'da sadece state'i kaydet.

### State persistence (boot sonrası)

Cihaz state'i (volume, channel, power) Raspi yeniden başladığında
kaybolmasın diye **tek bir JSON dosyasına** yaz (`/var/lib/smart-home/state.json` veya `~/.smart-home/state.json`). Boot'ta oku, ilk
komuttan önce DB'ye initial state publish et — böylece `actuator_current_states`
tablosu Raspi'nin gerçek görüşüne hizalanır.

### Resilience gereksinimleri

- **Auto-reconnect**: MQTT bağlantısı koparsa exponential backoff ile
  yeniden bağlan (örn. 1s, 2s, 4s, max 60s).
- **systemd unit dosyası**: `smart-home-controller.service` adında, boot'ta
  başlasın, çökünce restart edilsin. Brief'in altındaki kütüphane seçimini
  takip et.
- **Logging**: `journalctl` ile okunabilir olmalı (`logging` modülü stdout
  veya `SysLogHandler`).
- **Idempotency**: Aynı komut iki kez gelirse aynı state'i iki kez
  uygulamak güvenli olsun (özellikle power için).

### Kütüphane önerisi

`paho-mqtt` ile manual TLS yapılandırma yerine **`AWSIoTPythonSDK`** veya
yeni `awsiotsdk` kullan — AWS IoT için hazır wrapper, sertifika yolları
parametreleri direkt alıyor:

```bash
pip install AWSIoTPythonSDK
# veya yeni nesil:
pip install awsiotsdk
```

Tercihen **paho-mqtt + ssl** ile elle yapma — fazla boilerplate,
backoff/heartbeat ayarlarını sen yöneteceksin.

### Klasör yapısı (öneri)

```
~/smart-home-controller/
├── main.py                    # MQTT bağlantı + dispatcher
├── device_drivers.py          # AC/Oven/TV stub'ları (sonra IR/GPIO ile dolacak)
├── state_store.py             # JSON-backed local state
├── config.py                  # HOME_ID, endpoint, cert paths, deviceID mapping
├── requirements.txt
└── smart-home-controller.service   # systemd unit
```

### Yapma listesi (Raspi'deki Claude Code için)

1. Yukarıdaki klasör yapısını oluştur.
2. `config.py` — HOME_ID, endpoint ve 3 deviceID → driver eşlemesi.
3. `device_drivers.py` — stub'lar (sadece print + state).
4. `state_store.py` — JSON load/save.
5. `main.py` — MQTT subscribe + dispatch + state publish + reconnect.
6. `requirements.txt` ve `smart-home-controller.service`.
7. **Smoke test**: Brief'in en altındaki AWS-side test komutlarını
   kullanıcıya ver, "kullanıcı bunları PC'sinden çalıştıracak; senin
   görevin Raspi'de loglarda komutu gördüğünü ve state geri yayınlandığını
   doğrulamak" notuyla.
8. systemd ile servisi enable et.

### Kritik don't'lar

- **Yeni AWS sertifikası oluşturma** — mevcut PiPolicy'ye attach edilmiş
  cert var, onu kullan. Yeni cert için bulut tarafına ek iş gerekir.
- **Topic prefix değiştirme** — PiPolicy `homes/{HOME_ID}/*` dışında
  yetkilendirmiyor.
- **Client ID değiştirme** — `iot:Connection.Thing.ThingName` = HOME_ID
  şartı policy'de var; başka client ID ile bağlanma reddedilir.
- **Tanınmayan deviceID gelirse exception fırlatma** — başka servisler
  aynı topic'e bakıyor olabilir; sadece logla ve atla.
- **Power komutunda value tipi** — JSON'da string `"on"`/`"off"` gelir,
  `True`/`False` değil; karşılaştırırken dikkat et.

---

## AWS-side smoke test komutları (kullanıcı PC'sinden çalıştırır)

Raspi'de servis aktif olduktan sonra **bu makineden (Windows/git-bash)**
şu komutları çalıştırarak test edeceğiz. Raspi loglarında her birini
görmen ve state'in geri yayınlandığını teyit etmen gerek.

### Test 1 — AC power on

```bash
aws iot-data publish \
  --region us-east-1 \
  --topic 'homes/757bfcc9-a80b-4886-a8cd-854392454caf/command' \
  --qos 1 \
  --cli-binary-format raw-in-base64-out \
  --payload '{"deviceID":"16cb9159-69d5-408c-80a3-9a7ca388db47","commands":[{"property_name":"power","value":"on"}]}'
```

### Test 2 — TV volume = 50

```bash
aws iot-data publish \
  --region us-east-1 \
  --topic 'homes/757bfcc9-a80b-4886-a8cd-854392454caf/command' \
  --qos 1 \
  --cli-binary-format raw-in-base64-out \
  --payload '{"deviceID":"5d1fd81d-6eb6-4a94-a152-f3acf0fb466c","commands":[{"property_name":"volume","value":50}]}'
```

### Test 3 — Oven power off

```bash
aws iot-data publish \
  --region us-east-1 \
  --topic 'homes/757bfcc9-a80b-4886-a8cd-854392454caf/command' \
  --qos 1 \
  --cli-binary-format raw-in-base64-out \
  --payload '{"deviceID":"238a35b9-f593-4c30-89a2-f43d0141a4f9","commands":[{"property_name":"power","value":"off"}]}'
```

### Test 4 — DB'de state yansıdı mı?

Test 1-3'ten sonra mobil uygulamayı aç (`flutter run`). Cihaz kartlarının
durumu test ettiğin değerlerle eşleşmeli (5 saniyelik polling sonrası).

### Test 5 — Çoklu komut tek payload'da

```bash
aws iot-data publish \
  --region us-east-1 \
  --topic 'homes/757bfcc9-a80b-4886-a8cd-854392454caf/command' \
  --qos 1 \
  --cli-binary-format raw-in-base64-out \
  --payload '{"deviceID":"5d1fd81d-6eb6-4a94-a152-f3acf0fb466c","commands":[{"property_name":"power","value":"on"},{"property_name":"channel","value":7},{"property_name":"volume","value":30}]}'
```

### Test 6 — Bilinmeyen deviceID (ignored olmalı, exception YOK)

```bash
aws iot-data publish \
  --region us-east-1 \
  --topic 'homes/757bfcc9-a80b-4886-a8cd-854392454caf/command' \
  --qos 1 \
  --cli-binary-format raw-in-base64-out \
  --payload '{"deviceID":"00000000-0000-0000-0000-000000000000","commands":[{"property_name":"power","value":"on"}]}'
```

Raspi log'unda "unknown device, skipping" gibi bir mesaj görmeli, servis
çökmemeli, sonraki komutlar çalışmaya devam etmeli.

### Live log izleme (kullanıcı tarafında, gerçek mobil komutları görmek için)

Mobil app butonlarına basıldığında topic'e ne düştüğünü görmek için:

```bash
aws logs tail /aws/lambda/PublishCommandToPi --since 5m --region us-east-1 --follow
```

Veya state akışını izlemek için:

```bash
aws logs tail /aws/lambda/UpdateActuatorState --since 5m --region us-east-1 --follow
```
