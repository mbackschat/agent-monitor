# SwiftTUI upstream issue follow-up

Deferred follow-up, recorded 2026-10-26 at the user's request. Prepare reviewable GitHub issue drafts later; do not open issues, contact maintainers, change the dependency or create a fork as part of this task. No issues have been filed. [PLAN.md](../PLAN.md#existing-validation-follow-ups) owns scheduling; the [no-fork decision](decisions/swifttui-fork.md) remains binding.

## Preserve these inputs

- [Source findings](research/terminal-ui.md#ordered-input-and-retention-boundary--2026-10-26): native read accumulation, partial decoding, reader/wrapper streams, queued and drained events, and paste/key ordering.
- [Upstream comparison](research/terminal-ui.md#upstream-0160-comparison): 0.16.0 has internal WebHost admission machinery but does not close the inspected native/custom-host path.
- [Proposed contract](proposals/bounded-terminal-input.md): required behavior, proposed numeric limits, oversized-paste policy, cancellation and exclusions. This remains the single source for the proposed changes; it is not an implemented guarantee.

Evidence was read from SwiftTUI 0.14.0 (`581c3ab7e2383ce86fcebe36e81041aecac443a5`), 0.16.0 (`9ef8feec9fee6fc199767a52aa1c913976bdb2c9`) and Agent Monitor `e798ec9`. These findings are source-derived. No dedicated backlog reproduction or heap measurement has established their practical magnitude. Recheck upstream before drafting; these revisions must not be presented as the latest release indefinitely.

## Recommended issue split

Prepare two related issues. Retention needs one end-to-end contract, so avoid separate fixes that merely move the backlog between queues. Ordered host paste dispatch is a distinct public-API request and can be reviewed independently. Link the issues if filed, and follow upstream's preferred split if maintainers identify a better ownership boundary.

### TUI-UPSTREAM-01 — Bound native terminal input through dispatch

**Candidate type:** bug report with a proposed backpressure contract.

**Problem:** a stalled dispatcher can leave input accumulating in raw-read turns, incomplete paste/control sequences, the native reader's stream and runtime event batches. An event-count-only limit cannot bound one large paste. A queue-only limit misses drained-but-undispatched events.

**Changes to request:**

- Bound native read turns and partial decoding, including paste payload bytes and local decoded-event arrays.
- Reserve both event count and payload bytes until dispatch completes; pause upstream production when capacity is exhausted.
- Preserve accepted command and confirmation events in FIFO order. Do not substitute dropping stream buffers for backpressure.
- Reject oversized paste visibly and discard through its terminator with bounded framing state, without interpreting the discarded content as commands. Handle split markers and incomplete EOF explicitly.
- Wake blocked producers on cancellation, deregister native sources before terminal restoration, and prevent late dispatch into a replacement session.
- Consider extending the existing internal admission machinery to native/custom-host input rather than creating a parallel mechanism. Keep the current AsyncStream signature if pull production can satisfy the contract.

**Evidence to prepare later:** a finite fake-reader/dispatcher reproduction that stalls handling, observes upstream advancement and reservations, then releases the stall and checks exact FIFO delivery without duplicates or loss. Cover cancellation while blocked and split, oversized and unterminated paste containing command-looking bytes. Record only synthetic inputs and aggregate assertions; an allocated-byte ceiling requires separate measurement, not inference from event counts.

### TUI-UPSTREAM-02 — Expose ordered paste dispatch for custom hosts

**Candidate type:** public-API enhancement motivated by a host integration defect.

**Problem:** Agent Monitor intercepts paste in its reader adapter because the inspected public custom-host RunLoop seam exposes a key handler without an equivalent paste callback. Its producer-side paste mutation can overtake an earlier key queued for runtime dispatch. Attribute that defect to Agent Monitor's adapter; do not claim that SwiftTUI's built-in text controls reorder paste.

**Change to request:** a public typed paste/input handler invoked from the same ordered dispatch path as keys. It must allow a custom host to consume a paste as text without synthesizing command key presses. Preserve normal focused-control routing when the host does not consume the event. Do not prescribe a private registry hook or a terminal-framework replacement.

**Evidence to prepare later:** queue a phase-changing key, paste and another key behind a gated consumer. Check the host observes their original order and applies text to the phase current at dispatch. Include Return, Escape and Ctrl-Y inside paste to establish that content cannot activate commands. After an official API is available, remove Agent Monitor's producer-side paste mutation and test the production host composition.

## Later execution checklist

1. Recheck the official release/source and search for existing upstream issues; attach to an existing report where appropriate instead of duplicating it.
2. Prepare bounded deterministic reproductions and separate verified behavior from source inference. No live workloads, provider calls or large terminal stress run are needed for the initial drafts.
3. Write concise issue bodies with exact revisions, minimal reproduction, expected/actual behavior, impact and the proposed contract. Treat Agent Monitor's numeric limits as suggested host policy, not universal SwiftTUI requirements.
4. Review the drafts before any publication. Preparing this follow-up does not authorize posting or contacting maintainers.
5. If issues are subsequently filed, record their URLs here and in PLAN. Evaluate any official fix against both issue contracts before changing the pin; update notices and run the affected production-composition tests.

These issues concern TUI input retention and correctness. They do not resolve sampler CPU cost, short-worker measurement loss, Mac interaction acceptance or a whole-process heap ceiling.
