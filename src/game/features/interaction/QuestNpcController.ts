import Phaser from 'phaser';
import { gameEvents } from '../../core/EventBus';
import { getNpcDefinition } from '../../content/npcs/NpcCatalog';
import type { QuestView } from '../../content/quests/types';
import { questService } from '../../quests/QuestService';
import { storyProgress } from '../progression/StoryProgress';
import type { NpcQuestMarker } from '../npcs/NpcNameTags';
import type { NpcDialogueSurfacePort } from '../ui/NpcDialogueSurfacePort';
import type { QuestOfferSurfacePort } from '../ui/QuestOfferSurfacePort';
import type { InteractionCandidate, InteractionRouter, InteractionProvider } from './InteractionRouter';

const NPC_INTERACT_DISTANCE = 96;
const NPC_BADGE_OFFSET_X = 30;
const NPC_BADGE_OFFSET_Y = -30;
/** An NPC's body centre sits this far above its position; pointing near it picks the NPC. */
const NPC_BODY_RISE_PX = 24;

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
  readonly getOfferSurface: () => QuestOfferSurfacePort | undefined;
  readonly getDialogueSurface: () => NpcDialogueSurfacePort | undefined;
  readonly setMarker: (instanceId: string, marker: NpcQuestMarker | undefined) => void;
  readonly showMessage: (x: number, y: number, message: string, color?: 'white' | 'yellow' | 'green' | 'red', important?: boolean) => void;
}

/** Registers authored NPC objects, exposes one prioritized interaction provider, and keeps their quest markers current. */
export class QuestNpcController implements InteractionProvider {
  private readonly records: QuestNpcRecord[] = [];
  private readonly pendingReleases = new Set<() => void>();
  private unregisterRouter?: () => void;
  private disposed = false;
  /** NPCs can mount after finalize (world loading, save restore), so markers refresh on the next frame. */
  private markersDirty = true;

  constructor(private readonly ctx: QuestNpcControllerContext) {}

  private get modal(): QuestOfferSurfacePort {
    const surface = this.ctx.getOfferSurface();
    if (!surface) throw new Error('Quest NPC interactions require the authored offer surface.');
    return surface;
  }

  private get dialogue(): NpcDialogueSurfacePort {
    const surface = this.ctx.getDialogueSurface();
    if (!surface) throw new Error('NPC conversations require the authored dialogue surface.');
    return surface;
  }

  /** Where a quest NPC stands on this map, if it is here. */
  npcPosition(npcId: string): { readonly x: number; readonly y: number } | undefined {
    const record = this.records.find((entry) => entry.npcId === npcId);
    return record?.actor.getPosition();
  }

  register(registration: QuestNpcRegistration): void {
    if (!getNpcDefinition(registration.npcDefinitionId)) return;
    this.records.push({ actor: registration.actor, instanceId: registration.instanceId, npcId: registration.npcDefinitionId });
    this.markersDirty = true;
  }

  finalize(): void {
    if (this.unregisterRouter || this.disposed) return;
    this.unregisterRouter = this.ctx.router.register('quest-npcs', this);
    gameEvents.on('quest.changed', this.markMarkersDirty, this);
  }

  getCandidate(): InteractionCandidate | undefined {
    return this.inReach()[0]?.candidate;
  }

  /** Every NPC in reach, so the pointer can choose one that is not the nearest. */
  getCandidates(): readonly InteractionCandidate[] {
    return this.inReach().map(({ candidate }) => candidate);
  }

  /** NPCs in reach, best first: highest priority, then nearest. */
  private inReach(): readonly { readonly distance: number; readonly candidate: InteractionCandidate }[] {
    if (this.disposed) return [];
    if (this.markersDirty) this.refreshMarkers();
    const player = this.ctx.getPlayer();
    const found: { distance: number; candidate: InteractionCandidate }[] = [];
    for (const record of this.records) {
      if (!record.actor.isActive()) continue;
      const position = record.actor.getPosition();
      const distance = Phaser.Math.Distance.Between(player.x, player.y, position.x, position.y);
      if (distance > NPC_INTERACT_DISTANCE) continue;
      const actor = record.actor;
      found.push({
        distance,
        candidate: {
          ...this.candidateFor(record),
          // Beside the head so the badge never covers the NPC's name tag.
          anchor: () => {
            const at = actor.getPosition();
            return { x: at.x + NPC_BADGE_OFFSET_X, y: at.y + NPC_BADGE_OFFSET_Y };
          },
          // Pointing at the NPC's body picks it.
          origin: () => {
            const at = actor.getPosition();
            return { x: at.x, y: at.y - NPC_BODY_RISE_PX };
          },
        },
      });
    }
    return found.sort((left, right) => right.candidate.priority - left.candidate.priority || left.distance - right.distance);
  }

