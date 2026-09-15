import Phaser from 'phaser';
import { gameEvents } from '../../core/EventBus';
import { getNpcDefinition } from '../../content/npcs/NpcCatalog';
import type { BuiltNpcRegistration } from '../world/MapBuilder';
import { questService } from '../../quests/QuestService';
import { QuestOfferModal } from '../../ui/QuestOfferModal';
import type { InteractionCandidate, InteractionRouter, InteractionProvider } from './InteractionRouter';

const NPC_INTERACT_DISTANCE = 96;

interface QuestNpcRecord {
  readonly actor: NpcActorHandle;
  readonly instanceId: string;
  readonly npcId: string;
}

export interface NpcActorHandle {
  readonly instanceId: string;
  readonly npcId: string;
  isActive(): boolean;
  getPosition(): { readonly x: number; readonly y: number };
  acquireInteractionLock(): () => void;
}

export interface QuestNpcRegistration {
  readonly actor: NpcActorHandle;
  readonly instanceId: string;
  readonly npcDefinitionId: string;
}

export interface QuestNpcControllerContext {
  readonly scene: Phaser.Scene;
  readonly getPlayer: () => Phaser.Physics.Arcade.Sprite;
  readonly router: InteractionRouter;
  readonly modalStack: import('../../ui/ModalStack').ModalStack;
  readonly onPausedChange: (paused: boolean) => void;
  readonly showMessage: (x: number, y: number, message: string, color?: 'white' | 'yellow' | 'green' | 'red', important?: boolean) => void;
}

/** Registers authored NPC objects and exposes one prioritized interaction provider. */
export class QuestNpcController implements InteractionProvider {
  private readonly records: QuestNpcRecord[] = [];
  private readonly modal: QuestOfferModal;
  private readonly pendingReleases = new Set<() => void>();
  private unregisterRouter?: () => void;
  private disposed = false;

  constructor(private readonly ctx: QuestNpcControllerContext) {
    this.modal = new QuestOfferModal(ctx.scene, ctx.modalStack, ctx.onPausedChange);
  }

  register(registration: BuiltNpcRegistration | QuestNpcRegistration): void {
    if (!getNpcDefinition(registration.npcDefinitionId)) return;
    this.records.push({ actor: registration.actor, instanceId: registration.instanceId, npcId: registration.npcDefinitionId });
  }

  finalize(): void {
    if (this.unregisterRouter || this.disposed) return;
    this.unregisterRouter = this.ctx.router.register('quest-npcs', this);
  }

  getCandidate(): InteractionCandidate | undefined {
    if (this.disposed) return undefined;
    const player = this.ctx.getPlayer();
    let best: { record: QuestNpcRecord; distance: number; candidate: InteractionCandidate } | undefined;
    for (const record of this.records) {
      if (!record.actor.isActive()) continue;
      const position = record.actor.getPosition();
      const distance = Phaser.Math.Distance.Between(player.x, player.y, position.x, position.y);
      if (distance > NPC_INTERACT_DISTANCE) continue;
      const candidate = this.candidateFor(record);
      if (!best || candidate.priority > best.candidate.priority
        || (candidate.priority === best.candidate.priority && distance < best.distance)) {
        best = { record, distance, candidate };
      }
    }
    return best?.candidate;
  }

  private candidateFor(record: QuestNpcRecord): InteractionCandidate {
    const turnIn = questService.turnInsForNpc(record.npcId)[0];
    if (turnIn) {
      return {
        id: `quest-npcs:${record.instanceId}:turn-in`,
        prompt: `F  Return to ${getNpcDefinition(record.npcId)?.displayName ?? record.npcId}`,
        priority: 100,
        execute: () => {
          const release = record.actor.acquireInteractionLock();
          try {
            this.modal.openTurnIn(turnIn, record.npcId, () => this.talked(record.npcId), release);
          } catch (error) {
            release();
            throw error;
          }
          return true;
        },
      };
    }
    const offer = questService.offersForNpc(record.npcId)[0];
    if (offer) {
      return {
        id: `quest-npcs:${record.instanceId}:offer`,
        prompt: `F  Talk to ${getNpcDefinition(record.npcId)?.displayName ?? record.npcId}`,
        priority: 90,
        execute: () => {
          const release = record.actor.acquireInteractionLock();
          try {
            this.modal.openOffer(offer, () => this.talked(record.npcId), release);
          } catch (error) {
            release();
            throw error;
          }
          return true;
        },
      };
    }
    const reoffer = questService.reoffersForNpc(record.npcId)[0];
    if (reoffer) {
      return {
        id: `quest-npcs:${record.instanceId}:reoffer`,
        prompt: `F  Resume quest with ${getNpcDefinition(record.npcId)?.displayName ?? record.npcId}`,
        priority: 85,
        execute: () => {
          const release = record.actor.acquireInteractionLock();
          let result: ReturnType<typeof questService.reoffer>;
          try {
            result = questService.reoffer(reoffer.quest.questId, record.npcId);
          } catch (error) {
            const position = record.actor.getPosition();
            this.showTemporaryMessage(release, position.x, position.y - 52, error instanceof Error ? error.message : 'The quest could not be reopened.', 'red', true);
            return true;
          }
          if (!result.ok) {
            const position = record.actor.getPosition();
            this.showTemporaryMessage(release, position.x, position.y - 52, result.reason, 'red', true);
            return true;
          }
          const refreshed = questService.get(reoffer.quest.questId);
          if (!refreshed) {
            const position = record.actor.getPosition();
            this.showTemporaryMessage(release, position.x, position.y - 52, 'The quest could not be reopened.', 'red', true);
            return true;
          }
          try {
            this.modal.openOffer({ quest: refreshed, npcId: record.npcId }, () => this.talked(record.npcId), release);
          } catch (error) {
            release();
            throw error;
          }
          return true;
        },
      };
    }
    return {
      id: `quest-npcs:${record.instanceId}:talk`,
      prompt: `F  Talk to ${getNpcDefinition(record.npcId)?.displayName ?? record.npcId}`,
      priority: 50,
      execute: () => {
        const release = record.actor.acquireInteractionLock();
        const position = record.actor.getPosition();
        this.talked(record.npcId);
        this.ctx.showMessage(position.x, position.y - 52, getNpcDefinition(record.npcId)?.description ?? 'Hello!', 'white');
        this.scheduleRelease(release);
        return true;
      },
    };
  }

  destroy(): void {
    if (this.disposed) return;
    this.disposed = true;
    this.unregisterRouter?.();
    this.unregisterRouter = undefined;
    this.modal.destroy();
    for (const release of [...this.pendingReleases]) release();
    this.records.length = 0;
  }

  private talked(npcId: string): void {
    gameEvents.emit('npc.talked', { npcId });
  }

  private scheduleRelease(release: () => void): void {
    let timer: Phaser.Time.TimerEvent | undefined;
    let finished = false;
    const finish = (): void => {
      if (finished) return;
      finished = true;
      timer?.remove(false);
      this.ctx.scene.events.off(Phaser.Scenes.Events.SHUTDOWN, finish);
      this.pendingReleases.delete(finish);
      release();
    };
    this.pendingReleases.add(finish);
    timer = this.ctx.scene.time.delayedCall(700, finish);
    this.ctx.scene.events.once(Phaser.Scenes.Events.SHUTDOWN, finish);
  }

  private showTemporaryMessage(release: () => void, x: number, y: number, message: string, color: 'white' | 'yellow' | 'green' | 'red', important: boolean): void {
    try {
      this.ctx.showMessage(x, y, message, color, important);
    } finally {
      this.scheduleRelease(release);
    }
  }
}
