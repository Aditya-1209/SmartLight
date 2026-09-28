# Direct-control validation record

Date: 2026-09-28. SmartLight 2.0 replaces the Home Assistant backend with in-app Tapo/Tuya LAN clients.

## Automated checks

- Flutter 3.47.5 / Dart 3.13.4 on macOS 27, Apple Silicon, Xcode 27.
- `flutter analyze`: no issues.
- `flutter test --coverage`: **44 tests passed**, **1,642 / 1,840 executable lines (89.2%)**.
- Tests cover independent KLAP and Tuya packet vectors, KLAP v1/v2 logins, authentication cooldown, timeouts and redaction; Tuya 3.3/3.4/3.5 TCP negotiation/read/command round trips against simulated lights; integrity failures, bounded fragmented frame parsing, modern/legacy light mapping and RGB-mode brightness; partial room failures, foreground lifecycle, credential persistence, concurrent setup saves, demo controls, scenes, and responsive widgets.
- Protocol golden bytes were generated outside Dart with TinyTuya 1.20.0 and PyCryptodome. `tool/generate_protocol_vectors.py` reproduces them. The app has no Python runtime dependency.
- UI tests use 412×915, 1280×720 and 1920×1080 viewports. A setup queue initialization problem found by widget tests was corrected.
- `git diff --check`: pass. Credential-pattern scan found no access tokens or private keys in changed code/docs. Fixtures use explicit fake credentials.

## Platform builds

| Check | Result |
| --- | --- |
| macOS release build | Passed (45.4 MB); app rebuilt after final code changes |
| Native macOS integration tests | 2 passed: isolated Keychain/preferences probe and demo setup → power → brightness → RGB → Movie |
| Android ARM64 release for Pixel 8 | Passed (19.3 MB), version 2.0.0 / build 2 |
| APK network security resource inspection | Confirmed: base HTTP denied; exactly one private strip IP exception, no subdomains |
| Windows release | Built by GitHub Actions; see the Actions run for this commit |

Android's generated resource uses the current Gradle variant API; the initial obsolete SourceSet API attempt was corrected. The packaged APK (including the manifest's resource reference) was inspected with aapt2, not just the generated XML. Native integration used fake lights and removed its isolated storage probe. The runner emitted a foreground warning but both native tests completed successfully.

Source implementation: `3cd5a04`. GitHub Actions validates the final documentation commit with all three platform builds; consult the [Actions page](https://github.com/Aditya-1209/SmartLight/actions) for the exact run and artifacts.

## Physical verification and limitations

**No successful physical light connection or command has been verified.** A read-only handshake to the user-provided Tapo IP could not be reached from this Mac. No real Tapo password or Wipro local key was available or requested in chat.

Wipro SB22240 compatibility, the Wipro Next-to-Tuya key provisioning route, exact datapoints and white range remain unverified. Tapo legacy AES/TPAP-only firmware and Tuya 3.1/3.2/custom datapoints are not implemented. Automated protocol compatibility does not establish firmware compatibility.

The app needs the lights' LAN addresses and credentials, but no Home Assistant, Docker, hub or server. Connections stop in the background. Vendor apps still handle initial pairing and firmware; the lack of a SmartLight cloud dependency does not guarantee every vendor device's firmware works indefinitely without internet.

Android release builds permit HTTP only to the private Tapo IP supplied through `SMARTLIGHT_TAPO_IP` at build time. With no value, HTTP stays denied. The local address is confined to generated build resources and optional build defines, not committed. A broader HTTP exception was rejected by automatic review and replaced with this scoped approach. Debug builds retain the prior development-only HTTP policy. Android release uses debug signing for personal testing; macOS is not notarized.

See [LOCAL_SETUP.md](LOCAL_SETUP.md) and [REAL_DEVICE_TESTING.md](REAL_DEVICE_TESTING.md) before claiming hardware support.
