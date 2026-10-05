/**
 * AudioStreamPlayer / AudioStreamPlayer2D. The node keeps Godot's own
 * properties (volume, pitch, polyphony, bus, distance) and gets the cue
 * helper (`sfx_player.gd` / `sfx_player_2d.gd`), which reproduces the Phaser
 * playback rules: per-play pitch randomness, min interval, payload filter,
 * loop flag, autoplay through the helper and detached one-shots.
 */
import { gd } from './tscn.mjs';

export const SFX_PLAYER_SCRIPT = 'res://game/runtime/sfx_player.gd';
export const SFX_PLAYER_2D_SCRIPT = 'res://game/runtime/sfx_player_2d.gd';

const BUS_NAMES = { effects: 'Effects', music: 'Music', ambience: 'Ambience' };

/** Phaser descriptor defaults that differ from Godot's. */
const DEFAULT_POLYPHONY = 4;
const DEFAULT_MAX_DISTANCE = 800;
const DEFAULT_PAN_DISTANCE = 400;

/** `audio` resource → stream value (variants → AudioStreamRandomizer, uniform picks with repeats). */
export function audioStream(resource, assets) {
  if (!resource.variants?.length) return assets.audioStream(resource.assetId);
  const ids = [resource.assetId, ...resource.variants];
  const props = [['playback_mode', 1], ['random_pitch', gd.float(1)], ['streams_count', ids.length]];
  ids.forEach((assetId, index) => {
    props.push([`stream_${index}/stream`, assets.audioStream(assetId)]);
    props.push([`stream_${index}/weight`, gd.float(1)]);
  });
  return gd.sub('AudioStreamRandomizer', resource.resourceId, props);
}

const linearToDb = (volume) => (volume <= 0 ? -80 : Math.max(-80, 20 * Math.log10(volume)));

/** Properties of an audio player node (without position, which the caller adds). */
export function convertAudioProps(ctx, is2d) {
  const p = ctx.props;
  const props = [['script', gd.ext('Script', is2d ? SFX_PLAYER_2D_SCRIPT : SFX_PLAYER_SCRIPT)], ['process_mode', 3]];
  const streamRef = p.stream?.resourceId;
  if (streamRef) {
    const resource = ctx.resource(streamRef, 'audio');
    if (resource) props.push(['stream', audioStream(resource, ctx.project.assets)]);
  }
  const volume = p.volume ?? 1;
  if (volume !== 1) props.push(['volume_db', gd.float(Math.round(linearToDb(volume) * 1e4) / 1e4)]);
  if ((p.pitch ?? 1) !== 1) props.push(['pitch_scale', gd.float(p.pitch)]);
  props.push(['max_polyphony', p.polyphony ?? DEFAULT_POLYPHONY]);
  const bus = BUS_NAMES[p.bus ?? 'effects'];
  if (!bus) ctx.warn('unknown-audio-bus', `${ctx.label}: bus '${p.bus}' is not effects|music|ambience`);
  props.push(['bus', gd.stringName(bus ?? 'Effects')]);
  if (is2d) props.push(['max_distance', gd.float(p.maxDistance ?? DEFAULT_MAX_DISTANCE)]);
  if (p.pitchRandomness) props.push(['pitch_randomness', gd.float(p.pitchRandomness)]);
  if (p.minIntervalMs) props.push(['min_interval_ms', gd.float(p.minIntervalMs)]);
  if (p.payloadFilter) props.push(['payload_filter', p.payloadFilter]);
  if (p.loop) props.push(['loop', true]);
  if (p.autoplay) props.push(['autoplay_cue', true]);
  if (is2d && p.detached) props.push(['detached', true]);
  if (is2d) props.push(['pan_distance', gd.float(p.panDistance ?? DEFAULT_PAN_DISTANCE)]);
  return props;
}
