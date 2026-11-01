# Architecture guides

Start with the [architecture overview](../architecture.md) for system boundaries and resource-visibility priorities. Use these guides when changing a subsystem; the [product contract](../product.md) defines the information users must be able to understand.

| Task | Contract |
| --- | --- |
| Change CPU or memory accounting | [CPU and memory accounting](accounting.md) |
| Change acquisition scheduling or adaptation | [Acquisition and adaptive sampling](acquisition.md) |
| Change display cadence or bounded delivery | [Display windows and bounded delivery](display-windows.md) |
| Add attribution evidence or provider support | [Attribution and offline runtime](attribution.md) |
| Change diagnosis or verified actions | [CPU diagnosis and verified actions](diagnosis-actions.md) |
| Change grouping, selection, disclosure or pins | [Shared presentation state](presentation-state.md) |
| Change terminal rendering or input | [Terminal presentation and host](terminal.md) |
| Change contributor ranking, hierarchy or history | [Contributor overview and resource history](contributors.md) |
| Change native lifecycle, controls or status icon | [Native app lifecycle and interaction](native-app.md) |

For executable checks, use [development](../development.md). For controls and examples, use [usage](../usage.md). Open implementation and acceptance work belongs in [PLAN](../../PLAN.md).
