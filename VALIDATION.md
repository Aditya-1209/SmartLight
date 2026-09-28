# Direct-control validation record

Date: 2026-09-28. SmartLight 2.0.2 fixes AES fallback after an empty KLAP HTTP 400 response and adds explicit HTTP wire framing. Version 2.0.1 added legacy Tapo AES (login v1) and replaced the misleading compatibility-setting error. The 2.0 release replaced Home Assistant with in-app Tapo/Tuya LAN clients.

## Automated checks

- Flutter 3.47.5 / Dart 3.13.4 on macOS 27, Apple Silicon, Xcode 27.
- `flutter analyze`: no issues.
- `flutter test --coverage`: **62 tests passed**, **1,803 / 2,000 executable lines (90.1%)**.
- Tests cover independent KLAP and Tuya packet vectors, KLAP v1/v2 logins, AES RSA exchange/login/read/command/session reuse, independent Python AES login bytes, protocol selection after rejected KLAP endpoints, safe HTTP/device-code diagnostics, no fallback on a failed KLAP proof, no command replay, authentication cooldown, timeouts and redaction; Tuya 3.3/3.4/3.5 TCP negotiation/read/command round trips against simulated lights; integrity failures, bounded fragmented frame parsing, modern/legacy light mapping and RGB-mode brightness; partial room failures, foreground lifecycle, credential persistence, concurrent setup saves, demo controls, scenes, and responsive widgets.
- Real-socket tests inspect canonical headers, exact Content-Length framing, binary handshakes, cookie propagation, a persistent KLAP session, read/command responses, redirect refusal and destination restrictions. The HTTP 400 regression uses an empty response body matching the reported error. Header formatting is a compatibility improvement; it is not a confirmed cause of the physical strip’s failure.
- Protocol golden bytes were generated outside Dart with TinyTuya 1.20.0 and PyCryptodome. `tool/generate_protocol_vectors.py` reproduces them. The app has no Python runtime dependency.
- UI tests use 412×915, 1280×720 and 1920×1080 viewports. A setup queue initialization problem found by widget tests was corrected.
- `git diff --check`: pass. Credential-pattern scan found no access tokens or private keys in changed code/docs. Fixtures use explicit fake credentials.

## Platform builds

| Check | Result |
| --- | --- |
| macOS release build | 2.0.2 passed (46.5 MB), bundle version 4 |
| Native macOS integration tests | 2.0 baseline: 2 passed: isolated Keychain/preferences probe and demo setup → power → brightness → RGB → Movie |
| Android ARM64 release for Pixel 8 | 2.0.2 passed (19.5 MB), version 2.0.2 / build 4 |
| APK network security resource inspection | Confirmed: base HTTP denied; exactly one private strip IP exception, no subdomains |
| Windows release | Built by GitHub Actions; see the Actions run for this commit |

Android's generated resource uses the current Gradle variant API; the initial obsolete SourceSet API attempt was corrected. The packaged APK (including the manifest's resource reference) was inspected with aapt2, not just the generated XML. Native integration used fake lights and removed its isolated storage probe. The runner emitted a foreground warning but both native tests completed successfully.

Baseline implementation: `3cd5a04`. Every push runs analysis, tests and all three platform builds; consult the [Actions page](https://github.com/Aditya-1209/SmartLight/actions) for the run and artifacts matching the latest commit.

## Physical verification and limitations

**No successful physical light connection or command has been verified.** A read-only handshake to the user-provided Tapo IP could not be reached from this Mac. The user reports enabling Third-Party Compatibility and an empty HTTP 400 response at the initial KLAP handshake. Version 2.0.1 incorrectly stopped at that status before trying AES; 2.0.2 includes it in protocol selection. Read-only probes from the terminal still could not connect to port 80, so the strip’s actual protocol remains unconfirmed. No real Tapo password or Wipro local key was read or requested in chat.

Wipro SB22240 compatibility, the Wipro Next-to-Tuya key provisioning route, exact datapoints and white range remain unverified. Tapo TPAP-only firmware, AES login v2 and Tuya 3.1/3.2/custom datapoints are not implemented. Automated protocol compatibility does not establish firmware compatibility.

The app needs the lights' LAN addresses and credentials, but no Home Assistant, Docker, hub or server. Connections stop in the background. Vendor apps still handle initial pairing and firmware; the lack of a SmartLight cloud dependency does not guarantee every vendor device's firmware works indefinitely without internet.

Android release builds permit HTTP only to the private Tapo IP supplied through `SMARTLIGHT_TAPO_IP` at build time. With no value, HTTP stays denied. The local address is confined to generated build resources and optional build defines, not committed. A broader HTTP exception was rejected by automatic review and replaced with this scoped approach. Debug builds retain the prior development-only HTTP policy. Android release uses debug signing for personal testing; macOS is not notarized.

See [LOCAL_SETUP.md](LOCAL_SETUP.md) and [REAL_DEVICE_TESTING.md](REAL_DEVICE_TESTING.md) before claiming hardware support.
