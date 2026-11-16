# Online and multiplayer hunt — v0.31

Baseline: upstream and fork `main` at `63eb4a499b9586e7e04c41651de84b787cbc7ec9`, November 16, 2026. The fork was fast-forwarded from v0.28; pending Apple build work remains on its own branches/PR.

This pass examined room/seat lifecycle, joins, reconnect handling, remote prompts and server-driven bot reactions. All reproductions use local/in-memory fixtures and synthetic credentials. No production server tests, fixes, new public issues or PRs are part of this hunt checkpoint.

## Findings

| ID | Severity | Confirmed behavior |
|---|---|---|
| ON31-03 | High | Two bot drivers can run one TOCTOU reaction, drawing and playing extra hands before the interrupted player's turn resumes. |
| ON31-01 | Medium | Removing a lower seat leaves a remaining guest's credential stale; the custom-deck lobby stops rebuilding with an array-index error. |
| ON31-02 | Medium | Removing a lower seat during an in-flight join returns “full” but leaves the joining guest occupying an unreachable seat. |

### ON31-03: concurrent bot reaction drivers

Locations: [GameServer._process](../scripts/net/game_server.gd#L349), [GameServer._drive_reaction](../scripts/net/game_server.gd#L414), [GameServer._drive](../scripts/net/game_server.gd#L420).

`_drive_reaction()` starts the bot's reaction coroutine without registering it in `driving`. Once the paced bot yields, `_process()` sees no driver for the current reaction depth and starts `_drive()` as well. The handlers can act on the same player and call `end_turn()` independently. The primary reaction handler can continue playing the new hand that the other handler just drew.

The reproduction uses the unmodified `GameServer` class, a real authenticated `play` action over `LoopbackTransport`, a three-player game, a bot with TOCTOU and three Hackers, a lethal one-damage attack, and the supported 250 ms bot pace. A row of existing cards costing more than five prevents incidental buying/reserving; fixture and final-state card conservation are asserted.

Control: run the reaction's own driver while server polling is disabled. It plays exactly three cards, ends once, and returns to the attacker with the selected pacing.

Observed with normal server polling: a secondary driver is present, 13 cards are played and three end-turn events fire inside the same reaction. At that checkpoint the reaction has not returned to the attacker; some plays share the same millisecond despite the selected 250 ms pace. An earlier longer observation saw 13 end-turn events in ten seconds. These are extra draws/actions involving existing cards, not duplicated card objects. The test stops at three endings or five seconds; it does not claim the reaction is infinite.

Suggested correction: ensure both bot-driving entry points share a guard per reaction depth. Preserve the ability to take over idle human reaction turns; simply disabling all server driving during reactions would break that behavior.

### ON31-01: client seat number stays stale

Locations: [Worker remove_seat](../cloudflare/online/src/index.js#L247), [OnlineSession room update](../scripts/net/online_session.gd#L95), [custom-deck lobby](../scripts/ui/online.gd#L367).

1. Create a three-seat custom-deck room: Host (0), Bot (1), Guest (2).
2. Guest connects and can see **Submit deck**.
3. Host removes the bot's seat.

The Worker shifts Guest to seat 1. Room packets contain the new seat array but no authenticated recipient seat index; `OnlineSession` retains credential seat 2 and persists that stale value. The lobby accesses `room.seats[2]` in a two-element array and logs an invalid-index script error, leaving the lobby incomplete without its deck controls.

The local UI reproduction first verifies **Submit deck** exists, then supplies the actual post-removal room shape through `OnlineSession._message()`. The stored seat remains 2 and the deck button disappears. With more remaining seats, the stale index can instead mark another player as “[you]” or use that player's deck state.

Suggested correction: send the authenticated recipient's current seat index and update both live and remembered credentials before emitting the room update. Do not infer identity from handles, which need not be unique.

### ON31-02: join/removal race creates a ghost occupant

Location: [Room.joinRoom](../cloudflare/online/src/index.js#L153).

1. Start with Host (0), Bot (1), Open (2).
2. Guest begins joining; the room reserves seat 2 and waits for its stats RPC.
3. Host removes Bot (1), shifting the reserved guest to seat 1.
4. The join resumes and checks the old array index, sees a token mismatch, and returns HTTP 409 `full`.

The issued token is still attached to Guest at seat 1, but the caller never receives it. The room is now full and the guest cannot reconnect to that reservation. The host must kick/remove the ghost occupant or recreate the room.

The standalone Node reproduction executes the real Worker `Room` methods with a deterministic gate at `stat('join')`; it does not emulate an entire Cloudflare deployment. A no-removal control returns the correct seat/token. Cloudflare permits requests to interleave across external asynchronous I/O; the join's stats RPC occurs before its own storage save. See [Cloudflare concurrency guidance](https://developers.cloudflare.com/durable-objects/best-practices/rules-of-durable-objects/).

Suggested correction: after awaited work, find the reservation by the issued token and return its current seat, or undo the reservation if the join cannot succeed. Keep the existing protection against a kick/replacement returning another player's token.

## Reproduction commands

Use Godot 4.7.1 and a separate temporary data directory for each run:

```bash
XDG_DATA_HOME=$(mktemp -d) ~/.local/bin/godot4.7.1 --headless --path . -s tests/online_hunt_checks.gd
node --test tests/online_hunt_worker.mjs
XDG_DATA_HOME=$(mktemp -d) ~/.local/bin/godot4.7.1 --headless --path . -s tests/online_reaction_hunt.gd
```

These tests assert correct behavior and are expected to exit nonzero on the baseline:

- Seat/UI reproduction: four checks, three failures, plus the production lobby's invalid-index script error. The pre-removal control passes.
- Worker reproduction: two tests, one passing control and one failing race assertion.
- Reaction reproduction: nine checks, four failures. Both single-driver controls and physical-card conservation checks pass. Exact timestamps vary by scheduling.

They are separate from the regular CI suite and have not been added to that workflow. The Worker reproduction is outside the normal Worker test directory.

## Baseline verification

- Existing Worker tests: 70 passed, zero failed.
- `tests/net_checks.gd`: 21,705 checks, zero failures in the local run (the count varies with randomized games).
- `tests/online_ui_checks.gd`: 95 checks, zero failures. Expected handshake errors occur in its deliberate HTTP-429 refusal scenarios, alongside existing resource-cleanup diagnostics at exit; no script errors were reported.

No production game logic was modified. Fix and submission work can use these cases as regression tests, with ON31-03 taking priority because it changes the sequence of multiplayer gameplay actions.
