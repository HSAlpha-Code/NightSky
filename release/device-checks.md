# Manual release checks — record results, device/OS and build hash

Automated widget/unit tests cannot verify permissions, sensor behaviour, camera hardware,
the deployed provider configuration, or 16 KB execution. Keep
`device_and_16kb_tests_passed=false` until the relevant checks are performed.

- Fresh install: camera/location prompts, deny once/permanently, permission revocation, approximate location, location services off; no microphone/background location request.
- Upload disclosure: cancel causes no capture/upload; agree sends only to the named server; new app session and changing server ask again; revocation asks again. Declining auto-capture turns it off to avoid repeated dialogs.
- Camera: actual star field, no stars, cloud/daylight, portrait/landscape, large image, background/resume, device without camera; compare original with survey and show approximate result labels.
- Sky View: flight mode, manual location, GPS unavailable, no gyro/compass, sensor calibration, different latitudes/time zones, large fonts, small screen and rotation.
- Network: default production HTTPS, server timeout/down, provider outage/fallback, invalid custom server; no request body/photo/GPS in deployed request/error logs or traces unless explicitly disclosed with reviewed retention.
- Local data: captured temporary photo cleanup, leaving result clears session, cache bounds/clear app data/uninstall; backup disabled in final merged manifest.
- Legal screens: policy/credits/terms readable offline, complete publisher/contact, working source/licence links, installed-package notices actually included; public policy URL returns final HTML without login.
- Content: correct object/image assignment, verified full source credits/licences, every online survey fallback reviewed, no third-party logo suggesting endorsement.
- Install/upgrade: release-signed split delivery through Play internal testing on supported phones; update previous version without data loss; check application ID/versionCode and no debug certificate.
- Native libraries: inspect AAB/APKs with Android Studio/APK Analyzer or bundletool/official ELF alignment tools; check every ABI/library and run a 16 KB Android emulator/device. Record tool commands/results; don't infer from Flutter's version alone.
- Play pre-launch report: crashes/ANRs, accessibility, security, policy warnings and download/size reports. Test representative low-memory hardware and long sessions.

Official 16 KB procedure: https://developer.android.com/guide/practices/page-sizes
