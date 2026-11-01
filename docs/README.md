# Documentation index

Start with the [project README](../README.md) for a quick introduction and screenshots. Choose a guide by what you need to do.

## Use Agent Monitor

| Task | Start here |
| --- | --- |
| Install a release or build from source | [Installation](installation.md) |
| Find a coding agent's workload, read the charts or inspect a process | [Usage](usage.md), with [focused guides](usage/README.md) for the terminal, Mac app, CLI, measurements and actions |
| Understand what the product must make clear | [Product contract](product.md) |
| Check known limitations or unfinished work | [Validation coverage](development.md#validation-coverage) and [project plan](../PLAN.md) |

## Develop and release

| Task | Start here |
| --- | --- |
| Build, change code and select checks | [Development](development.md) and its [reference guides](development/README.md) |
| Understand subsystem ownership and accepted behavior | [Architecture](architecture.md) and its [detailed contracts](architecture/README.md) |
| Prepare a version and update release assets | [Releasing](releasing.md) |
| Review the deferred SwiftTUI follow-up | [Upstream follow-up](swifttui-upstream-follow-up.md) |

## Trace evidence and decisions

| Question | Record |
| --- | --- |
| What was observed, when, and with what limitations? | [Research](research/README.md) |
| Which designs are under review or approved but still open? | [Proposals](proposals/README.md) |
| What was deferred, rejected or superseded, and why? | [Decisions](decisions/README.md) |

Each documentation folder has an index. Proposal and decision status tables are generated; maintain them through the [documentation workflow](development.md#documentation-and-instruction-maintenance).

`assets/` holds generated documentation images. Change their generators as described in [preview maintenance](development.md#readme-preview); update the tracked Mac preview only for releases.
