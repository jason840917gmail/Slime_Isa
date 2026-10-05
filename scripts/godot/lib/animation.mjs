/**
 * `animation-library` resources → AnimationLibrary + Animation sub-resources.
 *
 * Phaser timeline semantics reproduced here (runtime spec §6.4):
 * - a clip has N = max(1, round(duration·fps)) whole frames; length = N/fps;
 * - keys sit at `at / fps`; key transitions map exactly onto Godot's ease
 *   curves (ease-in 2, ease-out 0.5, ease-in-out −2);
 * - Phaser never interpolates across the loop seam → `loop_wrap = false`;
 * - ping-pong clips are baked into a wrap loop of 2N−2 sampled frames;
 * - events become a method track calling `emit_animation_event` on the
 *   player (its path relative to `root_node = ".."`, i.e. the scene root).
 */
import { gd } from './tscn.mjs';
import { relativePath } from './scene-model.mjs';
import { spriteGeometry } from './sprite.mjs';

export const ANIMATION_PLAYER_SCRIPT = 'res://game/runtime/animation_player.gd';

const TRANSITIONS = { linear: 1, 'ease-in': 2, 'ease-out': 0.5, 'ease-in-out': -2 };

/** JSON property → Godot property suffix, update mode and key conversion. */
const TRACK_PROPERTIES = {
  frame: { godot: 'frame', discrete: true, convert: (v) => Math.round(v) },
  flipX: { godot: 'flip_h', discrete: true, convert: Boolean },
  flipY: { godot: 'flip_v', discrete: true, convert: Boolean },
  visible: { godot: 'visible', discrete: true, convert: Boolean },
  disabled: { godot: 'disabled', discrete: true, convert: Boolean },
  monitoring: { godot: 'monitoring', discrete: true, convert: Boolean },
  alpha: { godot: 'self_modulate:a', discrete: false, convert: (v) => gd.float(v) },
  rotation: { godot: 'rotation', discrete: false, convert: (v) => gd.float(v) },
  angleRad: { godot: 'rotation', discrete: false, convert: (v) => gd.float(v) },
  scale: { godot: 'scale', discrete: false, convert: ([x, y]) => gd.vec2(x, y) },
  position: { godot: 'position', discrete: false, positional: true },
  visualOffset: { godot: 'offset', discrete: false, visualOffset: true },
};

/** Properties with no Godot draw-order meaning (see runtime spec §6.4). */
const DROPPED_TRACK_PROPERTIES = new Set(['depthOffset']);

const roundTime = (value) => Math.round(value * 1e6) / 1e6;

/** Phaser's value of a track at timeline frame `f` (discrete or interpolated). */
function sampleTrack(keys, frame, numeric) {
  let left = keys[0];
  let right = keys[keys.length - 1];
  for (const key of keys) if (key.at <= frame) left = key;
  for (const key of [...keys].reverse()) if (key.at >= frame) right = key;
  if (!numeric || right.at <= left.at || frame <= left.at) return left.value;
  const ratio = ease((frame - left.at) / (right.at - left.at), left.transition);
  const lerp = (a, b) => a + (b - a) * ratio;
  return Array.isArray(left.value) ? left.value.map((v, i) => lerp(v, right.value[i])) : lerp(left.value, right.value);
}

function ease(x, transition) {
  switch (transition) {
    case 'ease-in': return x * x;
    case 'ease-out': return 1 - (1 - x) * (1 - x);
    case 'ease-in-out': return x < 0.5 ? 2 * x * x : 1 - 2 * (1 - x) * (1 - x);
    default: return x;
  }
}

/**
 * Builds the converter for one track: Godot path and a key-value mapper, or
 * a reason why the track is dropped.
 */
