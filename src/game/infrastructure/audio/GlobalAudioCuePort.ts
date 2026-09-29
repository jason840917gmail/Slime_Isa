import type { AudioCuePort } from '../../features/audio/AudioEventBridge';
import type { Node } from '../../runtime/scene/Node';
import { AudioStreamPlayer2DNode } from '../phaser-nodes/AudioStreamPlayer2DNode';
import { AudioStreamPlayerNode } from '../phaser-nodes/AudioStreamPlayerNode';

/** Resolves cue names to AudioStreamPlayer nodes under `Effects` in the mounted `audio.global` scene. */
export function createGlobalAudioCuePort(audioRoot: Node): AudioCuePort {
  const warned = new Set<string>();
  const find = (cue: string): AudioStreamPlayerNode | AudioStreamPlayer2DNode | undefined => {
    const path = `Effects/${cue}`;
    const node = audioRoot.has_node(path) ? audioRoot.get_node(path) : undefined;
    return node instanceof AudioStreamPlayerNode || node instanceof AudioStreamPlayer2DNode ? node : undefined;
  };
  return {
    stop(cue) {
      find(cue)?.stop();
    },
    play(cue) {
      const path = `Effects/${cue}`;
      const node = find(cue);
      if (node) {
        node.play();
        return;
      }
      if (import.meta.env.DEV && !warned.has(cue)) {
        warned.add(cue);
        console.warn(`audio.global has no AudioStreamPlayer at '${path}'`);
      }
    },
  };
}
