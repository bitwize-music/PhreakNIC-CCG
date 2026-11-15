# Known bugs

Bugs found in a review of v0.27 and re-verified on v0.28. A bug listed with checks is proven by tests that assert
the **correct** behaviour: each check fails while the bug exists and passes once it is fixed. `control:` checks
show the fixtures are sound and must always pass. Every check message starts with its bug ID.

The **Known bugs** job in `.github/workflows/tests.yml` runs these checks and stays red until every listed bug is
fixed; its run summary lists the checks still failing. The other jobs must stay green.

Each bug goes through the same steps:
1. A failing check here proves it.
2. A fix on its own branch turns the check green, with the full suite still green.
3. An issue in the upstream repository describes it.
4. A pull request with the fix and its regression test references the issue ("Fixes #N").

## Running the checks

Use a temporary `XDG_DATA_HOME` so no real saves, decks or stats are touched (the suites also back up and restore
`user://`):

```bash
export XDG_DATA_HOME=$(mktemp -d)
godot4.7.1 --headless --path . -s tests/bugs_engine_checks.gd   # engine and card rules
godot4.7.1 --headless --path . -s tests/bugs_bots_checks.gd     # bots, export presets, CI coverage
godot4.7.1 --headless --path . -s tests/bugs_online_checks.gd   # online client and table
godot4.7.1 --headless --path . -s tests/bugs_table_checks.gd    # in-game table UI (B38 runs tests/bugs_table_helper_close.gd)
godot4.7.1 --headless --path . -s tests/bugs_menu_checks.gd     # menus, stats, deck builder (B12/B13/B55 run tests/bugs_menu_helper.gd)
node --test cloudflare/online/test/known_bugs.test.js            # online Worker (Node 22.13+)
```

A few findings fall under [SECURITY.md](../SECURITY.md) (online abuse limits, content shown on other players'
screens). They're held back for private reporting and aren't listed here.

## Bugs with failing checks (42)

