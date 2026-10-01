# Connect your room directly

SmartLight 2 talks to lights from the phone or computer running the app. Home Assistant, Docker, a VM, a hub and a background server are not required. Closing the app stops its connections; lights keep their last settings. App scenes run only when you tap them. The original vendor apps can handle initial Wi-Fi pairing and firmware. Mac builds and the optional Android pairing build can pair compatible Wipro/Tuya lights inside SmartLight; hardware compatibility must still be tested.

## Start with the Tapo strip

1. Keep the strip powered and join the same home Wi-Fi on your phone/Mac/Windows PC. Avoid a guest network with client isolation.
2. In Tapo, open the strip's settings and find its IP address under Device Info. Reserve this address in your router if possible.
3. Enable **Third-Party Compatibility** in Tapo if your app/firmware offers it (the location varies by app version; look in Tapo Lab or third-party services).
4. In SmartLight, choose **Add your lights → Tapo Strip**. Enter the IP, your Tapo account email (preserve capitalization) and password. Enter credentials only in the app, not in chat or source files.
5. Choose **Test connection**, then **Connect & save**. This checks the light without changing its power or color. You can use just this strip while the battens remain unconfigured.
6. Return to My Room. Try power, brightness and color. The app reads device state after each command and every five seconds in the foreground.

SmartLight tries KLAP v1/v2 first, then legacy RSA/AES passthrough (login v1) when the KLAP endpoint rejects the handshake, including an empty HTTP 400 response. It never falls back after a valid KLAP challenge fails password verification. TPAP-only firmware and AES login v2 are not implemented. A rejected handshake does not prove that Third-Party Compatibility is disabled: errors include the connection stage, HTTP status and any numeric device error code. Account login failures have a one-minute cooldown per connection. No credentials are sent to a SmartLight server.

Capabilities come from the device response. Some L920 firmware reports a fixed white range (for example 9000–9000 K); SmartLight hides the temperature slider in that case. RGB white is available in color presets. Unsupported scene parameters are skipped. Addressable effects/music are not exposed; manual changes disable the strip's active lighting effect.

## Use the same lights on Mac, Android and Windows

Pair each light only once. On the device where it works, choose **Connect & save**, then **Settings → Use lights on another device → Send setup**. Choose a new transfer password (at least 12 characters), create an encrypted code and copy it to your other device. Share the transfer password separately.

On each receiving device, open **Settings → Use lights on another device → Receive setup**. Paste the code, enter the transfer password, choose **Unlock and review**, select the lights, then **Save selected lights**. Selected slots replace their old connection; other lights are preserved. Import stores the connection securely and tries to reconnect. It does not establish hardware compatibility or guarantee that an offline light is reachable.

Codes contain saved device IDs, local keys, LAN addresses, protocol/profile settings and any configured Tapo login credentials. They exclude Wi-Fi passwords and Tuya cloud/SDK pairing profiles. AES-256-GCM authenticates the contents; a fresh salt/nonce and PBKDF2-HMAC-SHA256 (600,000 iterations) protect each export. They are portable backups, not expiring or one-use tokens. Keep the code and password private. No upload, account sync or always-on computer is involved. Re-export if a light is reset/re-paired or its connection details change.

All controllers must be on the same LAN as the lights (2.4/5 GHz can coexist after provisioning). Android release builds still only permit Tapo HTTP at the IP configured when building; importing another address does not widen that policy. Keep the strip at its configured/reserved address.

## Wipro Next Smart Home battens

The user confirmed Wipro control on Android after SDK pairing and automatic protocol detection. Other firmware versions still need testing. A Wipro Next login is not sufficient for Tuya LAN control. Each compatible batten needs its local IPv4 address, device ID, a 16-byte local key, protocol version and light profile.

New Wipro connections use **Auto — test 3.3, 3.4 and 3.5** for the local protocol. With an IP and paired credentials entered, **Test connection** sends only status queries, closes each attempt, and selects the first version that returns a verified, usable light state. **Connect & save** verifies and stores the selected version. Existing saved connections keep their version; Auto remains available in the dropdown. This checks protocols at the entered address, not the whole network, and cannot compensate for a mismatched IP/key. Timeout messages distinguish opening TCP from the session handshake or status request. Pairing can return a cloud/public IP or no IP; only a private LAN address is accepted.

