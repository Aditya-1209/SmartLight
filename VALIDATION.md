# Validation record

Date: 2026-09-28. Implementation snapshot: `3fc44ab` (documentation follows separately).

## Environment

- macOS 27.0, Apple Silicon; Flutter 3.47.5 stable / Dart 3.13.4.
- Xcode 27.0; CocoaPods 1.17.0.
- Android SDK 36, Android Studio's bundled OpenJDK 25; Android licenses accepted. The build also installed required SDK 35/CMake components automatically.
- Git 2.54.0 and GitHub CLI 2.97.0. Existing GitHub authentication worked.
- Flutter doctor warned about missing iOS Simulator runtimes. iOS is not a target and macOS compilation succeeded.

## Automated checks

| Check | Result |
| --- | --- |
| `flutter pub get` | Pass |
| `dart format .` and format verification | Pass, 34 Dart files |
| `flutter analyze` | Pass, no issues |
| `flutter test --coverage` | Pass, 41 tests; 1,185 / 1,345 executable lines covered (88.1%) |
| `flutter test integration_test/demo_flow_test.dart -d macos` | Pass, 2 native integration tests |
| Credential-pattern scan of tracked text | No GitHub tokens, JWTs, or private-key headers found |

Native integration tests verify an isolated Keychain/preferences write/read/delete round trip and the demo setup → power → brightness → RGB → Movie flow. Temporary probe values are removed; no real credentials or physical lights are used. The macOS runner printed a foreground warning, but both integration tests completed successfully.

Widget checks include 412×915, 1280×720, and 1920×1080 layouts, connection testing, entity selection, friendly-name editing, save, power, scenes, brightness drag completion, unavailable-state disabling, unsupported-control hiding, and offline feedback. A desktop title overflow caught by tests was corrected. The release app's dark demo dashboard was also inspected through native UI automation.

## Builds

| Target | Result |
| --- | --- |
| macOS release | `flutter build macos` succeeded; final rebuild recorded in the task report |
| Android ARM64 debug / Pixel 8 architecture | `flutter build apk --debug --target-platform android-arm64` passed |
| Android ARM64 release | `flutter build apk --release --target-platform android-arm64` passed, approximately 19.1 MB |
| Android universal debug, local | Attempted; ran out of disk space during native-library extraction/packaging |
| Android universal debug, GitHub Actions | Passed |
| Windows x64 release, GitHub Actions | Passed |
| macOS release, GitHub Actions | Passed |

The universal local Android attempt was retried after removing only task-generated intermediate files, but still exceeded available disk. ARM64 builds then passed. No personal files or unrelated caches were deleted. Free several GB (preferably 10 GB) before running multiple full native builds locally.

## CI evidence

The first complete cross-platform run passed on commit `ed64077`: [run 36436329325](https://github.com/Aditya-1209/SmartLight/actions/runs/36436329325).

All four jobs (`checks`, `android`, `macos`, `windows`) succeeded. Verified artifacts: `SmartLight-Test-Coverage`, `SmartLight-Android-debug`, `SmartLight-macOS`, and `SmartLight-Windows`. Windows includes the complete Release directory and macOS uses a zip preserving the app bundle. The final task report links the subsequent run for the final pushed commit; consult the [Actions page](https://github.com/Aditya-1209/SmartLight/actions) for current status.

## Unverified behavior / limitations

- **No tests against the physical Wipro SB22240 battens or Tapo L920, or a real Home Assistant server.** Wipro integration/account/firmware support must be established in HA first.
- No physical Pixel 8 test or Windows interactive runtime test. Windows compilation passed in CI; native secure-storage runtime verification was on macOS only.
- Android release permits HTTP only for `homeassistant.local`; use HTTPS or a narrowly configured hostname exception. Debug accepts arbitrary LAN HTTP URLs.
- Android release uses a debug signing key for test installation. macOS artifacts are not notarized for distribution. No store packaging or installers are included.
- No custom-scene editor, direct vendor protocols, schedules, effects, automatic device discovery outside HA, or proxy-subpath URLs. Scene models support later extension.
- Demo tests model HA behavior; vendor firmware and integration latency may differ. Successful service requests are not proof of physical light output.

See [REAL_DEVICE_TESTING.md](REAL_DEVICE_TESTING.md) for the checkbox pass/fail acceptance plan and [README.md](README.md) for setup and troubleshooting.
