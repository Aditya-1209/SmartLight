# Direct-control physical test plan

Automated protocol tests do not replace this checklist. Use a trusted room Wi-Fi network and enter credentials only in the app. No Home Assistant, Docker or background helper should run during these checks.

| Check | Pass | Fail | Notes |
|---|---|---|---|
| Pair lights in their original vendor apps; confirm normal operation | [ ] | [ ] | |
| Reserve IP addresses; confirm phone/Mac/PC are on the same LAN | [ ] | [ ] | |
| Tapo: enable Third-Party Compatibility where available | [ ] | [ ] | |
| Add Tapo using IP and account credentials; test does not alter state | [ ] | [ ] | |
| Use Tapo alone with both battens unconfigured | [ ] | [ ] | |
| Wipro: establish SB22240 key export/account compatibility before any reset | [ ] | [ ] | |
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
