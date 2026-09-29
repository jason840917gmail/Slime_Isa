import type { GameEvents } from '../../core/EventBus';
import type { ModalStackChange } from '../../ui/ModalStack';
import { DisposableBag } from '../../shared/lifecycle/Disposable';

/**
 * Plays authored audio cues for global game events that have no scene node
 * of their own (progression, quests, status effects, menus, player actions
 * presented outside the player scene). Cue names are the names of
 * AudioStreamPlayer nodes under `Effects` in `audio.global`; the scene owns
 * the streams, volumes and buses, this bridge only decides when they play.
 *
 * Positional and per-entity sounds (hits, enemy voices, pickups, chests)
 * stay in their own scenes and are wired through signal connections.
 */
export interface AudioCuePort {
  play(cue: string): void;
  /** Stops a looping cue; one-shots simply finish. */
  stop(cue: string): void;
}

export interface AudioEventSource {
  on<T extends keyof GameEvents>(event: T, fn: (payload: GameEvents[T]) => void, context?: unknown): unknown;
  off<T extends keyof GameEvents>(event: T, fn: (payload: GameEvents[T]) => void, context?: unknown): unknown;
}

export interface AudioModalSource {
  observe(listener: (change: ModalStackChange) => void): () => void;
}

/** `player.action` animation/action ids → cue. */
const PLAYER_ACTION_CUES: Readonly<Record<string, string>> = {
  dodge: 'Dodge',
  eat: 'Eat',
  'ability-jump': 'Jump',
  'jump-land': 'Land',
  'ability-teleport': 'TeleportOut',
  'teleport-in': 'TeleportIn',
  'ability-squash-slam': 'SlamWindup',
  'slam-impact': 'SlamImpact',
  'ability-stretch-lash': 'Lash',
  'ability-denied': 'AbilityDenied',
};

const STATUS_CUES: Readonly<Record<string, string>> = {
  burn: 'StatusBurn',
  poison: 'StatusPoison',
  slow: 'StatusSlow',
  sticky: 'StatusSticky',
  bouncy: 'StatusBouncy',
  frenzy: 'StatusFrenzy',
};

/** Modal surfaces whose own scene or event already sounds on open/close. */
const SILENT_MODALS: ReadonlySet<string> = new Set(['chest-inventory', 'level-up', 'furniture-placement']);

/** Energy gains at least this large read as a restore (potion), not regeneration ticks. */
const ENERGY_RESTORE_CUE_MIN_DELTA = 20;

/** Weapon ids whose equip reads as drawing a blade rather than hefting a tool. */
const BLADE_WEAPON_PATTERN = /sword|spear/;

export class AudioEventBridge {
  private readonly disposables = new DisposableBag();

  constructor(private readonly cues: AudioCuePort, events: AudioEventSource, modals?: AudioModalSource) {
    const on = <T extends keyof GameEvents>(event: T, handler: (payload: GameEvents[T]) => void): void => {
      events.on(event, handler);
      this.disposables.add(() => events.off(event, handler));
    };

    on('player.action', ({ anim }) => this.play(PLAYER_ACTION_CUES[anim]));
    // Sleep heals a little every moment; only deliberate heals chime.
    on('player.heal', ({ source }) => { if (source !== 'rest') this.play('Heal'); });
    on('player.sleep', ({ asleep }) => { if (asleep) this.play('SleepBreath'); else this.cues.stop('SleepBreath'); });
    on('player.rested', () => this.play('Rested'));
    on('player.respawn', () => this.play('Respawn'));
    on('energy.changed', ({ delta }) => { if (delta >= ENERGY_RESTORE_CUE_MIN_DELTA) this.play('EnergyRestore'); });
    on('coins.changed', ({ delta }) => { if (delta > 0) this.play('Coin'); });
    on('level.up', () => this.play('LevelUp'));
    on('perk.taken', () => this.play('PerkChoose'));
    on('status.added', ({ kind }) => this.play(STATUS_CUES[kind]));
    on('status.removed', () => this.play('StatusExpire'));
    on('weapon.equipped', ({ weaponId }) => {
      if (weaponId) this.play(BLADE_WEAPON_PATTERN.test(weaponId) ? 'EquipBlade' : 'EquipTool');
    });
    on('craft.completed', () => this.play('CraftSuccess'));
    on('npc.talked', () => this.play('NpcBlip'));
    on('quest.accepted', () => this.play('QuestAccept'));
    on('quest.progressed', () => this.play('QuestProgress'));
    on('quest.stage-completed', () => this.play('QuestProgress'));
    on('quest.completed', () => this.play('QuestComplete'));
    on('quest.failed', () => this.play('QuestFailed'));
    on('boss.defeated', () => this.play('Victory'));
    on('area.enter', () => this.play('AreaTransition'));

    if (modals) {
      this.disposables.add(modals.observe(({ id, open }) => {
        if (SILENT_MODALS.has(id)) return;
        this.play(open ? (id === 'quest-journal' ? 'JournalOpen' : 'MenuOpen') : 'MenuClose');
      }));
    }
  }

  dispose(): void { this.disposables.dispose(); }

  private play(cue: string | undefined): void {
    if (cue) this.cues.play(cue);
  }
}
