# GreenWallGuildRoster 1.1.0-dev.1 long-session evaluation

## Test context

- Date: 2026-08-22 to 2026-08-23
- Character: Gabbaophant-Soulseeker
- Local guild: Milchbar
- Partner guild: Saftladen
- Build: `1.1.0-dev.1`, based on the released `1.0.10` synchronization logic
- Monitor interval: 300 seconds
- Monitor state after test: off; history retained
- Samples: 80/288
- Wall-clock span: 7 h 32 min
- Sampled runtime: 6 h 40 min

## Performance

| Metric | Result |
|---|---:|
| CPU average | 0.136 ms/s (~0.014% of one core) |
| CPU median | 0.132 ms/s |
| CPU p95 | 0.224 ms/s |
| CPU maximum | 0.260 ms/s |
| Memory minimum | 521 KB |
| Memory median | 3192 KB |
| Memory p95 | 7686 KB |
| Memory maximum | 9324 KB |
| Memory final | 3155 KB |

Memory repeatedly fell after garbage collection and finished far below its
maximum. The series is not monotonic and contains no indication of retained
growth. CPU cost is very low even with development monitoring enabled.

## Synchronization load

The diagnostics store per-five-minute deltas, so the following totals can be
summed directly across all 80 samples.

| Counter | Total | Average per hour of sampled runtime |
|---|---:|---:|
| HELLO whispers sent | 309 | 46.4 |
| ACK whispers sent | 5 | 0.8 |
| Full roster transfers started | 36 | 5.4 |
| Full roster whisper chunks delivered | 163 | 24.5 |
| Send failures | 0 | 0 |
| HELLO acknowledgements suppressed by freshness lease | 200 | 30.0 |
| Local guild fan-outs sent | 100 | 15.0 |
| Duplicate local fan-outs suppressed | 11 | 1.7 |

The measured automatic whisper messages represented by these counters are 309
HELLOs, 5 ACKs and 163 roster chunks: 477 messages, or about 71.6 per sampled
hour (one every 50 seconds on average). `fullTX` counts transfers whose actual
messages are already represented by `chunksDelivered`, so it must not be added
again. Version announcements introduced by dev.1 are not represented by these
counters and are therefore excluded from this total.

The average completed transfer used 4.53 roster chunks. No chunk or control
send failed.

## Queue and peer population

| Metric | Result |
|---|---:|
| Presence average / maximum | 14.1 / 37 |
| Local-guild peers average / maximum | 5.2 / 14 |
| Remote peers average / maximum | 8.9 / 23 |
| Queue average | 0.46 |
| Queue median | 0 |
| Queue p95 | 2 |
| Queue maximum | 5 |
| Queue final | 0 |

The paced queue drained normally. There is no evidence of accumulating
handshake work.

## Did 1.0.10 reduce whisper traffic?

**Yes, the test proves that the new suppression paths were active and removed
traffic. It does not provide a complete before/after percentage because no
1.0.9 monitor baseline was recorded under the same peer population.**

Directly demonstrated savings on this client:

1. The shared ten-minute peer-guild freshness lease suppressed 200 of 205 ACK
   opportunities: 97.6%. This directly prevented 200 outgoing ACK whispers.
   Because a sender only performs the full exchange after an ACK, it also
   prevented corresponding redundant roster transfers on the initiating
   clients; their exact saved chunk count is not present in this client's
   diagnostics.
2. Payload deduplication suppressed 11 of 111 attempted local-guild fan-outs,
   or 9.9%. These are guild addon messages rather than whispers, but they still
   reduce the shared addon-message budget.
3. Own-guild members accounted for an average 5.2 of 14.1 visible peers
   (approximately 37% of the observed presence pool). Version 1.0.10 excludes
   them before handshake queuing. This confirms that a substantial irrelevant
   candidate population existed, but the exact number of avoided HELLOs cannot
   be reconstructed because excluded candidates intentionally never increment
   a send counter.
4. Local fan-out allowed one successful cross-guild roster exchange to serve
   other local GuildRoster clients, while the freshness lease prevented those
   clients from all acknowledging the same peer independently.

The strongest measurable result is therefore not merely low traffic but the
combination of 200 exercised ACK suppressions, only five ACKs actually sent,
zero failures, a normally empty queue and continued correct roster behavior.

## Limitations

- There is no equivalent 1.0.9 dataset from the same time, population and
  session, so an overall “traffic reduced by X%” claim would not be defensible.
- The counters observe this client only. Transfers avoided on remote clients
  as a consequence of a suppressed local ACK are real protocol savings but
  cannot be counted exactly here.
- Development monitoring itself causes periodic CPU/memory accounting work and
  will be removed before the public 1.1.0 release.
- Version-message traffic is rate-limited separately and was not included in
  the dev.1 monitor counters.

## Decision

- [x] CPU use is suitable for release.
- [x] Memory behavior is bounded under the observed session.
- [x] The handshake queue remains bounded and drains.
- [x] No synchronization send failure was observed.
- [x] The 1.0.10 traffic-reduction mechanisms demonstrably activated.
- [x] Development monitoring can be removed while retaining `/gwgr status`
  and explicit debug facilities for user reports.

Final result: **PASS**
