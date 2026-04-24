# CopCarPasskey — System Architecture

## Overview

A proximity-based Bluetooth lock system. An Arduino Nano paired with a SparkFun BlueSMiRF v2
wakes on button press, scans for a registered iOS device or Apple Watch, runs a silent
challenge-response authentication, then triggers a relay to open the lock. No user interaction
required on the phone — proximity is sufficient.

## Component Map

```
┌─────────────────────────────────────────────────────────────────┐
│                        HARDWARE                                 │
│                                                                 │
│  [Button] ──► [Arduino Nano] ──► [BlueSMiRF v2]  ←── BLE ───► │ ── iOS App
│                     │                                           │ ── Apple Watch
│                     └──► [Relay Module] ──► [Door/Lock]        │
└─────────────────────────────────────────────────────────────────┘
                              │
                         (optional)
                              ▼
                      ┌──────────────┐
                      │  ASP.NET API │  key mgmt, audit log
                      └──────┬───────┘
                             │
                      ┌──────▼───────┐
                      │  React UI    │  admin portal
                      └──────────────┘
```

## BLE Topology

iOS/Watch act as **BLE peripherals** (advertisers). Arduino acts as **BLE central** (scanner).

This ensures the phone/watch can respond while backgrounded — iOS supports `bluetooth-peripheral`
background mode, keeping service UUIDs in the advertisement even when the app is suspended.

### Service Layout

```
Service UUID: A1B2C3D4-E5F6-7890-ABCD-EF1234567890  (CopCarPasskey Service)
  ├── CHALLENGE  (notify)   — Arduino writes a 32-byte random nonce
  ├── RESPONSE   (write)    — iOS/Watch writes HMAC-SHA256(nonce, secret)
  └── STATUS     (notify)   — Arduino broadcasts relay state (0x00/0x01)
```

## Authentication Protocol

```
Arduino                              iOS / Watch
   │                                    │
   │── connect ─────────────────────────►│
   │── write CHALLENGE (32-byte nonce) ──►│
   │                                    │  HMAC-SHA256(nonce, shared_secret)
   │◄── write RESPONSE (32-byte hmac) ───│
   │                                    │
   │  compare HMAC locally              │
   │  (shared_secret stored in EEPROM)  │
   │                                    │
   │  if valid → relay ON               │
```

No network call in the unlock critical path — works fully offline.

## Arduino State Machine

```
[SLEEP]  ──button──►  [SCANNING]  ──found──►  [CONNECTING]  ──conn──►  [AUTHENTICATING]
   ▲                      │                        │                           │
   │                   timeout                  timeout/fail               invalid
   │                      │                        │                           │
   └──────────────────────┴────────────────────────┴───────────────────────────┘
                                                                               │ valid
                                                                         [UNLOCKED]
                                                                          relay: ON
                                                                               │
                                                                 button / 5min timeout
                                                                               │
                                                                           [SLEEP]
                                                                          relay: OFF
```

## RSSI Proximity Tuning

The Arduino only connects if the scanned device RSSI > threshold (default: -70 dBm ≈ 5m).
For "NFC-style" Watch tap, tighten to -50 dBm (≈ 30cm). Configurable in `Config.h`.

## Key Distribution (Enrollment Flow)

1. Admin logs into web portal → creates a new passkey entry
2. Portal generates a 256-bit shared secret, displays as QR code
3. User opens iOS app → scans QR → secret stored in iOS Keychain
4. iOS app syncs secret to Watch via WatchConnectivity
5. Same secret is flashed to Arduino EEPROM via USB serial at setup time

## Folder Structure

```
CopCarPasskey/
├── app/CopCarPasskey/
│   ├── CopCarPasskey/          iOS target (SwiftUI, CoreBluetooth)
│   ├── CopCarPasskeyWatch/     watchOS target (SwiftUI, CoreBluetooth)
│   └── CopCarPasskeyShared/    Shared models, HMAC, constants
├── system/PasskeyLock/       Arduino firmware
├── web/
│   ├── api/                  ASP.NET Core 8 Web API
│   └── portal/               React + Vite + Tailwind admin UI
└── docs/
```

## Tech Stack

| Layer        | Technology                              |
|--------------|-----------------------------------------|
| iOS App      | Swift 5.9+, SwiftUI, CoreBluetooth, CryptoKit |
| watchOS App  | SwiftUI for watchOS, CoreBluetooth, WatchConnectivity |
| Arduino      | C++/Arduino, HMAC-SHA256 (custom)       |
| Web API      | ASP.NET Core 8, EF Core, SQLite         |
| Web Portal   | React 18, Vite, TailwindCSS             |
