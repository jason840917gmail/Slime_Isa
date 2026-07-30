# Modernized Pixel-Stylized Top-Down Visual Guide

Slime Isa uses a modernized pixel-stylized 2D top-down presentation. The
style keeps the clarity and charm of pixel art without requiring every source
image or concept illustration to be authored at a tiny native resolution.

## Core direction

- Use a fixed, readable top-down game camera with stable character scale.
- Favor chunky silhouettes, deliberate pixel clusters, and clear value steps.
- Use polished highlights and controlled gradients only when they improve
  material readability; avoid photorealism and glossy 3D rendering.
- Keep character designs expressive and contemporary rather than forcing a
  strict retro sprite treatment.
- Preserve the existing runtime frame contracts, source-frame dimensions, and
  nearest-filter rendering for authored gameplay sprites.
- Do not mix visual techniques inside one character set. Front, side, back,
  attack, and death views must share the same palette, lighting, camera, and
  rendering language.

## Palette language

The game uses a deep night field with luminous slime-family accents:

| Role | Color |
| --- | --- |
| World/UI base | `#0b1020` |
| Raised surface | `#111b32` |
| Surface highlight | `#192642` |
| Border and cool line | `#3b5c78` |
| Slime/mint accent | `#86f0c3` |
| Information cyan | `#72d8ff` |
| Warm reward highlight | `#ffd277` |
| Violet ability accent | `#a78bfa` |
| Danger/coral feedback | `#ff6f88` |
| Deep outline/shadow | `#081022` |

Biome materials may introduce local colors, but they should remain readable
against the dark base and use the same contrast hierarchy.

## Character readability

- Make the outer silhouette readable at gameplay scale before adding texture.
- Separate body, limbs, equipment, and effects with value or hue contrast.
- Keep shadows cool and highlights selective; do not flatten the character with
  uniform lighting.
- Preserve a consistent top-down grounding point and avoid floating anatomy.
- Treat attacks and status effects as separate readable layers. A character's
  idle/reference art should not permanently include an attack projectile.

## UI and editor presentation

The HUD, menus, chat, map editor, and development panels share the same night
field, cool slate surfaces, mint interaction accent, cyan information accent,
warm reward accent, and coral danger feedback. UI should feel like a playful
field atlas: compact, high-contrast, and tactile, with restrained shadows and
small pixel-inspired details.

## Asset generation

Use the Magnific MCP guide for model selection and call sequencing. Prompts
should describe the target as `modernized pixel-stylized top-down 2D game art`
and should explicitly preserve silhouette, palette, camera, scale, and action
constraints. Concepts may be generated at 1k or larger, but runtime assets
must still be authored into the project's established frame and manifest
contracts before they are loaded by gameplay.
