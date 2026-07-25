# Combat Hit Feedback Implementation Plan

1. Make `GameState.damage` return the actual clamped HP loss and make `HealthSystem.applyDamage` return an accepted/rejected `DamageResult`.
2. Route that result to `WorldScene` so floating text shows actual HP lost and accepted hits alone trigger feedback.
3. Extend enemy melee and projectile damage requests with normalized incoming direction and per-enemy knockback strength.
4. Add a 160 ms player movement-suppression window, a red hit flash, and 500 ms accepted-hit invulnerability.
5. Remove enemy attack telegraph tint while preserving the enemy damaged flash.
6. Tune raw damage to archer 22, swordsman 37, and brawler 52; tune knockback to 180, 260, and 340.
7. Ignore cursor aim when attacks are triggered; lock attacks to the player controller’s current facing.
8. Run enemy/content validators, TypeScript, production build, and browser smoke tests for projectile/melee damage feedback.
