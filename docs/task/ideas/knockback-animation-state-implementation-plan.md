# Knockback Animation State Implementation Plan

1. Add one-frame `knockback-side`, `knockback-up`, and `knockback-down` clips to each real enemy visual set and a one-frame `knockback` clip to the player visual set.
2. Extend enemy and visual validation so those clips are statically required.
3. Add `knockback` to the enemy visual-action state, preserve pre-hit facing, force-restart the clip on repeated hits, and stop deriving direction or movement animation from knockback velocity.
4. Add a player visual-priority deadline matching movement suppression; force `slime-knockback` for accepted nonlethal hits.
5. Protect `slime-die` from knockback, attack, ability, and delayed action-completion animation requests.
6. Run all content validators, TypeScript, production build, and browser smoke tests.
