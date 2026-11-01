# Releasing

Releases target Apple Silicon and macOS 27 with Xcode 27 and Swift 6.4. Publish two downloads: the CLI archive remains ad-hoc signed; the separate Mac app ZIP requires Developer ID signing, notarization and a stapled ticket. Release notes live only on [GitHub Releases](https://github.com/mbackschat/agent-monitor/releases).

## Release in three steps

### 1. Set the version and refresh the preview

Update `AgentMonitorVersion.current` in [Version.swift](../Sources/AgentMonitorCore/Version.swift). It supplies `--version`, the archive name and the Codex handshake.

Generate and visually review the [README native screenshot](development.md#build-and-coverage-details). Commit the version and any changed `docs/assets/menubar-preview.webp` on `main`. **Update this tracked WebP only for releases**; intermediate review images stay ignored.

### 2. Prepare and review

```sh
bash scripts/release.sh <version>
```

Preparation requires a clean `main` and an unused tag. It runs the doctor, documentation, formatting, Swift test, preview and release terminal checks with synthetic fixtures; it does not use live workloads or provider listings. It then builds and packages the CLI and builds the local Mac app. Run `python3 scripts/notarize-macos.py VERSION --identity DEVELOPER_ID_SHA1` to produce the app ZIP; [Mac signing and notarization](macos-release.md) covers Keychain setup and recovery.

Review `dist/notes-<version>.md`, drafted from `feat`, `fix` and `perf` commits since the previous tag. Write the summary, group or reword changes for users, and remove every `TODO`. Release notes are reviewed input, not an automatically published commit list.

### 3. Publish

```sh
bash scripts/release.sh <version> --publish
```

Publication performs these external changes:

1. Check that the Git email matches the previous release's author, then tag and push `main` and the tag.
2. Create the GitHub release with both archives, their checksums and reviewed notes.
3. Download the published assets again and verify checksums, CLI version/schema, and the Mac app’s version, signature, stapled ticket and Gatekeeper assessment.
4. Update both Homebrew recipes, audit them, install/test the CLI, verify the cask's fetched app archive, and push the tap.

Publication refuses changed HEAD or checksums, mismatched CLI/Mac source revisions, and missing or unverifiable native artifacts.

### Keep artifacts and recover deliberately

Outputs live under ignored `dist/`. Keep the unstripped executable for **every published version** so crash reports can be symbolicated.

To prepare again, delete `dist/agent-monitor-<version>-macos-arm64*`. If publishing stops partway, inspect the completed steps and finish the remaining commands from [release.sh](../scripts/release.sh) by hand; do not rerun the whole publication.

## Update Homebrew

The [Homebrew tap](https://github.com/mbackschat/homebrew-tap) owns two recipes: `agent-monitor` installs the CLI/TUI; `agent-monitor-app` installs only the Mac app. They use the same release version and separate checksummed downloads, so users can install either or both. Publication calls [update-homebrew.py](../scripts/update-homebrew.py) with the released version.

The helper reads both checksums from the published release and verifies the tap remote, `main` branch and GitHub email. It updates the formula URL/checksum and creates or updates the app cask's version/checksum. Before committing and pushing, it audits both recipes, installs or upgrades the CLI, runs `brew test`, and checks the installed version, guides and both schemas. It fetches the cask through Homebrew and verifies the extracted app's version, signature, ticket and Gatekeeper assessment. It does not launch or replace a running Mac app; the [user-run installation check](macos-release.md#installation-check-and-publication) remains separate. Homebrew auto-update and cleanup are disabled for this operation.

### Resume only the Homebrew step

If Homebrew fails after the GitHub release was published, fix the reported prerequisite and resume only that step:

```sh
python3 scripts/update-homebrew.py <version>
```

The helper accepts its own exact pending recipe edits or one unpushed release commit; repeating a completed update is safe. It refuses unrelated working changes or unpushed commits, downgrades and changed checksums for a published version. Remote divergence stops for reconciliation; it never force-pushes or overwrites release assets. Cask changes beyond its generated version/checksum need review and a matching helper update.

If the GitHub release does not yet exist, inspect the tag/push/release state and finish those commands from [release.sh](../scripts/release.sh) before running the helper. Release notes remain reviewed input, not an automatically published raw commit list.

Release automation checks use disposable files and fake external commands:

- `python3 scripts/test_macos_bundle.py` — native bundle, version and license guards.
- `python3 scripts/test_notarize_macos.py` — submission recovery, source identity and archive protection without Keychain access or Apple uploads.
- `python3 scripts/test_release.py` — Homebrew publication and retry behavior with disposable Git repositories.

These checks run in CI and before preparation; publication performs the real installed-binary and downloaded-app checks.

## Packaging details

[package-release.py](../scripts/package-release.py) reads version and architecture from the built executable and packages the schema bundle, project license, [third-party notices](../THIRD_PARTY_NOTICES.md), pinned dependency licenses/notices and original FIGlet font notices. Archive headers omit local user and group identities.

The packager strips the symbol table—more than half of the unstripped file—and verifies the stripped ad-hoc signature. From the extracted archive outside the checkout, it checks version, help, guide and both report/diagnosis schema discovery. Releases retain default `-O` optimization: `-Osize` saved another 3.5 MB stripped but was declined on 2026-10-15.

When dependencies or optional skills change, update the notice index against [Package.resolved](../Package.resolved) and [skills.lock](../skills.lock), including SwiftTUI's vendored licenses and embedded font notices. Read licenses/notices at the locked revisions; a package license does not replace separately licensed bundled components. Inspect packaged `THIRD_PARTY_NOTICES.md` and `licenses/` before publishing.
