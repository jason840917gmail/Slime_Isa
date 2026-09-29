## Character Animation Video Prompt

Create a clean character-animation video intended for frame extraction and
sprite-sheet creation in Slime Isa's cozy storybook woodland style. Start the
prompt with the style block from the
[art style guide](./visual-style-guide.md#generating-assets).

### Visual Style Contract

* Use hand-painted 2D miniature game art: soft painted shading with visible texture, warm golden light from the upper left, warm brown shadows, and a dark warm brown outline.
* Slimes are glossy translucent jelly: a bright rim light, small specular highlights, inner color depth, and a darker base; they look soft and squishy and have no legs.
* Keep chunky, rounded silhouettes that read at gameplay scale, and keep edges clean enough for gameplay.
* Use a fixed three-quarter top-down game camera (about 45°) and stable character scale. Preserve the same visual language for every frame in the animation.
* Avoid photorealism, 3D rendering, pixel art, low-poly geometry, cold blue shadows, flat black outlines, or style drift.

### Character Rules

* The character must remain facing **[DIRECTION: front / back / left / right / diagonal]** for the entire video.
* The character must never rotate, turn around, change direction, or look toward another direction unless explicitly requested.
* The character must perform only this action: **[ACTION]**.
* Do not add secondary actions, gestures, facial reactions, attacks, objects, particles, or environmental interactions.
* Preserve the character's exact design, clothing, proportions, colors, equipment, palette, and hand-painted storybook style throughout every frame.

### Positioning Rules

* Keep the character perfectly centered in the middle of the screen.
* The character must perform the animation in place.
* Do not allow the character to travel horizontally or vertically across the screen.
* For walking, running, or similar movement animations, animate the body and limbs as though the character is moving, but keep the character's central position fixed.
* Do not zoom in, zoom out, pan, tilt, rotate, shake, or move the camera.
* Keep the character at the same size and screen position throughout the entire video.
* Keep the entire character visible, including the head, feet, clothing, weapons, hair, and accessories.
* Leave generous empty space around the character.

### Background and Lighting

* Use a completely solid chroma-purple background: **#FF00FF**.
* The chroma background is only for removal and is not part of the game's visual palette.
* The background must be flat, uniform, and featureless.
* Do not add gradients, textures, scenery, floor lines, horizon lines, objects, fog, or background animation.
* Do not add shadows, reflections, glow, motion trails, dust, smoke, or particles.
* Do not use purple or magenta colors on the character that could blend into the background.
* Keep the character's warm upper-left lighting identical in every frame, with no flickering or color changes.

### Animation Requirements

* Action: **[ACTION]**
* Facing direction: **[DIRECTION]**
* Animation duration: **5 seconds**
* Frame rate: **12 frames per second**
* Animation speed: **[SLOW / NORMAL / FAST]**
* Camera view: **THREE-QUARTER TOP-DOWN (about 45°)**
* Visual style: **cozy storybook woodland, hand-painted 2D miniature**
* Character scale: **FULL BODY**
* Audio: **none; no voice, music, or sound effects**

Begin and end the video in the same neutral pose whenever the action is
intended to loop.

The motion must form a smooth, seamless animation cycle. The final pose should
connect naturally to the first pose without a visible jump.

Maintain consistent anatomy, proportions, clothing, equipment, colors,
perspective, camera distance, character placement, and stylized shading
in every frame.

### Strict Negative Instructions

Do not rotate the character.
Do not change the facing direction.
Do not move the character away from the center.
Do not make the character travel across the screen.
Do not move or rotate the camera.
Do not crop any part of the character.
Do not change the character's size.
Do not change the character's design.
Do not add extra actions.
Do not add extra characters.
Do not add objects or scenery.
Do not add shadows or reflections.
Do not add visual effects.
Do not add audio or sound effects.
Do not add text, borders, logos, or watermarks.
Do not change the background color.
Do not use transitions, cuts, or multiple camera angles.
Do not switch to photorealistic, 3D, pixel-art, or low-poly rendering.

### Final Prompt Example

[Style block from the art style guide], glossy translucent jelly slime body
with rim light, cute big glossy eyes. Create a seamless 5-second animation of
the provided slime character hopping in place. The character must face right
for the entire video and must never turn, rotate, or look in another
direction. Animate only a normal hopping cycle: the jelly body squashes on
landing, stretches on the jump, and its accessories bounce naturally. Keep the
character perfectly centered and fixed in the same screen position.

Use a completely solid #FF00FF chroma-purple background with no texture, floor,
horizon, shadows, reflections, particles, scenery, or gradients. The chroma
color is only a removable background and is not part of the game's visual
palette. Use a fixed three-quarter top-down game camera with no zooming,
panning, rotation, shaking, or perspective changes. Keep the entire character
visible and maintain identical size, proportions, accessories, colors, warm
upper-left lighting, and hand-painted storybook style in every frame.

The animation should last 5 seconds at 12 frames per second, contain no audio
or sound effects, and form a seamless loop. Begin and end at matching points in
the hopping cycle. Do not add attacks, gestures, facial reactions, objects,
secondary movements, text, borders, logos, or watermarks.
