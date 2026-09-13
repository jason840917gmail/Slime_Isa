import { loadTypescriptModule } from '../../tests/helpers/load-typescript.mjs';

let tooling;

export async function loadSceneTooling() {
  tooling ??= loadTypescriptModule('src/game/content/scenes/tooling.ts');
  return tooling;
}
