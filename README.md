# SmartLight

A Flutter app for controlling one room directly over Wi-Fi from **Android, macOS and Windows**. Open the app when you are in the room; no Home Assistant, Docker, virtual machine or always-on computer is required.

The intended room contains two Wipro SB22240 RGB/CCT battens and a Tapo L920 strip. The user has confirmed the Tapo strip works. Wipro local control is implemented and tested against protocol fixtures and simulated devices; **physical SB22240 compatibility and key provisioning remain unverified**. See [LOCAL_SETUP.md](LOCAL_SETUP.md) before resetting or moving any lights.

## How it works

```text
SmartLight on phone / Mac / Windows
  ├─ Tapo: local HTTP with KLAP or legacy AES encryption
  ├─ Wipro/Tuya batten 1: encrypted local TCP
  └─ Wipro/Tuya batten 2: encrypted local TCP
```

The device running SmartLight is the controller. Connections and five-second polling stop in the background and resume when reopened. Everyday light controls run locally. An optional personal Android build includes Tuya’s SDK for pairing and retrieving device keys; this setup flow needs internet and closes its SDK connection when you leave it. No always-on server is required.

- Responsive Material 3 dashboard, dark/light/system themes and per-light controls.
- Room power, brightness, RGB presets/custom colors and Study/Movie/Chill/Sleep scenes.
- Add lights one at a time; incomplete rooms remain usable.
- Optional Android in-app Wi-Fi pairing for compatible Wipro/Tuya lights (personal SDK build; hardware compatibility still needs testing).
- Capabilities derived from device state; unsupported controls are hidden.
- Separate failures for each light, foreground polling, manual refresh and diagnostics.
- Demo mode with three simulated lights and outage controls; saved credentials remain separate.

## Direct protocol support

| Device family | Implemented | Setup required |
|---|---|---|
| Tapo | KLAP v1/v2 or legacy AES (login v1), power, brightness, HSV/RGB, adjustable CCT where reported | Light IP + owning Tapo account email/password; Third-Party Compatibility where offered |
| Compatible Wipro/Tuya Wi-Fi lights | LAN 3.3/3.4/3.5; modern DP20–24 and legacy DP1–5 profiles | IP + device ID + local key + actual protocol/profile |

Tapo TPAP-only firmware, AES login v2, Tuya 3.1/3.2, vendor effects, music synchronization and arbitrary datapoint profiles are not supported. The SB22240 profile and key-export path must be verified on the real hardware. A Wipro Next password alone will not connect a batten.

## Run

Use Flutter **3.47.5 / Dart 3.13.4**, Xcode for macOS, Android SDK/JDK 17 for Android, or Visual Studio's C++ desktop workload for Windows.

```sh
git clone https://github.com/Aditya-1209/SmartLight.git
cd SmartLight
flutter pub get
flutter run -d macos
# Or: flutter run -d windows / flutter run -d <android-device-id>
```

Open **Add your lights**. The [setup guide](LOCAL_SETUP.md) covers Tapo credentials, Wipro/Tuya keys, IP reservations and limitations. Old Home Assistant settings are not used or migrated into direct device credentials; the previous implementation remains in Git history.

## Build and test

```sh
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test --coverage
flutter test integration_test/demo_flow_test.dart -d macos
flutter build macos
flutter build windows  # Windows host only
flutter build apk --debug
# Android release: use your own strip IP; example address below is a placeholder.
SMARTLIGHT_TAPO_IP=192.168.1.50 flutter build apk --release \
  --target-platform android-arm64 --dart-define=SMARTLIGHT_TAPO_IP=192.168.1.50
```

Android release HTTP is restricted to the build-time strip IP. An omitted IP leaves HTTP denied. Debug APKs use the existing development-only local HTTP policy. Builds currently use debug signing for personal testing, not store distribution. Install the ARM64 APK on Pixel 8; macOS builds run on Apple Silicon; Windows artifacts include the whole executable directory.

For in-app Android pairing, see the [personal SDK build instructions](LOCAL_SETUP.md#build-the-optional-sdk-apk). SDK credentials/security files and the resulting personal APK must stay private; public CI builds exclude the SDK.

GitHub Actions runs analysis/tests and builds Android debug, macOS release and Windows release on their respective hosts. Download artifacts from [Actions](https://github.com/Aditya-1209/SmartLight/actions). A green build does not establish device compatibility. See [VALIDATION.md](VALIDATION.md) and the [physical test checklist](REAL_DEVICE_TESTING.md).

## Code structure and security

`lib/services/local/` owns encryption, framing, device transports and capability mapping. `LocalLightsRepository` combines independent connections; Riverpod manages room state and actions. Device operations are serialized to prevent polling/command races. Packet parsing bounds input sizes and verifies CRC/HMAC/GCM or KLAP signatures. Legacy Tapo AES and Tuya 3.3 have weaker security than KLAP and modern Tuya protocols; use a trusted home LAN.

Credentials and local connection details are stored in platform secure storage. Only appearance/demo preferences and legacy non-sensitive slot data use preferences. Passwords/keys are masked and omitted from diagnostics/errors. The LAN control transports accept private/link-local IPv4 literals only, with no arbitrary URLs or HTTP redirects. The optional Android pairing SDK contacts Tuya services during setup. Never commit device exports, passwords or local keys. See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) for protocol references and licenses.

## Screenshots

Screenshot placeholders: room dashboard, direct setup and per-device controls. The live app and demo mode show the current UI.
