# Knockback Animation State Design

## Status

Completed and verified.

## Goal

Knockback must look like a character sliding backward from an impact while continuing to face the direction it was facing before the hit. Knockback velocity is a temporary physical effect, not intentional movement, and must never make a character turn around or play a walking animation.

The visual contract must also support dedicated authored knockback frames later, even though the current spritesheets do not contain them.

## Required visual clips

Every active enemy visual set must define:

- `knockback-side`;
- `knockback-up`;
- `knockback-down`.

The player visual set must define:

- `knockback`.

For now, each clip contains one existing directional frame, has `repeat: 0`, and uses a valid positive frame rate. These are explicit placeholders, not runtime fallbacks. Future art or editor tooling can replace the frame lists without changing gameplay code.

`scripts/check-enemies.mjs` must require the three directional enemy knockback clips. `scripts/check-visuals.mjs` must statically require the player visual set to contain `knockback`; the game must not defer discovery of a missing player clip until the first hit.

## Enemy behavior

When an enemy accepts damage:

1. Capture no new facing from the incoming knockback vector.
2. Preserve the enemy’s existing `direction` and `sideFlipped` values.
3. Cancel any active attack sequence.
4. Apply knockback velocity and extend hit-stun to `max(existingHitStunUntil, now + calculatedHitStunDuration)`.
5. Play `knockback-${direction}` using the preserved direction.

During hit-stun:

- velocity decays using the existing drag behavior;
- the visual remains on the knockback clip;
- velocity must not call `updateDirection`;
- velocity must not select `walk` or `idle`;
- another accepted hit extends hit-stun using the same deadline rule and forcibly restarts the preserved directional knockback clip without turning the enemy. The forced restart bypasses same-clip deduplication so future multi-frame knockback art restarts from its first frame.

On the first update after hit-stun ends, normal AI resumes. Only intentional chase, flee, or wander velocity may then update facing and select a movement animation.

Death has higher priority than knockback. A lethal hit immediately switches to the directional death clip instead of leaving the knockback placeholder visible.

## Player behavior

When an accepted player hit applies knockback:

1. Preserve the player controller’s current facing.
2. Apply the existing normalized knockback velocity and 160 millisecond movement-suppression window.
3. Play the static `slime-knockback` clip.
4. Prevent movement, attack, ability, and action-completion animation requests from replacing it while movement remains suppressed.

The scene owns a knockback visual-priority deadline matching movement suppression. While active, the central player animation dispatcher ignores every requested animation except `slime-die` and an explicit forced `slime-knockback` restart. While `HealthSystem.isDead()` is true, the dispatcher rejects every animation request except `slime-die`, independently of the knockback deadline. Gameplay timers for attacks and abilities continue; only their lower-priority visual requests are suppressed. When suppression ends, the normal movement update selects idle or movement animation from player input. Red hit flash and 500 millisecond damage invulnerability remain independent of the knockback animation duration.

On a lethal hit, player death has immediate priority: `HealthSystem` skips the knockback callback, `WorldScene` selects `slime-die`, and no later accepted-hit callback may replace death with `slime-knockback`. The final damage number may still be displayed.

## State priority

From highest to lowest:

1. death;
2. knockback/hit-stun;
3. attack or ability action;
4. intentional movement;
5. idle.

This priority ensures physical knockback cannot be misrepresented as walking and cannot override death.

## Future editor support

A future character/enemy visual editor should expose knockback as a standard animation action alongside idle, walk, attack, and death. It should allow directional frame lists, frame timing, per-frame visual offsets/scales, and previewing the clip while the stable physics anchor slides in the opposite direction.

The editor changes visual definitions only. Knockback strength, resistance, hit-stun duration, velocity decay, and state priority remain runtime gameplay rules.

## Validation

Implementation is complete when:

- all three real enemy visual sets contain the required directional knockback clips;
- the player visual set contains `knockback`;
- enemy validation rejects a real enemy missing any directional knockback clip;
- visual validation rejects a player visual set missing `knockback`;
- a nonlethal enemy hit preserves the pre-hit direction and horizontal flip for the entire hit-stun;
- enemy knockback never selects a walk animation;
- repeated enemy hits extend the deadline with `max(existingUntil, now + duration)`, forcibly restart the knockback clip, and do not turn the enemy;
- a lethal enemy hit selects death rather than knockback;
- an accepted player hit selects `slime-knockback` during movement suppression;
- player input and attack/ability completion callbacks do not replace that clip during the 160 millisecond suppression window;
- a lethal player hit selects `slime-die`, skips knockback animation/velocity, and cannot be overwritten by accepted-hit feedback or pending attack/ability completion callbacks;
- static checks, TypeScript, production build, and a browser smoke test pass without runtime errors.
