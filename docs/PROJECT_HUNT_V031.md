# Whole-project bug-hunt pass — v0.31

Reviewed November 16, 2026 against upstream `63eb4a499b9586e7e04c41651de84b787cbc7ec9`. Upstream was fetched again and had not advanced. Local branch: `hunt/project-v031-wide`, based on the three online-hunt checkpoints.

This pass confirms **three additional bugs**, spanning game rules, local saves and the website. Together with the twelve previously documented findings, the current hunt contains fifteen distinct findings. Production logic is unchanged. These are reproducible review findings, not completed fixes; no new issues, PRs, deployments or branch pushes were made.

| ID | Priority | Area | Confirmed behavior |
|---|---|---|---|
| W31-02 | Medium | Local saves / custom Hero selection | A legitimate Hero selection can make later base-set saves unreadable, despite successful writes. |
| W31-03 | Medium | Rules / custom decks | Different-state copies with the same name skip simultaneous-effect ordering; play-area order can decide the winner. |
| W31-01 | Medium | Website / invite integration | Current six-character room codes do not match the site's four-character invite redirect. |

Priorities describe gameplay/usability impact, not security severity. IDs are separate from the ON31 series so the earlier findings remain stable.

## W31-02 — selecting a custom Hero can disable Resume for a later base-set game

