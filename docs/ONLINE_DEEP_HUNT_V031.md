# Second online/multiplayer pass — v0.31

Reviewed November 16, 2026 against upstream `63eb4a499b9586e7e04c41651de84b787cbc7ec9`. Upstream was fetched again and had not advanced. Branch: `hunt/online-v031-deep`, based on the first hunt checkpoint. The [first three findings](ONLINE_HUNT_V031.md) remain separate.

This pass found **five additional functional bugs**. Tests run locally with synthetic credentials, controlled clocks and in-memory transports. The Worker tests call the actual `Room` methods with external I/O stubbed; they do not constitute a deployed Cloudflare test. No production game logic, public issues or PRs were changed.

## Findings

| ID | Priority | Behavior |
|---|---|---|
| ON31-06 | Medium | Restoring in a process with over ten minutes of uptime immediately spends the human's entire turn allowance. |
| ON31-05 | Medium | Reconnecting after a short outage can immediately hand the active human's turn to a bot. |
| ON31-07 | Medium | Leaving while Start is pending loses the guest's reconnect token while keeping their seat occupied. |
| ON31-04 | Medium | The second completion message can overwrite correct final totals with the previous board's values. |
| ON31-08 | Low | View final deck displays hidden placeholders for the player's remaining draw pile, even after the final view. |

These are gameplay/usability priorities, not security severity scores. ON31-03 from the first pass remains the highest priority because it permits extra bot hands/actions during one reaction.

### ON31-06 — process uptime is charged to a restored turn

