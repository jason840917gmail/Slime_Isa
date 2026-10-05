# Universal Scene Conversion Ledger

This file summarizes the checked-in machine ledger. Regenerate both with `node scripts/inventory-scene-conversion.mjs --write`.

## Coverage

| Family | Rows |
| --- | ---: |
| animation | 34 |
| area | 4 |
| asset | 70 |
| boss | 1 |
| character | 11 |
| effect | 5 |
| enemy | 3 |
| game-constants | 1 |
| item | 10 |
| map | 15 |
| npc | 5 |
| object | 27 |
| projectile | 1 |
| quest | 1 |
| recipe | 11 |
| terrain | 14 |
| ui | 15 |
| visual | 12 |
| weapon | 10 |
| **Total** | **250** |

Authored maps: 15 (3 production, 12 development/test).

Stable authored map instance persistence keys: 5314.

## Legacy writer endpoints

- `/__animation-library/catalog` — `src/game/content/animations/animationContentModulesPlugin.ts`
- `/__animation-library/references` — `src/game/content/animations/animationContentModulesPlugin.ts`
- `/__animation-library/save` — `src/game/content/animations/animationContentModulesPlugin.ts`
- `/__animation-library/transaction` — `src/game/content/animations/animationContentModulesPlugin.ts`
- `/__character-studio/asset/register` — `src/game/content/characters/characterContentModulesPlugin.ts`
- `/__character-studio/create` — `src/game/content/characters/characterContentModulesPlugin.ts`
- `/__character-studio/effect/create` — `src/game/content/characters/characterContentModulesPlugin.ts`
- `/__character-studio/effect/update` — `src/game/content/characters/characterContentModulesPlugin.ts`
- `/__character-studio/package/create` — `src/game/content/characters/characterContentModulesPlugin.ts`
- `/__character-studio/package/duplicate` — `src/game/content/characters/characterContentModulesPlugin.ts`
- `/__character-studio/package/update` — `src/game/content/characters/characterContentModulesPlugin.ts`
- `/__character-studio/projectile/create` — `src/game/content/characters/characterContentModulesPlugin.ts`
- `/__character-studio/projectile/update` — `src/game/content/characters/characterContentModulesPlugin.ts`
- `/__character-studio/weapon/create` — `src/game/content/characters/characterContentModulesPlugin.ts`
- `/__character-studio/weapon/save-package` — `src/game/content/characters/characterContentModulesPlugin.ts`
- `/__character-studio/weapon/update` — `src/game/content/characters/characterContentModulesPlugin.ts`
- `/__game-constants` — `src/game/content/gameConstantsContentPlugin.ts`
- `/__map-editor/create` — `vite.config.ts`
- `/__map-editor/object-gameplay/update` — `vite.config.ts`
- `/__map-editor/object-template/create` — `vite.config.ts`
- `/__map-editor/object-template/duplicate` — `vite.config.ts`
- `/__map-editor/object-template/update` — `vite.config.ts`
- `/__map-editor/save` — `vite.config.ts`

## Category routes

- `?editor=` — `src/game/config.ts`
- `?studio=` — `src/game/config.ts`

## Baseline hashes

- `asset/assets.json`: `c00387078084bc3dda311a18f6563c81fcc1b0e4a303a78f175882d644601257`
- `src/game/content/maps/174.map.json`: `58dc34b6b8c6f5587877c969e0db1a9eb5c2ed7aa76f501fd5fe54767dd15956`
- `src/game/content/maps/236.map.json`: `348342e61177101372c00cd1e94c6bcca0e6413fec84d85136e4cf3be5281204`
- `src/game/content/maps/cole.map.json`: `5fe7975fcf757007a7f16a01c8176ec7f92b4310266e2a25a5a506ae4bc21f3a`
- `src/game/content/maps/crystal-caverns.map.json`: `644d80315d4c797ea163f404f105079026deea25a25dc4896539ca1209b6d2e1`
- `src/game/content/maps/depth-occlusion-test.map.json`: `cbfffa9b13d232ed0820b9294cf0130a3c0f3f6c45b4d2ffcf77d10e01e6dbe7`
- `src/game/content/maps/emberleef.map.json`: `4eaadfd296cb0e3e2e36c2685613e15528ce04ef2593c16b27f42e39aabb72da`
- `src/game/content/maps/girls.map.json`: `2e4f05a21cfaac342260423fc54ee04221bf4939eb2bb92659f342e06379b47a`
- `src/game/content/maps/gloop-forest.map.json`: `ffabefb94e4f687f41c39804e44d4aa37d4301798cc8a054d3c0477d09952f11`
- `src/game/content/maps/hot.map.json`: `f7725467df862174d2ab96166510eb47f59da62235cf8c3d000e612128855d47`
- `src/game/content/maps/icege.map.json`: `19176ee36d467c12c812a676251d339fdcfdc7a33aadb33a78f987fbebd76908`
- `src/game/content/maps/jk.map.json`: `893be3224514da1cbc457a6afb3371cfc8f8ffba76e3504874ecf21e200b9e63`
- `src/game/content/maps/level-1.map.json`: `12fb29a9fd813961c1168626d0d48742cbbb602abbbe21af773115d9e8859f61`
- `src/game/content/maps/meadow-crossing.map.json`: `6087a78804ca97bc7d63e6bb494b4de93ae8283810e2243d6d22d0b1c4392730`
- `src/game/content/maps/test-rectangle.map.json`: `86ce85bbb2d1a8411330e74cdc075a4d952483f150fe52362df6509933ff8ff5`
- `src/game/content/maps/tiktok.map.json`: `a894efa825b8cc5b91810d1da40763cb81d4df51c790d85f7e72c035467960c0`

Every row records its current validator/catalog, construction owner, writable endpoint, destination ID, persistence keys, migration package, focused checks, and removal package in the JSON ledger.
