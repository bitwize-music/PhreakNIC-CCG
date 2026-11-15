# Public bug-fix checkpoint — November 15, 2026

Upstream v0.29 (`ee51d60`) contains the earlier 18 merged fix PRs and Rulings 26–29. The remaining public fixes were recovered, refreshed against v0.29, tested and submitted below. These are proposals awaiting upstream review/merge; they are not part of the v0.29 release.

## Submitted changes

| Bug IDs | Change | Issues | PR | Fork CI |
|---|---|---|---|---|
| B04, B23 | `toctou-reaction-turns` | [#58](https://github.com/Nirtom84/PhreakNIC-CCG/issues/58), [#59](https://github.com/Nirtom84/PhreakNIC-CCG/issues/59) | [#60](https://github.com/Nirtom84/PhreakNIC-CCG/pull/60) | [Passed](https://github.com/bitwize-music/PhreakNIC-CCG/actions/runs/43753953178) |
| B08 | `rookie-numbers-draw` | [#61](https://github.com/Nirtom84/PhreakNIC-CCG/issues/61) | [#62](https://github.com/Nirtom84/PhreakNIC-CCG/pull/62) | [Passed](https://github.com/bitwize-music/PhreakNIC-CCG/actions/runs/43753954698) |
| B24 | `grass-expiry-after-steal` | [#63](https://github.com/Nirtom84/PhreakNIC-CCG/issues/63) | [#64](https://github.com/Nirtom84/PhreakNIC-CCG/pull/64) | [Passed](https://github.com/bitwize-music/PhreakNIC-CCG/actions/runs/43754050361) |
| B09 | `stolen-attachment-owner` | [#85](https://github.com/Nirtom84/PhreakNIC-CCG/issues/85) | [#86](https://github.com/Nirtom84/PhreakNIC-CCG/pull/86) | [Passed](https://github.com/bitwize-music/PhreakNIC-CCG/actions/runs/43754052288) |
| B30, B33, B34 | `card-fixes` | [#65](https://github.com/Nirtom84/PhreakNIC-CCG/issues/65), [#66](https://github.com/Nirtom84/PhreakNIC-CCG/issues/66), [#67](https://github.com/Nirtom84/PhreakNIC-CCG/issues/67) | [#68](https://github.com/Nirtom84/PhreakNIC-CCG/pull/68) | [Passed](https://github.com/bitwize-music/PhreakNIC-CCG/actions/runs/43754233443) |
| B31 | `free-buy-choice` | [#69](https://github.com/Nirtom84/PhreakNIC-CCG/issues/69) | [#70](https://github.com/Nirtom84/PhreakNIC-CCG/pull/70) | [Passed](https://github.com/bitwize-music/PhreakNIC-CCG/actions/runs/43754316339) |
| B10, B29, B42 | `phone-board` | [#71](https://github.com/Nirtom84/PhreakNIC-CCG/issues/71), [#72](https://github.com/Nirtom84/PhreakNIC-CCG/issues/72), [#73](https://github.com/Nirtom84/PhreakNIC-CCG/issues/73) | [#74](https://github.com/Nirtom84/PhreakNIC-CCG/pull/74) | [Passed](https://github.com/bitwize-music/PhreakNIC-CCG/actions/runs/43754408472) |
| B14, B28, B38 | `back-escape-table` | [#76](https://github.com/Nirtom84/PhreakNIC-CCG/issues/76), [#77](https://github.com/Nirtom84/PhreakNIC-CCG/issues/77), [#78](https://github.com/Nirtom84/PhreakNIC-CCG/issues/78) | [#79](https://github.com/Nirtom84/PhreakNIC-CCG/pull/79) | [Passed](https://github.com/bitwize-music/PhreakNIC-CCG/actions/runs/43754514423) |
| B15, B43 | `ui-performance` | [#80](https://github.com/Nirtom84/PhreakNIC-CCG/issues/80), [#81](https://github.com/Nirtom84/PhreakNIC-CCG/issues/81) | [#82](https://github.com/Nirtom84/PhreakNIC-CCG/pull/82) | [Passed](https://github.com/bitwize-music/PhreakNIC-CCG/actions/runs/43754675147) |
| B17 | `dialog-stacking` | [#83](https://github.com/Nirtom84/PhreakNIC-CCG/issues/83) | [#84](https://github.com/Nirtom84/PhreakNIC-CCG/pull/84) | [Passed](https://github.com/bitwize-music/PhreakNIC-CCG/actions/runs/43754747723) |
| B55 | `leave-hang` | [#87](https://github.com/Nirtom84/PhreakNIC-CCG/issues/87) | [#88](https://github.com/Nirtom84/PhreakNIC-CCG/pull/88) | [Passed](https://github.com/bitwize-music/PhreakNIC-CCG/actions/runs/43754936164) |
| B53 | Unused card transcription files | [#22](https://github.com/Nirtom84/PhreakNIC-CCG/issues/22) | [#75](https://github.com/Nirtom84/PhreakNIC-CCG/pull/75) | [Passed](https://github.com/bitwize-music/PhreakNIC-CCG/actions/runs/43754230997) |
| B57 | DEFCON repeatability test scheduling | [#89](https://github.com/Nirtom84/PhreakNIC-CCG/issues/89) | [#90](https://github.com/Nirtom84/PhreakNIC-CCG/pull/90) | [Passed](https://github.com/bitwize-music/PhreakNIC-CCG/actions/runs/43754994628) |

The [known-bug ledger](../tests/KNOWN_BUGS.md) also records the bugs already fixed in v0.29 and the resolved designer questions.

## Validation

- Every bug-fix branch passes its targeted local suites and corresponding known-bug checks, then full fork CI before submission.
- With all 11 original fixes combined: all 155 Godot known-bug/control checks pass; all 9 explicit Worker known-bug/control tests pass; all 64 regular Worker tests pass.
- The combined regular Godot suites and legacy trace checks pass. The 450-game simulation completes with 230,825 checks and zero failures.
- The combined [Known bugs CI job](https://github.com/bitwize-music/PhreakNIC-CCG/actions/runs/43754996201) passes.
- B55's uncommitted post-search checks were preserved alongside v0.29's DEFCON waiting-time accounting. A new test-variable collision with v0.29's copy-cost ruling was corrected in the card-fix branch.
- The attachment branch's first fork CI attempt hit the pre-existing DEFCON repeatability flake; its original failure is retained in the run history. A separate test-only fix gives exact fixed-count comparisons a scheduling allowance, verifies completion, and preserves production time-limit tests. An injected 100 ms delay exposes incomplete batches under the old allowance; the corrected fixture passes all 471 checks with the delay and fresh isolated data.

## Branches and remaining work

- `known-bug-tests` tracks upstream plus the reproductions and this ledger. Its known-bug job remains red while upstream lacks the proposed fixes; this is intentional.
- [review/remaining-fixes-v029](https://github.com/bitwize-music/PhreakNIC-CCG/tree/review/remaining-fixes-v029) combines all fixes, the cleanup, the separate repeatability-test fix and the known-bug suites for review. Individual `fix/*-v029` branches remain independent PRs based on v0.29.
- Maintainers still need to review and merge the PRs and release the changes. Upstream PR CI runs separately from the successful fork runs linked above.
- Private security findings remain outside these public submissions. Private reporting is enabled under [SECURITY.md](../SECURITY.md); no submission of those findings is recorded here.
