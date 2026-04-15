# Smart Home

A Flutter-based smart home companion app with mood-aware automation, AI assistant, and multi-home support. Devices and sensors are managed through an AWS IoT + Cognito backend, facial emotion detection runs on a local Raspberry Pi, and an on-device Claude agent controls the house through natural language.

---

## Table of Contents

- [Feature Overview](#feature-overview)
- [Architecture](#architecture)
- [Tech Stack](#tech-stack)
- [Repository Layout](#repository-layout)
- [Core Modules](#core-modules)
  - [Authentication (Cognito)](#authentication-cognito)
  - [Dashboard & Home Selection](#dashboard--home-selection)
  - [Devices](#devices)
  - [Automations](#automations)
  - [AI Emotion Hub](#ai-emotion-hub)
  - [AI Chat Agent](#ai-chat-agent)
  - [Spotify Mood Tracks](#spotify-mood-tracks)
  - [Notifications](#notifications)
- [Backend Integration](#backend-integration)
- [Getting Started](#getting-started)
- [Environment Variables](#environment-variables)
- [Running on Device](#running-on-device)
- [Known Limitations](#known-limitations)
- [Contributing](#contributing)

---

## Feature Overview

| Area | What It Does |
| --- | --- |
| **Multi-home auth** | AWS Cognito sign-in/up with email + OTP, reset flow, and QR-based home invite/join |
| **Device control** | Real-time control of lights, outlets, curtains, speakers, stoves with live property updates |
| **Automations** | Trigger devices from sensor readings (temperature, humidity, gas, vibration) or from the user's mood, with a polished list + create UI |
| **Emotion detection** | Face scan → Raspberry Pi `/predict` endpoint returns emotion + confidence + per-class scores, with manual mood picker fallback |
| **AI chat agent** | Claude Haiku agent with tool use for `get_devices`, `control_device`, `get_sensor_data`, `get_automations`, `set_mood` |
| **Spotify integration** | OAuth PKCE flow, personalized mood-based recommendations sourced entirely from the user's own top tracks |
| **Push notifications** | Firebase Cloud Messaging with foreground alert dialog + persistent alert list |
| **Theming** | Light/dark themes with consistent mood-color palette across scan area, cards, and accents |

---

## Architecture

```
┌────────────────────────────────────────────────────────────────────────┐
│                            Flutter App                                 │
│  ┌───────────┐  ┌────────────┐  ┌────────────┐  ┌────────────────┐     │
│  │  Riverpod │  │ Auth / UI  │  │  Services  │  │  Notifications │     │
│  │  state    │  │  screens   │  │  (API, AI) │  │   (FCM)        │     │
│  └─────┬─────┘  └─────┬──────┘  └─────┬──────┘  └────────┬───────┘     │
└────────┼──────────────┼───────────────┼──────────────────┼─────────────┘
         │              │               │                  │
         ▼              ▼               ▼                  ▼
 ┌───────────────┐ ┌─────────────┐ ┌─────────────┐  ┌─────────────────┐
 │ Mood Provider │ │  Cognito    │ │ API Gateway │  │   FCM           │
 │ (local state) │ │  (AWS)      │ │  + Lambdas  │  │   (Google)      │
 └───────────────┘ └─────────────┘ └──────┬──────┘  └─────────────────┘
                                          │
                      ┌───────────────────┼───────────────────┐
                      ▼                   ▼                   ▼
                ┌───────────┐      ┌────────────┐     ┌───────────────┐
                │ DynamoDB  │      │ IoT Core   │     │ Raspberry Pi  │
                │ devices/  │      │ device     │     │ /predict      │
                │ automations│     │ shadows    │     │ emotion model │
                └───────────┘      └────────────┘     └───────────────┘

                 ┌──────────────────┐       ┌──────────────────┐
                 │ Spotify Web API  │◄──────│  Anthropic API   │
                 │ top tracks / OAuth│      │  Claude Haiku    │
                 └──────────────────┘       └──────────────────┘
```

Device control commands flow `Flutter → API Gateway → Lambda → IoT Core`. Sensor data is read from DynamoDB populated by device-side handlers. Emotion detection is local (Pi on the home Wi-Fi) to keep imagery off the cloud. Mood state lives in a Riverpod `NotifierProvider` so both the Emotion Hub and the chatbot can read/write it atomically.

---

## Tech Stack

**Frontend**
- Flutter 3.38.x (Dart 3.10)
- `flutter_riverpod` 3.x for state management
- `amplify_flutter` + `amplify_auth_cognito` for auth
- `http` for REST calls
- `firebase_core` + `firebase_messaging` for push
- `flutter_web_auth_2` for Spotify OAuth
- `image_picker` for camera capture
- `qr_code_scanner` + `qr_flutter` for home invites
- `shared_preferences` for token persistence

**Backend (existing infrastructure)**
- AWS Cognito (auth)
- AWS API Gateway + Lambda (REST endpoints)
- AWS IoT Core (device shadows)
- AWS DynamoDB (devices, sensors, automations)
- Firebase Cloud Messaging (push)
- Raspberry Pi (FastAPI + Keras emotion model, HTTPS)

**External APIs**
- Anthropic Messages API (Claude Haiku 4.5)
- Spotify Web API

---

## Repository Layout

```
lib/
├── main.dart                       # App entry, Firebase + Amplify bootstrap
├── amplifyconfiguration.dart       # Cognito config
├── firebase_options.dart           # FlutterFire config
├── constants/
│   └── app_colors.dart             # Theme-aware color tokens
├── theme/
│   └── app_theme.dart              # Light/dark Material themes
├── models/
│   └── sensor_data.dart            # Sensor reading model
├── providers/
│   ├── auth_provider.dart          # Cognito auth state
│   ├── home_provider.dart          # Selected home state
│   ├── alert_provider.dart         # Notification list
│   ├── theme_provider.dart         # Light/dark toggle
│   ├── mood_provider.dart          # Shared mood state (scan / manual / chatbot)
│   └── spotify_provider.dart       # Spotify auth state helper
├── services/
│   ├── api_service.dart            # AWS API Gateway client + network error suppression
│   ├── ai_agent_service.dart       # Claude agent loop with tool use
│   ├── emotion_api_service.dart    # Raspberry Pi /predict client
│   └── spotify_service.dart        # Spotify OAuth + personalized mood pipeline
└── screens/
    ├── onboarding/
    ├── auth/                       # Login, register, OTP, reset
    ├── dashboard/                  # Dashboard + home selection + QR
    ├── devices/                    # Device control screen
    ├── automations/                # List + create screens
    ├── ai_hub/emotion_hub_screen.dart
    ├── ai_agent/ai_chat_screen.dart
    ├── spotify/spotify_test_screen.dart
    ├── notifications/
    ├── profile/
    └── security/monitoring_screen.dart
```

`camera.py` at the repo root is a standalone Python helper that exercises the Pi `/predict` endpoint from a laptop webcam — useful when debugging the Pi independently of the app.

---

## Core Modules

### Authentication (Cognito)

- `auth_provider.dart` exposes `AuthState` (`initial | loading | authenticated | unauthenticated`)
- `main.dart` routes to `OnboardingScreen` or `HomeSelectionScreen` based on this state
- Full flows: sign in, sign up with email OTP, forgot password → reset confirmation
- Tokens are handled by Amplify; API calls pull the ID token via `Amplify.Auth.fetchAuthSession()`

### Dashboard & Home Selection

- Users can own multiple homes; `selectedHomeProvider` holds the active one
- QR-based invite flow: host generates a join code, guest scans with `qr_code_scanner`
- Dashboard polls `/prod/{homeId}/sensor` every 5 s; stale data triggers one-time network-outage log (no spam)

### Devices

- `device_control_screen.dart` shows live properties (power, brightness, color, volume, playback, position)
- Device-type icons auto-inferred from `device_type` or name keywords (EN + TR) — `door/kapı`, `speaker/hoparlör`, `stove/fırın`, `window/pencere`, `outlet/priz`
- Property writes go through `ApiService.sendCommand` → Lambda → IoT Core

### Automations

- Trigger types: sensor readings (`temperature > 30`, `gas > X`, etc.) or mood (`emotion=happy`)
- Actions: multi-device, multi-property (turn on + set brightness + set volume)
- List UI: custom header, live stats (Total / Active / AI), filter chips (All / Active / AI / Sensor), color-accented cards (AI = orange, sensor = blue)
- Swipe-to-delete with confirmation; pull-to-refresh; empty/error states with CTAs

### AI Emotion Hub

- **Scan** button captures a front-camera photo via `image_picker`
- JPEG bytes POSTed to `EMOTION_API_URL` (default `https://192.168.1.10:8000/predict`), self-signed cert bypass in debug mode
- Pi responds with:
  ```json
  {"status":"success","emotion":"happy","confidence":0.8722,
   "all_scores":{"angry":0.01,"happy":0.87,...}}
  ```
- Mood color + emoji animate the scan ring; `_moodColors`/`_moodEmojis` maps cover all 10 classes
- **Manual mood picker**: bottom sheet with 10 tappable mood pills for when the camera isn't convenient
- **Ambient section** (placeholder for upcoming light/curtain AWS integration) already suggests lighting tone + curtain position per mood

### AI Chat Agent

- `ai_agent_service.dart` runs the Anthropic Messages API loop (`claude-haiku-4-5-20251001`) with these tools:
  - `get_devices`, `get_sensor_data`, `get_automations`, `control_device` — proxy through `ApiService`
  - `set_mood` — invoked via `onSetMood` callback that writes to the shared `moodProvider`, bypassing any API call
- Tool descriptions are strict about calling `get_devices` before `control_device` so the agent uses the canonical `deviceid` rather than a name
- Mood updates: "Ben aslında üzgünüm" or "the scanner was wrong, I'm calm" → agent calls `set_mood(calm, 1.0)` → Emotion Hub updates + Spotify re-fetches automatically via `ref.listen`

### Spotify Mood Tracks

Spotify deprecated `/v1/recommendations`, `/v1/audio-features`, `/v1/audio-analysis`, and `/v1/artists/{id}/top-tracks` for apps created after November 2024. This app routes around that:

1. Pull the user's top tracks (short + medium + long term) via `/v1/me/top/tracks` → ~100-150 songs
2. For the current mood, apply word-boundary regex keyword matching against track name, album, and artist
3. Separate keyword lists for each mood in both English AND Turkish (so `hüzün`, `kırık`, `yalnız` etc. match Turkish sad songs)
4. Score and sort; fill remaining slots from the unmatched personal pool so everything stays 100% personal
5. Tracks labeled `catalog_mood_matched` (score > 0) or `catalog_fill` (personal, non-mood)

Because the pool is only the user's listening history, a Turkish listener never gets random foreign pop-rock recommended.

### Notifications

- Background and foreground FCM handlers in `main.dart`
- Foreground emergency alerts show a red modal dialog AND are appended to `alertListProvider`
- Alert types: `security (gas leak, earthquake)`, `device`, with `critical / warning / info` levels

---

## Backend Integration

**AWS endpoints** (via API Gateway):

| Method | Path | Purpose |
| --- | --- | --- |
| GET | `/prod/{homeId}/sensor` | Current sensor snapshot |
| GET | `/prod/{homeId}/devices` | All devices in home |
| POST | `/prod/{homeId}/command` | Change a device property |
| GET | `/prod/{homeId}/automations` | List automations |
| POST | `/prod/{homeId}/automations` | Create/update automation |
| DELETE | `/prod/{homeId}/automations?rule_id=...` | Delete automation |

**Pi endpoint:**

| Method | Path | Purpose |
| --- | --- | --- |
| POST | `/predict` | Multipart JPEG upload → `{emotion, confidence, all_scores}` |

All AWS calls attach the Cognito ID token as `Authorization: Bearer <token>`. Network failures are suppressed after the first log so intermittent Wi-Fi outages don't flood the console.

---

## Getting Started

### Prerequisites

- Flutter 3.38 or newer
- Android Studio (or Xcode for iOS)
- AWS account with Amplify/Cognito configured (use `amplify pull` if you have the project already)
- Firebase project with Android/iOS apps registered
- Spotify developer app with redirect URI `akilliev://callback`
- Anthropic API key
- Raspberry Pi on the home network running the FastAPI emotion service (see `camera.py` for a reference client)

### Install

```bash
git clone https://github.com/Dutchy-O-o/smart_home.git
cd smart_home
flutter pub get
```

### Configure

1. Copy `.env.example` to `.env` and fill in:

   ```env
   CLAUDE_API_KEY=sk-ant-...
   SPOTIFY_CLIENT_ID=...
   SPOTIFY_CLIENT_SECRET=...
   EMOTION_API_URL=https://192.168.1.10:8000/predict
   ```

2. Drop your Firebase `google-services.json` into `android/app/` and `GoogleService-Info.plist` into `ios/Runner/`.

3. Ensure `lib/amplifyconfiguration.dart` points at your Cognito user pool.

### Run

```bash
flutter run -d <device-id>
```

For Windows developers targeting a real Samsung phone: use a **USB-A to USB-C** cable (Samsung's included USB-C↔USB-C often fails USB role switching), enable USB debugging, and authorize the RSA fingerprint popup.

---

## Environment Variables

| Key | Required | Notes |
| --- | --- | --- |
| `CLAUDE_API_KEY` | Yes | Anthropic API key. AI chat falls back to a "not configured" screen without it. |
| `SPOTIFY_CLIENT_ID` | Yes | Spotify OAuth client id |
| `SPOTIFY_CLIENT_SECRET` | Yes | Spotify OAuth client secret |
| `EMOTION_API_URL` | No | Defaults to `https://192.168.1.10:8000/predict`; override for remote Pi |

---

## Running on Device

- **Emulator face detection will fail** — the simulated camera feed isn't a real face, so the Pi model returns "no face detected". Use the Manual Mood picker, a real device, or `ImageSource.gallery` with a sample face photo for testing.
- **Self-signed Pi cert** is auto-bypassed only in `kDebugMode`. For release builds, install a Let's Encrypt or private-CA cert on the Pi and switch `EmotionApiService._buildClient()` to plain `http.Client()`.
- Both phone and Pi must be on the same LAN for `/predict` to resolve.

---

## Known Limitations

- **Spotify:** The 2024 deprecation removed both `recommendations` and `audio-features`, so mood classification here is best-effort via keyword matching, not true audio analysis. The tradeoff: recommendations are always personal, but mood matching is coarser than with the old audio-feature targets.
- **Artist top-tracks:** `/v1/artists/{id}/top-tracks` also returns 403 for new Spotify apps. The catalog pool is therefore restricted to `/v1/me/top/tracks`.
- **Ambient tiles:** the Emotion Hub's "Ambient" section currently only displays suggested light/curtain states. Wiring them to real IoT commands is the next step.
- **Network:** AWS `execute-api` errors are suppressed after the first log — this keeps the console readable but means silent failures until the network recovers.

---

## Contributing

- Branching: feature work lives on feature branches that merge into `Test-Branch` for integration, then `Test-Branch` merges into `main`.
- Before opening a PR: run `flutter analyze` and make sure UI copy is in English (Turkish keyword lists in `spotify_service.dart` and device-name matching constants in `device_control_screen.dart` stay as-is for matching real data).
- If you touch the Pi `/predict` contract, keep the Flutter side (`emotion_api_service.dart`) and the optional `all_scores` field forward-compatible.
