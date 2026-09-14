import { loadTypescriptModule } from '../../tests/helpers/load-typescript.mjs';

let journalModule;

export async function loadContentWriteJournal() {
  journalModule ??= loadTypescriptModule('src/game/infrastructure/scenes/editor/ContentWriteJournal.ts');
  return journalModule;
}
