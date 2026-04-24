#!/usr/bin/env python3
"""
One-time Curve25519 key pair generator for CopCarPasskey BLE encryption.

Generates two key pairs (ESP32 + iOS) and writes them into:
  system/PasskeyLock/SessionKeys.h
  app/CopCarPasskey/CopCarPasskeyShared/SessionKeys.swift

Run from the repo root:
  python tools/generate_session_keys.py

Re-run to rotate keys. After rotating, rebuild and reflash both
the ESP32 firmware and the iOS app simultaneously.
"""

import os
import sys

try:
    from cryptography.hazmat.primitives.asymmetric.x25519 import X25519PrivateKey
except ImportError:
    print("ERROR: cryptography library not found. Run: pip install cryptography")
    sys.exit(1)


def fmt_c_array(name, data: bytes) -> str:
    vals = ", ".join(f"0x{b:02x}" for b in data)
    return f"static const uint8_t {name}[32] = {{ {vals} }};"


def fmt_swift_array(name, data: bytes) -> str:
    vals = ", ".join(f"0x{b:02x}" for b in data)
    return f"    static let {name}: [UInt8] = [ {vals} ]"


esp_priv_key = X25519PrivateKey.generate()
ios_priv_key = X25519PrivateKey.generate()

esp_priv_bytes = esp_priv_key.private_bytes_raw()
esp_pub_bytes  = esp_priv_key.public_key().public_bytes_raw()
ios_priv_bytes = ios_priv_key.private_bytes_raw()
ios_pub_bytes  = ios_priv_key.public_key().public_bytes_raw()

# ── SessionKeys.h (firmware) ──────────────────────────────────────────────────
h_content = f"""\
#pragma once
#include <stdint.h>

// Compile-time Curve25519 key material for BLE session encryption.
// Paired with app/CopCarPasskey/CopCarPasskeyShared/SessionKeys.swift.
// Re-run tools/generate_session_keys.py to rotate; rebuild + reflash both sides.

{fmt_c_array('ESP32_PRIVATE_KEY', esp_priv_bytes)}
{fmt_c_array('IOS_PUBLIC_KEY',    ios_pub_bytes)}
"""

# ── SessionKeys.swift (iOS) ───────────────────────────────────────────────────
swift_content = f"""\
// Compile-time Curve25519 key material for BLE session encryption.
// Paired with system/PasskeyLock/SessionKeys.h.
// Re-run tools/generate_session_keys.py to rotate; rebuild + reflash both sides.

enum SessionKeys {{
{fmt_swift_array('iosPrivateKeyBytes',  ios_priv_bytes)}
{fmt_swift_array('esp32PublicKeyBytes', esp_pub_bytes)}
}}
"""

script_dir = os.path.dirname(os.path.abspath(__file__))
repo_root  = os.path.dirname(script_dir)

h_path     = os.path.join(repo_root, "system", "PasskeyLock", "SessionKeys.h")
swift_path = os.path.join(repo_root, "app", "CopCarPasskey",
                          "CopCarPasskeyShared", "SessionKeys.swift")

with open(h_path, "w") as f:
    f.write(h_content)

with open(swift_path, "w") as f:
    f.write(swift_content)

print(f"Written: {h_path}")
print(f"Written: {swift_path}")
print("Done. Rebuild firmware and iOS app; flash both simultaneously.")
