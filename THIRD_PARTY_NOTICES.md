# Third-party notices

Agent Monitor uses the third-party components below. Its own [MIT license](LICENSE) does not replace their licenses. This index identifies the pinned sources and their license texts; release archives also contain the original license and notice files under `licenses/`.

## Swift package dependencies

Versions and revisions come from [Package.resolved](https://github.com/mbackschat/agent-monitor/blob/main/Package.resolved), also included as `licenses/Package.resolved` in release archives. The links below identify the exact dependency revisions reviewed for this index.

| Component | Version and use | License and attribution | License file in release archive |
|---|---|---|---|
| [Swift Argument Parser](https://github.com/apple/swift-argument-parser/tree/6a52f3251125d74daf04fcbd5e6f08a75d074382) | 1.8.2; command-line parsing | [Apache 2.0 with Swift Runtime Library Exception](https://github.com/apple/swift-argument-parser/blob/6a52f3251125d74daf04fcbd5e6f08a75d074382/LICENSE.txt); Apple Inc. and the Swift project authors | `licenses/swift-argument-parser/LICENSE.txt` |
| [SwiftTUI](https://github.com/SwiftTUI/swift-tui/tree/581c3ab7e2383ce86fcebe36e81041aecac443a5) | 0.14.0; terminal interface | [MIT](https://github.com/SwiftTUI/swift-tui/blob/581c3ab7e2383ce86fcebe36e81041aecac443a5/LICENSE); Copyright (c) 2026 OPTIONAL.DEV | `licenses/swift-tui/LICENSE` |
| [Swift Async Algorithms](https://github.com/apple/swift-async-algorithms/tree/d0b4a06d0f173a2f3be27d3ea21b3c3aa18db440) | 1.1.4; transitive SwiftTUI dependency | [Apache 2.0 with Swift Runtime Library Exception](https://github.com/apple/swift-async-algorithms/blob/d0b4a06d0f173a2f3be27d3ea21b3c3aa18db440/LICENSE.txt); Apple Inc. and the Swift project authors | `licenses/swift-async-algorithms/LICENSE.txt` |
| [Swift Collections](https://github.com/apple/swift-collections/tree/35a1edcb8ebd2bfe251d587f0b69e62af28f508c) | 1.7.3; transitive SwiftTUI dependency | [Apache 2.0 with Swift Runtime Library Exception](https://github.com/apple/swift-collections/blob/35a1edcb8ebd2bfe251d587f0b69e62af28f508c/LICENSE.txt); Apple Inc. and the Swift project authors | `licenses/swift-collections/LICENSE.txt` |

## Components vendored by SwiftTUI

These copies are part of the pinned SwiftTUI revision, not separate entries in the SwiftPM lock file. The release packager preserves the notices for all of SwiftTUI's vendored components, including swift-gif, whose animated-image target is not used by Agent Monitor's executable.

| Component | License and attribution | Files under `licenses/swift-tui/Vendor/` in release archives |
|---|---|---|
| UnixSignals, derived from Swift Service Lifecycle | [Apache 2.0](https://github.com/SwiftTUI/swift-tui/blob/581c3ab7e2383ce86fcebe36e81041aecac443a5/Vendor/UnixSignals/LICENSE.txt); Copyright 2019–2023 The ServiceLifecycle Project. The [upstream notice](https://github.com/SwiftTUI/swift-tui/blob/581c3ab7e2383ce86fcebe36e81041aecac443a5/Vendor/UnixSignals/NOTICE.txt) also records SwiftNIO-derived Lock and LockedValueBox implementations and the signal definition moved into SwiftTUIPlatformIO. | `UnixSignals/LICENSE.txt`, `UnixSignals/NOTICE.txt` |
| swift-figlet package code | [MIT](https://github.com/SwiftTUI/swift-tui/blob/581c3ab7e2383ce86fcebe36e81041aecac443a5/Vendor/swift-figlet/LICENSE); Copyright (c) 2026 OPTIONAL.DEV | `swift-figlet/LICENSE` |
| FIGlet and TOIlet fonts | Individual embedded notices and terms in the [original font files](https://github.com/SwiftTUI/swift-tui/tree/581c3ab7e2383ce86fcebe36e81041aecac443a5/Vendor/swift-figlet/Fonts); these are not relicensed by swift-figlet's MIT license. | `swift-figlet/Fonts/`, preserved in full with original headers |
| swift-jpeg | [MIT](https://github.com/SwiftTUI/swift-tui/blob/581c3ab7e2383ce86fcebe36e81041aecac443a5/Vendor/swift-jpeg/LICENSE); Copyright (c) 2026 OPTIONAL.DEV | `swift-jpeg/LICENSE` |
| swift-png | [MIT](https://github.com/SwiftTUI/swift-tui/blob/581c3ab7e2383ce86fcebe36e81041aecac443a5/Vendor/swift-png/LICENSE); Copyright (c) 2026 OPTIONAL.DEV | `swift-png/LICENSE` |
| swift-gif | [MIT](https://github.com/SwiftTUI/swift-tui/blob/581c3ab7e2383ce86fcebe36e81041aecac443a5/Vendor/swift-gif/LICENSE); Copyright (c) 2026 OPTIONAL.DEV | `swift-gif/LICENSE` |

## Optional development skills

The optional installer downloads these skills at the revisions in [skills.lock](https://github.com/mbackschat/agent-monitor/blob/main/skills.lock), retaining their licenses in the ignored `.skill-sources/` checkouts. They are not included in the Agent Monitor executable or release archives.

| Skill | License and attribution |
|---|---|
| [Swift Concurrency](https://github.com/AvdLee/Swift-Concurrency-Agent-Skill/tree/d5770817d2622e1585b1f7eaebc791a9cb0959c8) | [MIT](https://github.com/AvdLee/Swift-Concurrency-Agent-Skill/blob/d5770817d2622e1585b1f7eaebc791a9cb0959c8/LICENSE); Copyright (c) 2026 Antoine van der Lee |
| [Swift Testing](https://github.com/AvdLee/Swift-Testing-Agent-Skill/tree/798e9b1a2bcac164d4f0c781908199e754f0bab6) | [MIT](https://github.com/AvdLee/Swift-Testing-Agent-Skill/blob/798e9b1a2bcac164d4f0c781908199e754f0bab6/LICENSE); Copyright (c) 2026 Antoine van der Lee |
| [SwiftUI View Refactor](https://github.com/steipete/agent-scripts/tree/9989fe852a3f63f3933a1bdc20b4a25321240759/skills/swiftui-view-refactor) | [agent-scripts MIT](https://github.com/steipete/agent-scripts/blob/9989fe852a3f63f3933a1bdc20b4a25321240759/LICENSE); Copyright (c) 2026 Peter Steinberger. The skill credits Dimillian's `Dimillian/Skills` (2025-12-31); its MV reference credits Thomas Ricouard. These attributions and reference files are retained in the checkout. |
| [SwiftUI Performance Audit](https://github.com/steipete/agent-scripts/tree/9989fe852a3f63f3933a1bdc20b4a25321240759/skills/swiftui-performance-audit) | [agent-scripts MIT](https://github.com/steipete/agent-scripts/blob/9989fe852a3f63f3933a1bdc20b4a25321240759/LICENSE); Copyright (c) 2026 Peter Steinberger. The skill credits Dimillian's `Dimillian/Skills` (2025-12-31) and retains Apple/WWDC reference material. |

## Redistribution

Preserve `LICENSE`, `THIRD_PARTY_NOTICES.md`, and the complete `licenses/` directory when redistributing a release archive. The original upstream texts govern each component; this index does not replace them. For a source-built binary distribution, use the repository's [release packaging instructions](https://github.com/mbackschat/agent-monitor/blob/main/docs/releasing.md) to collect these files from the resolved dependency checkouts.
