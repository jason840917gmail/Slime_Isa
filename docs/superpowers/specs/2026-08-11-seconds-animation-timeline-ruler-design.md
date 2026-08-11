# Seconds-First Animation Timeline Ruler

## Problem

The animation ruler currently displays zero-based timeline frame numbers, but its grid is independent from the variable-width keyframe tiles. The labels therefore do not align with tile starts or holds and appear to be meaningless keyframe ordinals.

## Approved behavior

Character Studio and Weapon Studio use the same seconds-first ruler. The authored animation remains frame-snapped internally, while the primary timeline labels communicate elapsed time.

- Ruler labels use seconds, such as `0.00s`, `0.04s`, and `0.17s`.
- Every keyframe tile occupies the exact ruler columns covered by its authored hold.
- A tile shows its elapsed start time and duration in both seconds and frames, for example `0.17s · 4F`.
- The selected-keyframe summary shows elapsed time rather than an unexplained frame number.
- Decrease and increase controls continue changing the hold by exactly one playback frame.

## Design

The normalized animation clip remains the source of truth: `keyframeTimes` stores discrete playback-frame starts, `framesPerSecond` converts each start or hold to seconds, and `durationSeconds` defines the full clip duration.

The shared timeline view model will expose formatted start time and hold duration for each keyframe plus ruler ticks derived from `frameIndex / framesPerSecond`. Tick labels become sparser as the animation grows, while frame-grid columns remain present for snapping and alignment.

The shared panel will render the ruler and keyframe lane on the same frame-column grid. Each keyframe adapter supplies its authored start and hold as a grid start and span instead of approximating duration with an independent pixel width. Character hitbox/event tracks continue using the same underlying frame columns.

Seconds are the primary presentation. Frame counts remain visible inside tiles and in tooltips because sprite animation editing is discrete and decrease/increase operations must remain deterministic.

## Alternatives rejected

- Keyframe ordinals such as `00`, `01`, and `02` do not communicate elapsed animation time or hold duration.
- Seconds displayed only inside tiles provide no global timeline context.
- A Frames/Seconds toggle introduces persistent UI state without improving the approved seconds-first workflow.

## Verification

- Test tick labels at multiple FPS values and animation lengths.
- Test that keyframe grid starts and spans match `keyframeTimes` and calculated holds.
- Test seconds formatting and frame-count preservation on tiles and selection summaries in both studios.
- Run `pnpm typecheck`, `pnpm build`, character and weapon validators, and both Studio regression suites.
