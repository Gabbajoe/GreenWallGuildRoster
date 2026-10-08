# Hardware-event pass-through plan

Status: phase 1 released as 1.2.0; initial guild-chat spike passed on 2026-09-29; phase-2 sender complete for 1.3.0; Nils confirmed in-game testing and requested regular publication on 2026-10-09
Scope: self-contained GreenWallGuildRoster sender; GreenWall is the only addon dependency

## Goal

Remove the mandatory initial Broadcast popup/click when a real user chat action
can safely carry one pending GreenWallGuildRoster frame. The user's original
chat message must remain untouched and must always be sent first. No timer,
login event, roster event, incoming chat message, or unrelated UI click may be
treated as authorization to call GreenWall's protected `SendChatMessage` path.

The existing manual Broadcast button and presence-confirmed whisper sync remain
available. Pass-through improves first contact and refresh opportunities; it
does not replace the safe whisper transport.

## Constraints confirmed from the current code

- `GreenWallAPI.SendMessage` ultimately uses protected `SendChatMessage` on a
  custom channel.
- It succeeds only inside a genuine hardware-event call stack.
- GreenWall's current supported chat path confirms that the active chat edit
  boxes are the relevant UI surface. For the broker, an `OnEnterPressed`
  post-hook is preferred over `ParseText`: it preserves the invariant that the
  user's own message is processed first.
- GreenWall may take several seconds to join its configured channel. Nothing
  may be armed until `GreenWallAPI.GetChannelNumbers()[1]` is greater than zero.
- GreenWall base64/framing overhead leaves materially less than the nominal
  255-byte channel limit. The existing conservative raw roster budget is 140
  bytes before adding any new transaction header.
- Quiet users may produce no eligible hardware event. Automatic correctness
  therefore cannot depend exclusively on pass-through.

## Architecture

GreenWallGuildRoster owns its chat adapter and bounded queue internally.
`Core/HardwareBroker.lua` supplies the queue, `Core/HardwareChat.lua` installs
supported chat edit-box hooks, and `Core/PassThrough.lua` owns transaction
framing, retries, echo correlation and snapshot commit. The queue interface
is held in the private addon namespace; no global sender API is exposed.
GuildMap GreenWall is not involved. There must be no shared queue, hooks,
producer registration or cross-addon sender API between these addons. This
independence was explicitly required on 2026-09-29.

Queue rules:

- validate the sending addon ID against installed TOC names;
- bound item count, payload bytes and lifetime;
- deduplicate by `(ownerAddon, key)`;
- expire stale work; never persist payloads across logout/reload;
- submit at most one frame per eligible user chat action;
- call `GreenWallAPI.SendMessage` synchronously;
- guard against recursion while GreenWall sends its frame;
- treat submission as best effort; require producer echo for confirmation;
- suspend on channel loss or combat lockdown, keeping frames out of
  GreenWall's own deferred combat queue.

Only a supported chat edit box `OnEnterPressed` post-hook is eligible. The
broker must not flush from the global `SendChatMessage` hook, because that hook
also observes addon-originated and deferred sends that have already caused
`ADDON_ACTION_BLOCKED` in live testing. Before building the queue, a minimal
live spike must prove that the post-hook still retains the hardware-event
permission on the target Classic client; if it does not, the design stops and
does not fall back to consuming unrelated clicks.

## GreenWallGuildRoster two-phase rollout

The rollout is deliberately split. Phase 2 must not ship before Phase 1 has
been live-tested and deployed, because a partially received full roster must
not be mistaken for a complete snapshot.

### Phase 1: prepare, receive, and remain backward compatible

No automatic pass-through sends yet.

1. Extract roster collection into a side-effect-free `PrepareSnapshot` step.
   It returns frozen rows plus the proposed next values for `lastOnlineSet`,
   `lastKnownMembers`, `missingStreak`, and `lastFullSyncTime`.
2. Add explicit `CommitSnapshot` and `AbortSnapshot` operations. Collection
   must no longer advance sync state before transport acceptance.
