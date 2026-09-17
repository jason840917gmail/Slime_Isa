import test from 'node:test';
import assert from 'node:assert/strict';
import { loadTypescriptModule } from '../helpers/load-typescript.mjs';

const t = await loadTypescriptModule('src/game/features/scripts/tooling.ts');

test('legacy chest and boss UI bridges expose only typed view actions and clean their leases', () => {
  const panelEvents = [];
  const chestUi = new t.LegacyChestUiBridge({
    open: (id) => panelEvents.push(['open', id]),
    close: () => panelEvents.push(['close']),
    destroy: () => panelEvents.push(['destroy']),
  });
  let transfers = 0;
  chestUi.open({
    mapId: 'level-1', instanceId: 'chest', contents: { key: 1 },
    transferStack: () => { transfers += 1; return 1; }, close: () => {},
  });
  assert.deepEqual(chestUi.getContents('chest'), { key: 1 });
  assert.equal(chestUi.transferStack('chest', 'key'), 1);
  assert.equal(transfers, 1);
  chestUi.close('other');
  chestUi.close('chest');
  chestUi.dispose();
  assert.deepEqual(panelEvents, [['open', 'chest'], ['close'], ['destroy']]);

  const bossEvents = [];
  const bossUi = new t.LegacyBossUiBridge((campId, bossId) => ({
    defeat: () => bossEvents.push(['defeat', campId, bossId]),
    destroy: () => bossEvents.push(['destroy', campId, bossId]),
  }));
  bossUi.showBoss('camp', 'fatty');
  bossUi.hideBoss('camp', true);
  bossUi.showBoss('camp', 'fatty');
  bossUi.dispose();
  assert.deepEqual(bossEvents, [['defeat', 'camp', 'fatty'], ['destroy', 'camp', 'fatty']]);
});
