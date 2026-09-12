# Fatty Player-Death and Return Interruption Fix

## Goal

Fix two Fatty One Eye state-machine failures without changing encounter balance or presentation:

1. A lethal Fatty attack must complete its current update safely instead of destroying the boss re-entrantly and breaking the game.
2. A Fatty who is walking back to the arena center must immediately resume pursuit when the living player enters the combat arena.

## Player-death reset

`WorldScene` continues to notify `BossCampController` through `resetActiveFights()` when player health reaches zero. The controller will no longer destroy a live boss synchronously from that call. It marks the camp for a pending transient reset instead.

Each camp record owns `pendingTransientReset` and `suppressSpawnUntilOutside`, both initially `false`. Repeated reset requests are idempotent. `resetActiveFights()` marks every live, non-dead boss as pending.

`BossCampController.update()` applies pending resets at deterministic safe points:

1. A reset already pending when a camp iteration starts is flushed before that boss, its health bar, cleanup, or spawn logic is updated.
2. A reset requested from inside the currently executing boss update is flushed immediately after that update returns, before health-bar updates, inactive-boss cleanup, any later camp's boss update, or spawn evaluation.
3. Flushing destroys the boss and health bar, clears `pendingTransientReset`, enables `suppressSpawnUntilOutside`, and ends that camp iteration so it cannot respawn in the same frame.

This guarantees a lethal contact-hop or leap callback can unwind before its runner, sprites, physics body, and presentation objects are destroyed. With multiple camps, later pending camps are flushed at the beginning of their iteration rather than receiving another update.

After the reset, the camp suppresses spawning while the player remains inside its activation perimeter, including its exact boundary. Observing the player outside clears the suppression; because the player is then outside, no spawn occurs until a later entry. A successful spawn clears both flags. This prevents Fatty from respawning over the defeated player during the death delay.

True boss defeat has precedence over a pending transient reset. `onDefeated` clears the pending flag without applying transient reset or spawn suppression, then preserves the normal persisted respawn deadline and exit/re-entry state. Destroying the controller discards both flags with the camp records.

## Return interruption

The player's combat-arena containment controls whether Fatty may begin pursuit or a new attack:

- Whenever the player is outside the combat arena, a grounded Fatty enters or remains in `return-to-center`, even if Fatty is already inside the arena.
- On reaching the authored center while the player remains outside, Fatty stops there but stays in `return-to-center`. He does not transition to chase, start contact hop, or begin the long-jump sequence.
- While in `return-to-center`, a player entering the combat arena immediately changes Fatty to `chase` with the current leap deadline preserved.
- The chase update may target the player normally even while Fatty is still outside, allowing him to walk back through pursuit rather than resuming the return state on the following frame.
- If the player leaves again, Fatty resumes returning to center.

Airborne, landing, recovery, contact-hop, and an already-started long-jump windup remain uninterruptible. Fatty may therefore finish an attack outside the arena if the player exits after it starts. The containment decision is applied once that action finishes, but no new attack may start while the player is outside.

## Automated verification

Add pure behavior tests for return eligibility, waiting at center, pursuit resumption, inclusive boundaries, and an overdue leap deadline. Add source wiring coverage proving contact hop and long-jump startup are unreachable while the player is outside. Add controller regression coverage for reset-before-update, reset-during-update, repeated requests, multiple camps, spawn suppression, and true-defeat precedence. Run boss tests, strict TypeScript validation, and the production build. Do not perform browser or visual testing.

## Manual acceptance checks

The user should verify lethal contact-hop and large-leap deaths, the full death/respawn delay, and entering/leaving the combat arena while Fatty is visibly walking toward center.
