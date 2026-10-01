import { gameEvents } from '../../core/EventBus';
import { getNpcDefinition } from '../../content/npcs/NpcCatalog';
import type { QuestObjectiveDefinition, QuestView, TutorialControlId } from '../../content/quests/types';
import type { JsonValue } from '../../content/scenes/types';
import { questService } from '../../quests/QuestService';
import { controlLabel } from '../player/ControlLabels';
import type { UiPresentationModel, UiSurfacePort } from '../scripts/ui/UiSurfaceScript';

const SURFACE_ID = 'quest-tracker';
/** Quest slots authored in `ui/quest-tracker.scene.json` (Quest1..Quest4). */
export const TRACKED_QUEST_SLOTS = 4;
const WIDTH = 284;
/** Directly under the HUD card (16..84), aligned to its left edge. */
const TOP = 96;
const LEFT = 16;
const HEADER_HEIGHT = 26;
const TITLE_HEIGHT = 20;
/** Objectives render at 12px with 1.45 line height, one requirement per row. */
const LINE_HEIGHT = 18;
const QUEST_GAP = 8;
/** Roughly how many 12px characters fit across the objectives column before a row wraps. */
const CHARS_PER_ROW = 40;
const FOOTER_HEIGHT = 22;
const MAIN_COLOR = '#ffd277';
const SIDE_COLOR = '#d9ecff';

/** Rows an objective occupies once long labels wrap, so the card always shows every requirement. */
function wrappedRows(line: string): number {
  return Math.max(1, Math.ceil([...line].length / CHARS_PER_ROW));
}

interface TrackedEntry {
  readonly quest: QuestView;
  readonly main: boolean;
  readonly title: string;
  readonly lines: readonly string[];
}

/** The key a tutorial objective needs, from the binding table (content text never names keys). */
function controlKey(controlId: TutorialControlId): string {
  switch (controlId) {
    case 'menu:inventory': return controlLabel('menu');
    case 'menu:crafting':
    case 'menu:journal': return `${controlLabel('menu')}, then its tab`;
    case 'menu:map': return controlLabel('map');
    case 'sprint': return `hold ${controlLabel('sprint')}`;
    case 'weapon-switch': return controlLabel('weapon-next');
    case 'pause': return controlLabel('pause');
  }
}

/** An objective's label as the tracker and journal show it: tutorial controls get their key. */
export function objectiveLabel(objective: QuestObjectiveDefinition): string {
  return objective.kind === 'use-control' && objective.controlIds[0]
    ? `${objective.label} (${controlKey(objective.controlIds[0])})`
    : objective.label;
}

function npcName(npcId: string | undefined): string {
  return npcId ? getNpcDefinition(npcId)?.displayName ?? npcId : 'the quest giver';
}

/**
 * Every quest worth showing, most important first (the WoW-style tracker):
 * main story before side quests, and within each, quests in progress (newest
 * first) before quests waiting to be picked up from an NPC.
 */
export function trackedQuestViews(): readonly QuestView[] {
  const rank = (quest: QuestView) => (quest.definition.category === 'mandatory' ? 0 : 2) + (quest.status === 'active' ? 0 : 1);
  const active = questService.list('active');
  const offers = questService.list('available').filter((quest) => quest.definition.acquisition.kind === 'npc');
  return [...active, ...offers].sort((a, b) => rank(a) - rank(b) || (b.acceptedAt ?? 0) - (a.acceptedAt ?? 0));
}

/** The most important quest: the one the player should be doing now. */
export function trackedQuestView(): QuestView | undefined {
  return trackedQuestViews()[0];
}

function describe(quest: QuestView): TrackedEntry {
  const main = quest.definition.category === 'mandatory';
  const title = quest.definition.title;
  if (quest.status !== 'active') {
    const acquisition = quest.definition.acquisition;
    const giver = acquisition.kind === 'npc' ? npcName(acquisition.npcIds[0]) : undefined;
    return { quest, main, title, lines: [`! Talk to ${giver ?? 'the quest giver'}`] };
  }
  if (quest.readyToTurnIn && quest.definition.completion.kind === 'npc-turn-in') {
    return { quest, main, title, lines: [`? Return to ${npcName(quest.definition.completion.npcIds[0])}`] };
  }
  const stage = quest.definition.stages.find((candidate) => candidate.id === quest.activeStageId);
  const lines = stage?.objectives.map((objective) => {
    const current = Math.min(objective.target, quest.progress[objective.id] ?? 0);
    const count = objective.target > 1 ? `  ${current}/${objective.target}` : '';
    return `${current >= objective.target ? '✓' : '•'} ${objectiveLabel(objective)}${count}`;
  }) ?? [];
  return { quest, main, title, lines: lines.length > 0 ? lines : [stage?.description ?? ''] };
}

