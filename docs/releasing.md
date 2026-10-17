# Releasing

Releases target Apple Silicon and macOS 27 with Xcode 27 and Swift 6.4. They are ad-hoc signed, not Developer ID signed or notarized; never describe them otherwise. Release notes live only on [GitHub Releases](https://github.com/mbackschat/agent-monitor/releases).

## Release in three steps

1. **Set the version.** Change `AgentMonitorVersion.current` in `Sources/AgentMonitorCore/Version.swift`, which feeds `--version`, the archive name and the Codex handshake, and commit it on `main`.
2. **Prepare.** Run `bash scripts/release.sh <version>`. It requires a clean `main` and an unused tag, runs the doctor, documentation, formatting, Swift test, preview and release terminal checks with the synthetic fixture (no live workloads or provider listings), builds and packages the release, and drafts `dist/notes-<version>.md` from the `feat`, `fix` and `perf` commits since the previous tag. Edit the draft: write the summary, group or reword the changes for users, and remove every `TODO`.
3. **Publish.** Run `bash scripts/release.sh <version> --publish`. It refuses a Git email that differs from the previous release's author, then tags, pushes `main` and the tag, creates the GitHub release with the archive, checksum and notes, downloads the published assets again and verifies checksum, version and schema. It then updates, audits, installs/tests and pushes the Homebrew formula automatically. Publishing refuses a changed HEAD or archive checksum after preparation.

Everything is written under ignored `dist/`, including the unstripped executable for symbolicating crash reports; keep it for every published version. To prepare again, delete `dist/agent-monitor-<version>-macos-arm64*`. If publishing stops partway, finish the remaining commands from `scripts/release.sh` by hand rather than rerunning it.

## Update Homebrew

The [Homebrew tap](https://github.com/mbackschat/homebrew-tap) owns the canonical formula. Publication calls [update-homebrew.py](../scripts/update-homebrew.py) with the released version. It reads the checksum from the published GitHub release, checks the tap remote, `main` branch and GitHub email, and updates only the versioned URL/checksum. It runs `brew audit --strict`, installs or upgrades the CLI, runs `brew test`, and checks the installed version, guides and both schema resources before committing and pushing. Homebrew auto-update and cleanup are disabled for this operation. The native app is not distributed through this formula.

If Homebrew fails after the GitHub release was published, fix the reported prerequisite and resume only that step:

```sh
python3 scripts/update-homebrew.py <version>
```

The helper accepts its own exact pending formula edit or one unpushed release commit, and a completed update is safe to repeat. It refuses unrelated working changes or unpushed commits, downgrades and changed checksums for a published version. Remote divergence stops for reconciliation; it never force-pushes or overwrites release assets. If publication fails before the GitHub release exists, inspect the tag/push/release state and finish those commands from [release.sh](../scripts/release.sh) before running the helper. Release notes remain reviewed input rather than automatically publishing a raw commit list.

Run `python3 scripts/test_release.py` for regression coverage using disposable Git repositories and fake Homebrew commands. These checks run in CI and before preparation; the real installed-binary checks run during publication.

## Packaging details

[package-release.py](../scripts/package-release.py) reads version and architecture from the built executable, includes the schema bundle, project license, [third-party notice index](../THIRD_PARTY_NOTICES.md), pinned dependency licenses/notices and original FIGlet font notices, and omits local user and group identities from archive headers. It strips the symbol table, which is more than half of the unstripped file, verifies the stripped ad-hoc signature, and checks version, help, guide and both report/diagnosis schema discovery from the extracted archive outside the source checkout. Releases keep the default `-O` optimization: building for size (`-Osize`) saved a further 3.5 MB stripped but was declined on 2026-10-15.

When dependencies or optional skills change, update the third-party index against [Package.resolved](../Package.resolved) and [skills.lock](../skills.lock), including SwiftTUI's vendored licenses and embedded font notices. Read license and notice files at the locked revisions; a package-level license does not replace separately licensed bundled components. Inspect the packaged `THIRD_PARTY_NOTICES.md` and `licenses/` directory before publishing.
