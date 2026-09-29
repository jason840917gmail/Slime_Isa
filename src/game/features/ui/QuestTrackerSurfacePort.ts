import { gameEvents } from '../../core/EventBus';
import { getNpcDefinition } from '../../content/npcs/NpcCatalog';
import type { QuestView } from '../../content/quests/types';
import type { JsonValue } from '../../content/scenes/types';
import { questService } from '../../quests/QuestService';
import type { UiPresentationModel, UiSurfacePort } from '../scripts/ui/UiSurfaceScript';

const SURFACE_ID = 'quest-tracker';
const WIDTH = 284;
/** Directly under the HUD card (16..112), aligned to its left edge. */
const TOP = 124;
const LEFT = 16;
const HEADER_HEIGHT = 44;
/** Objectives render at 12px with 1.45 line height, one requirement per row. */
const LINE_HEIGHT = 18;
/** Roughly how many 12px characters fit across the objectives column before a row wraps. */
const CHARS_PER_ROW = 38;
const FOOTER_HEIGHT = 26;

/** Rows an objective occupies once long labels wrap, so the card always shows every requirement. */
function wrappedRows(line: string): number {
  return Math.max(1, Math.ceil([...line].length / CHARS_PER_ROW));
}

interface TrackedQuest {
  readonly heading: string;
  readonly title: string;
  readonly lines: readonly string[];
  readonly hint: string;
}

function npcName(npcId: string | undefined): string {
  return npcId ? getNpcDefinition(npcId)?.displayName ?? npcId : 'the quest giver';
}

/** Newest-first, main story before side quests: the one quest the player should be doing now. */
function trackedQuest(): TrackedQuest | undefined {
  const active = [...questService.list('active')]
    .sort((a, b) => Number(b.definition.category === 'mandatory') - Number(a.definition.category === 'mandatory')
      || (b.acceptedAt ?? 0) - (a.acceptedAt ?? 0));
  const current = active[0];
  if (current) return describeActive(current);
  const offer = questService.list('available')
    .filter((quest) => quest.definition.acquisition.kind === 'npc')
    .sort((a, b) => Number(b.definition.category === 'mandatory') - Number(a.definition.category === 'mandatory'))[0];
  if (!offer || offer.definition.acquisition.kind !== 'npc') return undefined;
  const giver = npcName(offer.definition.acquisition.npcIds[0]);
  return {
    heading: offer.definition.category === 'mandatory' ? 'NEW MAIN QUEST' : 'NEW SIDE QUEST',
    title: offer.definition.title,
    lines: [`! Talk to ${giver}`],
    hint: 'Look for the ! above their head',
  };
}

function describeActive(quest: QuestView): TrackedQuest {
  const heading = quest.definition.category === 'mandatory' ? 'MAIN QUEST' : 'SIDE QUEST';
  if (quest.readyToTurnIn && quest.definition.completion.kind === 'npc-turn-in') {
    return {
      heading,
      title: quest.definition.title,
      lines: [`? Return to ${npcName(quest.definition.completion.npcIds[0])}`],
      hint: 'Your reward is waiting',
    };
  }
  const stage = quest.definition.stages.find((candidate) => candidate.id === quest.activeStageId);
  const lines = stage?.objectives.map((objective) => {
    const current = Math.min(objective.target, quest.progress[objective.id] ?? 0);
    const count = objective.target > 1 ? `  ${current}/${objective.target}` : '';
    return `${current >= objective.target ? '✓' : '•'} ${objective.label}${count}`;
  }) ?? [];
  const stepLabel = quest.definition.stages.length > 1 && stage
    ? `Step ${quest.definition.stages.indexOf(stage) + 1}/${quest.definition.stages.length}: ${stage.title}`
    : stage?.description ?? '';
  return { heading, title: quest.definition.title, lines, hint: stepLabel };
}

/** Always-visible answer to "what do I do next?", tucked under the HUD. */
export class QuestTrackerSurfacePort implements UiSurfacePort {
  private readonly listeners = new Set<(model: UiPresentationModel) => void>();
  private model: UiPresentationModel = {};
  private stopped = false;

  constructor() {
    gameEvents.on('quest.changed', this.publish, this);
    this.model = this.build();
  }

  snapshot(surfaceId: string): UiPresentationModel {
    return surfaceId === SURFACE_ID && !this.stopped ? this.model : {};
  }

  subscribe(surfaceId: string, listener: (model: UiPresentationModel) => void): () => void {
    if (surfaceId !== SURFACE_ID || this.stopped) return () => undefined;
    this.listeners.add(listener);
    return () => { this.listeners.delete(listener); };
  }

  invoke(_surfaceId: string, _actionId: string, _payload?: JsonValue): void {}

  destroy(): void {
    if (this.stopped) return;
    this.stopped = true;
    gameEvents.off('quest.changed', this.publish, this);
    this.listeners.clear();
  }

  private build(): UiPresentationModel {
    const tracked = trackedQuest();
    const lineCount = Math.max(1, (tracked?.lines ?? []).reduce((rows, line) => rows + wrappedRows(line), 0));
    const height = HEADER_HEIGHT + lineCount * LINE_HEIGHT + FOOTER_HEIGHT;
    return {
      visible: !!tracked,
      heading: tracked?.heading ?? '',
      title: tracked?.title ?? '',
      objectives: tracked?.lines.join('\n') ?? '',
      hint: tracked?.hint ?? '',
      offsetMin: [LEFT, TOP],
      offsetMax: [LEFT + WIDTH, TOP + height],
    };
  }

  private publish(): void {
    if (this.stopped) return;
    this.model = this.build();
    for (const listener of this.listeners) listener(this.model);
  }
}
