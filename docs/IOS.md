# iOS preview builds

The Linux machine can export the Xcode project. Compiling the device executable and Simulator app uses Xcode on a Mac, including a standard GitHub-hosted macOS runner. The `Apple builds` workflow builds on our fork before any upstream release.

## Commands

```bash
tools/build_all.sh ios-project    # Linux or macOS: generate build/ios/project/PhreakNICCCG.xcodeproj
tools/build_all.sh ios            # macOS + Xcode: build/ios/PhreakNIC-CCG-v<version>-unsigned.ipa
tools/build_all.sh ios-simulator  # macOS + Xcode: Simulator .app under build/ios/simulator/
```

Install Godot 4.7.1 and the matching `ios.zip` export template. On Linux its directory is `~/.local/share/godot/export_templates/4.7.1.stable/`; on macOS it is `~/Library/Application Support/Godot/export_templates/4.7.1.stable/`. Set `GODOT=/path/to/Godot` if it is not installed at the build script's default path.

Use Xcode 26.3 for the official Godot 4.7.1 template. The fork's first device build exposed missing SDK symbols with the runner's default Xcode 16.4; the workflow explicitly selects the installed Xcode 26.3 through `DEVELOPER_DIR`.

The official 4.7.1 Simulator static library contains x86_64 objects only, despite its XCFramework manifest listing arm64 too. The Simulator build therefore selects `ARCHS=x86_64`, and the iOS CI job runs on `macos-15-intel`. The device IPA remains ARM64. Use an Intel Mac for the Simulator smoke check with this template.

The iOS targets are opt-in, so existing default builds and release packaging do not depend on Xcode. The preset supports iPhone and iPad on iOS 15+, uses the shared phone layout and landscape orientation, and inherits the project version. Its all-zero Team ID is an explicit placeholder for unsigned project generation; it is not an Apple signing identity.

An **unsigned IPA cannot be installed directly on an ordinary iPhone**. Sign and provision it with an appropriate Apple identity/device installation tool, or configure an Apple developer team in Xcode and use its supported device/TestFlight distribution workflow. The CI build does not use Apple credentials or publish to TestFlight or the App Store.

See [Godot's iOS export documentation](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_ios.html) for Xcode and signing setup. Native sharing, safe-area layout and background/reconnect behavior still need device testing before an iOS release.

## Fork build checks

`.github/workflows/apple-builds.yml` runs when the `build/apple-platforms` branch is pushed, and can also be started manually once the workflow is available on the repository's default branch. It:

- Downloads the official Godot 4.7.1 Mac editor and templates and checks their pinned SHA-256 hashes.
- Builds a universal Mac ZIP on both Intel and Apple Silicon runners, verifies its ad-hoc signature, launches the packaged executable headlessly, and runs the affected platform/UI checks.
- Compiles an unsigned ARM64 device IPA using the iPhoneOS SDK.
- Builds the separate Simulator executable, installs it on an available iPhone Simulator, waits for the launched game PID, checks that the process stays alive and captures a screenshot.
- Uploads ZIPs, the unsigned IPA, checksums and logs as Actions artifacts for seven days.

Standard GitHub-hosted runners are [free for public repositories](https://docs.github.com/en/actions/how-tos/write-workflows/choose-where-workflows-run/choose-the-runner-for-a-job). A Simulator launch is a smoke check; it does not establish real-device playability or App Store readiness. CI artifacts are preview builds rather than published game releases.

## Verified fork build, November 15, 2026

[Apple builds run 43761358237](https://github.com/bitwize-music/PhreakNIC-CCG/actions/runs/43761358237) tests source commit `d1df701` on the fork's `build/apple-platforms` branch:

- Intel and Apple Silicon Mac jobs passed export, signature verification, headless launch and 102 platform/UI checks per runner.
- The ARM64 iPhoneOS IPA compiled with Xcode 26.3. The downloaded artifact passed its SHA-256 checksum check.
- The x86_64 Simulator app compiled, installed and launched. `simctl` returned the game PID and the helper verified that the actual game process stayed alive before and after the screenshot.
- The inspected screenshot shows the game launch splash. Menu rendering and gameplay have **not** been verified on iOS; manual device testing remains necessary.

Artifacts are `macos-macos-15`, `macos-macos-15-intel` and `ios-unsigned-preview`. The last contains the unsigned device IPA, checksum, build logs, Simulator launch PID and screenshot. Download from the run's artifacts section, or from Linux with:

```bash
gh run download 43761358237 --repo bitwize-music/PhreakNIC-CCG \
  --name ios-unsigned-preview --dir build/apple-ci/ios
```

Earlier fork runs exposed an old default Xcode SDK, the misleading Simulator architecture manifest and insufficient pipeline/launch checks. Those checks now use strict Bash pipeline handling, an Intel Simulator build and the launched application's PID. The separate existing `Known bugs (red until fixed)` job remains a different check from these Apple builds.
