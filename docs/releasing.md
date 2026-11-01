# Releasing

Releases target Apple Silicon and macOS 27 with Xcode 27 and Swift 6.4. They are ad-hoc signed, not Developer ID signed or notarized; never describe them otherwise. Release notes live only on [GitHub Releases](https://github.com/mbackschat/agent-monitor/releases).

## Release in three steps

### 1. Set the version and refresh the preview

Update `AgentMonitorVersion.current` in [Version.swift](../Sources/AgentMonitorCore/Version.swift). It supplies `--version`, the archive name and the Codex handshake.

Generate and visually review the [README native screenshot](development.md#build-and-coverage-details). Commit the version and any changed `docs/assets/menubar-preview.webp` on `main`. **Update this tracked WebP only for releases**; intermediate review images stay ignored.

### 2. Prepare and review

```sh
bash scripts/release.sh <version>
```

Preparation requires a clean `main` and an unused tag. It runs the doctor, documentation, formatting, Swift test, preview and release terminal checks with synthetic fixtures; it does not use live workloads or provider listings. It then builds and packages the release.

Review `dist/notes-<version>.md`, drafted from `feat`, `fix` and `perf` commits since the previous tag. Write the summary, group or reword changes for users, and remove every `TODO`. Release notes are reviewed input, not an automatically published commit list.

### 3. Publish

```sh
bash scripts/release.sh <version> --publish
```

Publication performs these external changes:

1. Check that the Git email matches the previous release's author, then tag and push `main` and the tag.
2. Create the GitHub release with archive, checksum and reviewed notes.
3. Download the published assets again and verify checksum, version and schema.
4. Update, audit, install/test and push the Homebrew formula.

Publication refuses a changed HEAD or archive checksum after preparation.

### Keep artifacts and recover deliberately

Outputs live under ignored `dist/`. Keep the unstripped executable for **every published version** so crash reports can be symbolicated.

To prepare again, delete `dist/agent-monitor-<version>-macos-arm64*`. If publishing stops partway, inspect the completed steps and finish the remaining commands from [release.sh](../scripts/release.sh) by hand; do not rerun the whole publication.

## Update Homebrew

The [Homebrew tap](https://github.com/mbackschat/homebrew-tap) owns the canonical formula. It distributes the CLI, not the native app. Publication calls [update-homebrew.py](../scripts/update-homebrew.py) with the released version.

The helper reads the checksum from the published release, verifies the tap remote, `main` branch and GitHub email, and changes only the versioned URL/checksum. Before committing and pushing, it runs `brew audit --strict`, installs or upgrades the CLI, runs `brew test`, and checks the installed version, guides and both schema resources. Homebrew auto-update and cleanup are disabled for this operation.

### Resume only the Homebrew step

If Homebrew fails after the GitHub release was published, fix the reported prerequisite and resume only that step:

```sh
python3 scripts/update-homebrew.py <version>
```

The helper accepts its own exact pending formula edit or one unpushed release commit; repeating a completed update is safe. It refuses unrelated working changes or unpushed commits, downgrades and changed checksums for a published version. Remote divergence stops for reconciliation; it never force-pushes or overwrites release assets.

If the GitHub release does not yet exist, inspect the tag/push/release state and finish those commands from [release.sh](../scripts/release.sh) before running the helper. Release notes remain reviewed input, not an automatically published raw commit list.

Run `python3 scripts/test_release.py` for regression coverage with disposable Git repositories and fake Homebrew commands. These checks run in CI and before preparation; publication performs the real installed-binary checks.

## Packaging details

[package-release.py](../scripts/package-release.py) reads version and architecture from the built executable and packages the schema bundle, project license, [third-party notices](../THIRD_PARTY_NOTICES.md), pinned dependency licenses/notices and original FIGlet font notices. Archive headers omit local user and group identities.

The packager strips the symbol table—more than half of the unstripped file—and verifies the stripped ad-hoc signature. From the extracted archive outside the checkout, it checks version, help, guide and both report/diagnosis schema discovery. Releases retain default `-O` optimization: `-Osize` saved another 3.5 MB stripped but was declined on 2026-10-15.

When dependencies or optional skills change, update the notice index against [Package.resolved](../Package.resolved) and [skills.lock](../skills.lock), including SwiftTUI's vendored licenses and embedded font notices. Read licenses/notices at the locked revisions; a package license does not replace separately licensed bundled components. Inspect packaged `THIRD_PARTY_NOTICES.md` and `licenses/` before publishing.
