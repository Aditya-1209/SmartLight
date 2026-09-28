# Real-device acceptance checklist

**Status: UNVERIFIED. No physical lights were available during automated development.**

Test separately on Pixel 8, MacBook Air M4, and Windows 11 x64. Record the app commit, OS, HA version, and light firmware below. Do not record tokens or passwords.

- App commit:
- Platform / OS:
- Home Assistant version:
- Wipro firmware:
- Tapo firmware:
- Tester / date:

| Done | Step | Pass | Fail | Notes |
| --- | --- | --- | --- | --- |
| [ ] | 1. Add Wipro SB22240 batten #1 to Home Assistant and verify native HA controls. | [ ] | [ ] | |
| [ ] | 2. Add Wipro SB22240 batten #2 to Home Assistant and verify native HA controls. | [ ] | [ ] | |
| [ ] | 3. Add the Tapo L920 strip through the TP-Link integration and verify native HA controls. | [ ] | [ ] | |
| [ ] | 4. Confirm all three appear as distinct light.* entities; record actual supported color modes. | [ ] | [ ] | |
| [ ] | 5. Create a Home Assistant long-lived access token (never put the token in this document). | [ ] | [ ] | |
| [ ] | 6. Launch SmartLight on the target platform. | [ ] | [ ] | |
| [ ] | 7. Enter the Home Assistant URL. | [ ] | [ ] | |
| [ ] | 8. Enter the token. | [ ] | [ ] | |
| [ ] | 9. Test connection; verify Connected and discovered lights. | [ ] | [ ] | |
| [ ] | 10. Map Wipro Tube 1 to the correct entity. | [ ] | [ ] | |
| [ ] | 11. Map Wipro Tube 2 to the correct entity. | [ ] | [ ] | |
| [ ] | 12. Map Tapo Strip to the correct entity; Save. | [ ] | [ ] | |
| [ ] | 13. Test power on/off for each light and verify physical output. | [ ] | [ ] | |
| [ ] | 14. Test brightness at 1%, 5%, 50%, and 100%; verify UI/physical state. | [ ] | [ ] | |
| [ ] | 15. Test RGB presets and custom RGB on each supported light. | [ ] | [ ] | |
| [ ] | 16. Test warm/mid/cool temperature on each supported light. | [ ] | [ ] | |
| [ ] | 17. Test master power on and off. | [ ] | [ ] | |
| [ ] | 18. Test master brightness and 0% handling. | [ ] | [ ] | |
| [ ] | 19. Test master RGB color; incompatible lights are skipped. | [ ] | [ ] | |
| [ ] | 20. Test Study: tubes ~100%, strip ~60%, neutral/cool white. | [ ] | [ ] | |
| [ ] | 21. Test Movie: tubes off, strip ~15% purple/blue. | [ ] | [ ] | |
| [ ] | 22. Test Chill: tubes ~30% warm, strip ~25% purple. | [ ] | [ ] | |
| [ ] | 23. Test Sleep: tubes off, strip ~5% red. | [ ] | [ ] | |
| [ ] | 24. Disconnect one physical light; wait for HA to mark it unavailable. | [ ] | [ ] | |
| [ ] | 25. Verify disabled device controls and per-device master/scene failure messages; other lights respond. | [ ] | [ ] | |
| [ ] | 26. Reconnect the light; verify state updates without restarting. | [ ] | [ ] | |
| [ ] | 27. Change a light in the Home Assistant UI; verify live state in SmartLight. | [ ] | [ ] | |
| [ ] | 28. Stop/restart HA or disconnect Wi-Fi; verify stable offline/reconnect behavior and manual refresh. | [ ] | [ ] | |
| [ ] | 29. Test outside the LAN without remote access; verify an actionable error. | [ ] | [ ] | |
| [ ] | 30. Restart SmartLight; verify credentials, names, mappings, and theme persist. | [ ] | [ ] | |
| [ ] | 31. Enable demo, manipulate lights, then disable demo; verify real configuration is preserved. | [ ] | [ ] | |
| [ ] | 32. Check Diagnostics contains no token; test each diagnostic control. | [ ] | [ ] | |
| [ ] | 33. Test dark/light/system theme and keyboard focus; check phone and 1280×720 / 1920×1080 desktop layouts. | [ ] | [ ] | |
| [ ] | 34. On Android, verify debug HTTP and release HTTPS/homeassistant.local policy. | [ ] | [ ] | |
| [ ] | 35. On macOS, verify Local Network permission and Keychain persistence after app relaunch. | [ ] | [ ] | |
| [ ] | 36. On Windows, run the unpacked complete artifact on Windows 11 x64 and verify credential persistence. | [ ] | [ ] | |

If a feature is not exposed by the integration, record N/A and the reported capabilities. A skipped unsupported color parameter is expected; a falsely reported successful command or app crash is a failure.
