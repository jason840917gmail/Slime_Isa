# Character Animation Video Prompt Template

Copy this template into the generation tool and replace every `[MARKER]` before
submitting it. Keep the camera, background, and output rules unchanged so the
result can be converted into a predictable sprite sheet.

## Replacement markers

- `[CHARACTER_DESCRIPTION]` — exact appearance, colors, body shape, equipment, and accessories.
- `[ACTION]` — `idle`, `walk`, `attack`, `die`, `knockback`, `hurt`, `jump`, `cast`, or another single action.
- `[ACTION_BEATS]` — what happens during the motion, in order.
- `[FACING_DIRECTION]` — `front`, `down`, `up`, or `side`.
- `[SIDE_FACING]` — `left` or `right` when the direction is `side`.
- `[LOOP_MODE]` — `seamless loop` or `one-shot`.
- `[START_POSE]` and `[END_POSE]` — opening and final poses.
- `[IMPACT_BEAT]` — the exact contact, recoil, hit, or collapse moment; use `none` when not applicable.
- `[MOTION_INTENSITY]` — `subtle`, `normal`, or `dramatic`.
- `[DURATION]` — normally `5 seconds`.
- `[FRAME_RATE]` — normally `12 frames per second`.

Project naming note: runtime enemy clips use `down`, `side`, and `up`. Use
`down` for the game's front-facing/down-screen view when the generated sheet
will become an enemy package. Use `front` when the art tool or source sheet
uses that convention, then map it to the runtime name during import.

## General prompt

```text
Create a clean character-animation video for frame extraction and sprite-sheet
creation in Slime Isa's modernized pixel-stylized top-down 2D game style.

The character is [CHARACTER_DESCRIPTION]. Preserve the exact character design,
silhouette, proportions, colors, palette, facial features, clothing, weapons,
equipment, accessories, and material details throughout the entire video.

Animate only this action: [ACTION]. The action beats are: [ACTION_BEATS]. The
character must face [FACING_DIRECTION]. If this is a side-facing animation,
the character faces [SIDE_FACING]. Never rotate, turn around, change facing
direction, or introduce a second action.

The character begins in [START_POSE] and ends in [END_POSE]. Use [MOTION_INTENSITY]
motion. The key impact or contact moment is [IMPACT_BEAT]. The animation must
be a [LOOP_MODE]. For a seamless loop, the final pose and motion must connect
naturally to the first pose. For a one-shot, do not add an artificial loop or
return to the starting pose unless explicitly requested.

Keep the character perfectly centered and performing in place. Do not let the
character travel across the screen. Walking, recoil, knockback, jump, attack,
and death motion may move the body within the animation, but the character's
center stays fixed so every frame fits one spritesheet cell.

Use a fixed top-down game camera and keep the character at the same scale and
screen position in every frame. Do not zoom, pan, tilt, rotate, shake, cut, or
change perspective. Keep the entire character visible with generous empty
space around the head, feet, equipment, weapons, and effects.

Use modernized pixel-stylized 2D game art: chunky readable silhouettes,
deliberate pixel clusters, saturated colors, selective highlights, and cool
shadows. Keep edges crisp and preserve the same visual language in every frame.
Do not switch to photorealism, glossy 3D, painterly illustration, low-poly
rendering, or a different art style.

Use a completely solid chroma-purple background: #FF00FF. The background must
be flat, uniform, and featureless for removal. Do not add scenery, floor lines,
horizon lines, gradients, texture, fog, shadows, reflections, glow, dust,
smoke, particles, motion trails, or background animation. Do not use purple or
magenta on the character where it could blend into the background.

Duration: [DURATION]. Frame rate: [FRAME_RATE]. Camera: fixed TOP-DOWN. Audio:
none. No voice, music, or sound effects.

Maintain identical anatomy, proportions, design, palette, lighting, camera
distance, screen position, scale, and facing direction in every frame. Generate
clean, stable motion suitable for extracting individual frames into a uniform
sprite sheet.
```

## Action presets

Use one preset to fill the matching markers in the general prompt.

### Idle

