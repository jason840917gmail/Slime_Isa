# The Bow's body poses (2026-11-20)

The Bow is the slime's own body bent into a bow (docs/godot/BODY_SHAPES.md "The Bow"). The owner
picked "B, the body bends" from a mockup of two ideas (A: two goo arms grow into the bow; B: the whole
body bends), then had it turned the right way: the belly and the face bulge toward the target, the two
horns sweep back, and the goo string sits behind the body and is pulled back. Generated with Magnific
GPT 2.5 (`gpt-2-mini`, 1:1, 1k, `transparentBackground: true` in `extraSettings`), with the slime's
turnaround (`../turnaround-e.png`) and the spear's side poses (`../shapes/poses-spear-side.png`) as
references; the front and back sheets also took the chosen side sheet, the front one the axe's front
poses (`../shapes/poses-axe-down.png`). Still key poses, like the Heavy grab's.

## Files

| File | What it is |
|---|---|
| `bow-side.png` | Side view facing right (take 2 of 2): gather (stretched tall into two horns), drawn (bent like ")", the belly and face toward the right, the string pulled back behind on the left, the goo arrow's tip out of the front), release (the string snapped straight behind, droplets), recoil (back toward the blob) |
| `bow-down.png` | Front view, shooting down at the viewer (take 2 of 2): gather (stretched wide), drawn (the horns curve back up the picture, the string behind the head, the arrow tip under the face), release, recoil |
| `icon-bow.png` | The HUD icon's source (take 2 of 2, from the Goo Bomb icon and the side sheet), fitted to 96 x 96 in `godot/asset/UI/hud-console/ability-bow.webp` |
| `bow-up.png` | Back view, shooting up the picture, no face (take 2 of 2): gather, drawn (the horns curve toward the viewer, the string in front pulled down, the arrow tip over the sprout), release, recoil |

`python scripts/characters/pack-slime-bow.py` packs them into page 7 rows 3-4 (`../page-7.json`); then
`tools/build_player_clips.gd -- --only=bow-` builds `bow-draw-<direction>` (gather, drawn) and
`bow-shot-<direction>` (release, recoil). The front and back gather poses are wider than a cell and
are drawn a little smaller (0.84 and 0.90); they show for 70 ms.

## Prompts

"A SPRITE SHEET of ONLY the EXACT same little green glossy translucent jelly slime as the reference
(same leaf sprout, same outline, same eyes), ALONE, seen from the SIDE and FACING RIGHT [from the
FRONT, facing the viewer / FROM BEHIND, no face], its whole body bending into a BOW to shoot to the
RIGHT [DOWN toward the viewer / UP the picture]. No wooden bow, no separate object: the bow IS the
slime's body. Four poses in a 2 by 2 grid, each centred in its own quarter, all on the same
baseline:" then the four poses as in the table, "Isolated on a transparent background, no ground
shadow plate, no scenery, no grid lines, no borders, no text."

## Cost

About 640 credits at 40 an image: the two mockup strips (two ideas, two takes each), the two side
takes after the turn, two front and two back takes, and two icon takes.
