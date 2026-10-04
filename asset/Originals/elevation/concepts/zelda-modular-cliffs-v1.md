# Zelda-style modular earth cliffs

Generated with the built-in image generation tool from the user's three visual references.

## Intended atlas layout

Eight columns; nine rows.

- Rows 1–3: raised walls, top cap / repeatable middle / bottom foot.
- Rows 4–6: recessed pit walls, top rim / repeatable middle / bottom foot.
- Rows 7–9: corners, top cap / repeatable middle / bottom foot.
- Direction columns for rows 1–6: N, NE, E, SE, S, SW, W, NW.
- Corner columns for rows 7–9: convex NW, NE, SE, SW; concave NW, NE, SE, SW.

Construction intent: top + zero or more middle segments + bottom. Raised rims put grass on the plateau side; pits put grass on the surrounding-ground side. Inner and outer corners must connect to the neighboring wall faces.

## Status

Generated source artwork, not registered in the runtime media catalog. Grid coordinates, directional coverage, and exact edge continuity need verification and pixel cleanup before treating it as a production autotile atlas. The layout above is the requested generation layout, not a verified atlas manifest. Arbitrary-height seamless assembly has not been validated in the game. No gameplay, collision, or elevation behavior was changed.

## Reusable generation prompt

Use case: stylized-concept
Asset type: modular pixel-art cliff / wall sprite atlas for a top-down 2D game.
Generate a new coherent tileset using the three supplied images as STYLE AND GEOMETRY REFERENCES, not edit targets. Image 1 demonstrates an eight-sided recessed hole; image 2 an eight-sided raised elevation; image 3 demonstrates a corner transition. Match their classic Zelda-like 16-bit overhead perspective, dark moss-green grassy lip, ochre/brown layered earth faces, dark outlines, crisp stepped pixels, restrained palette. No water required: the blue in reference 1 is not part of this earth-wall kit.
Deliver one transparent PNG sprite sheet, landscape, precisely organized as an 8-column by 9-row grid of equally sized square cells, no labels, no text, no grid lines. Each sprite occupies its own cell, uniform alignment and scale. All cells needed, none blank.
ROWS 1-3: raised plateau wall sides in all eight compass orientations, columns N, NE, E, SE, S, SW, W, NW. Row 1 top cap / grass border and first earth band; row 2 repeatable earth wall extension, NO grass or bottom lip; row 3 bottom termination / foot. Every column's three parts shares the exact same join profile and width. Repeating middle sections between top and bottom must permit arbitrarily tall cliffs.
ROWS 4-6: recessed hole / pit walls in the same eight compass directions N, NE, E, SE, S, SW, W, NW. Row 4 grassy upper rim cap on surrounding ground; row 5 repeatable inward-facing earthen shaft extension; row 6 lowest foot termination. Maintain the overhead hollow geometry from reference 1, with correct inward orientation, distinct from raised outer faces.
ROWS 7-9: modular corner transitions. Columns 1-4 are convex outer corners NW, NE, SE, SW. Columns 5-8 are concave inner corners NW, NE, SE, SW, including the bowed inward cut of reference 3. Row 7 grassy top corner cap; row 8 vertically repeatable corner wall extension WITHOUT grass or bottom; row 9 corner bottom foot. All corner edge profiles meet adjacent straight and diagonal pieces of rows 1-6 with no cracks.
Critical geometry: these are connecting TILE PIECES, not isolated complete islands, rounded stones, or whole octagonal donuts. Cardinal modules have straight join edges, diagonal modules use consistent 45-degree staircase edges. Grass appears only on top caps. Middle strips have matching top/bottom pixels and restrained horizontally stratified texture to support seamless vertical repetition; matching lateral seams for wall runs. Consistent height increment, projection, directional shading, and boundary contact coordinates throughout. Transparent empty space outside wall silhouettes, true alpha, no painted checkerboard, no shadows cast into empty space, no antialiasing or blur. Flat overhead Zelda-style cliff construction, never isometric cubes. Prioritize modular precision and all eight directions over decoration.

## Final fresh-generation prompt

Create a transparent pixel-art sprite sheet based on the original supplied Zelda-style cliff references. Use a strict TOP-DOWN camera, NOT isometric. This is a modular terrain atlas, not a collection of floating blocks. Moss green rims, ochre earth strata, dark brown outlines, crisp pixel edges.
Layout: 8 columns × 9 rows, equal cells, no text. Each column corresponds to a DIFFERENT direction. CRITICAL: north is a horizontal narrow back edge; east is a VERTICAL narrow right edge; south is a horizontal wide front face; west is a VERTICAL narrow left edge. The other four columns are diagonal edges of an octagon. In order: N NE E SE S SW W NW. Do not draw diagonal pieces in E and W columns. Do not repeat the south face for north.
Rows 1 2 3 are raised cliff top rim, repeatable middle earth, bottom foot. Rows 4 5 6 are recessed pit top rim, repeatable middle earth, bottom foot. Rows 7 8 9 are corner top rim, repeatable corner middle, corner bottom. Four outer convex corners followed by four inner concave corners, each group NW NE SE SW. Middle pieces are open-ended strips, not closed rocks, with matching boundary pixels so they repeat into taller faces.
Imagine the eight-sided cliff rings in the original references cut apart into directional segments and divided into top / repeatable middle / bottom. Raised grass belongs on the inside of the perimeter. Pit grass belongs outside the hole perimeter. All cut edges straight and connectable. Transparent background and empty space, no baked shadows, no checkerboard. These pieces must assemble into arbitrary raised islands and deep holes, with matching convex and concave corners. Maintain a two-dimensional overhead terrain projection throughout.

## Observed limitations

The saved PNG improves east/west edges and pit rims, but some directions and corners still repeat, grass remains on extension pieces, and joins are not pixel matched. It is a visual draft and does not yet satisfy seamless arbitrary-height assembly.

Validation: pnpm typecheck could not run because its dependency bootstrap requested a module-directory purge and aborted without a terminal. No game source or media catalog edits were made.


## Directional refinement prompt

undefined
