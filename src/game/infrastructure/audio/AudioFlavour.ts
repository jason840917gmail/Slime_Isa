/**
 * Audio flavour selection. Manifest audio sources carry the synthesized take
 * as their default path and CC0 library samples as `alternates.library`.
 * Library samples are the shipping default; `?sfx=synth` switches the session
 * to the synthesized takes for comparison (cues without a library take always
 * use the synthesized one).
 */
export const DEFAULT_AUDIO_FLAVOUR = 'library';

export function activeAudioFlavour(): string | undefined {
  if (typeof window === 'undefined') return DEFAULT_AUDIO_FLAVOUR;
  const requested = new URLSearchParams(window.location.search).get('sfx');
  if (requested === 'synth') return undefined;
  return requested && /^[a-z0-9-]+$/.test(requested) ? requested : DEFAULT_AUDIO_FLAVOUR;
}
