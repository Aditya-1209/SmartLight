# SmartLight

A Flutter app for controlling one room directly over Wi-Fi from **Android, macOS and Windows**. Open the app when you are in the room; no Home Assistant, Docker, virtual machine or always-on computer is required.

The intended room contains two Wipro SB22240 RGB/CCT battens and a Tapo L920 strip. The user has confirmed Tapo control and Wipro control on Android after in-app pairing and automatic protocol detection. This is verification of the user's setup, not a guarantee for every firmware version. See [LOCAL_SETUP.md](LOCAL_SETUP.md) before resetting or moving any lights.

## How it works

```text
SmartLight on phone / Mac / Windows
  ├─ Tapo: local HTTP with KLAP or legacy AES encryption
  ├─ Wipro/Tuya batten 1: encrypted local TCP
  └─ Wipro/Tuya batten 2: encrypted local TCP
```

The device running SmartLight is the controller. Connections and five-second polling stop in the background and resume when reopened. Everyday light controls run locally. Timers are stored on compatible lights and continue with SmartLight closed. Mac includes a setup-only Tuya Cloud/EZ pairing flow, and an optional personal Android build includes Tuya’s mobile SDK; this setup flow needs internet and closes its SDK connection when you leave it. No always-on server is required.

- Responsive Material 3 dashboard, dark/light/system themes and per-light controls.
- Room power, brightness, RGB presets/custom colors and Study/Movie/Chill/Sleep scenes.
- Figma-based adaptive room overview, live light-card dimmers, scene previews and a three-tab interface for Android, Mac and Windows. Diagnostics are available in Settings.
- Custom scenes with names, icons, per-light power/brightness/white/color, current-state capture, editing, duplication and undoable deletion. Saving does not send light commands.
- Built-in light timers: turn on/off after a delay or once at a chosen local clock time within the next 24 hours. Select one or more lights, confirm by reading back from each light, and view/cancel timers from another connected SmartLight device. No server, paid service or background app is used.
- Add lights one at a time; incomplete rooms remain usable.
- Detect the Tuya LAN protocol during setup using read-only checks for 3.3, 3.4 and 3.5.
- Pair once, then transfer saved connections between Mac, Android and Windows using a password-protected setup code. Import lets you review the lights and keeps other saved connections.
- Mac in-app fast-blinking (EZ) pairing using your own linked Central Europe Tuya project.
- Optional Android in-app Wi-Fi pairing for compatible Wipro/Tuya lights (personal SDK build).
- Capabilities derived from device state; unsupported controls are hidden.
- Separate failures for each light, foreground polling, manual refresh and diagnostics.
- Demo mode with three simulated lights and outage controls; saved credentials remain separate.

## Direct protocol support

| Device family | Implemented | Setup required |
|---|---|---|
| Tapo | KLAP v1/v2 or legacy AES (login v1), power, brightness, HSV/RGB, adjustable CCT where reported | Light IP + owning Tapo account email/password; Third-Party Compatibility where offered |
| Compatible Wipro/Tuya Wi-Fi lights | LAN 3.3/3.4/3.5; modern DP20–24 and legacy DP1–5 profiles | IP + device ID + local key + actual protocol/profile |

Tapo TPAP-only firmware, AES login v2, Tuya 3.1/3.2, vendor effects, music synchronization and arbitrary datapoint profiles are not supported. A Wipro Next password alone will not connect a batten.

### Timers

Open **My room → Timers & schedules**, or the same button on a light’s page. Choose **Turn off** or **Turn on**, then a delay (1–1,440 minutes) or a clock time. Clock times run once, not daily. Timers are read from the lights when this page opens, every 30 seconds while visible, and after a change. Each light supports one active timer; cancel it before creating another. Failed reads are shown as unknown, not as “no timer.”

Tapo uses its local countdown-rule API. Wipro/Tuya requires a modern lighting profile and a valid reported DP26 countdown; unsupported firmware is rejected without guessing a datapoint or falling back to an app timer. Wipro countdowns reverse the current power state: turn the tube on before scheduling off, or off before scheduling on. A subsequent power change cancels the Wipro countdown. Keep wall power supplied; timers may be lost if a light loses power. Other vendor schedules can still affect a light. Device read-back confirms the timer is armed, not that a future physical action has already occurred.

