# Known bugs

Bugs found in a review of v0.27/v0.28 and re-verified against upstream v0.29 (`ee51d60`) on November 15, 2026. A bug listed with checks is proven by tests that assert
the **correct** behaviour: each check fails while the bug exists and passes once it is fixed. `control:` checks
show the fixtures are sound and must always pass. Every check message starts with its bug ID.

The **Known bugs** job in `.github/workflows/tests.yml` runs these checks and stays red until every listed bug is
fixed; its run summary lists the checks still failing. The other jobs must stay green.

Each bug goes through the same steps:
1. A failing check here proves it.
2. A fix on its own branch turns the check green, with the full suite still green.
3. An issue in the upstream repository describes it.
4. A pull request with the fix and its regression test references the issue ("Fixes #N").

## Current checkpoint — November 15, 2026

- Upstream v0.29 merged 18 fix PRs covering 33 bug IDs; B53 still had unused-file cleanup outstanding.
- The other 19 public bugs have fixes on 11 refreshed v0.29 branches. All 11 fix PRs are submitted with green fork CI; their issue/PR links are recorded below.
- The four designer questions are resolved by Rulings 26–29 in v0.29.
- `known-bug-tests` follows upstream plus the reproductions: failures for unmerged fixes remain expected here.
- [review/remaining-fixes-v029](https://github.com/bitwize-music/PhreakNIC-CCG/tree/review/remaining-fixes-v029) combines all remaining fixes and the reproductions. Locally all 155 Godot known-bug checks pass, the regular CI suites pass, and the 450-game simulation passes (230,825 checks). All 64 regular Worker tests and 9 explicit Worker known-bug/control tests pass.
- B55's uncommitted follow-up was recovered and incorporated while preserving v0.29's DEFCON timing fix. The original branches/worktrees remain available.
- Security findings remain outside this public ledger. Upstream enabled private reporting in issue #5; no private report submission is recorded in this public-fix checkpoint.

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

## Bugs with automated checks (42; 19 still fail on upstream v0.29)

| ID | Bug | Severity | Checks | Status |
|---|---|---|---|---|
| B01 | Five Mog printings lose their effects in the Mog Variant set and in custom decks: Touch Mog doesn't stop buying, Mog's CTF Bangers adds no damage, Mogmart isn't free after heartsh8ped, pTFMOG doesn't make pTFS Heroes free, Mog's Makeshift Lectern doesn't discount Heroes | High | engine ×10 | Merged in v0.29: PR [#4](https://github.com/Nirtom84/PhreakNIC-CCG/pull/4) |
| B02 | A player who reconnects after the game ended is never told it's over (frozen board, Resume keeps coming back) | High | worker ×1 | Merged in v0.29: PR [#33](https://github.com/Nirtom84/PhreakNIC-CCG/pull/33) |
| B03 | A refused socket means "Reconnecting…" forever: Remove seat on a joined human, kicked while offline, host away over 60 s, room over 8 h | Medium | online ×3 | Merged in v0.29: PR [#33](https://github.com/Nirtom84/PhreakNIC-CCG/pull/33) |
| B04 | A nested TOCTOU reaction turn ends the outer human's reaction turn | Medium | engine ×2 | Issue [#58](https://github.com/Nirtom84/PhreakNIC-CCG/issues/58); fix in PR [#60](https://github.com/Nirtom84/PhreakNIC-CCG/pull/60) (fork CI passed) |
| B05 | Online Mog Variant and custom-deck games open the table on the default card set (debug builds: the table stops following the game; release builds, by reading: wrong art or card backs) | Medium | online ×6 | Merged in v0.29: PR [#35](https://github.com/Nirtom84/PhreakNIC-CCG/pull/35) |
| B06 | DEFCON's hostile target choice calls `value()` on human seats' deciders (script error) | Medium | bots ×1 | Merged in v0.29: PR [#12](https://github.com/Nirtom84/PhreakNIC-CCG/pull/12) |
| B07 | DEFCON's 80 ms turn budget counts time spent waiting for a human | Medium | bots ×1 | Merged in v0.29: PR [#12](https://github.com/Nirtom84/PhreakNIC-CCG/pull/12) |
| B08 | Rookie Numbers takes life one seat at a time, so the higher seat wins instead of a draw | Medium | engine ×2 | Issue [#61](https://github.com/Nirtom84/PhreakNIC-CCG/issues/61); fix in PR [#62](https://github.com/Nirtom84/PhreakNIC-CCG/pull/62) (fork CI passed) |
| B09 | Cards coming off a stolen pTFS or The Book keep their old owner and end up in the old owner's discard pile | Medium | engine ×2 | Issue [#85](https://github.com/Nirtom84/PhreakNIC-CCG/issues/85); fix in PR [#86](https://github.com/Nirtom84/PhreakNIC-CCG/pull/86) (fork CI passed) |
| B10 | Phone layout: the Auto toggles (Botnet, Tableskirts…) can't be reached | Medium | table ×1 | Issue [#71](https://github.com/Nirtom84/PhreakNIC-CCG/issues/71); fix in PR [#74](https://github.com/Nirtom84/PhreakNIC-CCG/pull/74) (fork CI passed) |
| B11 | Knocked out of a 3–4 player game: Resume game brings you back alive | Medium | menu ×1 | Merged in v0.29: PR [#51](https://github.com/Nirtom84/PhreakNIC-CCG/pull/51) |
| B12 | Android Back on the Stats screen quits the app | Medium | menu ×1 | Merged in v0.29: PR [#44](https://github.com/Nirtom84/PhreakNIC-CCG/pull/44) |
| B13 | Escape on the web main menu calls `quit()` | Medium | menu ×1 | Merged in v0.29: PR [#44](https://github.com/Nirtom84/PhreakNIC-CCG/pull/44) |
| B14 | Back or Escape on the match summary opens a hidden in-game menu that takes the summary's clicks | Medium | table ×2 | Issue [#76](https://github.com/Nirtom84/PhreakNIC-CCG/issues/76); fix in PR [#79](https://github.com/Nirtom84/PhreakNIC-CCG/pull/79) (fork CI passed) |
| B15 | `UIStyle.compact()` re-reads settings.cfg on every call: about 1,600 file reads per phone-layout redraw | Medium | table ×1 (Linux only) | Issue [#80](https://github.com/Nirtom84/PhreakNIC-CCG/issues/80); fix in PR [#82](https://github.com/Nirtom84/PhreakNIC-CCG/pull/82) (fork CI passed) |
| B17 | One answer resolves two stacked dialogs: "Yes" on TOCTOU's prompt also answers "Leave without saving?" | Medium | table ×3 | Issue [#83](https://github.com/Nirtom84/PhreakNIC-CCG/issues/83); fix in PR [#84](https://github.com/Nirtom84/PhreakNIC-CCG/pull/84) (fork CI passed) |
| B18 | Export presets still give version 0.25 (Android and Windows) | Medium | bots ×4 | Merged in v0.29: PR [#16](https://github.com/Nirtom84/PhreakNIC-CCG/pull/16) |
| B20 | CI doesn't run the official-rulings checks on pull requests, and never runs bot_checks | Low–medium | bots ×2 | Merged in v0.29: PR [#23](https://github.com/Nirtom84/PhreakNIC-CCG/pull/23) |
| B22 | Start doesn't re-check the room's version after a deploy | Low | worker ×1 | Merged in v0.29: PR [#39](https://github.com/Nirtom84/PhreakNIC-CCG/pull/39) |
| B23 | Game end isn't detected during a TOCTOU turn that interrupted a simultaneous loss | Low | engine ×2 | Issue [#59](https://github.com/Nirtom84/PhreakNIC-CCG/issues/59); fix in PR [#60](https://github.com/Nirtom84/PhreakNIC-CCG/pull/60) (fork CI passed) |
| B24 | A stolen Grass lingers when the turn counters differ (extra turns) | Low | engine ×1 | Issue [#63](https://github.com/Nirtom84/PhreakNIC-CCG/issues/63); fix in PR [#64](https://github.com/Nirtom84/PhreakNIC-CCG/pull/64) (fork CI passed) |
| B26 | A win after rejoining an online game sets Fastest win from the partial turn count | Low | menu ×1 | Merged in v0.29: PR [#49](https://github.com/Nirtom84/PhreakNIC-CCG/pull/49) |
| B27 | Back in the deck editor throws away an unsaved deck without asking | Low | menu ×3 | Merged in v0.29: PR [#57](https://github.com/Nirtom84/PhreakNIC-CCG/pull/57) |
| B28 | In the tutorial, Back closes the coach instead of the open card or prompt | Low | table ×2 | Issue [#77](https://github.com/Nirtom84/PhreakNIC-CCG/issues/77); fix in PR [#79](https://github.com/Nirtom84/PhreakNIC-CCG/pull/79) (fork CI passed) |
| B29 | Phone layout: Open board and Deck/Discard do nothing during a TOCTOU reaction turn | Low | table ×2 | Issue [#72](https://github.com/Nirtom84/PhreakNIC-CCG/issues/72); fix in PR [#74](https://github.com/Nirtom84/PhreakNIC-CCG/pull/74) (fork CI passed) |
| B30 | JousterL can't put itself on top of the deck | Minor | engine ×1 | Issue [#65](https://github.com/Nirtom84/PhreakNIC-CCG/issues/65); fix in PR [#68](https://github.com/Nirtom84/PhreakNIC-CCG/pull/68) (fork CI passed) |
| B31 | Clarion Inn Staff's free buy is used up by the first matching card | Minor | engine ×1 | Issue [#69](https://github.com/Nirtom84/PhreakNIC-CCG/issues/69); fix in PR [#70](https://github.com/Nirtom84/PhreakNIC-CCG/pull/70) (fork CI passed) |
| B32 | What is Truth? becomes free after heartsh8ped (Walmart's "this card") | Minor | engine ×2 | Merged in v0.29: PR [#4](https://github.com/Nirtom84/PhreakNIC-CCG/pull/4) |
| B33 | Egg in Your Soup adds counters to every Sandwich Factory instead of one | Minor | engine ×1 | Issue [#66](https://github.com/Nirtom84/PhreakNIC-CCG/issues/66); fix in PR [#68](https://github.com/Nirtom84/PhreakNIC-CCG/pull/68) (fork CI passed) |
| B34 | CRT LAN Party and Speakers Needed reshuffle without `card_moved` (no shuffle sound) | Minor | engine ×2 | Issue [#67](https://github.com/Nirtom84/PhreakNIC-CCG/issues/67); fix in PR [#68](https://github.com/Nirtom84/PhreakNIC-CCG/pull/68) (fork CI passed) |
| B35 | A draw counts as a loss in lifetime stats | Minor | menu ×1 | Merged in v0.29: PR [#49](https://github.com/Nirtom84/PhreakNIC-CCG/pull/49) |
| B37 | Players without a Hero get "as —" in the share text and result card | Minor | menu ×3 | Merged in v0.29: PR [#49](https://github.com/Nirtom84/PhreakNIC-CCG/pull/49) |
| B38 | The desktop close button is ignored while a prompt is open | Minor | table ×1 | Issue [#78](https://github.com/Nirtom84/PhreakNIC-CCG/issues/78); fix in PR [#79](https://github.com/Nirtom84/PhreakNIC-CCG/pull/79) (fork CI passed) |
| B39 | Renaming the selected custom deck switches the selection to Tag Team | Minor | menu ×1 | Merged in v0.29: PR [#55](https://github.com/Nirtom84/PhreakNIC-CCG/pull/55) |
| B40 | The player count resets to 2 when the main menu reopens | Minor | menu ×2 | Merged in v0.29: PR [#55](https://github.com/Nirtom84/PhreakNIC-CCG/pull/55) |
| B41 | Music volume changed with the mouse wheel or keyboard isn't saved | Minor | menu ×2 | Merged in v0.29: PR [#55](https://github.com/Nirtom84/PhreakNIC-CCG/pull/55) |
| B42 | Ability buttons and tooltips show raw `{H}`/`{D}` tokens | Minor | table ×3 | Issue [#73](https://github.com/Nirtom84/PhreakNIC-CCG/issues/73); fix in PR [#74](https://github.com/Nirtom84/PhreakNIC-CCG/pull/74) (fork CI passed) |
| B43 | Signal connections grow with every card move | Minor | table ×1 | Issue [#81](https://github.com/Nirtom84/PhreakNIC-CCG/issues/81); fix in PR [#82](https://github.com/Nirtom84/PhreakNIC-CCG/pull/82) (fork CI passed) |
| B44 | The custom-deck D20 roll lingers after a refused start and into later games | Minor | worker ×3 | Merged in v0.29: PR [#39](https://github.com/Nirtom84/PhreakNIC-CCG/pull/39) |
| B45 | Double-tapping Start reports "servers are full" while the game is starting | Minor | worker ×1 | Merged in v0.29: PR [#39](https://github.com/Nirtom84/PhreakNIC-CCG/pull/39) |
| B48 | Custom-deck bots learn which card O.P.R.A.H. drew into a hidden hand | Minor | bots ×1 | Merged in v0.29: PR [#14](https://github.com/Nirtom84/PhreakNIC-CCG/pull/14) |
| B55 | Leaving after being knocked out at Instant bot pace hangs the game in an endless error loop | Medium | menu ×1 | Issue [#87](https://github.com/Nirtom84/PhreakNIC-CCG/issues/87); fix in PR [#88](https://github.com/Nirtom84/PhreakNIC-CCG/pull/88) (fork CI passed) |

## Findings originally without an automated check

| ID | Bug | Why there's no check | Status |
|---|---|---|---|
| B19 | Most suites pass even when SCRIPT ERRORs occur | About the test harness itself | Merged in v0.29: PR [#23](https://github.com/Nirtom84/PhreakNIC-CCG/pull/23) |
| B36 | Online custom-deck games are recorded as offline and "Script Kiddie" | Originally blocked by B05; the merged stats fix adds coverage in `tests/v17_checks.gd` | Merged in v0.29: PR [#49](https://github.com/Nirtom84/PhreakNIC-CCG/pull/49) |
| B46 | The online server README lists outdated rate-limit numbers | Documentation fix | Merged in v0.29: PR [#24](https://github.com/Nirtom84/PhreakNIC-CCG/pull/24) |
| B49 | `tools/build_all.sh release` stages a debug-signed APK when the signing setup is missing | Build script | Merged in v0.29: PR [#26](https://github.com/Nirtom84/PhreakNIC-CCG/pull/26) |
| B50 | README's test commands wipe real user data unless `XDG_DATA_HOME` is set | Documentation and harness | Merged in v0.29: PR [#24](https://github.com/Nirtom84/PhreakNIC-CCG/pull/24) |
| B51 | Exports ship `reference/`, `decks/custom/` and the baseline bots | Export filters | Merged in v0.29: PR [#28](https://github.com/Nirtom84/PhreakNIC-CCG/pull/28) |
| B52 | A suite whose `run()` aborts hangs CI for 25 minutes | Harness | Merged in v0.29: PR [#23](https://github.com/Nirtom84/PhreakNIC-CCG/pull/23) |
| B53 | Housekeeping: unused `tools/card_data_0*.json`, an incomplete README test list, a "300-game" CI comment | Documentation | Docs/CI merged in PRs #23/#24; remaining file cleanup in PR [#75](https://github.com/Nirtom84/PhreakNIC-CCG/pull/75) |
| B54 | `link_server.gd` logs harmless errors when a socket drops | Log noise | Merged in v0.29: PR [#41](https://github.com/Nirtom84/PhreakNIC-CCG/pull/41) |
| B56 | `tests/v22_checks.gd` is flaky (about 4% of runs): it reserves whichever card the clock-seeded row deals first, and a card with a buy prompt (mog, Nuvious, Fore04) collides with B17. Seeds 6, 15, 101, 132, 136, 140, 141, 145, 178, 200 and 215 always fail | Fix belongs in that test (fixed seed) and B17 | Merged in v0.29: PR [#30](https://github.com/Nirtom84/PhreakNIC-CCG/pull/30) |

## Designer rulings — resolved in v0.29

- **Q1 / [#6](https://github.com/Nirtom84/PhreakNIC-CCG/issues/6):** Ruling 26 resolves all damage, including overflow to life, before last-counter text; eliminated players do not resolve it.
- **Q2 / [#7](https://github.com/Nirtom84/PhreakNIC-CCG/issues/7):** Ruling 27 only moves Rickroll from the discard pile; otherwise the replacement is used without moving it.
- **Q3 / [#8](https://github.com/Nirtom84/PhreakNIC-CCG/issues/8):** Ruling 28 uses the copied Location's cost.
- **Q4 / [#9](https://github.com/Nirtom84/PhreakNIC-CCG/issues/9):** Ruling 29 confirms that taking another player's permanent counts as acquiring; the engine already did this.

## Regression-test compatibility

- B01's Mog trace, B27's deck-editor expectation and B35's loss fixture were updated in the merged fixes.
- B30's existing “JousterL stays in discard” check still passes: its scripted choice selects a different discard card. The card-fix branch updates one legacy trace and adds explicit self-selection coverage.
- B31's existing “Staff free-buy token” check still passes because that player cannot pay the normal price; the new test covers saving the token when payment is possible.
- B48's existing census check still passes: its decks do not contain O.P.R.A.H. The merged fix adds separate hidden-draw checks.
- The v0.29 copy-cost test introduced a `restaurant` variable that collided with B33's new test. The refreshed card-fix branch renames its local variable to `factory_copy`.

## Additional finding during integration

- **B57:** `v21_checks` sometimes fails repeatability comparisons because fixed-count searches still use the live 80 ms cutoff. Issue [#89](https://github.com/Nirtom84/PhreakNIC-CCG/issues/89), test-only fix in PR [#90](https://github.com/Nirtom84/PhreakNIC-CCG/pull/90). The production time limits remain unchanged.
