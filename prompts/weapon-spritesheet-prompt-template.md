# Weapon Animation Spritesheet Prompt Template

Use this template for a weapon-only animation sheet. Replace every
`[BRACKETED VALUE]` before sending it to an image model, then attach the
reference image separately.

## Inputs

- Weapon: `[WEAPON NAME AND TYPE]`
- Reference image: `[ATTACH REFERENCE IMAGE HERE]`
- Columns: `[COLUMN COUNT]`
- Rows: `[ROW COUNT]`
- Cell size: `[CELL WIDTH] x [CELL HEIGHT] px`
- Full canvas: `[TOTAL WIDTH] x [TOTAL HEIGHT] px`
- Row directions, top to bottom: `[ROW 1]`, `[ROW 2]`, `[ROW 3]`
- Frame phases: `[PREPARATION]`, `[ACTIVE ATTACK]`, `[FOLLOW-THROUGH / RECOVERY]`

## Copy/paste prompt

Create exactly one weapon animation spritesheet for **[WEAPON NAME AND TYPE]**.
Use the attached reference image as the authoritative source for the weapon's
silhouette, proportions, materials, colors, ornament shapes, and distinctive
design details. Preserve the same weapon identity in every frame; change only
the pose, direction, motion accents, and attack phase.

### Exact sheet format

- One uniform grid of **[COLUMN COUNT] columns x [ROW COUNT] rows**.
- Every cell is exactly **[CELL WIDTH] x [CELL HEIGHT] px**.
- The complete output is exactly **[TOTAL WIDTH] x [TOTAL HEIGHT] px**.
- Fill the entire canvas and every cell with one perfectly flat solid chroma
  purple background: **#8000FF**.
- Cell boundaries are invisible: the purple background continues uninterrupted
  across the sheet. No visible grid lines, cell dividers, borders, gutters,
  gradients, texture, scenery, checkerboard, labels, captions, or frame numbers.
- Keep each pose completely inside its own cell with a clean purple margin.
- Do not crop the weapon, blade, trail, spark, glow, or impact accent.

### Project art direction

Render as **modernized pixel-stylized top-down 2D game art** for a readable
action game. Use a chunky, unmistakable silhouette, deliberate pixel clusters,
deep cool outlines, cool shadow shapes, selective bright highlights, and
controlled material gradients only where they improve readability. Keep the
camera angle, scale, lighting direction, outline language, palette, and level of
detail consistent in every cell. The reference image takes priority over generic
weapon details.

### Layout and animation rules

- Use the row directions exactly as follows, from top to bottom:
  - Row 1: **[ROW 1 DIRECTION AND FACING]**.
  - Row 2: **[ROW 2 DIRECTION AND FACING]**.
  - Row 3: **[ROW 3 DIRECTION AND FACING]**.
- Keep the weapon's logical attachment pivot in the same relative position in
  every cell and row.
- Preserve a consistent weapon scale; do not resize the weapon to fill a cell
  differently from frame to frame.
- Read each row from left to right as one complete attack:
  - Columns 1–3: preparation and wind-up. Show the starting pose, the weapon
    being raised or drawn back, and a clear loaded pose.
  - Columns 4–6: active attack. Show acceleration, the strongest swing, and the
    clearest contact or maximum-reach moment.
  - Columns 7–[COLUMN COUNT]: follow-through and recovery. Show overswing,
    deceleration, settling, and a clean end pose.
- Make neighboring frames progress naturally. Do not jump from the starting
  pose directly to the impact pose.
- Use motion trails, sparks, glints, or impact flashes sparingly and only when
  they clarify the action. Keep the weapon silhouette readable above all effects.
- Keep the side-facing row safe to mirror when the game needs the opposite
  horizontal direction.

### Exclusions

Weapon only. Do not include a character, UI, text, damage numbers, enemies,
scenery, floor, particles unrelated to the attack, alternate weapons, extra
objects, or decorative props. Do not create a collage, a character sheet, a
collection of unrelated illustrations, or a single weapon repeated in frozen
poses. Do not add extra rows or columns. Do not add a second background color.

Avoid photorealism, glossy 3D rendering, soft airbrush blur, smeared motion
blur, inconsistent perspective, unstable proportions, random redesigns,
cropped silhouettes, edge-touching effects, unreadable dark masses, and
inconsistent facing.

### Export instruction

Return one crisp PNG at exactly **[TOTAL WIDTH] × [TOTAL HEIGHT] px** with the
solid **#8000FF** field preserved edge to edge. Keep hard pixel-friendly edges
and do not apply soft resampling, a matte, or a post-process background effect.

## Artist QA checklist

- [ ] The output is exactly `[COLUMN COUNT] × [ROW COUNT]` uniform cells.
- [ ] Each cell is exactly `[CELL WIDTH] × [CELL HEIGHT] px`.
- [ ] The complete canvas is exactly `[TOTAL WIDTH] × [TOTAL HEIGHT] px`.
- [ ] The background is one flat `#8000FF` color everywhere.
- [ ] Every frame stays inside its cell with a clean purple margin.
- [ ] The pivot, scale, camera, lighting, and weapon identity remain stable.
- [ ] Every row progresses from preparation through attack to recovery.
- [ ] No frame is duplicated, skipped, frozen, cropped, or accidentally rotated.
- [ ] The PNG contains no text, labels, borders, gutters, scenery, or extra rows.
