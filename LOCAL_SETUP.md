# Connect your room directly

SmartLight 2 talks to lights from the phone or computer running the app. Home Assistant, Docker, a VM, a hub and a background server are not required. Closing the app stops its connections; lights keep their last settings. App scenes run only when you tap them. The original vendor apps still handle initial Wi-Fi pairing, account ownership and firmware.

## Start with the Tapo strip

1. Keep the strip powered and join the same home Wi-Fi on your phone/Mac/Windows PC. Avoid a guest network with client isolation.
2. In Tapo, open the strip's settings and find its IP address under Device Info. Reserve this address in your router if possible.
3. Enable **Third-Party Compatibility** in Tapo if your app/firmware offers it (the location varies by app version; look in Tapo Lab or third-party services).
4. In SmartLight, choose **Add your lights → Tapo Strip**. Enter the IP, your Tapo account email (preserve capitalization) and password. Enter credentials only in the app, not in chat or source files.
5. Choose **Test connection**, then **Connect & save**. This checks the light without changing its power or color. You can use just this strip while the battens remain unconfigured.
6. Return to My Room. Try power, brightness and color. The app reads device state after each command and every five seconds in the foreground.

SmartLight tries KLAP v1/v2 first, then legacy RSA/AES passthrough (login v1) when the KLAP endpoint rejects the handshake, including an empty HTTP 400 response. It never falls back after a valid KLAP challenge fails password verification. TPAP-only firmware and AES login v2 are not implemented. A rejected handshake does not prove that Third-Party Compatibility is disabled: errors include the connection stage, HTTP status and any numeric device error code. Account login failures have a one-minute cooldown per connection. No credentials are sent to a SmartLight server.

Capabilities come from the device response. Some L920 firmware reports a fixed white range (for example 9000–9000 K); SmartLight hides the temperature slider in that case. RGB white is available in color presets. Unsupported scene parameters are skipped. Addressable effects/music are not exposed; manual changes disable the strip's active lighting effect.

## Wipro Next Smart Home battens

**The exact SB22240 model has not been verified with this implementation.** A Wipro Next login is not sufficient for Tuya LAN control. Each compatible batten needs its local IPv4 address, device ID, a 16-byte local key, protocol version and light profile.

An existing Tuya/TinyTuya key export can provide these values. Otherwise the commonly documented one-time route is:

1. Confirm that your exact light can be linked to a **Smart Life or Tuya Smart** account. Wipro Next account linking is not guaranteed. Do not reset all your lights to investigate this; retain the working Wipro setup until compatibility is established.
2. For a light already linked to one of those compatible apps, create a Tuya developer cloud project in the account's matching data center, authorize the required device APIs, and link the app account using the project's QR flow. API access availability and trial/subscription requirements may vary.
3. On a computer, run the [TinyTuya setup wizard](https://github.com/jasonacox/tinytuya#setup-wizard---getting-local-keys). Its current instructions explain account linking and key retrieval. This is a one-time provisioning tool, not a server needed during daily use. Example in an isolated Python environment:

   ```sh
   python3 -m venv ~/smartlight-key-setup
   ~/smartlight-key-setup/bin/pip install tinytuya
   ~/smartlight-key-setup/bin/python -m tinytuya wizard
   ```

4. Keep `devices.json`, `tinytuya.json` and any key exports private. They contain credentials. Enter the appropriate device ID and key in SmartLight; do not commit or share the files.
5. Select the actual local protocol (3.3, 3.4 or 3.5). Start with the profile matching the device's reported lighting datapoints: modern uses 20–24; legacy uses 1–5. The connection test refuses a profile when its power datapoint is absent. Optional color/temperature controls appear only when the corresponding values are reported.
6. Set the batten's actual warm/cool range if different from 2700–6500 K. Connect and save each batten individually.

If SB22240 cannot be linked/exported through a supported account, or exposes different datapoints, Wipro control remains blocked until its provisioning/profile is established. SmartLight cannot invent or discover a secret local key from an IP address. A factory reset or re-pair can change an existing key. Tuya 3.1/3.2 and arbitrary/custom datapoint mappings are outside this version.

## Android's narrow HTTP exception

Tapo uses encrypted KLAP or legacy AES messages over HTTP on port 80. Android release builds default to denying HTTP. Build with `SMARTLIGHT_TAPO_IP` to allow **only your strip's private IPv4 address**. The generated exception stays in ignored build output; your address is not committed. Runtime destinations are also restricted to literal private/link-local IPv4 addresses and redirects are refused.

```sh
# Replace this example with your strip's address.
SMARTLIGHT_TAPO_IP=192.168.1.50 flutter build apk --release \
  --target-platform android-arm64 --dart-define=SMARTLIGHT_TAPO_IP=192.168.1.50
```

The optional Dart define prefills the address in setup. If the strip changes address, reserve the old address in your router or rebuild with the new address. Debug APKs retain the development-only HTTP policy. Release APKs without the environment variable do not permit Tapo HTTP connections. Tuya uses its own encrypted TCP connection on port 6668.

## Troubleshooting

- **Cannot reach device:** same LAN, correct reserved IP, power on, local-network permission granted, no client isolation/VPN route interference. A device being visible in its cloud app does not prove that the LAN connection is reachable.
- **Tapo handshake rejected with compatibility already enabled:** verify the IP under Tapo → Device Info and note the firmware version. Use SmartLight 2.0.2 or later: 2.0.1 accidentally stopped at HTTP 400 without trying AES. Version 2.0.2 also sends canonical HTTP header names, explicit body lengths and requests for uncompressed responses. Separate KLAP/AES statuses identify where connection setup stopped; they do not prove that the setting is disabled.
- **Tapo account login rejected:** check account owner and capitalization. Do not keep guessing credentials; wait for the cooldown.
- **Wipro decode/authentication failure:** check the exact local key and protocol version. A Wipro password is not a local key.
- **Wrong Wipro profile:** choose the profile whose datapoints match the device. A successful connection still needs the physical checks in REAL_DEVICE_TESTING.md.
- **One light offline:** other connected lights remain usable; room actions report failures by light.
- **App reopened:** foreground connections are recreated and refreshed. There is no always-on process.
- **Several controllers:** some Tuya firmware permits one local connection. Close other local controllers; SmartLight closes each Tuya connection after its operation.