3. Add a bounded outbound transaction object:
   transaction ID, kind (`full`/`delta`), chunks, next chunk, created/expiry
   times, retry count, and proposed commit state.
4. Add a versioned transaction wire format with `BEGIN`, numbered `DATA`, and
   `COMMIT`. Recalculate the data budget after the complete GreenWall frame;
   start conservatively at no more than 120 raw payload bytes.
5. Add receiver staging keyed by `(source tag, sender, transaction ID)`.
   Apply nothing until all numbered chunks and `COMMIT` are present.
6. Bound staged transactions by count, byte total, chunk count, and TTL. Reject
   malformed indices, duplicate-conflicting chunks, oversized rows and unknown
   guild tags. Identical duplicate chunks remain idempotent.
7. Continue accepting the current legacy `tag#payload` frames.
8. Continue sending the current legacy format from the manual Broadcast button.
9. Advertise transaction capability through the existing version/presence
   exchange, but do not require it yet.
10. Add status counters: prepared, staged, committed, aborted, expired,
    pass-through queued/submitted/echoed, legacy fallback, and queue depth.

Phase-1 acceptance:

- old sender to new receiver still works;
- new manual sender to old receiver still works;
- incomplete transaction changes no visible roster data;
- out-of-order and duplicate chunks commit exactly once;
- reload discards staged/outbound transactions without corrupting sync state;
- current whisper sync and local-guild fan-out remain unchanged;
- no protected-action errors are introduced.

### Phase 2: enable optional pass-through sending

1. Use the internal queue and wait until `IsReady()` confirms GreenWall's actual
   guild channel is joined.
2. Prepare an initial full snapshot, but do not commit local sync bookkeeping.
3. Enqueue one transaction frame at a time. Each genuine user chat send may
   submit at most one frame; the original user message is never delayed.
4. Correlate GreenWall's own `echo=true` API callback with the submitted frame.
   Advance only after echo. On timeout, retain a bounded retry for a later
   eligible event; never retry from a timer.
5. Commit the prepared snapshot only after the complete transaction is echoed.
   Update `lastBroadcast` at commit, not enqueue time.
6. Use transaction format only for a peer guild with confirmed capability.
   Until then retain legacy/manual introduction and whisper sync. Do not
   dual-send every snapshot indefinitely.
7. Add an option enabled by default: `Use safe chat pass-through when
   available`. Turning it off restores today's fully manual behavior.
8. Keep the Broadcast button as an explicit synchronous fallback and as a way
   to flush a complete snapshot immediately.

Phase-2 acceptance:

- logging in alone sends nothing;
- timers and roster events only prepare/enqueue work and never call
  `GreenWallAPI.SendMessage`;
- the first eligible typed chat after channel join submits exactly one frame;
- unrelated addon-originated guild/death messages submit nothing;
- a multi-chunk snapshot advances by one frame per later user chat action;
- silence leaves work queued without errors or stolen clicks;
- channel loss pauses the queue and channel recovery resumes it;
- manual Broadcast continues to work with the chat sender disabled;
- mixed old/new GuildRoster clients converge through compatibility fallback.

## What pass-through does not change

- Presence-confirmed whispers remain the normal paced background sync.
- Local `GUILD` addon-message fan-out remains automatic and hardware-event
  independent.
- The 200-online-row safety cap remains until separately redesigned.
- Pass-through does not make arbitrary periodic custom-channel broadcasts
  possible: it only drains when the user genuinely sends chat.
- It cannot bypass GreenWall framing or byte limits.

## Test matrix

Test each phase with: sender enabled/disabled, GreenWall configured/unconfigured,
channel joined/late/failed/rejoined, solo/group/instance, quiet user, rapid chat,
multiple producer queues, old/new GuildRoster peers, reload mid-transaction,
duplicate/out-of-order/missing frames, and a 900+ member local roster.

Capture `/gwgr status`, BugGrabber output, queue high-water
marks, echo latency, transaction expiry and total GreenWall frames. A release
candidate requires zero `ADDON_ACTION_BLOCKED` reports attributable to
GuildRoster.
