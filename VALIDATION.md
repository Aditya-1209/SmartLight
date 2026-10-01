# Direct-control validation record

## 2026-10-01 — SmartLight 2.5.0 Figma interface

- Implemented the shared Android, macOS and Windows interface from the SmartLight Figma construction records and reviewed screens. The Figma connector remained rate-limited on Starter; no upgrade was selected.
- Added the original room/icon SVG assets and locally bundled Inter fonts; updated the theme, compact light cards with live brightness sliders, room overview, scene filters/gallery/summary, adaptive scene editor, saved confirmation, light controls and Settings navigation.
- Kept all app identifiers, secure-storage keys, preference formats, protocol/pairing code and connection transfer unchanged. Existing custom scenes, device mappings and credentials remain compatible. Saving a scene does not apply it. Saved confirmation provides a separate Apply action.
- Static analysis passed. All **103 tests passed**, including setup, encrypted transfers, persistence/credential-write guards, scene workflows and mobile/desktop UI checks.
- Rendered and reviewed the actual Flutter UI at 360 × 800, 412 × 915 and 1440 × 1000, using simulated lights only. Preview captures are in the ignored build/ui-review directory.
- Platform packaging results are recorded below once complete. Android installation remains deferred; the personal pairing APK stays local.

## 2026-10-01 — SmartLight 2.4.0 custom scenes and interface update

