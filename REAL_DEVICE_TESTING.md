# Direct-control physical test plan

Automated protocol tests do not replace this checklist. Use a trusted room Wi-Fi network and enter credentials only in the app. No Home Assistant, Docker or background helper should run during these checks.

## Built-in timers (2.6.0)

- Open **Timers & schedules** and confirm each light reports timer availability. A missing/invalid Wipro DP26 must show unsupported, and an unreachable light must show a check failure.
- With a chosen light on, set a one-minute off timer, confirm it appears, then fully quit SmartLight. Verify the physical light goes off without the app running. Repeat for each supported model/firmware.
- Set a timer on one platform and read/cancel it from another platform with the same saved connection. Confirm cancellation on the first platform after refresh.
- Set a one-time clock action across midnight; verify the Today/Tomorrow label and physical action. These are not repeating daily schedules.
- Confirm a Wipro off timer requires power on first; change its power through normal controls and verify the timer cancels. A Wipro on timer requires power off first.
- Confirm an existing vendor-app countdown is displayed and cannot be silently overwritten. Ordinary vendor schedules may still act independently.
- With one light unavailable, schedule the other lights and verify the report names the failed light without claiming the whole room succeeded. Lost acknowledgements must not automatically replay a timer write.
- Leave wall power on. Record whether a power outage clears each firmware’s countdown rather than assuming persistence through a power loss.

## General controls

| Check | Pass | Fail | Notes |
|---|---|---|---|
| Pair lights in their original vendor apps; confirm normal operation | [ ] | [ ] | |
| Reserve IP addresses; confirm phone/Mac/PC are on the same LAN | [ ] | [ ] | |
| Tapo: enable Third-Party Compatibility where available | [ ] | [ ] | |
| Add Tapo using IP and account credentials; test does not alter state | [ ] | [ ] | |
| Use Tapo alone with both battens unconfigured | [ ] | [ ] | |
| Wipro: establish SB22240 key export/account compatibility before any reset | [ ] | [ ] | |
| Android: prepare SDK setup before resetting one tube; verify EZ/AP pairing returns a key | [ ] | [ ] | |
| Android: cancel pairing, reopen setup and recover the paired light without resetting it | [ ] | [ ] | |
| Android: reopen normal controls after pairing and confirm LAN operation with WAN disconnected | [ ] | [ ] | |
| Add batten 1 with its own ID/key, version and matching datapoints | [ ] | [ ] | |
| Add batten 2 with its distinct ID/key/IP | [ ] | [ ] | |
| Verify correct warm/cool endpoints against the actual battens | [ ] | [ ] | |
| Power each light on and off | [ ] | [ ] | |
| Brightness 1%, 50%, 100%, 0% off; record firmware minimum brightness | [ ] | [ ] | |
| Red, green, blue, white and custom color on each compatible light | [ ] | [ ] | |
| Adjust brightness while in color mode; color is preserved | [ ] | [ ] | |
| White slider appears only for a valid adjustable range | [ ] | [ ] | |
| Manual Tapo controls cancel active strip effects | [ ] | [ ] | |
| Room on/off, brightness and color affect compatible connected lights | [ ] | [ ] | |
| Study, Movie, Chill and Sleep; unsupported parameters are skipped | [ ] | [ ] | |
| Unplug one light; other lights work and failures name the correct light | [ ] | [ ] | |
| Change state in a vendor app; SmartLight updates within a polling cycle | [ ] | [ ] | |
| Leave Wi-Fi; unavailable states appear without crashes | [ ] | [ ] | |
| Return to Wi-Fi; refresh reconnects | [ ] | [ ] | |
| Background/close app; connections stop and lights keep their settings | [ ] | [ ] | |
| Reopen app; credentials/settings persist and state refreshes | [ ] | [ ] | |
| Bad Tapo credentials show useful error and limit repeat authentication | [ ] | [ ] | |
| Wrong Tuya key/version fails safely without claiming a successful connection | [ ] | [ ] | |
| Demo mode remains distinct from real lights | [ ] | [ ] | |
| Remove a device; other connections remain intact | [ ] | [ ] | |
| Remove last device; app returns to setup state | [ ] | [ ] | |
| Pixel 8 release APK connects to the allowed strip IP | [ ] | [ ] | |
| macOS grants local-network permission; direct commands work | [ ] | [ ] | |
| Windows 11 firewall/LAN access and direct commands work | [ ] | [ ] | |

Record model, hardware/firmware version, protocol, profile, platform and failure messages. Do not include credentials or local keys in shared reports.