/**
 * The always-visible quest tracker under the HUD: up to four quests, main
 * story first, each with its objectives. Clicking a quest shows the way to it
 * (the gold arrow); clicking it again hides the way.
 */
export class QuestTrackerSurfacePort implements UiSurfacePort {
  private readonly listeners = new Set<(model: UiPresentationModel) => void>();
  private model: UiPresentationModel = {};
  private stopped = false;
  private waypointOn = false;
  private waypointFound = false;
  private selectedQuestId?: string;

  constructor(private readonly onToggleWaypoint: (on: boolean) => void = () => undefined) {
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

  invoke(surfaceId: string, actionId: string, _payload?: JsonValue): void {
    if (this.stopped || surfaceId !== SURFACE_ID) return;
    const slot = /^track-(\d)$/.exec(actionId);
    const questId = slot ? this.entries()[Number(slot[1]) - 1]?.quest.questId : undefined;
    if (!questId) return;
    if (this.waypointOn && questId === this.trackedQuestId) {
      this.waypointOn = false;
    } else {
      this.selectedQuestId = questId;
      this.waypointOn = true;
    }
    this.onToggleWaypoint(this.waypointOn);
    this.publish();
  }

  /** Whether the player asked for the way to the selected quest. */
  get showingWay(): boolean { return this.waypointOn; }

  /** The quest the gold arrow follows: the one the player clicked, else the most important. */
  get trackedQuestId(): string | undefined {
    return this.waypointQuest()?.questId;
  }

  waypointQuest(): QuestView | undefined {
    const quests = trackedQuestViews();
    return quests.find((quest) => quest.questId === this.selectedQuestId) ?? quests[0];
  }

  /** Tells the card whether the waypoint found somewhere to point at on this map. */
  setWaypointFound(found: boolean): void {
    if (found === this.waypointFound) return;
    this.waypointFound = found;
    this.publish();
  }

  destroy(): void {
    if (this.stopped) return;
    this.stopped = true;
    gameEvents.off('quest.changed', this.publish, this);
    this.listeners.clear();
  }

  private entries(): readonly TrackedEntry[] {
    return trackedQuestViews().slice(0, TRACKED_QUEST_SLOTS).map(describe);
  }

  private build(): UiPresentationModel {
    const all = trackedQuestViews();
    const entries = this.entries();
    const selected = this.trackedQuestId;
    const model: Record<string, JsonValue> = {};
    let y = HEADER_HEIGHT;
    for (let slot = 1; slot <= TRACKED_QUEST_SLOTS; slot += 1) {
      const entry = entries[slot - 1];
      const rows = entry ? entry.lines.reduce((sum, line) => sum + wrappedRows(line), 0) : 0;
      const height = entry ? TITLE_HEIGHT + rows * LINE_HEIGHT : 0;
      const pointing = !!entry && this.waypointOn && entry.quest.questId === selected;
      model[`quest${slot}Visible`] = !!entry;
      model[`quest${slot}Title`] = entry ? `${pointing ? '➜ ' : ''}${entry.title}` : '';
      model[`quest${slot}Color`] = entry?.main ? MAIN_COLOR : SIDE_COLOR;
      model[`quest${slot}Objectives`] = entry?.lines.join('\n') ?? '';
      model[`quest${slot}OffsetMin`] = [10, y];
      model[`quest${slot}OffsetMax`] = [-10, y + height];
      if (entry) y += height + QUEST_GAP;
    }
    const more = all.length - entries.length;
    const height = y - QUEST_GAP + FOOTER_HEIGHT;
    const footer = this.waypointOn
      ? (this.waypointFound ? '➜ Follow the gold arrow · click it again to hide' : 'Nothing to point at on this map')
      : 'Click a quest to show the way';
    return {
      ...model,
      visible: entries.length > 0,
      heading: `QUESTS · ${all.length}`,
      hint: more > 0 ? `${footer}  (+${more} in the book)` : footer,
      bookHint: `${controlLabel('menu')} · Journal tab`,
      offsetMin: [LEFT, TOP],
      offsetMax: [LEFT + WIDTH, TOP + height],
    };
  }

  private readonly publish = (): void => {
    if (this.stopped) return;
    this.model = this.build();
    for (const listener of this.listeners) listener(this.model);
  };
}