  private candidateFor(record: QuestNpcRecord): InteractionCandidate {
    const name = getNpcDefinition(record.npcId)?.displayName ?? record.npcId;
    const turnIn = questService.turnInsForNpc(record.npcId)[0];
    if (turnIn) {
      return {
        id: `quest-npcs:${record.instanceId}:turn-in`,
        prompt: `Return to ${name}`,
        priority: 100,
        execute: () => this.converse(record, turnIn.definition.dialogue?.complete, 'Claim reward  ▸',
          (release) => this.modal.openTurnIn(turnIn, record.npcId, () => this.talked(record.npcId), release)),
      };
    }
    const offer = questService.offersForNpc(record.npcId)[0];
    if (offer) {
      return {
        id: `quest-npcs:${record.instanceId}:offer`,
        prompt: `Talk to ${name}`,
        priority: 90,
        execute: () => this.converse(record, offer.quest.definition.dialogue?.offer, 'Continue  ▸',
          (release) => this.modal.openOffer(offer, () => this.talked(record.npcId), release)),
      };
    }
    const reoffer = questService.reoffersForNpc(record.npcId)[0];
    if (reoffer) {
      return {
        id: `quest-npcs:${record.instanceId}:reoffer`,
        prompt: `Resume quest with ${name}`,
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
      prompt: `Talk to ${name}`,
      priority: 50,
      execute: () => {
        const definition = getNpcDefinition(record.npcId);
        const waiting = this.activeQuestFrom(record.npcId);
        const pages = waiting
          ? [...(waiting.definition.dialogue?.progress ?? []), progressLine(waiting)]
          : definition?.dialogue ?? [definition?.description ?? 'Hello!'];
        const release = record.actor.acquireInteractionLock();
        try {
          this.dialogue.open({ speaker: name, pages, onClosed: release });
        } catch (error) {
          release();
          throw error;
        }
        this.talked(record.npcId);
        return true;
      },
    };
  }

  destroy(): void {
    if (this.disposed) return;
    this.disposed = true;
    gameEvents.off('quest.changed', this.markMarkersDirty, this);
    this.unregisterRouter?.();
    this.unregisterRouter = undefined;
    this.ctx.getOfferSurface()?.close();
    this.ctx.getDialogueSurface()?.close();
    for (const release of [...this.pendingReleases]) release();
    this.records.length = 0;
  }

  /**
   * Speaks the quest's lines first, then opens the decision surface. Esc during the
   * lines ends the conversation without a decision; the quest stays where it was.
   */
  private converse(record: QuestNpcRecord, pages: readonly string[] | undefined, finishLabel: string, decide: (release: () => void) => void): boolean {
    const release = record.actor.acquireInteractionLock();
    const openDecision = (): void => {
      try {
        decide(release);
      } catch (error) {
        release();
        throw error;
      }
    };
    if (!pages?.length) { openDecision(); return true; }
    try {
      this.dialogue.open({
        speaker: getNpcDefinition(record.npcId)?.displayName ?? record.npcId,
        pages,
        finishLabel,
        onFinished: openDecision,
        onClosed: release,
      });
    } catch (error) {
      release();
      throw error;
    }
    return true;
  }

  private activeQuestFrom(npcId: string): QuestView | undefined {
    return questService.list('active').find((quest) => quest.definition.acquisition.kind === 'npc'
      && quest.definition.acquisition.npcIds.includes(npcId));
  }

  private markerFor(npcId: string): NpcQuestMarker | undefined {
    if (questService.turnInsForNpc(npcId).length > 0) return 'turn-in';
    const offers = questService.offersForNpc(npcId);
    if (offers.some((offer) => offer.quest.definition.category === 'mandatory')) return 'main-offer';
    if (offers.length > 0 || questService.reoffersForNpc(npcId).length > 0) return 'side-offer';
    const wantsWord = questService.list('active').some((quest) => {
      const stage = quest.definition.stages.find((candidate) => candidate.id === quest.activeStageId);
      return stage?.objectives.some((objective) => objective.kind === 'talk-to-npc'
        && objective.npcIds.includes(npcId)
        && (quest.progress[objective.id] ?? 0) < objective.target) ?? false;
    });
    if (wantsWord) return 'talk';
    const waiting = questService.list('active').some((quest) => quest.definition.completion.kind === 'npc-turn-in'
      && quest.definition.completion.npcIds.includes(npcId));
    return waiting ? 'in-progress' : undefined;
  }

  private markMarkersDirty(): void {
    this.markersDirty = true;
  }

  private refreshMarkers(): void {
    this.markersDirty = false;
    for (const record of this.records) this.ctx.setMarker(record.instanceId, this.markerFor(record.npcId));
  }

  private talked(npcId: string): void {
    storyProgress.recordTalk(npcId);
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

/** One line reminding the player what the giver is still waiting for. */
function progressLine(quest: QuestView): string {
  const stage = quest.definition.stages.find((candidate) => candidate.id === quest.activeStageId);
  const remaining = stage?.objectives
    .filter((objective) => (quest.progress[objective.id] ?? 0) < objective.target)
    .map((objective) => `${objective.label} (${quest.progress[objective.id] ?? 0}/${objective.target})`) ?? [];
  return remaining.length > 0
    ? `Still to do for "${quest.definition.title}":\n${remaining.map((line) => `• ${line}`).join('\n')}`
    : `"${quest.definition.title}" — come back to me when you're ready.`;
}
