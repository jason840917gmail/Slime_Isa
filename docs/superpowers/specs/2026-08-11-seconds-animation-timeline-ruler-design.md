# Seconds-First Animation Timeline Ruler

## Problem

The animation ruler currently displays zero-based timeline frame numbers, but its grid is independent from the variable-width keyframe tiles. The labels therefore do not align with tile starts or holds and appear to be meaningless keyframe ordinals.

## Approved behavior

Character Studio and Weapon Studio use the same seconds-first ruler. The authored animation remains frame-snapped internally, while the primary timeline labels communicate elapsed time.

- Ruler labels use seconds, such as `0.00s`, `0.04s`, and `0.17s`.
- Every keyframe tile occupies the exact ruler columns covered by its authored hold.
- A tile shows `START 0.17s` and `HOLD 0.17s / 4F`; compact visual labels may omit the words while the tooltip retains them.
- The selected-keyframe summary shows elapsed time first and its explicitly labeled start frame second, for example `TIME 0.17s / START F04`.
- Decrease and increase controls continue changing the hold by exactly one playback frame.

## Design

The normalized animation clip remains the source of truth: `keyframeTimes` stores discrete playback-frame starts, `framesPerSecond` converts each start or hold to seconds, and `durationSeconds` defines the full clip duration. Valid normalized clips require a positive integer FPS, nonnegative strictly increasing integer starts, a first start of zero, and a final start below the total playback-frame count. Existing normalization and validation reject invalid clips before rendering.

Total playback frames equal `max(1, round(durationSeconds * framesPerSecond))`. A non-final keyframe hold equals the next keyframe start minus its start. The final hold equals total playback frames minus its start. No additional rounding is applied to a hold.

Increasing a hold from `n` to `n + 1` shifts every later keyframe start forward by one, increases total playback frames by one, and sets duration to `totalPlaybackFrames / framesPerSecond`. Decreasing a hold from `n` to `n - 1` performs the inverse operation only when `n > 1`. A hold of one frame is the minimum and decreasing it is a no-op. Editing the final hold changes total playback frames and duration but shifts no keyframe starts.

The shared timeline view model will expose formatted start time and hold duration for each keyframe plus ruler ticks derived from `frameIndex / framesPerSecond`. Time values use two decimal places through 100 FPS and three decimal places above 100 FPS, rounded with JavaScript `toFixed`. The ruler keeps one grid column per playback frame but labels at most approximately twelve starts: label stride is `max(1, ceil(totalPlaybackFrames / 12))`. Tick frames are the deduplicated, ascending set containing frame zero, every stride boundary below the total, and the final playback-frame start at `totalPlaybackFrames - 1`.

The shared panel will render the ruler and keyframe lane on the same frame-column grid. Authored playback frame `f` maps to one-based CSS grid column `f + 1`. A keyframe starting at `s` with hold `n` uses `grid-column: (s + 1) / span n`, so it occupies exactly `n` ruler columns. Ruler, tile, hitbox, and event lanes use the same column definition and no independent duration width calculation. Character hitbox/event tracks continue using these frame columns.

Seconds are the primary presentation. Tiles show start time plus hold seconds and hold frames. Selection summaries use `KEYFRAME nn / TIME 0.00s / START Fnn / SOURCE n`. Frame counts remain visible because sprite animation editing is discrete and decrease/increase operations must remain deterministic.

## Alternatives rejected

- Keyframe ordinals such as `00`, `01`, and `02` do not communicate elapsed animation time or hold duration.
- Seconds displayed only inside tiles provide no global timeline context.
- A Frames/Seconds toggle introduces persistent UI state without improving the approved seconds-first workflow.

## Verification

- Test a one-frame clip at 24 FPS: one `0.00s` tick, start frame zero, grid column one, and span one.
- Test formatting at 100 FPS (`0.01s` for frame one) and 101 FPS (`0.010s` for frame one).
- Test thirteen playback frames with stride two produces tick frames `[0, 2, 4, 6, 8, 10, 12]` without duplicating the final tick; test fourteen frames additionally forces final tick thirteen.
- Test that keyframe grid starts and spans match `keyframeTimes` and calculated holds.
- Test seconds formatting and frame-count preservation on tiles and selection summaries in both studios.
- Test in both studios that decrease and increase change the targeted hold by exactly one playback frame and change duration by exactly `1 / framesPerSecond` seconds.
- Test minimum-hold decrease is a no-op and final-keyframe increase changes duration without shifting starts.
- Run `pnpm typecheck`, `pnpm build`, character and weapon validators, and both Studio regression suites.
