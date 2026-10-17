# The Watch Oak (the Weaver Hollow's forecourt)

The base of the giant hollow oak that grew round the Thorn Guard's old watch fort, its stone arch
bricked up: the Weaver Hollow's entrance in `gloop-forest-f4`
(docs/design/2026-10-16-dungeon-weaver-hollow.md, "The forecourt").

- Generated 2026-10-17 with Magnific GPT 2.5 (`gpt-2-mini`), transparent background, 16:9 at 1k,
  the Lili creation as the style reference; two takes, 200 credits.
- `watch-oak-a.png` is used (honey bark, the arch with its leaf keystone, a few cracked bricks, silk
  strands, moss); `watch-oak-b.png` was left (its bark is purple).
- Packed as `godot/asset/MAPS/landmarks/watch-oak.webp` (lossless, the whole picture) with Pillow:
  the soft grey halo round the tree cut (alpha 110 to 240 stretched to 0 to 255), and the top 42% of
  the picture faded to transparent (smoothstep), so the upper trunk melts into the forest painted
  behind it in `gloop-forest-f4`. Placed at 0.6 scale (806 x 451 units).

Prompt (after the style block of docs/assets/visual-style-guide.md):

> The base of a colossal ancient hollow oak tree, the Watch Oak: the lower trunk is far wider than
> tall in view, gnarled grey-brown bark with deep grooves, huge knotted roots flaring out at its foot
> to both sides and gripping the ground. In the middle of the trunk's foot, between two great roots,
> an old weathered stone archway of a forgotten guard fort is grown into the wood; its doorway is
> bricked up with rough grey stone bricks, and a few bricks show fine dark cracks. Thin strands of
> grey spider silk drape across the bark and hang from the roots, patches of moss and a few small
> mushrooms. The view ends at the trunk's foot where the roots meet the ground; the top of the image
> is cut by the frame. Isolated on a transparent background, no ground shadow plate, no scenery.
