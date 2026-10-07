## Completed

- [x] The former starter map used its authored map JSON as the source of truth
  for houses and enemy-spawn authorization.

  Solution: removed runtime procedural house and bed placement. Houses were
  painted only from authored map JSON through `MapBuilder`. Enemy spawning now
  runs only when the loaded map JSON contains `spawns`; a missing `spawns`
  section produces no monsters. The automatic training dummy was also removed,
  while the explicit debug hotkey remains available.