```text
[ACTION] = idle
[ACTION_BEATS] = subtle breathing, gentle body settling, and a small repeated
                 idle motion without changing the character's footprint
[START_POSE] = neutral standing pose
[END_POSE] = neutral standing pose
[IMPACT_BEAT] = none
[LOOP_MODE] = seamless loop
[MOTION_INTENSITY] = subtle
```

### Walk

```text
[ACTION] = walk
[ACTION_BEATS] = a readable in-place walking cycle with alternating body sway,
                 lower-body motion, and a stable center of mass
[START_POSE] = neutral contact pose
[END_POSE] = matching contact pose at the next cycle boundary
[IMPACT_BEAT] = none
[LOOP_MODE] = seamless loop
[MOTION_INTENSITY] = normal
```

### Attack

```text
[ACTION] = attack
[ACTION_BEATS] = anticipation, wind-up, committed attack motion, [IMPACT_BEAT],
                 brief recovery, then hold the final pose
[START_POSE] = ready combat pose
[END_POSE] = recovered combat pose
[IMPACT_BEAT] = the frame where the weapon, limb, projectile, or body attack
                reaches its strongest contact position
[LOOP_MODE] = one-shot
[MOTION_INTENSITY] = dramatic
```

### Die

```text
[ACTION] = die
[ACTION_BEATS] = brief reaction, loss of balance, collapse or defeat pose, and
                 a readable final resting pose
[START_POSE] = normal combat pose
[END_POSE] = final defeated/resting pose
[IMPACT_BEAT] = the hit reaction or defeat transition
[LOOP_MODE] = one-shot
[MOTION_INTENSITY] = dramatic
```

### Knockback

```text
[ACTION] = knockback
[ACTION_BEATS] = sharp hit reaction, body pushed backward by an external force,
                 short slide or recoil, then a stable recovery pose
[START_POSE] = current combat pose
[END_POSE] = controlled recovery pose facing the same direction
[IMPACT_BEAT] = the instant the incoming hit lands
[LOOP_MODE] = one-shot
[MOTION_INTENSITY] = normal
```

## Direction presets

Use one direction per video. Do not ask for multiple directions in one clip.

```text
[FACING_DIRECTION] = front
Show the character's front-facing view clearly and keep that view unchanged.
```

```text
[FACING_DIRECTION] = down
Show the character oriented toward the bottom of the game screen. Keep the
down-facing silhouette and readable front details unchanged throughout.
```

```text
[FACING_DIRECTION] = up
Show the character oriented toward the top of the game screen. Preserve the
back-facing silhouette and visible top/back details consistently.
```

```text
[FACING_DIRECTION] = side
[SIDE_FACING] = right
Show a clean right-facing profile. Do not turn toward or away from the camera.
The game can mirror this source for the opposite side.
```

## Negative prompt

```text
No rotation. No direction change. No camera movement. No zoom. No pan. No
tilt. No shake. No cuts. No transitions. No multiple camera angles. No travel
across the screen. No cropping. No changing scale. No changing character
design. No style drift. No extra characters. No extra actions. No secondary
gestures. No objects or scenery. No floor or horizon. No shadows or reflections.
No glow. No dust, smoke, particles, or motion trails. No text. No border. No
logo. No watermark. No audio. No purple or magenta details that blend into
#FF00FF.
```

## Sprite-sheet handoff checklist

1. Extract frames at `[FRAME_RATE]` and keep the original frame order.
2. Remove the chroma-purple background without trimming the character's cell.
3. Place every frame on a uniform grid with identical cell dimensions.
4. Keep the character centered and grounded consistently across frames.
5. Confirm frame `0` is valid; Character Studio uses it as the safe starter frame.
6. Register the finished PNG sheet through [Adding Game Assets](./adding-assets.md).
7. For a character or enemy, continue with [Character Sprites And Animated Visuals](./character-sprites-guide.md) and create the package in Character Studio.
8. Run `pnpm assets:check`, `pnpm visuals:check`, the relevant content checks,
   and `pnpm build` before placing the asset in a map.
