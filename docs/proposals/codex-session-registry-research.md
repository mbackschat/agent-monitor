# Codex session listing: research brief

Status: investigated 2026-10-16 against Codex CLI and the live default app-server 0.163.0; no implementation is authorized. Findings and unresolved empirical limits are in [Codex process and session identities](../research/codex-terminal-attribution.md#session-listing-investigation--2026-10-16), indexed in the [research index](../research/README.md). The separate [registry assessment](codex-session-registry.md) records accepted deferral because the available listings lack the required native process relation. The original questions and limits below retain the investigation scope.

## Why

Claude runtimes now bind to their sessions through `claude agents --json` (the [harness session registry](../architecture.md#harness-session-registries)). Codex already binds a runtime holding exactly one thread writer descriptor, and marker-less children below it, with `writerLock` evidence. Two Codex cases remain unresolved:

- A **shared runtime** with several writer descriptors, such as an app-server hosting several threads, is labeled “Shared runtime” and stays ambiguous.
- Its children without a readable marker, such as Apple platform binaries (`/bin/zsh`, `/bin/sleep`) whose environment macOS does not expose, stay ambiguous too.

## Questions

1. Does the installed Codex CLI offer a non-interactive, read-only listing of live runtimes and their threads with kernel PIDs, comparable to `claude agents --json`? Check subcommands and `--help` first, then app-server methods such as loaded-thread or background-terminal listings. The [existing research](../research/codex-terminal-attribution.md) found background-terminal `osPid` documented as nullable; establish whether it is populated in the current release.
2. If a listing exists, does it map a **runtime PID to sessions** (fits the existing `RuntimeSession` facet; a shared runtime would still list several threads and stay unbound) or a **process PID to a thread** (could resolve children inside a shared runtime, but needs a new contract shape)? Describe the needed shape; do not implement it.
3. What does one call cost (wall time, CPU), and what are its side effects: network connections, started daemons or app servers, authentication prompts, writes under `~/.codex`, effects on running sessions? Is there a documented way to suppress nonessential network traffic?
4. Is the interface documented and versioned, or observed only? Pin source revisions and CLI versions.
5. Do `codex exec`, IDE- or desktop-hosted runtimes and `app-server proxy` sessions appear in the listing?

## Method and limits

Read-only observation of the installed CLI and pinned sources. Do not read transcripts, start turns, send messages, or connect to existing sessions beyond documented read-only listing calls. Start disposable sessions only with the user's explicit approval. Keep dated observations, sources and labeled inferences in the research note; put any design recommendation in a new proposal.