### Pair inside SmartLight on Mac

Mac setup uses Tuya Cloud OpenAPI plus an in-process Dart implementation of Tuya EZ (fast-blinking) provisioning. It does not require a phone, Docker, Home Assistant, Node, Python or a background helper. It currently targets a **Central Europe** Smart Home project and an India (`91`) pseudonymous user profile.

1. In Tuya, create your own Smart Life SDK registration and link it to your existing Smart Home cloud project through **Devices → Link My App**. The project needs the applicable IoT Core, Authorization and Smart Home APIs. This is different from scanning a Wipro account QR code.
2. In the Mac app, open **Settings → Wipro Tube → Pair inside SmartLight**. Enter the **cloud project's** Access ID/Secret and the SDK app's **schema**. These are not the Android SDK AppKey/AppSecret. **Check setup** verifies project access, creates/reuses a private profile, requests a test pairing token and retrieves existing devices before showing reset instructions. Credentials/profile stay in macOS Keychain, never in the compiled app, source or diagnostics.
3. Only after the check succeeds, keep the Mac connected over Wi-Fi, enter your 2.4 GHz network name/password and select the Mac Wi-Fi interface. Put **one** tube into fast-blinking mode using its supplied instructions. Re-pairing may remove it from Wipro Next and changes its local key. Other lights should stay as they are.
4. Confirm that only this tube is blinking and choose **Pair this tube**. Keep the app open for up to two minutes. The Wi-Fi password is used in memory for local setup and is not persisted. AP/slow-blinking mode is not implemented on Mac.
5. The app retrieves the local key, listens for the light's LAN address/protocol, then returns to device settings. If discovery is unavailable, enter the local IP/protocol manually. Check the modern/legacy profile and choose **Connect & save**; the LAN connection must work before the light is stored.
6. If pairing finishes after a timeout or the LAN connection fails, choose **Check setup** again and select the existing light. Do not reset repeatedly before checking for a completed pairing. Cancelling/closing the screen stops the setup HTTP and UDP sockets.

Everyday commands use only the LAN transports. A Tuya developer trial expiring can prevent future pairing/retrieval, but the app does not call that API for lights whose working local credentials are already saved. No paid plan is automatically purchased. Keep the saved pairing profile. Use the encrypted setup transfer above to copy working connections to Android or Windows without resetting the light again.

The Mac release enables the sandbox's incoming-network entitlement for the short-lived UDP discovery listeners on ports 6666/6667/7000. No HTTP listener or persistent service is created. UDP discovery data is untrusted until the existing authenticated TCP connection test succeeds.

