# Releasing

## Build and verify

Releases target Apple Silicon and macOS 27. Use Xcode 27 with Swift 6.4. Before packaging, run the tests and formatting checks in the [development guide](development.md#build-and-verify).

The first publication also requires an owner-selected project license and a review of every commit being pushed for private validation identifiers. The packaging script requires the root `LICENSE`; dependency licenses do not license this project's code.

The release version lives in `AgentMonitorVersion.current` (`Sources/AgentMonitorCore/Version.swift`) and feeds both `--version` and the Codex handshake. Update it and the version behavior test together for a new release. The tag and archive version must match the executable's `--version` output.

```sh
swift build -c release -debug-info-format none
uv run scripts/package-release.py .build/release
```

The packaging script requires Python 3.12 or later, reads the version and architecture from the built executable, and includes its schema bundle, project license, [third-party notice index](../THIRD_PARTY_NOTICES.md), pinned dependency licenses/notices, and original FIGlet font notices. Archive headers omit the build machine's user and group identities. It strips the packaged executable's symbol table, which is more than half of the unstripped file, and verifies that the result is stripped and validly ad-hoc signed; keep the unstripped `.build/release/agent-monitor` of a published version to symbolicate crash reports. Releases keep the default `-O` optimization: building for size (`-Osize`) saved a further 3.5 MB stripped, but was declined on 2026-10-15. It extracts the resulting archive and verifies version, help, and schema discovery outside the source checkout. It refuses to overwrite an existing archive.

When changing dependencies or optional skills, update the third-party index against [Package.resolved](../Package.resolved) and [skills.lock](../skills.lock), including SwiftTUI's vendored licenses and embedded font notices. Read the license and notice files at the locked revisions; a package-level license does not replace separately licensed bundled components. Inspect the packaged `THIRD_PARTY_NOTICES.md` and `licenses/` directory before publication.

Artifacts are written under ignored `dist/`: a versioned `.tar.gz` and its SHA-256 checksum. Review the archive contents and run the release terminal check from the development guide before publication. The first release is ad-hoc signed and not notarized; do not describe it as Developer ID signed or notarized.

## Publish

Commit the validated source and release documentation, tag that commit with `v` followed by the CLI version, and push the branch and tag. Check the Git author email against the target remote before pushing. Create the GitHub release from that existing tag and upload both generated assets. Use [release notes](releases/0.1.0.md) as the initial format, updating capabilities and verification for each version.

After publication, download the assets from GitHub into a fresh directory, check the checksum, and repeat version/schema checks against the extracted executable. Confirm the repository visibility, tag commit, and README download link.

## Update Homebrew

The [Homebrew tap](https://github.com/mbackschat/homebrew-tap) owns the canonical formula. After publishing a new archive, update its versioned URL and SHA-256; keep existing release assets immutable. Run `brew audit --strict mbackschat/tap/agent-monitor`, verify installation or upgrade, and run `brew test mbackschat/tap/agent-monitor` before pushing the formula. The installed schema check guards the required resource bundle beside the executable. Keep the formula's architecture/macOS requirements aligned with the published binary.
