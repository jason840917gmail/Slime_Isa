# Animation ping-pong loop mode

Status: Complete

## Goal

Allow an authored looping animation to play forward from its first frame to its
last frame, then backward to its first frame before repeating. The existing
loop behavior remains the default wrap mode.

## Completed

- [x] Add a backward-compatible `loopMode` field with `wrap` and `ping-pong` values.
- [x] Register ping-pong clips with Phaser's yoyo playback while retaining normal wrap playback.
- [x] Keep Character Studio preview playback in sync with the runtime sequence.
- [x] Expose the mode selector beside the Studio loop toggle and persist it with the package.
- [x] Update validation, schema, generated starter packages, and animation duration calculations.
- [x] Treat a ping-pong cycle as `start … end … start` without duplicating the endpoint frames.

## Data shape

Existing packages without `loopMode` continue to use `wrap`:

```json
{
  "frames": [0, 1, 2, 3],
  "framesPerSecond": 8,
  "loop": true,
  "loopMode": "ping-pong"
}
```

The runtime sequence is `0, 1, 2, 3, 2, 1`, then repeats. A one-frame clip
always remains on its only frame regardless of mode.

## Implementation notes

The shared animation-loop helper owns cycle length, frame lookup, and duration
calculation so Phaser playback, authored track events, gameplay action timing,
and Studio playback use the same endpoint rules.
