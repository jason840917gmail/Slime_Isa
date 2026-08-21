export function handleStudioHistoryShortcut(
  event: KeyboardEvent,
  undo: () => boolean,
  redo: () => boolean,
): boolean {
  if (event.isComposing || !(event.ctrlKey || event.metaKey) || event.altKey) return false;
  const key = event.key.toLowerCase();
  if (key === 'z') {
    event.preventDefault();
    if (event.shiftKey) redo();
    else undo();
    return true;
  }
  if (key === 'y') {
    event.preventDefault();
    redo();
    return true;
  }
  return false;
}
