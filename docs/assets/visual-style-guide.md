# Slime Isa Art Style Guide

> **Status: the art direction for all new assets.** Defined on 2026-09-29 from
> the reference art the game already ships. Every new sprite, icon, and
> building is checked against this guide before it is registered.

## The Style In One Line

**Cozy storybook woodland, hand-painted miniatures:** glossy jelly slimes with
warm painted light, living in a world of chunky wooden, mossy, leafy, and
mushroom-topped things, seen from a gentle three-quarter top-down view.

## Reference Art

When in doubt, put the new asset next to these and compare.

| Reference | File | What it defines |
|---|---|---|
| Village Elder Plop | `godot/asset/characters/authored/npcs/village-elder-plop.webp` | Slime characters: translucent jelly body, painted shading, one or two props |
| Lili | `godot/asset/characters/authored/npcs/lili.webp` | Cute slime faces: big glossy eyes, blush, a small accessory |
| Mushroom furniture and props | `godot/asset/MAPS/interiors/192x192-tile_8x8-interior-mushroom-furniture-props.webp` | Objects and props: materials, detail level, palette |
| Beds | `godot/asset/MAPS/interiors/256x256-tile_6x8-interior-beds-directional.webp` | Camera angle, directional variants, the sprout motif |

## Camera And Form

- Three-quarter top-down: we see the top and the front of every object, as if
  looking down at a tabletop diorama from about 45°. Characters show front,
  back, and side views in the same camera.
- Objects are **chunky and rounded**: thick planks, fat cushions, bulging
  baskets, stubby legs. Nothing is thin, sharp, or spindly unless it is a
  weapon edge.
- Silhouettes read at gameplay scale before any texture is added.
- Every object sits on the ground with a clear footprint; nothing floats.

## Rendering

- **Hand-painted, not pixel art and not 3D.** Soft painted shading with visible
  material texture: wood grain, woven straw, moss fuzz, cloth folds, stone
  speckle.
- **Light comes from the upper left**, warm and golden. Highlights are warm;
  shadows are deep warm browns, never flat black or cold blue.
- **A dark, soft outline** (deep brown, not pure black) surrounds every object
  and character, so it separates from any ground.
- **Slimes are jelly:** translucent glossy bodies with a bright rim light,
  small specular highlights, inner color depth, and a darker base where they
  touch the ground. They should look soft and squishy.
- Detail stays inside the silhouette. Small decorations (a leaf, a flower, a
  tiny mushroom) make objects feel alive but never change their outline.

## Palette

The world is warm and earthy; slimes and magic supply the saturated color.

| Role | Colors | Where it appears |
|---|---|---|
| Wood | honey brown to dark walnut (`#b5793a` → `#5a3418`) | furniture, buildings, tools |
| Foliage and moss | leaf green to deep moss (`#7cb342` → `#3d5a1e`) | leaves, moss, cushions, trim |
| Straw and cloth | warm cream and wheat (`#f1e4c3`, `#d9b56b`) | baskets, sheets, sacks |
| Mushroom accent | toadstool red with cream dots (`#c9352b`, `#f6ecd4`) | caps, ornaments |
| Cozy blue | muted royal blue (`#3e64a8`) | fabrics, curtains, pillows |
| Stone and metal | warm grey and iron (`#8d857a`, `#4a4a4f`) | cauldrons, anvils, stone |
| Outline and shadow | deep warm brown (`#2a1a0e`) | outlines, contact shadows |
| Slime bodies | any saturated hue, glossy (orange, sky blue, mint, pink…) | characters |
| Magic and effects | bright mint green, gold glow | potions, abilities, pickups |

Each slime character owns one body hue that no other main character shares.

## Motifs

- **The sprout:** a two-leaf seedling on headboards, banners, bed covers, and
  quilts. It is Slimeshire's emblem; use it on anything made in town.
- Leaves, small flowers, moss patches, and tiny red mushrooms decorate objects.
- Things look homemade and loved: rope lashings, pegs, patches, and stitched
  cloth rather than nails, chrome, or clean machinery.

## Characters

- Slimes are round, bottom-heavy blobs with no legs. Personality comes from the
  face and one or two accessories (a hat, glasses, a bow, a scarf, a cane).
- Faces are cute and expressive: large glossy eyes with highlights, small
  mouths, optional blush.
- Enemies follow the same painting and lighting but may be less cute: worms,
  spiders, and wild slimes use sharper shapes and meaner eyes.
- Keep all views of one character identical in palette, light, and
  proportions.

## States And Variants

- Directional objects ship every view they need (front, side, back), as the
  beds do.
- Objects with states ship each state in the same sheet: open and closed
  chests, empty and full cauldrons, lit and unlit ovens.
- A **ruined** building is the same building, damaged: collapsed roof, missing
  planks, overgrown with moss and weeds, lighter and duller in color. The
  restored version must match its silhouette and footprint.

## Checklist For A New Asset

- [ ] Three-quarter top-down, grounded, same camera as the references.
- [ ] Hand-painted shading, warm light from the upper left, dark brown outline.
- [ ] Palette from the table above; saturated color only on slimes, magic, or
      one accent.
- [ ] Chunky, rounded silhouette that reads at gameplay scale.
- [ ] At least one cozy detail (leaf, moss, flower, sprout, rope) when it
      suits the object.
- [ ] Every needed direction and state in one sheet, at the frame size in
      [asset-sheet-spec.md](asset-sheet-spec.md).
- [ ] Next to the reference sheets, it looks like it belongs.

## UI

The approved artwork-first HUD keeps the world visible behind the HUD, minimap,
and hotbar (see the
[HUD spec](../archive/phaser/superpowers/specs/2026-09-04-world-hud-artwork-first-design.md)).
Menus and panels use the organic frames in `godot/asset/UI/` (wood, paper, and leaf
edges), cream paper for reading surfaces, and the same warm palette. Accents:
mint for interaction, gold for rewards, coral red for danger.

## Generating Assets

Follow the [Magnific MCP guide](magnific-mcp-guide.md) for models and call
order. This style block is the single source of the style wording: start every
image and video prompt with it, then describe the asset.

```text
Cozy storybook woodland game art, hand-painted 2D miniature, three-quarter
top-down view, chunky rounded shapes, warm golden light from the upper left,
soft painted shading with visible wood grain, moss and cloth texture, dark warm
brown outline, earthy palette of honey wood, leaf green, cream and toadstool
red, no text.
```

For slime characters, add: `glossy translucent jelly slime body with rim
light, cute big glossy eyes`. Then add the background line for the output
type from the Magnific guide: a transparent background for every image, or
the `#FF00FF` chroma background for animation videos.

Always attach one reference sheet from the [Reference Art](#reference-art)
table as a style reference (upload steps are in the Magnific guide): Elder
Plop or Lili for characters, the mushroom furniture sheet for objects and
buildings, and the beds sheet for directional objects. Concepts may be
generated large, but runtime assets must be packed to the project's frame and
manifest contracts before gameplay loads them.
