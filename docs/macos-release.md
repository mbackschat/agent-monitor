# Sign and notarize the Mac app

Distribute the native app as a Developer ID-signed, notarized ZIP alongside the CLI archive on GitHub. The CLI Homebrew formula remains separate. This workflow runs locally with Xcode; private keys and notarization credentials stay in Keychain.

[Release guide](releasing.md) · [Installation](installation.md)

## One-time Apple setup

1. Activate the paid Apple Developer Program membership and sign in under **Xcode → Settings → Accounts**.
2. Select the team, open **Manage Certificates**, and create **Developer ID Application**. Apple Development and Apple Distribution certificates serve different purposes. Check availability with `security find-identity -v -p codesigning`.
3. Create an app-specific password under **Apple Account → Sign-In and Security → App-Specific Passwords**. In your own terminal, save it through the secure prompt:

```sh
xcrun notarytool store-credentials agent-monitor-notary \
  --apple-id "YOUR_APPLE_ACCOUNT_EMAIL" --team-id YOUR_TEAM_ID
```

The command validates the credentials before storing them. Do not put passwords, private keys or certificate exports into source, release notes or chat. See Apple's [Developer ID certificate guide](https://developer.apple.com/help/account/certificates/create-developer-id-certificates/) and [app-specific password instructions](https://support.apple.com/en-us/102654).

## Prepare the app

First complete the version, preview, commit and checks in [release preparation](releasing.md#release-in-three-steps). `release.sh` builds the local app but deliberately leaves it ad-hoc signed. Signing a release requires the explicit identity below.

Use the intended version and the SHA-1 identity from `security find-identity`. Start in the repository root with an unused staging directory:

```sh
release_version=0.4.0
signing_identity=YOUR_DEVELOPER_ID_APPLICATION_SHA1
mac_stage="dist/macos-$release_version"
mkdir "$mac_stage"
ditto '.build/Agent Monitor.app' "$mac_stage/Agent Monitor.app"
cp "$mac_stage/Agent Monitor.app/Contents/MacOS/agent-monitor-menubar" \
  "dist/agent-monitor-app-$release_version-macos-arm64-unstripped"
strip "$mac_stage/Agent Monitor.app/Contents/MacOS/agent-monitor-menubar"
codesign --force --sign "$signing_identity" --options runtime --timestamp \
  --entitlements scripts/macos-release.entitlements "$mac_stage/Agent Monitor.app"
codesign --verify --deep --strict "$mac_stage/Agent Monitor.app"
ditto -c -k --keepParent "$mac_stage/Agent Monitor.app" "$mac_stage/submission.zip"
git rev-parse HEAD > "$mac_stage/source.commit"
```

Stop if any command fails. The bundle's release and build versions come from `AgentMonitorVersion.current`. Both resource bundles, project notices and locked dependency licenses are included. Retain the unstripped native executable for published releases, just as for the CLI.

Hardened Runtime uses only the [Apple Events entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.automation.apple-events), needed by the existing Terminal focus action. It does not enable App Sandbox, debugging access or relaxed library validation. Runtime collection remains offline; the development-time signing/notarization tools contact Apple.

## Submit once and keep the submission ID

```sh
xcrun notarytool submit "$mac_stage/submission.zip" \
  --keychain-profile agent-monitor-notary --output-format json > "$mac_stage/submission.json"
```

Read the returned `id`, then wait for that submission:

```sh
xcrun notarytool wait SUBMISSION_ID --keychain-profile agent-monitor-notary --timeout 10m
xcrun notarytool log SUBMISSION_ID --keychain-profile agent-monitor-notary "$mac_stage/notary-log.json"
```

Proceed only when the status is **Accepted**, and inspect the log even after success. If waiting times out, Apple continues processing: use `info` or `wait` with the same ID, without uploading another copy. For **Invalid**, inspect the log, fix the reported issue and prepare a new signed submission. Keep the prior ID and source revision for diagnosis. Apple's [custom notarization workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow) explains submission, recovery and ticket handling.

## Staple, package and verify

Staple the ticket to the app, then create a new ZIP containing that app. The submission ZIP predates stapling and is not the download artifact.

```sh
xcrun stapler staple "$mac_stage/Agent Monitor.app"
xcrun stapler validate "$mac_stage/Agent Monitor.app"
mac_name="agent-monitor-app-$release_version-macos-arm64"
ditto -c -k --keepParent "$mac_stage/Agent Monitor.app" "dist/$mac_name.zip"
python3 scripts/macos_bundle.py --verify-archive "dist/$mac_name.zip" "$release_version"
```

The verifier extracts to a temporary directory and checks version, bundle identity, signature, stapled ticket and Gatekeeper assessment without launching the app. After it passes, record the checksum and original source revision:

```sh
(cd dist && shasum -a 256 "$mac_name.zip" > "$mac_name.zip.sha256")
cp "$mac_stage/source.commit" "dist/$mac_name.commit"
```

If source changed since preparation, rebuild and revalidate the release instead of relabeling the old archive. Do not modify resources or re-sign after notarization.

## Installation check and publication

For the first signed release, the user checks the final extracted app through Finder: copy it to Applications, open it, confirm the menu bar panel and sampling work, and exercise Terminal focus with a disposable target if available. Signature and Gatekeeper checks do not establish physical interaction or Automation consent. Record unperformed checks as pending.

Return to [publication](releasing.md#3-publish). It requires both CLI and Mac artifacts from the prepared revision, verifies their checksums, uploads both, downloads them again and repeats the Mac archive checks. The Homebrew update remains CLI-only. A cask, installer, automatic updates, login item and shared background collector are separate work.
