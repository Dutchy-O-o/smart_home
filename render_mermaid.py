"""
Render Mermaid sources to PNG via the public mermaid.ink service.
Falls back to mermaid.ink/svg if PNG fails. Saves under images/.
"""

import base64
import os
import sys
import urllib.parse
import urllib.request


FIG_5_10 = """
flowchart TB
    Start([App Launch])
    Init[Bootstrap<br/>dotenv · Firebase · Amplify]
    Auth{authState}

    Onb[OnboardingScreen]
    Reg[RegisterScreen]
    OTP[OtpVerificationScreen]
    Login[LoginScreen]
    Forgot[ForgotPasswordScreen]
    Reset[ResetConfirmationScreen]

    Home[HomeSelectionScreen]
    Shell[MainShell · persistent bottom nav]

    Dash[Dashboard]
    Dev[Devices]
    Auto[Automations]
    AIHub[AI Hub]
    Prof[Profile]

    QR[QR Invite / Scan]
    Notif[NotificationScreen]
    Mon[MonitoringScreen]
    Chat[AiChatScreen]
    Spotify[SpotifyTestScreen]

    %% Boot column
    Start --> Init --> Auth

    %% Auth tree (symmetric: register branch left, login branch right)
    Auth -- unauthenticated --> Onb
    Onb  --> Reg
    Onb  --> Login
    Reg  --> OTP
    Login --> Forgot
    Forgot --> Reset
    Reset -. retry .-> Login

    %% Convergence into Home
    OTP   --> Home
    Login --> Home
    Auth  -- authenticated --> Home

    %% Main shell
    Home --> Shell
    Shell --> Dash
    Shell --> Dev
    Shell --> Auto
    Shell --> AIHub
    Shell --> Prof

    %% Modals
    Home  -. modal .-> QR
    Dash  -. modal .-> Notif
    Dev   -. modal .-> Mon
    AIHub -. modal .-> Chat
    AIHub -. modal .-> Spotify

    classDef boot  fill:#FEF3C7,stroke:#B45309,color:#1F2937,stroke-width:1.5px
    classDef auth  fill:#FEE2E2,stroke:#B91C1C,color:#1F2937,stroke-width:1.5px
    classDef main  fill:#DBEAFE,stroke:#1E40AF,color:#1F2937,stroke-width:1.5px
    classDef modal fill:#EDE9FE,stroke:#6D28D9,color:#1F2937,stroke-width:1.5px

    class Start,Init,Auth boot
    class Onb,Login,Reg,OTP,Forgot,Reset auth
    class Home,Shell,Dash,Dev,Auto,AIHub,Prof main
    class Notif,Chat,Spotify,Mon,QR modal
""".strip()


FIG_5_16 = """
flowchart LR
    subgraph Sensors["▎Input Sensors"]
        direction TB
        DHT["DHT11<br/>Temp + Humidity"]
        MQ["MQ-3 / MQ-4<br/>Gas"]
        MPU["MPU6050<br/>Vibration"]
        LDR["LDR<br/>Photoresistor"]
        RFID["RC522<br/>RFID Reader"]
        CAM["USB Micro<br/>Camera"]
    end

    Pi["<b>Raspberry Pi 5</b><br/><br/>paho-mqtt client<br/>FastAPI /predict<br/>sensor daemon<br/>hardware drivers"]

    subgraph Actuators["▎Output Actuators"]
        direction TB
        LED["RGB LED Strip<br/>PWM × 3"]
        Motor["Curtain Motor<br/>Stepper"]
        AC["AC / Stove<br/>Relay"]
        Speaker["Speaker<br/>PWM Volume"]
        Siren["Safety Siren<br/>autonomous"]
    end

    Cloud[("AWS IoT Core")]

    DHT  -- "GPIO 4"  --> Pi
    MQ   -- "GPIO 17" --> Pi
    MPU  -- "I²C"     --> Pi
    LDR  -- "GPIO 15" --> Pi
    RFID -- "SPI"     --> Pi
    CAM  -- "USB"     --> Pi

    Pi -- "PWM 18/13/19"   --> LED
    Pi -- "GPIO 5/6/12/16" --> Motor
    Pi -- "GPIO 22/23"     --> AC
    Pi -- "GPIO 26"        --> Speaker
    Pi -- "GPIO 24"        --> Siren

    Pi <-. "TLS 1.2 / MQTT" .-> Cloud

    classDef sensor fill:#DCFCE7,stroke:#15803D,color:#1F2937,stroke-width:1.5px
    classDef pi     fill:#FEF3C7,stroke:#B45309,color:#1F2937,stroke-width:2px
    classDef act    fill:#DBEAFE,stroke:#1E40AF,color:#1F2937,stroke-width:1.5px
    classDef cloud  fill:#FEE2E2,stroke:#B91C1C,color:#1F2937,stroke-width:1.5px

    class DHT,MQ,MPU,LDR,RFID,CAM sensor
    class Pi pi
    class LED,Motor,AC,Speaker,Siren act
    class Cloud cloud
""".strip()


def render_via_mermaid_ink(source: str, out_path: str, fmt: str = "png"):
    """Use the public mermaid.ink renderer."""
    encoded = base64.urlsafe_b64encode(source.encode("utf-8")).decode("ascii")
    if fmt == "png":
        url = f"https://mermaid.ink/img/{encoded}?type=png&bgColor=FFFFFF&width=1600"
    else:
        url = f"https://mermaid.ink/svg/{encoded}"
    print(f"  Fetching: {url[:80]}…")
    req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
    with urllib.request.urlopen(req, timeout=30) as r:
        data = r.read()
    with open(out_path, "wb") as f:
        f.write(data)
    print(f"  Wrote {out_path} ({len(data)} bytes)")
    return out_path


def main():
    os.makedirs("images", exist_ok=True)
    targets = [
        ("fig_5_10_app_screen_flow.png", FIG_5_10),
        ("fig_5_16_pi_wiring.png", FIG_5_16),
    ]
    for name, source in targets:
        out = os.path.join("images", name)
        try:
            render_via_mermaid_ink(source, out, fmt="png")
        except Exception as e:
            print(f"  PNG render failed: {e}; trying SVG…")
            svg_out = out.replace(".png", ".svg")
            render_via_mermaid_ink(source, svg_out, fmt="svg")


if __name__ == "__main__":
    main()
