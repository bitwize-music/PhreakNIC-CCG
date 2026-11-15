# macOS preview builds

The `macOS` Godot export preset produces one application for Intel x86_64 and Apple Silicon arm64. Its deployment targets are macOS 11 on Intel and macOS 13 on Apple Silicon. The game, assets, bots and online protocol are shared with the other platforms.

This is a preview port. A Linux export and archive inspection cannot verify launch, rendering, input, audio or Gatekeeper behavior on a real Mac. Complete the Mac checks below before describing it as tested.

## Initial Linux validation

- Godot 4.7.1 release export completed successfully using the official, SHA-256-verified template archive.
- ZIP integrity, bundle identifier, inherited version 0.29, Retina flag, icon, executable permissions, Intel/ARM64 Mach-O slices and ad-hoc signature structures checked.
- The exported game resource pack loaded the main menu headlessly with the Linux editor without errors.
- `v07_checks` passed 47 checks and `v08_checks` passed 52 checks, using isolated user data. The v07 suite also reported an ObjectDB leak warning at exit.
- A temporary release-packaging fixture verified stable asset names and checksums, and confirmed that a missing Mac ZIP is rejected before removing previous release files.

## Build on Linux

Install Godot 4.7.1 and its matching standard export templates from the [official release](https://github.com/godotengine/godot/releases/tag/4.7.1-stable). Verify the downloaded archive against the release checksums. In Godot, use **Editor → Manage Export Templates → Install from File** to install the `.tpz` archive. The default Linux template directory is `~/.local/share/godot/export_templates/4.7.1.stable/`; the macOS exporter needs `macos.zip` there.

```bash
tools/build_all.sh macos
# Or use an editor installed somewhere else:
GODOT=/path/to/godot tools/build_all.sh macos
```

The output is `build/macos/PhreakNIC-CCG-v<version>.zip`, containing a `.app` bundle, plus `build/macos/SHA256SUMS.txt`. Godot generates the Mac icon from the existing PNG, includes both CPU architectures and preserves executable file permissions in the ZIP. The bundle versions inherit `project.godot`, so they follow game releases automatically.

The Mac-only build needs neither Xcode nor the Android SDK. `tools/build_all.sh` with no arguments now builds all five client platforms; `tools/build_all.sh release` packages the Linux, Windows, macOS and Android outputs already built for the current version. Its Mac release asset is `build/release/PhreakNIC-CCG-macos.zip`.

There is no new release download link in the game menu yet: a maintainer must first publish that asset with a release.

## Install the preview on a Mac

1. Transfer the ZIP to a Mac and extract it with Archive Utility.
2. Move the extracted `.app` into Applications and open it.
3. This preview has an **ad-hoc signature**, without an Apple Developer ID certificate or notarization. A downloaded copy may be blocked by Gatekeeper. After verifying its source, follow Apple's **System Settings → Privacy & Security → Open Anyway** process if offered. See [Apple's instructions for opening an app from an unidentified developer](https://support.apple.com/en-us/102445).

Ad-hoc signing permits local testing and supplies the signature required on Apple Silicon; it does not establish a verified publisher. Do not label this preview as Apple-notarized or App Store approved.

Saves, settings, decks and lifetime statistics use Godot's `user://` directory, normally `~/Library/Application Support/Godot/app_userdata/PhreakNIC CCG/`. Browser and other-platform saves are not automatically migrated.

## Developer ID signing and notarization

The checked-in preset uses **Testing**, **Built-in (ad-hoc only)** signing, disabled notarization and no App Sandbox. It is intended for direct downloads rather than the Mac App Store.

For a normal public download, enroll in the Apple Developer Program and configure Developer ID signing and notarization. Godot supports doing this from Linux with `rcodesign`; a Mac is not required for that export workflow. In the macOS export options, select **Distribution**, **rcodesign** for signing, and **rcodesign** for notarization. Set the `rcodesign` executable path in Godot's editor settings. Use the appropriate Apple Team ID and disable the debugging entitlement.

Keep certificates, passwords and App Store Connect private keys outside the repository. Godot accepts these environment variables for the credentials:

```text
GODOT_MACOS_CODESIGN_CERTIFICATE_FILE
GODOT_MACOS_CODESIGN_CERTIFICATE_PASSWORD
GODOT_MACOS_NOTARIZATION_API_UUID
GODOT_MACOS_NOTARIZATION_API_KEY
GODOT_MACOS_NOTARIZATION_API_KEY_ID
```

Follow the [Godot macOS signing and notarization instructions](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_macos.html), including checking notarization status and stapling the accepted ticket. If signing or stapling changes the application, recreate the ZIP and regenerate its checksum before distributing it. No Apple credentials are needed for the default preview build.

## Mac checks before release

- Launch on Apple Silicon and Intel, checking the minimum supported OS versions where hardware is available.
- Check the icon, Retina text, resizing, fullscreen, card previews, trackpad scrolling and music/sound.
- Complete the tutorial and an offline game; save, quit, relaunch and resume. Check Command-Q during a game.
- Export a deck and a result image; open their folders and verify clipboard copying and browser links.
- Create/join an online room with another platform on the same game version. Disconnect and reconnect; test sleep/wake.
- Use **Report a bug** and confirm macOS is selected in the issue form.
- For a notarized release, download a fresh copy through a browser onto a Mac and check Gatekeeper without developer overrides.