Locations: [custom Hero offerings](../scripts/ui/style.gd#L153), [menu Hero selection](../scripts/ui/menu.gd#L415), [card-set switch](../scripts/ui/menu.gd#L228), [table avatar metadata](../scripts/ui/table.gd#L279), [save writer](../scripts/ui/table.gd#L1783), [save reader validation](../scripts/core/save_game.gd#L219).

The custom catalog exposes separate Mog printing IDs, such as `JousterL@mog` (MogsterL), in the Hero picker. Selecting one stores that ID in `Sfx.hero_id`. Switching the main menu back to the base set changes the card catalog but preserves the ID.

A subsequently launched local table copies that ID into `seat_heroes`. The save writer accepts it and returns success. The reader validates every avatar against the saved game's card catalog; the base-set catalog does not contain `JousterL@mog`, so it rejects the entire save. The rules snapshot and match-statistics record themselves are valid.

Reproduction using actual menu/table handlers:

1. Select the custom card set and choose MogsterL from the Hero picker.
2. Click the normal Base Set button, then launch a local game.
3. Reach the human's turn and save.
4. Read the save through `SaveGame.read()`, the same path the menu uses to offer Resume.

Observed: `pool=2025`, `hero=JousterL@mog`, the file exists, `save_game()` returns true, but `SaveGame.read()` returns `{}`. The game remains playable in the current session, while the menu cannot resume its save. This is rejection of an existing file, not physical deletion of it.

Controls: the selected ID is actually offered by `UIStyle.heroes()`; the stock menu set-switch callback preserves it; card conservation passes; `SaveGame.restore(raw.game)` and `valid_match_stats(raw.table)` both succeed. Changing only the table's avatar ID to `JousterL` and saving the same game makes it readable.

Suggested correction: keep avatar selection valid across set switches, or validate/resolve avatars independently of the game's playable card catalog. Validate metadata before reporting a successful save, and consider recovering otherwise valid existing saves whose only invalid field is an avatar. Do not discard valid progress merely to repair an image choice.

This differs from the previous custom-deck rename issue #52 and eliminated-player resume issue #50. Neither is involved in this reproduction.

## W31-03 — identical names suppress a strategically necessary trigger-order choice

Locations: [simultaneous trigger resolver](../scripts/core/rules.gd#L571), [start-of-turn triggers](../scripts/core/effects.gd#L1121), [The Juice counter/loss effect](../scripts/core/effects.gd#L1143). Expected behavior: [confirmed start-of-turn ordering rule](../reference/rules.md#L159).

`resolve_triggers()` asks the active player for an order only if at least two pending display names differ and the triggers are not all marked as commuting. Equal names do not establish that effects are interchangeable: two copies can have different counters or other state.

The custom-deck format legally allows multiple copies of The Juice. At the beginning of a turn, each copy adds a counter; reaching the fifth counter eliminates its controller, while lower totals deal that much damage to opponents.

Reproduction:

1. Use a validated custom deck containing two copies of The Juice.
2. Put both on the active player's board, one at four counters and the other at zero. Set the opponent to one life. These are legal card/counter states; the fixture moves existing physical instances and checks conservation.
3. At the start of the turn, the player wants the zero-counter copy to resolve first: it reaches one counter, deals one damage and wins the game before the other trigger resolves.
4. Place the four-counter copy earlier in the play-area array. The decider is prepared to select the second trigger if asked.

Observed: no order choice is requested. The first copy reaches five counters, eliminates the active player and awards the opponent the game. Reversing only the two copies' counter placement lets the active player win, again without a choice. The same pair of simultaneous effects produces opposite winners solely from internal ordering.

Suggested correction: do not use equal display names as a substitute for proving effects commute. Offer an order for these triggers and distinguish copies in the UI using counters or other relevant state. Keep the existing suppression for effects explicitly known to commute.

This is independent of the prior TOCTOU findings and issue #61's simultaneous life-loss handling: no reaction turn or simultaneous-damage group occurs here.

## W31-01 — current invite links miss the site's redirect

Locations: [six-character generator and validator](../cloudflare/online/src/lib/protocol.js#L2), [actual invite-link construction](../scripts/ui/online.gd#L333), [four-character site route](../cloudflare/site/src/index.js#L32), [site assets configuration](../cloudflare/site/wrangler.jsonc#L7).

The Room service generates six-character codes and accepts both six-character and legacy four-character codes. The lobby's Copy invite link button constructs `https://phreaknic-ccg.net/join/<code>`. The website still matches only `{4}` characters in this path, so new codes miss the redirect to `/?join=<code>` and instead reach `ASSETS.fetch()` as a nonexistent file path.

The checked-in assets configuration does not enable a single-page-application fallback. Cloudflare documents that `ASSETS.fetch()` applies the configured missing-asset handling, and that returning `index.html` for unmatched routes requires the SPA setting. [Assets binding documentation](https://developers.cloudflare.com/workers/static-assets/binding/), [static asset routing](https://developers.cloudflare.com/workers/static-assets/#routing-behavior).

Local reproduction calls the actual site Worker with an asset-miss binding:

- Legacy `/join/AB23` returns `302` to `/?join=AB23` without touching the asset binding.
- A six-character code from the actual current generator, `222222`, passes the room validator but `/join/222222` reaches the asset binding and returns its `404` instead of redirecting.

This proves the route mismatch and the outcome with the configured asset-miss behavior. It is not a live deployment test: no room was created or joined, and no request was sent to the production game service.

Suggested correction: accept both currently supported code lengths in the website redirect, ideally sharing the validator, and add a contract test that feeds generated codes into the real site handler. Update the README's four-character description as part of that correction. The existing site test exercises only `/join/AB23` and checks security headers, not compatibility with newly generated room codes.

## Scope and validation

The pass broadened beyond the online lifecycle into these areas:

| Area | Review/verification performed |
|---|---|
| Rules and card data | Read core action, damage, elimination, trigger, copy, acquisition and start/end-turn paths against checked-in rulings; reproduced the duplicate-trigger outcome. |
| Saves and local play | Traced snapshot validation, menu launch/resume, identity persistence and table saving; reproduced the custom-Hero save rejection. |
| Custom decks and UI | Reviewed deck validation/code bounds, editor persistence, set switches, Hero selection, tutorial/back handling, stats and sharing paths; ran the custom UI suite. |
| Bots and training tools | Reviewed turn-driving and decision boundaries plus benchmark, fit and self-play orchestration/reporting paths. No additional finding established; no new large training campaign was run. |
| Website and online integration | Checked current code generation, invite construction, site routing/assets/cache handling, and existing public issues; ran the Worker suite. Earlier online findings remain in their own reports. |
| Builds and project tooling | Inspected CI, export presets, build/release and deploy scripts; parsed Python tooling and checked shell syntax. No native exports, deployments or hardware-specific behavior were exercised in this pass. The separate Apple PR was not modified. |
| Sound and touch | Reviewed music lifecycle and touch/modal routing. No additional defect was established; these were source reviews, not physical-device/audio-device tests. |

New standalone reproductions (intentionally excluded from normal CI):

```sh
XDG_DATA_HOME=$(mktemp -d) ~/.local/bin/godot4.7.1 --headless --path . -s tests/project_hunt_checks.gd
node --test tests/project_hunt_site.mjs
```

| Suite | Checks/tests | Failed |
|---|---:|---:|
| New `project_hunt_checks.gd` | 15 | 3 expected assertions, covering W31-02 and W31-03 |
| New `project_hunt_site.mjs` | 2 | 1 expected assertion, covering W31-01 |
| Existing `rules_checks_runner.gd` | 161 | 0 |
| Existing `save_checks.gd` | 1,608 | 0 |
| Existing `v25_ui_checks.gd` | 1,014 | 0 |
| Existing Worker tests | 70 | 0 |

All twelve Godot control assertions and the legacy-invite control pass. Godot version: `4.7.1.stable.official.a13da4feb`. Every Godot invocation used an isolated `XDG_DATA_HOME`; actual user saves/settings/stats were not touched. The final reproduction and baseline logs contain no `SCRIPT ERROR`. Existing and new headless UI runs can emit resource-cleanup warnings at exit; these are not findings. Python AST parsing and `bash -n` checks passed for the tooling inspected.

Existing issue titles and bodies were checked for overlap. Rejected leads included a Restaurant copying Touch Grass (Grass is Technology, not Location), Mog's Ice Cream's play-order dependency (explicitly intended by Ruling 5), and online elimination deleting a local save (the code already guards that path). This is a broad review pass, not an assertion that unreported areas are bug-free.
