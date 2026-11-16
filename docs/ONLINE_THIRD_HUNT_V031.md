# Third online/multiplayer pass — v0.31

Reviewed November 16, 2026 against upstream `63eb4a499b9586e7e04c41651de84b787cbc7ec9`; another fetch found no upstream change. Local branch: `hunt/online-v031-third`, based on the second hunt checkpoint, `6b9ac11`.

This pass confirms **four additional functional bugs**, bringing the three-pass total to twelve. The [first pass](ONLINE_HUNT_V031.md) and [second pass](ONLINE_DEEP_HUNT_V031.md) describe the other eight. Production code is unchanged; these are review findings and failing reproductions, not completed fixes. No new public issues, PRs, deployments or branch pushes were made.

| ID | Priority | Confirmed behavior |
|---|---|---|
| ON31-12 | Medium | Clicking an obsolete Buy button can disable every client action until a new view arrives, although the server still allows the turn. |
| ON31-11 | Medium | Failed recovery of an unfinished match displays Stalemate and records a lifetime draw. |
| ON31-09 | Low | Inspecting a permanent inside an online target-selection prompt hides its remaining ICE. |
| ON31-10 | Low | Disconnect/reconnect does not publish updated countdowns to the other players. |

These are gameplay/usability priorities, not security ratings. The target inspection issue can affect strategic choices; the connection issue is stale status, not proof that the server's disconnect timeout itself is wrong.

## ON31-12 — a refused stale purchase leaves the client unable to act

