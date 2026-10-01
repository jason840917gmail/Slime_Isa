/**
 * The plain HTML loading screen in index.html (`#boot-loader`). It covers the
 * time before Phaser can draw its own loading bar: downloading the game code
 * and preparing scenes. Boot removes it once the Phaser bar is up.
 */
function loader(): HTMLElement | null {
  return document.getElementById('boot-loader');
}

/** Hides it while a startup prompt needs the screen. */
export function hideBootLoader(): void {
  const element = loader();
  if (element) element.hidden = true;
}

export function showBootLoader(): void {
  const element = loader();
  if (element) element.hidden = false;
}

export function removeBootLoader(): void {
  loader()?.remove();
}