| ID | Bug | Severity | Checks | Status |
|---|---|---|---|---|
| B01 | Five Mog printings lose their effects in the Mog Variant set and in custom decks: Touch Mog doesn't stop buying, Mog's CTF Bangers adds no damage, Mogmart isn't free after heartsh8ped, pTFMOG doesn't make pTFS Heroes free, Mog's Makeshift Lectern doesn't discount Heroes | High | engine ×10 | Issue [#3](https://github.com/Nirtom84/PhreakNIC-CCG/issues/3), fix in PR [#4](https://github.com/Nirtom84/PhreakNIC-CCG/pull/4) |
| B02 | A player who reconnects after the game ended is never told it's over (frozen board, Resume keeps coming back) | High | worker ×1 | Open |
| B03 | A refused socket means "Reconnecting…" forever: Remove seat on a joined human, kicked while offline, host away over 60 s, room over 8 h | Medium | online ×3 | Open |
| B04 | A nested TOCTOU reaction turn ends the outer human's reaction turn | Medium | engine ×2 | Open |
| B05 | Online Mog Variant and custom-deck games open the table on the default card set (debug builds: the table stops following the game; release builds, by reading: wrong art or card backs) | Medium | online ×6 | Open |
| B06 | DEFCON's hostile target choice calls `value()` on human seats' deciders (script error) | Medium | bots ×1 | Open |
| B07 | DEFCON's 80 ms turn budget counts time spent waiting for a human | Medium | bots ×1 | Open |
| B08 | Rookie Numbers takes life one seat at a time, so the higher seat wins instead of a draw | Medium | engine ×2 | Open |
| B09 | Cards coming off a stolen pTFS or The Book keep their old owner and end up in the old owner's discard pile | Medium | engine ×2 | Open |
| B10 | Phone layout: the Auto toggles (Botnet, Tableskirts…) can't be reached | Medium | table ×1 | Open |
| B11 | Knocked out of a 3–4 player game: Resume game brings you back alive | Medium | menu ×1 | Open |
| B12 | Android Back on the Stats screen quits the app | Medium | menu ×1 | Open |
| B13 | Escape on the web main menu calls `quit()` | Medium | menu ×1 | Open |
| B14 | Back or Escape on the match summary opens a hidden in-game menu that takes the summary's clicks | Medium | table ×2 | Open |
| B15 | `UIStyle.compact()` re-reads settings.cfg on every call: about 1,600 file reads per phone-layout redraw | Medium | table ×1 (Linux only) | Open |
| B17 | One answer resolves two stacked dialogs: "Yes" on TOCTOU's prompt also answers "Leave without saving?" | Medium | table ×3 | Open |
| B18 | Export presets still give version 0.25 (Android and Windows) | Medium | bots ×4 | Open |
| B20 | CI doesn't run the official-rulings checks on pull requests, and never runs bot_checks | Low–medium | bots ×2 | Open |
| B22 | Start doesn't re-check the room's version after a deploy | Low | worker ×1 | Open |
| B23 | Game end isn't detected during a TOCTOU turn that interrupted a simultaneous loss | Low | engine ×2 | Open |
| B24 | A stolen Grass lingers when the turn counters differ (extra turns) | Low | engine ×1 | Open |
| B26 | A win after rejoining an online game sets Fastest win from the partial turn count | Low | menu ×1 | Open |
| B27 | Back in the deck editor throws away an unsaved deck without asking | Low | menu ×3 | Open |
| B28 | In the tutorial, Back closes the coach instead of the open card or prompt | Low | table ×2 | Open |
| B29 | Phone layout: Open board and Deck/Discard do nothing during a TOCTOU reaction turn | Low | table ×2 | Open |
| B30 | JousterL can't put itself on top of the deck | Minor | engine ×1 | Open |
| B31 | Clarion Inn Staff's free buy is used up by the first matching card | Minor | engine ×1 | Open |
| B32 | What is Truth? becomes free after heartsh8ped (Walmart's "this card") | Minor | engine ×2 | Part of issue [#3](https://github.com/Nirtom84/PhreakNIC-CCG/issues/3), fix in PR [#4](https://github.com/Nirtom84/PhreakNIC-CCG/pull/4) |
| B33 | Egg in Your Soup adds counters to every Sandwich Factory instead of one | Minor | engine ×1 | Open |
| B34 | CRT LAN Party and Speakers Needed reshuffle without `card_moved` (no shuffle sound) | Minor | engine ×2 | Open |
| B35 | A draw counts as a loss in lifetime stats | Minor | menu ×1 | Open |
| B37 | Players without a Hero get "as —" in the share text and result card | Minor | menu ×3 | Open |
| B38 | The desktop close button is ignored while a prompt is open | Minor | table ×1 | Open |
| B39 | Renaming the selected custom deck switches the selection to Tag Team | Minor | menu ×1 | Open |
| B40 | The player count resets to 2 when the main menu reopens | Minor | menu ×2 | Open |
| B41 | Music volume changed with the mouse wheel or keyboard isn't saved | Minor | menu ×2 | Open |
| B42 | Ability buttons and tooltips show raw `{H}`/`{D}` tokens | Minor | table ×3 | Open |
| B43 | Signal connections grow with every card move | Minor | table ×1 | Open |
| B44 | The custom-deck D20 roll lingers after a refused start and into later games | Minor | worker ×3 | Open |
| B45 | Double-tapping Start reports "servers are full" while the game is starting | Minor | worker ×1 | Open |
| B48 | Custom-deck bots learn which card O.P.R.A.H. drew into a hidden hand | Minor | bots ×1 | Open |
| B55 | Leaving after being knocked out at Instant bot pace hangs the game in an endless error loop | Medium | menu ×1 | Open |

## Confirmed without an automated check

| ID | Bug | Why there's no check |
|---|---|---|
| B19 | Most suites pass even when SCRIPT ERRORs occur | About the test harness itself |
| B36 | Online custom-deck games are recorded as offline and "Script Kiddie" | Blocked by B05: the client table fails before the game can finish; testable once B05 is fixed |
| B46 | The online server README lists outdated rate-limit numbers | Documentation fix |
| B49 | `tools/build_all.sh release` stages a debug-signed APK when the signing setup is missing | Build script |
| B50 | README's test commands wipe real user data unless `XDG_DATA_HOME` is set | Documentation and harness |
| B51 | Exports ship `reference/`, `decks/custom/` and the baseline bots | Export filters |
| B52 | A suite whose `run()` aborts hangs CI for 25 minutes | Harness |
| B53 | Housekeeping: unused `tools/card_data_0*.json`, an incomplete README test list, a "300-game" CI comment | Documentation |
| B54 | `link_server.gd` logs harmless errors when a socket drops | Log noise |
| B56 | `tests/v22_checks.gd` is flaky (about 4% of runs): it reserves whichever card the clock-seeded row deals first, and a card with a buy prompt (mog, Nuvious, Fore04) collides with B17. Seeds 6, 15, 101, 132, 136, 140, 141, 145, 178, 200 and 215 always fail | Fix belongs in that test (fixed seed) and B17 |

## Waiting on a designer ruling (no check yet)

- **Q1:** ICE "last counter" triggers resolve before the overflow damage, and the overflow is dropped if the game ends (`rules.gd:431-433`); a defender who took lethal damage can win.
- **Q2:** Rickroll's buy replacement pulls the Rickroll from any zone, including removed-from-game (`rules.gd:296-304`); Ruling 3 describes it moving from the discard pile.
- **Q3:** Talks Fun Police treats a [Restaurant Name] Restaurant copying a 6-cost Location as cost 4 (`effects.gd:876`); Ruling 10 says "printed cost".
- **Q4:** Altk3y and Botnet Takeover taking an opponent's card count as acquiring (`rules.gd:531-538`).

## Existing tests that assert the current (buggy) behaviour

A fix for these bugs has to update the listed test too:

- B01: `tests/defcon_trace_hashes.json` entry `0/2026mog/77103` records a trace in which Mog's Makeshift Lectern is ignored.
- B27: `tests/v25_ui_checks.gd` ("Back returns to list").
- B30: `tests/ui_state_sync.gd` ("JousterL stays in discard").
- B31: `tests/rules_checks.gd` ("Staff free-buy token").
- B35: `tests/v17_checks.gd` ("Loss resets streak" with a stalemate).
- B48: `tests/custom_bot_checks.gd` (census matches the real Center Deck after every turn).
