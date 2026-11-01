# Decisions

These records preserve settled questions that were deferred, rejected or superseded. Each states the decision, its reason and the conditions for reconsideration; new implementation needs the applicable authorization.

The full earlier proposal remains in Git history:

```sh
git log --follow docs/decisions/<record>.md
```

Use the [documentation lifecycle](../development.md#documentation-and-instruction-maintenance) when retiring or reopening a proposal.

The table is generated from each record's `Status:` line; do not edit it by hand.

<!-- status-table:begin -->
| Decision | Status | Since |
| --- | --- | --- |
| [Claude detached-workload link through `CLAUDE_PID`](claude-detached-runtime-link.md) | deferred | 2026-10-16 |
| [Codex session registry integration](codex-session-registry.md) | deferred | 2026-10-16 |
| [Menu bar app: login item, distribution and shared collector](menubar-product-scope.md) | deferred | 2026-10-15 |
| [Recovering CPU of exited descendants](exited-descendant-cpu.md) | deferred | 2026-10-16 |
| [Resource overview extensions](resource-overview-extensions.md) | deferred | 2026-10-24 |
| [Contributor overview alternatives](contributor-overview-alternatives.md) | rejected | 2026-10-28 |
| [Privileged resource tracing](privileged-resource-tracing.md) | rejected | 2026-10-26 |
| [SwiftTUI fork](swifttui-fork.md) | rejected | 2026-10-26 |
<!-- status-table:end -->
