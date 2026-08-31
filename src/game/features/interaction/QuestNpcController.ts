import Phaser from 'phaser';
import { gameEvents } from '../../core/EventBus';
import { getNpcDefinition } from '../../content/npcs/NpcCatalog';
import { getObjectArchetype, isObjectArchetypeId } from '../../content/objects/ObjectCatalog';
import type { BuiltObjectRegistration } from '../world/MapBuilder';
import { questService } from '../../quests/QuestService';
import { QuestOfferModal } from '../../ui/QuestOfferModal';
import type { InteractionCandidate, InteractionRouter, InteractionProvider } from './InteractionRouter';

const NPC_INTERACT_DISTANCE = 96;

interface QuestNpcRecord {
  readonly image: Phaser.GameObjects.Image;
  readonly instanceId: string;
  readonly npcId: string;
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
  private unregisterRouter?: () => void;
  private disposed = false;

  constructor(private readonly ctx: QuestNpcControllerContext) {
    this.modal = new QuestOfferModal(ctx.scene, ctx.modalStack, ctx.onPausedChange);
  }

  register(registration: BuiltObjectRegistration): void {
    if (!isObjectArchetypeId(registration.objectId)) return;
    const definition = getObjectArchetype(registration.objectId);
    const npcId = registration.npcDefinitionId ?? definition.npc?.definitionId;
    if (!npcId || !getNpcDefinition(npcId)) return;
    this.records.push({ image: registration.image, instanceId: registration.instanceId, npcId });
    registration.image.setData('npcId', npcId);
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
      if (!record.image.active || !record.image.visible) continue;
      const distance = Phaser.Math.Distance.Between(player.x, player.y, record.image.x, record.image.y);
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
          this.modal.openTurnIn(turnIn, record.npcId, () => this.talked(record.npcId));
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
          this.modal.openOffer(offer, () => this.talked(record.npcId));
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
          const result = questService.reoffer(reoffer.quest.questId, record.npcId);
          if (!result.ok) {
            this.ctx.showMessage(record.image.x, record.image.y - 52, result.reason, 'red', true);
            return true;
          }
          const refreshed = questService.get(reoffer.quest.questId);
          if (!refreshed) {
            this.ctx.showMessage(record.image.x, record.image.y - 52, 'The quest could not be reopened.', 'red', true);
            return true;
          }
          this.modal.openOffer({ quest: refreshed, npcId: record.npcId }, () => this.talked(record.npcId));
          return true;
        },
      };
    }
    return {
      id: `quest-npcs:${record.instanceId}:talk`,
      prompt: `F  Talk to ${getNpcDefinition(record.npcId)?.displayName ?? record.npcId}`,
      priority: 50,
      execute: () => {
        this.talked(record.npcId);
        this.ctx.showMessage(record.image.x, record.image.y - 52, getNpcDefinition(record.npcId)?.description ?? 'Hello!', 'white');
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
    this.records.length = 0;
  }

  private talked(npcId: string): void {
    gameEvents.emit('npc.talked', { npcId });
  }
}
