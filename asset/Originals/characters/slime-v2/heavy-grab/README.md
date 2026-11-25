# Heavy grab poses (2026-10-19)

The slime's push and pull poses for the Heavy skin's grab on heavy blocks and statues
(docs/godot/SKINS.md "Heavy"). Generated with Magnific GPT 2.5 (`gpt-2-mini`, 1:1, 1k,
`transparentBackground: true`), with the slime's turnaround (`../turnaround-e.png`, uploaded) and the Lili
creation `XmsSFu2Bfo` as references. Still key poses, like page 6, not videos.

The owner approved the side view first, from a mockup beside the pedestal at game scale (push A and
pull B, 2026-10-19); the front and back views were then made with the approved side sheet as a third
reference, so they keep its squash, snout and faces.

## Files

| File | What it is | Used |
|---|---|---|
| `push-side-a.png`, `push-side-b.png` | Side view facing right, pushing a block that is not drawn: brace, shove, step, rest | **a** (all four) |
| `pull-side-a.png`, `pull-side-b.png` | Side view facing right, the mouth bitten onto the block, heaving back: grip, heave, tug, rest | **b** (all four) |
| `push-down-a.png`, `push-down-b.png` | Front view, pushing toward the viewer | the top rows of both (brace, shove of each); their bottom rows turned to the side |
| `push-up-a.png`, `push-up-b.png` | Back view, pushing away from the viewer | a's brace, shove and rest, b's shove |
| `pull-down-a.png`, `pull-down-b.png` | Front view, the snout down onto the block, the body leaning back | **a** |
| `pull-up-a.png`, `pull-up-b.png` | Back view, the snout up onto the block, the body leaning toward the viewer | **a** |

`python scripts/characters/pack-slime-heavy-grab.py` (its `LAYOUT` holds the picks) packs them into
page 7 (`../page-7.json`, the slime-v2 README's "Page 7 layout"); `tools/build_player_clips.gd --
--only=push-,pull-,grab-` builds the clips. The grab holds the pull's grip; the push loops its four poses
once per 640 ms cell; the pull alternates heave and tug.

## Prompts

Each starts with the style block of docs/assets/visual-style-guide.md and the slime line ("Glossy
translucent jelly slime body with rim light, cute big glossy eyes"; the back views leave the eyes out),
then: "A SPRITE SHEET of ONLY the EXACT same little green jelly slime as the reference ..., ALONE,
holding NOTHING, [the view] PUSHING / PULLING a very heavy stone block that is NOT drawn: the block would
stand just off the right edge / right in front of it / right beyond it ..." and four poses in a 2 by 2
grid "each centred in its own quarter, all four the same size on the same baseline", ending "Isolated on
a transparent background, no ground shadow plate, no scenery, no block, no wall (no rope, no handle),
no grid lines, no borders."

- Push: "its [front] pressed FLAT against an invisible vertical surface"; bracing (leaning in, eye
  squeezed half shut, mouth a tight wavy line, sprout bent back), shoving hard (squashed, eye squeezed
  like a > shape, cheek puffed, a sweat drop), a step (its back end pushing off the ground like a foot),
  catching its breath while still leaning (teeth gritted).
- Pull: "The slime has BITTEN onto the block's edge with its wide mouth and drags it backward: its front
  is stretched into a short thick jelly snout whose open mouth clamps onto an invisible edge, while its
  body leans far BACK"; gripping, heaving back (squashed low, back end dug in like a heel, the snout long
  and thin), the hardest tug (stretched like taffy, a sweat drop), a short rest (puffing).
- Front and back views: "seen from the FRONT, facing the viewer (both eyes visible)" / "seen FROM
  BEHIND, facing away from the viewer like the back view in the turnaround (NO face, NO eyes visible at
  all)", the block "between the slime and the viewer" / "beyond it, toward the top of the picture", and
  "the same squash / snout and expressions as the side-view push / pull sheet".

## Cost

1,200 credits (12 images at 100): the four side sheets (two takes each of push and pull) and the eight
front and back sheets. Nothing was rejected by the filter.
