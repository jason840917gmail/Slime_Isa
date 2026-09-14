import { parseSceneStudioRoute } from './SceneStudioRoute';

export function mountSceneStudio(container: HTMLElement): void {
  const route = parseSceneStudioRoute(window.location.search);
  container.innerHTML = `<main class="scene-studio" data-scene-studio><header><span>FIELD CARTOGRAPHER</span><h1>Scene Studio</h1></header><section aria-live="polite">${route.scene ? `Opening ${route.scene}…` : 'Choose a scene to begin.'}</section></main>`;
}
