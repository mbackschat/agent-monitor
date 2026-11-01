# Sign and notarize the Mac app

Distribute the native app as a Developer ID-signed, notarized ZIP alongside the CLI archive on GitHub. The `agent-monitor-app` Homebrew cask uses that same ZIP; the CLI formula remains separate. Signing runs locally with Xcode, and private keys and notarization credentials stay in Keychain.

[Release guide](releasing.md) · [Installation](installation.md)

## One-time Apple setup

1. Activate the paid Apple Developer Program membership and sign in under **Xcode → Settings → Accounts**.
2. Select the team, open **Manage Certificates**, and create **Developer ID Application**. Apple Development and Apple Distribution certificates serve different purposes. Check availability with `security find-identity -v -p codesigning`.
3. Create an app-specific password under **Apple Account → Sign-In and Security → App-Specific Passwords**. In your own terminal, save it through the secure prompt:

```sh
xcrun notarytool store-credentials agent-monitor-notary \
  --apple-id "YOUR_APPLE_ACCOUNT_EMAIL" --team-id YOUR_TEAM_ID
```

The command validates the credentials before storing them. Never put passwords, private keys or certificate exports into source, release notes or chat. See Apple's [Developer ID certificate guide](https://developer.apple.com/help/account/certificates/create-developer-id-certificates/) and [app-specific password instructions](https://support.apple.com/en-us/102654).

## Prepare the app

### Required app-icon review

A public Mac release must include a recognizable application icon. The image inside the panel and the live menu bar status icon do not satisfy this requirement. Signing and notarization do not establish icon quality or even correct icon wiring.

Before signing, complete these checks against the release bundle:

- Review the design against current [Apple app-icon guidance](https://developer.apple.com/design/human-interface-guidelines/app-icons), including small-size legibility and appearance variants. Use the [recorded findings](research/native-menu-design.md#application-icon-release-review--2026-11-01) to distinguish current Icon Composer guidance from legacy ICNS packaging.
- Inspect default, dark, clear and tinted renditions against light and dark backgrounds. Preserve the same identifying shapes; record any unsupported or unverified appearance instead of assuming it works.
- Verify the bundle declares its app icon and includes the corresponding compiled resources. Decode or render them and inspect the icon macOS resolves for the actual `.app`; checking a source image or filename alone is insufficient.
- Show changed artwork for design review before publication. For the current replacement release, the user explicitly requires approval of the revised icon before release.
- Check the extracted download and Homebrew-installed app retain the approved icon. The user's Finder check remains separate from headless resource validation.

Bundle assembly and archive verification check the declared icon, inspect its compiled catalog for layered artwork and 32–1024-pixel representations, and decode its ICNS fallback. These guards reject the missing icon that escaped the initial 0.4.0 release. They establish resource integrity, not visual approval or live Finder appearance.

Track the editable [Icon Composer source](../Resources/README.md) in Git. Xcode generates the compiled catalog and ICNS during packaging; keep those binaries and review images ignored. This preserves a small, reviewable design history without retaining generated image versions.

### Build and notarize

Complete [release preparation](releasing.md#release-in-three-steps) first. It builds the local app and records the validated source revision. Then, from the repository root, supply the release version and the Developer ID Application certificate's SHA-1:

```sh
python3 scripts/notarize-macos.py 0.4.0 \
  --identity YOUR_DEVELOPER_ID_APPLICATION_SHA1
```

The script stages the app, retains its unstripped executable, strips and signs it, submits it to Apple, waits for acceptance, staples the ticket, and creates the final ZIP. It verifies the extracted app's version, bundle identity, signature, ticket and Gatekeeper assessment before writing the checksum and source receipt. The default Keychain profile is `agent-monitor-notary`; override it with `--keychain-profile NAME`.

Allow any macOS Keychain prompt locally. A long authorization wait can cause signing to fail with differing timestamps; rerun the command to sign with a fresh timestamp. No notarization upload occurs until signing succeeds.

Both bundle versions come from `AgentMonitorVersion.current`. Resources and locked dependency notices are retained. Hardened Runtime uses only the [Apple Events entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.automation.apple-events), required by the existing Terminal focus action. It does not enable App Sandbox, debugging access or relaxed library validation. Runtime monitoring remains offline; development-time signing and notarization contact Apple.

## Submit once and keep the submission ID

The script saves Apple's ID before waiting. The default wait timeout is ten minutes; `--timeout 20m` changes it. A timeout does not cancel Apple's work: rerun the same command to resume that submission without signing or uploading again.

If the upload itself is interrupted before its ID is saved, the script refuses to upload another copy. Inspect Apple's history, identify the original submission, and supply its ID explicitly:

```sh
xcrun notarytool history --keychain-profile agent-monitor-notary
python3 scripts/notarize-macos.py 0.4.0 \
  --identity YOUR_DEVELOPER_ID_APPLICATION_SHA1 \
  --submission-id ORIGINAL_SUBMISSION_ID
```

The accepted log's SHA-256 must match the retained submission ZIP before the script staples anything. An **Invalid** submission stops packaging and leaves the log for diagnosis. Fix the reported cause; preserve the failed staging directory and its ID before preparing a new attempt. Never replace published release assets.

Source changes stop resumption: rebuild and revalidate the release from the final commit instead of relabeling old artifacts. Concurrent invocations for the same version are refused. Apple's [custom notarization workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow) explains submission recovery and ticket handling.

## Staple, package and verify

The script proceeds only after **Accepted** and reads the notarization log even on success. It staples the app before building the download ZIP; the earlier submission ZIP is not the release download. Once a complete archive and matching receipts exist, rerunning verifies them without another submission or app signature.

Retained files under ignored `dist/`:

| File | Purpose |
| --- | --- |
| `macos-VERSION/source.commit` | Original source revision; must match the prepared CLI release. |
| `macos-VERSION/submission.json` | Apple's submission ID. |
| `macos-VERSION/submission-started.json` | Prevents another upload when the result is uncertain. |
| `macos-VERSION/submission.zip` | Exact uploaded bytes, checked against Apple's log. |
| `macos-VERSION/notary-log.json` | Apple's result and any reported issues. |
| `agent-monitor-app-VERSION-macos-arm64.zip`, `.zip.sha256`, `.commit` | Verified download and publication receipts. |
| `agent-monitor-app-VERSION-macos-arm64-unstripped` | Symbols for crash analysis; retain for every published version. |

Do not modify app resources or re-sign after notarization. `python3 scripts/test_notarize_macos.py` exercises recovery and publication guards with fake Apple commands and disposable files; it neither accesses Keychain nor submits an app.

## Installation check and publication

Return to [publication](releasing.md#3-publish). It verifies both CLI and Mac artifacts from the prepared revision, uploads them, downloads them again and repeats their checks. The Homebrew update publishes the `agent-monitor` formula and `agent-monitor-app` cask; the cask installs only the app. Its Homebrew-fetched ZIP passes the same verifier before the tap is pushed. If Homebrew refuses to audit a newly added local cask as untrusted, trust only that reviewed package with `brew trust --cask mbackschat/tap/agent-monitor-app`.

For the first signed release, the user installs with `brew install --cask mbackschat/tap/agent-monitor-app`, opens the app from Applications, and checks the menu bar panel and sampling. Exercise Terminal focus with a disposable target if available. Signature and Gatekeeper checks do not establish physical interaction or Automation consent; record unperformed checks as pending.

An installer, in-app updater, login item and shared background collector remain separate work.