function describeTrack(ctx, playerNode, track) {
  const spec = TRACK_PROPERTIES[track.property];
  if (DROPPED_TRACK_PROPERTIES.has(track.property)) return { dropped: 'depth-offset' };
  if (!spec) return { error: `track property '${track.property}' has no Godot mapping` };
  const target = ctx.scene.resolveBinding(playerNode, track.binding);
  if (!target) return { error: `binding '${track.binding}' does not resolve` };
  const targetNode = target.node;
  const segments = ctx.scene.nodeSegments(targetNode.id);
  const path = `${segments.length ? segments.join('/') : '.'}:${spec.godot}`;
  let convert = spec.convert;
  if (spec.positional) {
    convert = positionKeyMapper(ctx, targetNode);
  } else if (spec.visualOffset) {
    const geometry = spriteGeometry(ctx, targetNode, targetNode.properties ?? {});
    convert = ([x, y]) => gd.vec2(x + geometry.offsetBase[0], y + geometry.offsetBase[1]);
  } else if (track.property === 'scale' && targetNode.type === 'Sprite2D' && targetNode.properties?.depthBounds) {
    ctx.warn('animated-depth-bounds-scale', `${ctx.label}: scale track on depthBounds sprite '${targetNode.name}' keeps the static sort-line shift`);
  }
  return { path, discrete: spec.discrete, convert };
}

/**
 * Position keys of a direct child of a re-anchored root shift by −anchor; a
 * key on the root itself moves by +anchor·scale; a depthBounds sprite keeps
 * its sort-line shift.
 */
function positionKeyMapper(ctx, targetNode) {
  const scene = ctx.scene;
  let shift = scene.childShift(targetNode);
  if (targetNode.id === scene.root.id && scene.depthAnchor) {
    const [sx, sy] = scene.rootScale;
    shift = [scene.depthAnchor[0] * sx, scene.depthAnchor[1] * sy];
  }
  if (targetNode.type === 'Sprite2D') {
    const geometry = spriteGeometry(ctx, targetNode, targetNode.properties ?? {});
    shift = [shift[0], shift[1] + geometry.sortShiftY];
  }
  return ([x, y]) => gd.vec2(x + shift[0], y + shift[1]);
}

function valueTrackProps(index, path, discrete, keys) {
  return [
    [`tracks/${index}/type`, 'value'],
    [`tracks/${index}/imported`, false],
    [`tracks/${index}/enabled`, true],
    [`tracks/${index}/path`, gd.nodePath(path)],
    [`tracks/${index}/interp`, 1],
    [`tracks/${index}/loop_wrap`, false],
    [`tracks/${index}/keys`, {
      times: gd.packedFloat32(keys.map((key) => key.time)),
      transitions: gd.packedFloat32(keys.map((key) => key.transition)),
      update: discrete ? 1 : 0,
      values: keys.map((key) => key.value),
    }],
  ];
}

/** Keys of a wrap/non-loop clip: one Godot key per authored key. */
function directKeys(track, fps, convert) {
  return [...track.keys].sort((a, b) => a.at - b.at).map((key) => ({
    time: roundTime(key.at / fps),
    transition: TRANSITIONS[key.transition ?? 'linear'] ?? 1,
    value: convert(key.value),
  }));
}

/** Ping-pong bake: steps 0..2N−3 visit frames 0..N−1..1; a key wherever the value changes. */
function pingPongKeys(track, fps, frameCount, convert, numeric) {
  const keys = [...track.keys].sort((a, b) => a.at - b.at);
  const result = [];
  let previous;
  for (let step = 0; step < 2 * frameCount - 2; step += 1) {
    const frame = step < frameCount ? step : 2 * frameCount - 2 - step;
    const value = sampleTrack(keys, frame, numeric);
    const text = JSON.stringify(value);
    if (text === previous) continue;
    previous = text;
    result.push({ time: roundTime(step / fps), transition: 1, value: convert(value) });
  }
  return result;
}

