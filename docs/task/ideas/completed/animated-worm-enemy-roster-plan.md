# Animated worm enemy roster implementation plan

Status: completed and verified.

1. Register the three character sheets, arrow, and hit sheet in the asset manifest; add populated frame counts to the manifest schema and validators.
2. Add archer, swordsman, brawler, and brawler-effect visual sets with the reviewed frame lists.
3. Add the JSON enemy catalog and validator; make maps validate against its three stable IDs.
4. Refactor `Enemy` around a stable physics anchor, directional clip selection, typed attack sequences, one-shot melee damage, and animated death.
5. Route archer shots through the authored arrow and spawn the brawler hit animation at impact.
6. Replace map/editor/bake spawn IDs with the three active worms and disable Blobfather runtime wiring.
7. Preserve every removed enemy and boss definition in a future-enemies idea document, then remove obsolete procedural textures.
8. Run asset, visual, enemy, object, map, type, build, and browser smoke checks.