References: [Tuya cloud signing](https://developer.tuya.com/en/docs/iot/new-singnature?id=Kbw0q34cs2e5g), [user registration](https://developer.tuya.com/en/docs/legacy-reference-of-cloud-service-apis/21707ff1ba?id=Kcojoa8xvg843), [TuyaAPI desktop provisioning reference](https://github.com/TuyaAPI/link).

### Pair inside SmartLight on Android (personal development build)

This optional flow uses the official Tuya Smart Life SDK 7.8.0 during setup. It creates a pseudonymous pairing profile for this installation, stored with Flutter Secure Storage, and a home without geographical coordinates. It sends setup/device information to Tuya and supplies the home Wi-Fi credentials to the light. SmartLight does not retain the Wi-Fi password. India (`91`) is currently the profile country for this personal build. Existing Wipro accounts are not imported.

1. Install the **personal pairing APK** over the existing Android app. Keep its app data. Public CI APKs do not include this private SDK registration.
2. Open Settings, expand one Wipro tube, and select **Pair inside SmartLight**. Continue with Tuya setup while connected to the internet. Android may request location access for Wi-Fi pairing, and Tuya's development edition may show a testing notice.
3. Enter the 2.4 GHz Wi-Fi name and password. Put only that tube into the appropriate pairing mode using its supplied instructions. Re-pairing may remove it from Wipro Next and changes its local key. Do not reset both tubes as a test.
4. Select fast blinking (EZ) or slow blinking (AP), confirm the tube is blinking, then **Prepare pairing**. For AP, get the token while still on home Wi-Fi, use **Open Wi-Fi settings** to join the tube's hotspot, and return before **Start pairing**. If a token expires, rejoin home Wi-Fi and prepare again.
5. Pairing returns the device ID/key and, when available, a private IPv4 address, supported protocol version and light profile. If the SDK has no private IP or a recognized protocol, supply/check those fields yourself. Choose **Connect & save** to verify LAN access before the connection is stored.
6. If pairing succeeded but the LAN test failed, reopen pairing and select the light under **Already paired here** to retrieve its details again. This does not reset the light. The SDK connection is closed when the pairing screen closes.

The local controller used by normal lighting commands has not changed. Once valid connection details are stored, those commands do not use the SDK or Tuya developer cloud API. The SDK requires internet during pairing/refresh. SDK compatibility and real offline control on SB22240 remain unverified until a physical test succeeds. Keep the app's data: clearing it or uninstalling loses the installation's pairing profile. Updates using the same application ID and signing certificate preserve it. Use the encrypted setup transfer above to copy working connections to Mac and Windows.

The [Tuya SDK development edition](https://developer.tuya.com/en/docs/app-development/app-sdk-price?id=Kbu0tcr2cbx3o) is intended for noncommercial development/personal use with limits. Do not publish this private SDK APK on an app store or upload it as a public GitHub artifact. No paid subscription is needed to build this edition; terms/availability can change.

#### Build the optional SDK APK

1. Register a Smart Life SDK app on Tuya with Android package `com.aditya.smartlight.smart_light`, obtain its Android AppKey/AppSecret, and register the SHA-256 of the signing certificate used by the build. This project currently uses the local Android debug certificate for personal release builds.
2. Download the app-specific development SDK. Place its `security-algorithm-1.0.0-beta.aar` in `android/app/libs/`. This binary is ignored by Git.
3. Copy `android/tuya.properties.example` to `android/tuya.properties` and enter the Android SDK keys. Keep this file private (mode 600). SDK credentials are embedded in the personal APK, as required by the vendor; they are not server secrets and the APK must stay private.
4. Run:

   ```sh
   SMARTLIGHT_TAPO_IP=192.168.1.50 tool/build_pairing_android.sh
   ```

   Set `SMARTLIGHT_FLUTTER_BIN` if Flutter is not on PATH. Output: `build/distributions/SmartLight-Android-pairing.apk`. The script enables `smartlightTuya=true` and scopes AGP's shared-namespace compatibility setting to this SDK build. Ordinary Android/CI builds use a stub and require neither SDK secrets nor its proprietary security component.

Reference: [Tuya Android integration](https://developer.tuya.com/en/docs/app-development/integrated?id=Ka69nt96cw0uj), [UID login](https://developer.tuya.com/en/docs/app-development/useruid?id=Ka6a99lybyr0k), [device information/localKey](https://developer.tuya.com/en/docs/app-development/devicemanage?id=Ka6ki8r2rfiuu).

### Existing keys / developer QR alternative

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

## Custom scenes and updates (2.4.0)

Open **Scenes → New scene**. Enter a name, choose an icon, and select the lights to include. For each included light, choose on/off, brightness (or leave it unchanged), and white/color settings. **Use current light settings** captures only lights currently available; offline lights are left unchecked. Saving a scene does not change the lights. Activate it from Scenes or the four quick-access scene cards on My Room.

Use a scene's **⋮** menu to edit, duplicate, or delete it. Deletion offers **Undo**. Built-in presets remain available and can be duplicated. Up to 60 custom scenes are stored on each device. Scenes are local preferences, not automatically synchronized; the existing encrypted setup transfer carries light connections only.

Update the existing app in place. Bundle/package IDs, secure-storage keys, pairing profiles, light settings and transfer format are unchanged. The preferences format adds optional custom scenes and reads older settings without a reset. On Android, install an update signed with the same certificate; do not uninstall or clear app data. macOS may ask for login-Keychain access after an app rebuild; grant it in the system dialog and use Retry if needed. Scene, theme and connection-setting writes are serialized to preserve simultaneous changes.