Locations: [`last_tick` initialization](../scripts/net/game_server.gd#L37), [`_idle_tick`](../scripts/net/game_server.gd#L368), [`restore`](../scripts/net/game_server.gd#L439), [link recovery creates a new GameServer](../scripts/net/link_server.gd#L149).

`last_tick` starts at zero. On the first tick, `step = now() - last_tick` therefore includes all time since the Godot process started. `restore()` does not initialize it. `_idle_tick()` initializes the current turn's idle state, but then adds that already-computed interval to `turn_used`.

A room link can reconnect while its container remains running. The link's restore handler creates a fresh GameServer inside that existing process. If the process has been running for at least 600 seconds and the active human reconnects before the new server's first tick, the turn immediately exceeds `TURN_LIMIT`.

Local reproduction:

1. Take a real, valid snapshot at the beginning of a human turn.
2. Restore it into a new GameServer whose injected monotonic clock reads 700 seconds.
3. Authenticate both clients through LoopbackTransport; the active seat can initially act.
4. Run the timer tick without advancing the clock.

Observed: `turn_used = 700`, connected idle time `0`, and the human can no longer act because `idle_bot` is set. The identical snapshot at process uptime zero remains playable with no time charged.

Suggested correction: initialize/reset the tick baseline when starting/restoring the server, and avoid charging an interval that precedes the current turn's accounting period. Preserve the hard limit for an actual ten-minute turn.

### ON31-05 — an outage counts toward connected inactivity

Locations: [disconnect tracking](../scripts/net/game_server.gd#L204), [hello/reconnect](../scripts/net/game_server.gd#L217), [`_idle_tick`](../scripts/net/game_server.gd#L368).

The disconnected-seat branch skips connected-idle processing without pausing or advancing `idle_at`. On reconnection, the disconnect record is removed and human control is restored, but the connected-idle calculation still uses the time before the outage.

Local reproduction:

1. Leave the active human connected and idle for 100 seconds.
2. Disconnect for 85 seconds, below the separate 120-second disconnected takeover threshold.
3. Reauthenticate that same seat. Human control initially returns.
4. On the next timer tick, the server counts 185 seconds of connected inactivity, sets `idle_bot`, and blocks the human's actions.

The shorter, 40-second outage control remains playable. Both cases use real GameServer authentication and close handling, with a controlled clock instead of waiting several minutes. No bot takeover occurs during either outage.

Suggested correction: exclude disconnected intervals from connected-idle accounting, or explicitly restart that inactivity deadline on successful reconnect. Keep the cumulative turn limit separate so reconnecting cannot keep a turn alive indefinitely.

### ON31-07 — refused Leave discards the only reconnect credential

Locations: [Worker startup gate](../cloudflare/online/src/index.js#L211), [Start's awaited slot claim](../cloudflare/online/src/index.js#L233), [`leave_lobby`](../scripts/ui/online.gd#L405).

During Start's asynchronous capacity check, `this.starting` is true and every other lobby action, including a guest's Leave, receives `busy`. The client sends Leave, waits two frames, clears the remembered credential and exits without checking whether the departure succeeded.

Local paired reproductions:

1. The actual Worker reserves the startup operation and pauses at `Lobby.claim()`.
2. Guest sends Leave. The Worker refuses it with `busy` (503).
3. Release the capacity check with a `busy` refusal. The room is still in its lobby and the guest's token still occupies its seat. Ordinary Leave, without a concurrent Start, releases the seat correctly.
4. In the actual Godot lobby, deliver that same refusal before the two-frame wait completes. The session displays the refusal, but the screen still exits and the saved credential becomes `{}`.

The guest cannot resume their retained seat; rejoining encounters the full room until the host removes them. This differs from ON31-02, which loses a newly issued token during an in-flight join and array compaction.

Suggested correction: acknowledge departure, retain credentials when it is refused, and offer retry. If the Worker accepts or queues Leave during startup, revalidate occupied seats before committing Start; simply removing the startup gate could start an unfilled room.

Test limit: Worker and UI halves run independently against the same response shape. Their external asynchronous boundaries are controlled; no live Cloudflare room was used.

### ON31-04 — duplicate completion overwrites final totals

Locations: [both completion messages emit `finished`](../scripts/net/online_session.gd#L109), [`Table.game_over`](../scripts/ui/table.gd#L1533), [`MatchStats.finish`](../scripts/ui/match_stats.gd#L60).

The game server sends `game_over` with authoritative `final_players`. The Room subsequently sends `over` after recording the result and stopping the container. OnlineSession emits `finished` for each. Table calls `match_stats.finish()` **before** checking `online_over`, so the second invocation overwrites the corrected final life/deck totals using the client mirror, then returns without restoring `final_players`.

This matters when the Room's `over` arrives before the final coalesced view, or that final view is not delivered. If the final view arrives first, its current values avoid the visible error.

The reproduction sends a real authenticated Damage play that eliminates a guest at one life. Card conservation is checked. With final-view polling paused, the first completion correctly records guest life `0`; the Room completion changes it back to `1`. If both completions precede the deferred summary construction, that stale value is what the summary displays.

Suggested correction: make completion idempotent before mutating MatchStats, or consistently preserve the authoritative final totals on subsequent completion notifications.

### ON31-08 — own final deck remains partly hidden

Locations: [NetView always masks draw piles](../scripts/net/net_view.gd#L45), [final-deck button](../scripts/ui/table.gd#L1637), [`final_deck`](../scripts/ui/table.gd#L1654).

Masking the player's draw pile during play is correct. The same masking persists after the game, while the result screen always offers View final deck. That viewer uses the mirror's card objects, so it cannot identify cards still in the draw pile.

In the completed game from ON31-04, explicitly deliver an up-to-date final view and open the actual final-deck viewer. Five of the winner's ten cards are still `hidden` placeholders. The game is finished and the button works; the missing information is not caused by the earlier result-message ordering bug.

Suggested correction: provide the authenticated player's complete final card collection once the game has ended, for example as an unordered result payload. Retain hidden deck order during play. A final result payload also avoids depending on a last view arriving before container shutdown.

## Reproduce

Godot 4.7.1; isolate user data for each command:

```bash
XDG_DATA_HOME=$(mktemp -d) ~/.local/bin/godot4.7.1 --headless --path . -s tests/online_deep_state_checks.gd
node --test tests/online_deep_worker.mjs
XDG_DATA_HOME=$(mktemp -d) ~/.local/bin/godot4.7.1 --headless --path . -s tests/online_deep_leave_checks.gd
```

Expected on unmodified v0.31:

- State/result suite: 20 checks, four failed behavior assertions (ON31-04/05/06/08); all controls pass.
- Worker suite: two tests, one passing ordinary-Leave control and one failing concurrent-Leave case.
- Client Leave suite: four checks, one failure; request delivery and refusal receipt controls pass.

These reproductions intentionally exit nonzero and are not wired into CI. No script errors occurred. Godot reports resource-cleanup diagnostics at exit; these are not counted as additional findings.

## Existing regression coverage

The following existing suites passed during this pass:

| Suite | Checks/tests | Failures |
|---|---:|---:|
| Worker | 70 | 0 |
| `v11_checks` — idle limits, recovery, reactions | 350 | 0 |
| `v15_checks` — UI, timers, result summaries | 13,157 | 0 |
| `online_ui_checks` | 95 | 0 |
| `net_checks` | 15,985 | 0 |
| `link_checks` | 5,420 | 0 |

Simulation-dependent counts vary. Online UI refusal scenarios produce their expected handshake diagnostics; none of these runs printed a script error.

Other inspected areas included seat authentication/replacement, pending-prompt replay and timeouts, custom-deck submission guards, setup/restore handshakes, snapshot boundaries, nested reactions, client action readiness and final-result delivery. Initial views for all standard pools with two/four players and a valid 200-card custom deck passed transport limits (largest sampled packet: 6,189 nodes, approximately 38 KB). This is not a claim that every possible later board state fits.

## Review of the previous hunt's reaction test

The old ON31-03 test treated `server.driving.has(depth)` as proof of a duplicate driver. A correct shared guard also sets that entry. The test now checks the actual number of cards played instead, alongside one ending, return to the interrupted player, pacing and conservation.

On stock v0.31 it still reports nine checks/four failures and 13 plays/three endings. A temporary review-only subclass that guards the existing reaction driver passes those gameplay assertions; this is a narrow experimental control, not a finished or submitted production fix.

## Public-issue check and scope

All 58 existing public issues were checked. No matching public issue was found for these five cases. Nearby closed issues #31 (rejoining after completion), #32 (revoked seats reconnecting forever), #38 (double-tap Start message), and #45/#47 (online stats) address different behavior. Private reports were not inspected.

The original ON31-01/02 seat-removal findings and ON31-03 overlapping reaction drivers are not counted again. This checkpoint contains tests and documentation only; issue filing and game fixes remain separate work.