- Added custom scene creation, current-state capture, per-slot inclusion/on/off/brightness/white/RGB, optional unchanged brightness/color, names and icons. Scenes can be edited, duplicated and deleted with Undo. Built-in scenes can be duplicated. Saving only updates preferences; lighting commands run only on activation.
- Added a custom-scene gallery and home-screen quick access. Updated light/dark colors, card spacing, status styling, room controls, color labels and mobile header sizing across the shared Mac/Android/Windows UI.
- Existing package/bundle identifiers, secure-storage keys, connection schema, pairing profiles and setup-transfer format are unchanged. Preferences gain an optional customScenes field. Scene/theme/device saves share a queue; failed or blocked scene saves do not overwrite previously loaded state. Scene creation/edit/delete never writes credentials. Scenes are saved per device and are not included in connection-only setup codes.
- Analyzer and formatting checks passed. All **99 tests passed**, including old-preference migration, restart persistence, concurrent saves, failed/locked-storage preservation, selected-light-only activation, active-color capture, corrupt scene validation and create → capture → activate → edit → duplicate → delete → undo at 390×844, 1280×800 and 1920×1080. Physical light commands were not sent for UI testing.
- Before the Mac update, its existing dashboard showed saved cards for both Wipro tubes and the Tapo strip. The user previously confirmed Wipro control on Android; no additional physical firmware-wide compatibility claim is made.
- macOS release **2.4.0 / build 9** built successfully (47.3 MB) and passed deep/strict signature verification. The previous local app bundle was retained before replacement. Android installation is deferred at the user's request; Windows/Android/macOS CI results are attached to the commit's Actions run.
- The updated Mac app loaded all three saved connections: both Wipro entries retained protocol 3.5 and the Tapo entry retained its automatic protocol. Existing dark appearance also loaded. Gallery/editor visuals were inspected natively without activating a scene or changing real lights. The lights were unreachable during this check; stored setup and current reachability are separate observations.
- Native inspection identified offline placeholders without capability data; the editor now retains brightness/color options in that case. The final change passed analysis and all **10 custom-scene tests**, including a new offline-editing regression. The initial personal Android 2.4.0 build also succeeded (44.5 MB); the final packages are rebuilt after this correction.
- Final code commit `551ebc0`: [Actions run 36825266488](https://github.com/Aditya-1209/SmartLight/actions/runs/36825266488) completed successfully for **checks, Windows, Android and macOS**. CI confirmed **100 tests passed**. The final local Mac and personal Android builds also succeeded; Mac signing and Android version 2.4.0 / build 9 with the existing certificate were verified. Android was not installed or otherwise changed on the phone.
- Downloaded the matching Windows artifact and verified its x64 executable, embedded 2.4.0 version and required runtime/data files. Versioned Mac/Windows ZIP archives passed integrity checks. Packages are retained in the ignored local `build/distributions` directory; the personal Android APK was not published. The final Mac scene editor was inspected with offline brightness/white/color controls available, then returned to the gallery without saving a test scene.

## 2026-09-30 — SmartLight 2.3.1 Tuya protocol detection

- The personal 2.3.0 APK was installed on the Pixel 8. The user subsequently reported both battens paired, and the SDK screen listed two existing devices, but returned no usable LAN address. Two candidate addresses accepted TCP connections on port 6668 from the Pixel; discovery did not confirm their device-ID mapping. The user reported both candidates timing out with protocol 3.3. This establishes neither a wrong key nor a working local-control connection.
- Added setup-only **Auto** protocol selection: try the preferred version and the remaining supported 3.3/3.4/3.5 versions, stop on a verified usable status, and close each attempt. Tests do not send lighting commands or save unverified candidates. The successful version is selected in the form and verified again before saving. Existing saved connections keep their version.
- Tuya timeouts now identify TCP connection, session handshake, status request or control request. A connection reset after TCP opens is distinguished from an unreachable host so protocol detection can continue. Combined detection failures expose fixed error categories, not credentials or arbitrary error details. Detection stops on network unreachability or when setup is abandoned.
- Analyzer and formatting checks passed; all **90 tests passed**. The final connection-reset classification also passed the **22 affected protocol/detection tests**. New coverage includes fallback/early success, attempt disposal, no writes/control commands during detection, error redaction, cancellation, real-socket timeout stages and a phone-sized Auto → test → save flow.
- Personal Android ARM64 pairing release **2.3.1 / build 8** built successfully (44.4 MB). APK package/version and the existing signing certificate were verified. An in-place update completed successfully on the authorized Pixel 8; the package manager confirmed version 2.3.1 / build 8. App data was not cleared. The personal APK remains local.
- Wipro local control still requires a successful physical connection test. No additional reset, cloud account, paid service or always-on process is required by this change.

## 2026-09-29 — SmartLight 2.3.0 setup transfer

- Added password-protected setup codes shared by Android, macOS and Windows. Only saved light connections are exported; Wi-Fi passwords and developer/SDK pairing profiles are excluded. AES-256-GCM uses a fresh salt/nonce, PBKDF2-HMAC-SHA256 with 600,000 iterations, authenticated version context and bounded input. Key derivation runs in a background isolate. Clipboard writes require the user's Copy action.
- Import previews selectable lights before saving, merges selected room slots, preserves other connections, rejects conflicting IPs and respects the existing secure-storage read guard. Settings refresh imported fields while preserving normal Connect & save feedback. Fixed the light-type dropdown's overflow at phone width.
- All **85 tests passed**. Encryption checks include an independent Python fixture, credential round trips, fresh randomness, wrong passwords, tampered ciphertext, size/schema limits and invalid private-address data. A phone-sized widget test covers Settings → receive → review → save → refreshed settings; controller checks cover merge conflicts and storage failures. Analyzer and formatting checks passed. A final null-guard adjustment also passed the four affected screen tests.
- macOS release **2.3.0 / build 7** built (47.1 MB), passed deep/strict signature verification, and opened successfully. Xcode emitted warnings about previously removed precompiled-module paths, but completed the build. Both transfer forms were inspected in the native app. After the user approved the updated app's login-Keychain access, Retry restored the existing Tapo connection; My Room showed **Online, On, 74%**.
- Personal Android ARM64 pairing release **2.3.0 / build 7** built (44.4 MB) using the existing private SDK registration. Package/version and the existing signing certificate were verified, and the packaged network policy retains only the configured Tapo IP exception. The APK remains local and is not a public CI artifact. The matching Windows release is produced by the GitHub Actions run for this commit; consult that run for its actual result.
- The user's desktop EZ attempt did not register the Wipro tube, including an attempt while the Mac was confirmed on 2.4 GHz; the tube kept blinking quickly. Android SDK AP/slow-blinking pairing is the next physical test. No Wipro local key has been obtained, and no real three-platform Wipro control or setup-code transfer has been claimed. No Home Assistant, always-on computer or new paid service was introduced.

## 2026-09-29 — SmartLight 2.2.0 Mac pairing

- Linked the existing SmartLight SDK app to the existing Central Europe cloud project after explicit user approval. No new paid plan or add-on was selected. The Wipro QR account link remains unused.
- Added a Mac-only setup screen backed by Tuya Cloud OpenAPI and native Dart EZ Wi-Fi provisioning. The live release app successfully authenticated, verified the SDK app, registered its private profile, obtained a pairing token and retrieved its device list. Cloud setup credentials/profile are stored in macOS Keychain and survive independently of the source/build; no credentials are compiled or committed.
- Implemented bounded HTTP setup requests, cancellation, safe error codes, stable profile recovery, byte-correct UTF-8 EZ encoding and short-lived UDP discovery. Discovery addresses are untrusted until the existing authenticated LAN connection test succeeds. Daily controls use the existing local transports.
- All **78 tests passed** and `flutter analyze` reported no issues. New tests cover independent Python signing vectors, upstream @tuyapi/link encoding vectors (including UTF-8), token reuse, error redaction, cancellation during registration, profile recovery, discovery integrity/private addresses, and the Mac screen's access-check/reset gate.
- Mac release **2.2.0 / build 6** built successfully (46.8 MB) and opened on this Mac. The initial full build emitted Xcode warnings about previously cleared precompiled-module cache paths; the final incremental build completed cleanly. An incremental build left the outer signature stale after replacing App.framework. Added a personal-build script that reseals ad-hoc builds only; final deep/strict code signature verification passed.
- A startup storage error was observed in the native UI; the user subsequently showed the macOS login-Keychain permission dialog. That permission must be completed by the user. Fixed Retry to reload storage and prevented device saves/removals from overwriting unread saved connections; both behaviors have regression tests.
- No tube was reset or paired by the agent. Actual SB22240 acceptance of desktop EZ provisioning, returned local key and LAN lighting controls still require the user's physical test. Mac AP/slow-blinking mode and automatic key transfer between Mac/Android/Windows are not implemented. Windows retains manual local setup; Android retains its optional mobile SDK pairing flow.

## 2026-09-29 — SmartLight 2.1.0 personal Android pairing

- Created the Tuya Smart Life SDK development registration, accepted the SDK agreement with explicit user approval, and registered the local Android signing certificate. No paid edition or add-on was selected.
- Added optional SDK 7.8.0 pairing inside Android: persistent secure installation identity, home creation without coordinates, existing-device retrieval, EZ/AP pairing, permission handling, cancellation/timeouts and session cleanup. Ordinary lighting commands continue through the existing Dart LAN transports.
- Analyzer passed. All 68 tests passed, including a phone-sized end-to-end widget test of consent → setup → pairing → returning connection details and closing the SDK session. These use fake SDK responses, not real Wipro hardware.
- Native SDK bridge and the SDK-free fallback both compiled. A personal release APK was built and its signature, package/version, embedded private SDK configuration and packaged narrow Tapo HTTP policy were checked. Tuya's duplicate library namespaces require the scoped build-script compatibility setting; generated R8 rules cover unused Flutter Play Store split classes.
- SDK keys/security component are git-ignored. Personal APKs are not uploaded to public CI. Signing remains the existing local debug certificate for sideloaded testing.
- No Android device was attached. SDK startup, account registration, EZ/AP radio behavior, returned Wipro keys and real LAN control still need a Pixel/Wipro test. No tube was reset or re-paired during development. The user reported the Tapo strip already works.
- macOS/Windows have no SDK pairing or automatic key transfer. Their preceding build results below are historical, not new 2.1.0 validation.

## 2.0.2 baseline

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

**The user subsequently confirmed Tapo control and Wipro control on Android; see the dated records above.** The following Tapo investigation predates that confirmation. A read-only handshake to the user-provided Tapo IP could not be reached from this Mac. The user reports enabling Third-Party Compatibility and an empty HTTP 400 response at the initial KLAP handshake. Version 2.0.1 incorrectly stopped at that status before trying AES; 2.0.2 includes it in protocol selection. Read-only probes from the terminal still could not connect to port 80, so the strip’s actual protocol remains unconfirmed. No real Tapo password or Wipro local key was read or requested in chat.

Broader Wipro SB22240 firmware compatibility, the Wipro Next-to-Tuya account-link route and exact white range remain unverified. Android SDK pairing and LAN control succeeded for the user’s setup. Tapo TPAP-only firmware, AES login v2 and Tuya 3.1/3.2/custom datapoints are not implemented. Automated protocol compatibility does not establish firmware compatibility.

The app needs the lights' LAN addresses and credentials, but no Home Assistant, Docker, hub or server. Connections stop in the background. Vendor apps handle firmware. The optional Android SDK route requires Tuya internet access during setup. Local runtime commands do not imply every vendor device’s firmware works indefinitely without internet.

Android release builds permit HTTP only to the private Tapo IP supplied through `SMARTLIGHT_TAPO_IP` at build time. With no value, HTTP stays denied. The local address is confined to generated build resources and optional build defines, not committed. A broader HTTP exception was rejected by automatic review and replaced with this scoped approach. Debug builds retain the prior development-only HTTP policy. Android release uses debug signing for personal testing; macOS is not notarized.

See [LOCAL_SETUP.md](LOCAL_SETUP.md) and [REAL_DEVICE_TESTING.md](REAL_DEVICE_TESTING.md) before claiming hardware support.