Locations: [inspector Buy callback](../scripts/ui/table.gd#L1953), [client send/action handling](../scripts/net/net_client.gd#L34), [client error handling](../scripts/net/net_client.gd#L80), [server refusal](../scripts/net/game_server.gd#L213), [server action validation](../scripts/net/game_server.gd#L267).

The inspector's Buy button retains the card UID and enabled state from when the sheet opened. Turn changes and incoming views redraw the board but do not rebuild this sheet. `sheet_buy()` checks general availability, then submits the old UID without rechecking whether that card can still be bought.

`NetClient.send_action()` immediately sets `can_act = false`. If the server refuses the stale action, it sends an error but does not mark the view dirty. The client only displays that error; it neither requests a fresh view nor restores availability. With everyone waiting for the active player, no further gameplay event need arrive before idle takeover.

Reproduction through the actual UI and authenticated transports:

1. Open the inspector for an affordable center-row card. The controlled fixture uses The Clarion Inn, six Hacking, an empty hand and four more expensive row cards; all physical cards are conserved.
2. Leave the sheet open through the 180-second idle timeout. The real bot driver buys that card and ends the turn.
3. The other human ends their turn. The first human receives the new view and regains control, but the old inspector and its enabled Buy button remain.
4. Click that original button. No fabricated invalid network request is needed.

Observed: the UI receives `illegal action`; `server.available(0) == true`, client/table availability is false, and `server.dirty == false` after another polling frame. End Turn and all other normal actions depend on that same client availability flag. A real authenticated reconnect restores the client immediately.

Suggested correction: revalidate or invalidate inspector actions on new views, and make action refusals recover the client's authoritative readiness through a fresh view or explicit acknowledgement. Do not blindly set `can_act = true` for every error: an error can also mean that it is genuinely another player's turn or a prompt is pending.

This is distinct from ON31-05/06: no erroneous timer calculation is needed. The idle bot finishes a turn legitimately; the stale button and missing refusal recovery cause the subsequent failure.

## ON31-11 — failed recovery is recorded as a completed draw

Locations: [LinkServer restore failure](../scripts/net/link_server.gd#L209), [OnlineSession terminal messages](../scripts/net/online_session.gd#L109), [table result handling](../scripts/ui/table.gd#L1533), [lifetime recording](../scripts/ui/table.gd#L1550).

An incompatible snapshot causes LinkServer to send `{t:"over", winner:-1, reason:"restore_failed"}`. OnlineSession recognizes the reason and displays an error notice, but still emits the normal `finished(-1)` signal. If an existing table is open, it finishes the match statistics and displays the ordinary Stalemate result. The deferred summary then records a lifetime game with neither a win nor a loss: a draw.

Reproduction:

1. Start an online game and open its actual table while the authoritative game is unfinished.
2. Pass a real snapshot with an incompatible version to the actual LinkServer restore handler.
3. Forward its resulting terminal message to the existing client, as Room does after a failed recovery.
4. Let the real result screen write lifetime statistics in an isolated test profile.

Observed: the recovery-error notice is present, `online_over == true`, the headline is Stalemate, and lifetime totals change from zero to `games=1, wins=0, losses=0`. The fixture explicitly enables the production stats-writing path that headless runs normally skip.

Suggested correction: distinguish an aborted match from a completed match. Close or explain the interrupted game without awarding a result or updating completed-match totals; preserve the normal draw path for an actual in-game stalemate.

This is not the old issue #31 (missing results when returning after completion), issue #46 (draws counted as losses), or ON31-04 (duplicate completion overwriting final totals). Here a match that never reached a result is counted as one.

## ON31-09 — target-card inspection omits live ICE

Locations: [prompt serialization](../scripts/net/remote_decider.gd#L8), [prompt card reconstruction](../scripts/net/net_client.gd#L112), [online prompt](../scripts/ui/table.gd#L2264), [inspector permanent-membership check](../scripts/ui/table.gd#L1894).

RemoteDecider includes the target's UID, owner, controller and counters. NetClient reconstructs a new CardInstance for the choice dialog. The inspector displays live permanent details only when the exact object belongs to `engine.permanents()`. A reconstructed prompt object is never that same object, even when its UID matches a visible permanent on the board.

Reproduction:

1. Put an opponent's The Clarion Inn into play with three remaining ICE and AI Fingers (internal ID `Sticky Fingers`) in the active human's hand, moving existing cards only.
2. Inspect the ordinary board card: the panel correctly shows `ICE: 3`.
3. Play AI Fingers through the authenticated client, opening the server's real "Take control of permanent" prompt.
4. Right-click the offered target button, using its actual UI input callback.

Observed: the real prompt payload contains `counters=3`, but the inspector omits the ICE line. Selecting the target still resolves the effect correctly and conserves the cards. The defect is missing decision information, not a failed theft effect or hidden draw-pile identities.

Suggested correction: resolve visible prompt targets against the mirror by UID, or pass explicit live permanent information to the inspector. Preserve the prompt's authoritative counters if the mirror predates the prompt. Avoid exposing hidden objects or assuming that every offered card is a permanent in play.

## ON31-10 — connection changes leave other players' countdowns stale

Locations: [server disconnect handler](../scripts/net/game_server.gd#L204), [hello/reconnect handler](../scripts/net/game_server.gd#L217), [view publication](../scripts/net/game_server.gd#L331), [timer payload](../scripts/net/game_server.gd#L481), [table countdown application](../scripts/ui/table.gd#L2383).

`_closed()` updates `disconnected` but does not set `dirty`. A successful hello clears that state and sends a view to the returning client, without publishing a new view to the other clients. Their countdowns are updated only by incoming views.

Reproduction with two humans and normal initial views fully flushed:

1. Disconnect the active human at injected time seven seconds and poll the real server on a new frame.
2. The server's `timer_state()` contains a disconnected countdown. The remaining player's actual table receives zero new views and keeps the normal turn countdown.
3. As a control, explicitly publish one view: the remaining table immediately shows the disconnected countdown correctly.
4. Reconnect the active human at twelve seconds. Authentication succeeds and the player can act, but the other table receives zero new views and keeps its disconnected countdown until another update occurs.

Suggested correction: publish personalized views when authenticated connection state changes, using the existing frame-coalescing mechanism. The first half reproduces a normal quiet two-human room; the explicit publication in the second half isolates the equally missing reconnect notification.

## Validation and limits

The new [reproduction suite](../tests/online_third_state_checks.gd) uses the real GameServer, NetClient, OnlineSession, LinkServer restore handler and table UI. LoopbackTransport stands in for the network, clocks are controlled, and a LinkServer subclass captures its outgoing message. The suite does not contact production services or exercise a deployed Cloudflare container.

Run from the repository root with an isolated profile:

```sh
XDG_DATA_HOME=$(mktemp -d) ~/.local/bin/godot4.7.1 --headless --path . --script tests/online_third_state_checks.gd
```

Godot `4.7.1.stable.official.a13da4feb` results:

| Suite | Checks | Failed assertions |
|---|---:|---:|
| `online_third_state_checks.gd` | 26 | 5, covering four findings |
| Existing `v11_checks.gd` — server idle/recovery/reaction coverage | 350 | 0 |
| Existing `v18_checks.gd` — UI and automatic activation coverage | 71 | 0 |

All 21 control assertions in the new suite passed. ON31-10 has separate disconnect and reconnect assertions, accounting for the fifth failure. The suite deliberately exits nonzero on stock v0.31. The incompatible-restore case also deliberately triggers the production `room AB23CD restore failed` diagnostic. There were no GDScript parse/runtime errors. Resource-cleanup warnings occur at process exit in both the new and existing suites; they are not counted as findings.

The previous pass's broader Worker, UI, network and link results remain documented in its report; those were not all rerun for this tests-only change. Existing public issue titles/bodies were checked for overlap. Speculative dropped-action and relay-ordering scenarios were not counted without a demonstrated stock-client trigger.
