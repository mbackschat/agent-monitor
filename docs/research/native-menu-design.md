# Native menu bar interface references

Observed 2026-10-15. Apple guidance was read on that date; upstream repositories were inspected at the revisions below. Screenshots are repository examples, not proof of current runtime behavior, dimensions or accessibility. No upstream app was executed and no source or image was vendored.

## Apple guidance

| Source | Finding |
| --- | --- |
| [The menu bar](https://developer.apple.com/design/human-interface-guidelines/the-menu-bar) | Prefer a menu for a menu bar extra; a popover is an exception for functionality too complex for a menu. Use a recognizable template icon or symbol. Extras can be hidden by the system, so their position and continued visibility are not guaranteed. |
| [Popovers](https://developer.apple.com/design/human-interface-guidelines/popovers) | Keep the surface focused on a few related tasks and size it to its contents. Avoid stacked popovers. Automatic dismissal must preserve work; discarding changes should require explicit cancellation. Detachability is optional. |
| [Disclosure controls](https://developer.apple.com/design/human-interface-guidelines/disclosure-controls) | Disclose secondary details while keeping essential information visible. A disclosure triangle expresses a hierarchy. The restriction on multiple disclosure buttons concerns the push-style control, not every triangle in an outline. |
| [DisclosureGroupStyle](https://developer.apple.com/documentation/swiftui/disclosuregroupstyle) | Apple's custom-style example wraps the label in a button and gives it a rectangular content shape. This supports a larger click target than the triangle alone. |
| [Labels](https://developer.apple.com/design/human-interface-guidelines/labels), [typography](https://developer.apple.com/design/human-interface-guidelines/typography), [accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility) | Prefer system typography, concise labels and semantic text colors. macOS text-size guidance differs from touch platforms; compactness still requires legibility, sufficient contrast and accessible controls. |
| [Designing for macOS](https://developer.apple.com/design/human-interface-guidelines/designing-for-macos), [layout](https://developer.apple.com/design/human-interface-guidelines/layout) | Comfortable density, alignment and limited navigation depth suit precise pointing. Keyboard access, localization and changing content remain relevant even in a small surface. |

## Inspected repositories and screenshots

| Repository | Pinned revision | Visually inspected examples |
| --- | --- | --- |
| [Peter Steinberger's CodexBar](https://github.com/steipete/CodexBar) — coding-provider usage in the menu bar | [`a8eb7b8c4cd4ed00f8483831a78a9f4368145c79`](https://github.com/steipete/CodexBar/tree/a8eb7b8c4cd4ed00f8483831a78a9f4368145c79) | [Full menu](https://github.com/steipete/CodexBar/blob/a8eb7b8c4cd4ed00f8483831a78a9f4368145c79/docs/codexbar.png), [compact accounts](https://github.com/steipete/CodexBar/blob/a8eb7b8c4cd4ed00f8483831a78a9f4368145c79/docs/screenshots/claude-multi-account-compact-after.png) |
| [RepoBar](https://github.com/steipete/RepoBar) — repository activity and actions | [`ccc5912cade7ebb2d456d43b71f9cace96431841`](https://github.com/steipete/RepoBar/tree/ccc5912cade7ebb2d456d43b71f9cace96431841) | [Repository rows and submenus](https://github.com/steipete/RepoBar/blob/ccc5912cade7ebb2d456d43b71f9cace96431841/docs/assets/repobar.png) |
| [Trimmy](https://github.com/steipete/Trimmy) — cleanup of copied terminal commands | [`0a219a7eb9c3f69d004e0e486ffc8c52db9059d7`](https://github.com/steipete/Trimmy/tree/0a219a7eb9c3f69d004e0e486ffc8c52db9059d7) | [Actions and text previews](https://github.com/steipete/Trimmy/blob/0a219a7eb9c3f69d004e0e486ffc8c52db9059d7/trimmy-screenshot.png) |

CodexBar's screenshots distinguish prominent provider/metric labels from subdued update/reset metadata and align complementary values across a row. The compact-account example retains identity and a small numeric/bar summary while revealing more information for the active account. Its [compact row source](https://github.com/steipete/CodexBar/blob/a8eb7b8c4cd4ed00f8483831a78a9f4368145c79/Sources/CodexBar/MenuCardCompactAccountRow.swift) uses semantic fonts, monospaced numeric values and five points of vertical padding. Its [metric row](https://github.com/steipete/CodexBar/blob/a8eb7b8c4cd4ed00f8483831a78a9f4368145c79/Sources/CodexBar/MenuCardMetricRow.swift) omits supplemental reset/detail text in compact mode. Compactness comes partly from choosing information, not merely shrinking type.

CodexBar's [UI notes](https://github.com/steipete/CodexBar/blob/a8eb7b8c4cd4ed00f8483831a78a9f4368145c79/docs/ui.md) describe custom hosted menu content, pointer highlighting, keyboard selection and native menu scrolling. They also document rendering workarounds and background icon updates. These are evidence of platform-specific engineering, not proof that Agent Monitor should inherit its polling or hosting architecture.

RepoBar's screenshot shows repeated aligned repository summaries, subdued metadata, a full-row selection highlight and actions in submenus. Its [menu hosting](https://github.com/steipete/RepoBar/blob/ccc5912cade7ebb2d456d43b71f9cace96431841/Sources/RepoBar/StatusBar/MenuItemHosting.swift) explicitly passes highlight state into hosted SwiftUI content. [MenuStyle](https://github.com/steipete/RepoBar/blob/ccc5912cade7ebb2d456d43b71f9cace96431841/Sources/RepoBar/Support/MenuStyle.swift) centralizes padding/spacing, including six-point card vertical padding. The screenshot's multiple submenu levels are an observed product choice, not an Apple requirement.

Trimmy's screenshot puts useful actions first, adds subordinate text previews and separates the toggle, settings/about and quit groups. Its [menu content](https://github.com/steipete/Trimmy/blob/0a219a7eb9c3f69d004e0e486ffc8c52db9059d7/Sources/Trimmy/MenuContentView.swift) uses caption-sized monospaced previews and compact padding. It illustrates command hierarchy more directly than a monitoring table.

## Inferences for Agent Monitor

CodexBar is the closest visual reference: concise identity, aligned metrics, subordinate metadata and progressive disclosure fit process/session monitoring. RepoBar supplies a useful comparison for repeated status rows; Trimmy supplies one for command grouping. This does not imply copying their colors, pixel dimensions, submenu depth or background behavior.

The inline message editor and action review provide a concrete reason to use Apple's complex-content exception for a transient popover. A two-line process summary can retain process/PID/CPU on the first line and project/session/footprint on the second without a repeated singleton group heading. Whole-row disclosure follows the user's interaction requirement and Apple's custom-style example. These are project design judgments, not dimensions mandated by Apple.

## Unresolved empirical questions

- Does the live panel remain legible with long names, localized numbers, light/dark appearance and accessibility settings? Offscreen size assertions do not establish VoiceOver order, keyboard navigation or contrast on a real desktop.
- Does the fixed-height panel leave unnecessary empty space with sparse data? Apple's content-fitting guidance makes this a separate concern from row spacing.
- Does automatic dismissal preserve an unsent message? The current close path resets the action panel, so draft loss is a concrete mismatch with Apple's guidance; safe recipient revalidation would still be necessary before sending a restored draft.
- Do native menu-like highlighting, focus and dismissal behave as expected? Upstream screenshots and source do not establish our app's behavior.

Accepted behavior belongs in [architecture](../architecture.md#native-menu-bar-app); pending work belongs in [PLAN.md](../../PLAN.md).

## Content sizing API observations — 2026-10-15

Apple's [NSPopover.contentSize](https://developer.apple.com/documentation/appkit/nspopover/contentsize) documentation says the initial content size matches the content view when its controller is assigned. [NSHostingController.sizingOptions](https://developer.apple.com/documentation/swiftui/nshostingcontroller/sizingoptions) controls generated sizing constraints; Apple notes that fewer options reduce layout measurements when the host can make size assumptions. The [preferred-content-size option](https://developer.apple.com/documentation/swiftui/nshostingsizingoptions/preferredcontentsize) concerns the ideal size and requires hosting-controller constraints; it does not apply directly to `NSHostingView`. [Size-based scroll bounce](https://developer.apple.com/documentation/swiftui/scrollbouncebehavior/basedonsize) applies only when content exceeds the viewport.

The subsequent [sizing experiment](development-tools.md#content-sizing-application--2026-10-15) distinguishes source guidance from observed offscreen behavior. The original fixed-height and draft-loss observations above describe the pre-change implementation; current accepted behavior is in [architecture](../architecture.md#native-menu-bar-app).


## Fixed-height clarification — 2026-10-15

The user explicitly requested a stable panel height with optional user resizing, and a freeze control for inspecting rows that reorder. This is a distinct requirement from compact row spacing. Apple's general content-fitting guidance does not establish that a continuously updating process list should resize its outer panel on each membership/disclosure change. The [accepted contract](../architecture.md#native-menu-bar-app) now uses explicit height presets and shared snapshot pause; earlier content-sizing observations above retain their historical context.


## Pin controls and keyboard intent — 2026-10-15

Apple's [keyboard guidance](https://developer.apple.com/design/human-interface-guidelines/keyboards/) describes consistent standard shortcuts, and [focus and selection guidance](https://developer.apple.com/design/human-interface-guidelines/focus-and-selection/) distinguishes keyboard focus and selection. Search-visible official excerpts were available during this review; fetching the full linked Markdown pages failed in the browser tool, so this is not a fresh complete-page audit.

Inference: a keyboard command aimed at the hovered row can conflict with the focused control. A dedicated native Pin button and context-menu command make the target explicit while preserving whole-row disclosure. The user selected Space for TUI Pin/Unpin and `p` for Pause, superseding the earlier proposed `i` key; PID sorting moved to `n` to remove the collision. Native Space retains focused-button activation. Live keyboard and VoiceOver behavior remain empirical checks, independently of the model and offscreen rendering tests.

## Readable load icon — 2026-10-15

The user rejected a thin sparkline as potentially illegible on large displays and selected three thick load bars with a brief new-heavy highlight. This is a user readability requirement, not an empirically established superiority over sparklines. The current scale and highlight semantics are in [architecture](../architecture.md#native-menu-bar-app).

The installed macOS 27 SDK's `NSButton.h` describes `contentTintColor` as tinting template image/text content on borderless buttons; `NSImage.h` describes template images as black/clear images processed into context-appropriate variants. The official [template-image page](https://developer.apple.com/documentation/appkit/nsimage/istemplate) and [status-item length page](https://developer.apple.com/documentation/appkit/nsstatusitem/length) were consulted, but the browser exposed JavaScript placeholders and could not fetch their linked Markdown versions. The SDK headers are the directly inspected API evidence for this change. A simultaneous underline supplies a non-color cue; actual contrast and readability across displays remain live checks.

## Built-in popover detachment — 2026-10-15

Apple’s [`popoverShouldDetach(_:)` documentation](https://developer.apple.com/documentation/appkit/nspopoverdelegate/popovershoulddetach(_:)) states that returning true without a custom detachable window lets AppKit reuse the popover’s content controller. It also states that closing the detached popover delivers the normal close callbacks. Source inspection found the host already used an NSPopover delegate and explicitly returned false. Inference: enabling implicit detachment preserves the current content and close lifecycle without a second window implementation. Physical dragging, closing and reopening have not been exercised through computer control.
