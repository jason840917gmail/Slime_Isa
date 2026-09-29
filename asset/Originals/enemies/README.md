# Worm enemy sheets

Each PNG is an `8 × 6` sheet of `64 × 64` frames on solid `#8000FF`.

| Row | Columns 1–4 | Columns 5–8 |
| --- | --- | --- |
| 1 | Side idle | Side walk |
| 2 | Side attack | Side die |
| 3 | Up idle | Up walk |
| 4 | Up attack | Up die |
| 5 | Down idle | Down walk |
| 6 | Down attack | Down die |

Side frames face right and can be flipped at runtime for left-facing movement.

These are the magenta-keyed sources. The transparent runtime sheets live in
`asset/MAPS/enemies/` (`enemy.worm.*` in `asset/assets.json`); the swordsman was
repacked there as a `4 × 10` sheet. `future/` holds sticky spider-slime
generations and `spider ideas/` loose spider concepts; neither is loaded.
