# Releasing

Releases target Apple Silicon and macOS 27 with Xcode 27 and Swift 6.4. They are ad-hoc signed, not Developer ID signed or notarized; never describe them otherwise. Release notes live only on [GitHub Releases](https://github.com/mbackschat/agent-monitor/releases).

## Release in three steps

1. **Set the version.** Change `AgentMonitorVersion.current` in `Sources/AgentMonitorCore/Version.swift`, which feeds `--version`, the archive name and the Codex handshake, and commit it on `main`.
2. **Prepare.** Run `bash scripts/release.sh <version>`. It requires a clean `main` and an unused tag, runs the doctor, documentation, formatting, Swift test, preview and release terminal checks, builds and packages the release, and drafts `dist/notes-<version>.md` from the `feat`, `fix` and `perf` commits since the previous tag. Edit the draft: write the summary, group or reword the changes for users, and remove every `TODO`.
3. **Publish.** Run `bash scripts/release.sh <version> --publish`. It refuses a Git email that differs from the previous release's author, then tags, pushes `main` and the tag, creates the GitHub release with the archive, checksum and notes, downloads the published assets again and verifies checksum, version and schema. It prints the Homebrew URL and SHA-256.

Everything is written under ignored `dist/`, including the unstripped executable for symbolicating crash reports; keep it for every published version. To prepare again, delete `dist/agent-monitor-<version>-macos-arm64*`. If publishing stops partway, finish the remaining commands from `scripts/release.sh` by hand rather than rerunning it.

## Update Homebrew

The [Homebrew tap](https://github.com/mbackschat/homebrew-tap) owns the canonical formula. Set its URL and SHA-256 to the printed values; keep published release assets immutable. Run `brew audit --strict mbackschat/tap/agent-monitor`, upgrade or install, and run `brew test mbackschat/tap/agent-monitor` before pushing the formula. Keep its architecture and macOS requirements aligned with the binary.

## Packaging details

[package-release.py](../scripts/package-release.py) reads version and architecture from the built executable, includes the schema bundle, project license, [third-party notice index](../THIRD_PARTY_NOTICES.md), pinned dependency licenses/notices and original FIGlet font notices, and omits local user and group identities from archive headers. It strips the symbol table, which is more than half of the unstripped file, verifies the stripped ad-hoc signature, and checks version, help and schema discovery from the extracted archive outside the source checkout. Releases keep the default `-O` optimization: building for size (`-Osize`) saved a further 3.5 MB stripped but was declined on 2026-10-15.

When dependencies or optional skills change, update the third-party index against [Package.resolved](../Package.resolved) and [skills.lock](../skills.lock), including SwiftTUI's vendored licenses and embedded font notices. Read license and notice files at the locked revisions; a package-level license does not replace separately licensed bundled components. Inspect the packaged `THIRD_PARTY_NOTICES.md` and `licenses/` directory before publishing.
