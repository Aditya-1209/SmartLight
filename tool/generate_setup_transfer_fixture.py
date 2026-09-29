"""Independent PBKDF2-HMAC-SHA256 / AES-256-GCM interoperability fixture.

Only synthetic credentials. Requires PyCryptodome; not used by the app.
"""
import base64
import hashlib
import json
from pathlib import Path

from Crypto.Cipher import AES

password = "synthetic fixture password"
salt = bytes(range(16))
nonce = bytes(range(12))
key = hashlib.pbkdf2_hmac("sha256", password.encode(), salt, 600_000, dklen=32)
device = dict(slotId="tube1", name="Fixture tube", brand="tuya",
              host="192.168.1.25", deviceId="synthetic-fixture-device",
              localKey="0123456789abcdef", version="v35", profile="modern")


def seal(data):
    cipher = AES.new(key, AES.MODE_GCM, nonce=nonce)
    cipher.update(b"SmartLight setup transfer v1")
    ciphertext, tag = cipher.encrypt_and_digest(json.dumps(data, separators=(",", ":")).encode())
    return "SMARTLIGHT1." + base64.urlsafe_b64encode(salt + nonce + ciphertext + tag).decode()


fixture = dict(password=password, code=seal(dict(version=2, devices=[device])),
               invalidCodes=[seal(dict(version=99, devices=[device])),
                             seal(dict(version=2, devices=[dict(device, host="8.8.8.8")]))])
Path("test/fixtures/setup_transfer.json").write_text(json.dumps(fixture, indent=2) + "\n")