Demo timers are simulated only while the demo is open. Real timers do not change the credentials or scenes stored on Mac, Android or Windows.

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

## Install on Windows

1. Sign in to GitHub and download [SmartLight-Windows 2.6.0](https://github.com/Aditya-1209/SmartLight/actions/runs/36981421137/artifacts/11215687025) from the successful [2.6.0 build](https://github.com/Aditya-1209/SmartLight/actions/runs/36981421137). You can also find **SmartLight-Windows** under that run’s **Artifacts**. See [GitHub’s download instructions](https://docs.github.com/en/actions/how-tos/manage-workflow-runs/download-workflow-artifacts).
2. Right-click the downloaded ZIP, choose **Extract All**, and keep the complete extracted folder together. Launch **smart_light.exe** from that folder; the adjacent DLLs and `data` folder are required. An APK is for Android and cannot be used as the Windows app.
3. Connect the Windows laptop to the same home Wi-Fi as the lights.
4. On your working phone or Mac, open **Settings → Use lights on another device → Send setup**. Choose a transfer password of at least 12 characters and select **Create encrypted code**, then **Copy encrypted code**.
5. On Windows, open **Settings → Use lights on another device → Receive setup**. Enter the code and the same transfer password, select **Unlock and review**, then **Save selected lights**. This imports light connections without pairing the lights again; it does not transfer custom scenes.

For the new interface, automatic Tapo address recovery and built-in timers, choose a completed **2.6.0 / build 12** run. The older 2.4.0 download does not include these features. Windows packages contain the entire app folder, not just the executable.

## Build and test

```sh
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test --coverage
flutter test integration_test/demo_flow_test.dart -d macos
tool/build_macos.sh
flutter build windows  # Windows host only
flutter build apk --debug
# Android release supports changing local Tapo addresses.
flutter build apk --release --target-platform android-arm64
```

Tapo connections on Android use a bounded private-IPv4 transport, so changing addresses do not require a rebuild. General release HTTP stays denied. Debug APKs use the existing development-only local HTTP policy. Builds currently use debug signing for personal testing, not store distribution. Install the ARM64 APK on Pixel 8; macOS builds run on Apple Silicon; Windows artifacts include the whole executable directory.

For a personal Mac release, `tool/build_macos.sh` also verifies the final bundle signature and reseals an ad-hoc build if Flutter changed its nested framework during an incremental build. It does not replace a developer signing identity. Set `SMARTLIGHT_FLUTTER_BIN` if Flutter is not on PATH.

For in-app Android pairing, see the [personal SDK build instructions](LOCAL_SETUP.md#build-the-optional-sdk-apk). SDK credentials/security files and the resulting personal APK must stay private; public CI builds exclude the SDK.

GitHub Actions runs analysis/tests and builds Android debug, macOS release and Windows release on their respective hosts. Download artifacts from [Actions](https://github.com/Aditya-1209/SmartLight/actions). A green build does not establish device compatibility. See [VALIDATION.md](VALIDATION.md) and the [physical test checklist](REAL_DEVICE_TESTING.md).

## Code structure and security

`lib/services/local/` owns encryption, framing, device transports and capability mapping. `LocalLightsRepository` combines independent connections; Riverpod manages room state and actions. Device operations are serialized to prevent polling/command races. Packet parsing bounds input sizes and verifies CRC/HMAC/GCM or KLAP signatures. Legacy Tapo AES and Tuya 3.3 have weaker security than KLAP and modern Tuya protocols; use a trusted home LAN.

Credentials and local connection details are stored in platform secure storage. Only appearance/demo preferences and legacy non-sensitive slot data use preferences. Passwords/keys are masked and omitted from diagnostics/errors. The LAN control transports accept private/link-local IPv4 literals only, with no arbitrary URLs or HTTP redirects. The Mac cloud setup client and optional Android pairing SDK contact Tuya only through their setup flows. Mac setup credentials are entered at runtime and saved in Keychain; they are never embedded in builds. Never commit device exports, passwords or local keys. See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) for protocol references and licenses.

## Screenshots

Screenshot placeholders: room dashboard, direct setup and per-device controls. The live app and demo mode show the current UI.