function convertClip(ctx, playerNode, name, clip, report) {
  const fps = clip.framesPerSecond;
  const frameCount = Math.max(1, Math.round(clip.durationSeconds * fps));
  const pingPong = clip.loop && clip.loopMode === 'ping-pong' && frameCount > 1;
  const length = (pingPong ? 2 * frameCount - 2 : frameCount) / fps;
  const props = [
    ['resource_name', name],
    ['length', gd.float(roundTime(length))],
    ['loop_mode', clip.loop ? 1 : 0],
    ['step', gd.float(roundTime(1 / fps))],
  ];
  let index = 0;
  for (const track of clip.tracks) {
    if (track.enabled === false) continue;
    const described = describeTrack(ctx, playerNode, track);
    if (described.dropped) {
      report.dropped('AnimationTrack', track.property);
      continue;
    }
    if (described.error) {
      ctx.warn('animation-track-skipped', `${ctx.label} clip '${name}': ${described.error}`);
      continue;
    }
    const numeric = !described.discrete;
    if (pingPong && numeric) ctx.warn('ping-pong-numeric-track', `${ctx.label} clip '${name}': numeric ${track.property} track sampled per frame`);
    const keys = pingPong
      ? pingPongKeys(track, fps, frameCount, described.convert, numeric)
      : directKeys(track, fps, described.convert);
    if (!keys.length) continue;
    props.push(...valueTrackProps(index, described.path, described.discrete, keys));
    index += 1;
  }
  const events = eventKeys(ctx, playerNode, name, clip, fps, frameCount, pingPong);
  if (events.length) {
    const playerPath = relativePath([], ctx.scene.nodeSegments(playerNode.id));
    props.push(
      [`tracks/${index}/type`, 'method'],
      [`tracks/${index}/imported`, false],
      [`tracks/${index}/enabled`, true],
      [`tracks/${index}/path`, gd.nodePath(playerPath)],
      [`tracks/${index}/interp`, 1],
      [`tracks/${index}/loop_wrap`, true],
      [`tracks/${index}/keys`, {
        times: gd.packedFloat32(events.map((event) => event.time)),
        transitions: gd.packedFloat32(events.map(() => 1)),
        values: events.map((event) => ({ method: gd.stringName('emit_animation_event'), args: event.args })),
      }],
    );
  }
  return { props, hasEvents: events.length > 0 };
}

/** Method-track keys; events at frames a non-loop clip never reaches are dropped. */
function eventKeys(ctx, playerNode, name, clip, fps, frameCount, pingPong) {
  const result = [];
  for (const event of [...(clip.events ?? [])].sort((a, b) => a.at - b.at)) {
    if (event.at >= frameCount) {
      ctx.warn('animation-event-unreachable', `${ctx.label} clip '${name}': event '${event.eventId}' at frame ${event.at} ≥ ${frameCount} never fires`);
      continue;
    }
    const args = [event.eventId, event.payload ?? {}, event.gameplay ?? false, event.at];
    result.push({ time: roundTime(event.at / fps), args });
    if (pingPong && event.at > 0 && event.at < frameCount - 1) {
      result.push({ time: roundTime((2 * frameCount - 2 - event.at) / fps), args });
    }
  }
  return result.sort((a, b) => a.time - b.time);
}

/**
 * AnimationPlayer properties: the helper script, the library, the process
 * domain, autoplay and randomized start.
 */
export function convertAnimationPlayerProps(ctx) {
  const p = ctx.props;
  const props = [['script', gd.ext('Script', ANIMATION_PLAYER_SCRIPT)]];
  const libraryId = p.library?.resourceId;
  const library = libraryId ? ctx.resource(libraryId, 'animation-library') : null;
  let hasEvents = false;
  if (library) {
    const entries = [];
    for (const [name, clip] of Object.entries(library.animations)) {
      const converted = convertClip(ctx, ctx.node, name, clip, ctx.report);
      hasEvents ||= converted.hasEvents;
      entries.push([gd.stringName(name), gd.sub('Animation', `${libraryId}:${name}`, converted.props)]);
    }
    props.push(['libraries/', gd.sub('AnimationLibrary', libraryId, [['_data', gd.dict(entries)]])]);
    if (p.autoplay && !Object.hasOwn(library.animations, p.autoplay)) {
      ctx.warn('missing-autoplay-clip', `${ctx.label}: autoplay clip '${p.autoplay}' is not in the library`);
    }
  }
  if ((p.domain ?? 'render') === 'physics') props.push(['callback_mode_process', 0]);
  if (hasEvents) props.push(['callback_mode_method', 1]);
  if (p.autoplay) props.push(['autoplay', gd.stringName(p.autoplay)]);
  if (p.randomizeStart) props.push(['randomize_start', true]);
  return props;
}
