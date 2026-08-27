import type { EffectDefinition, EffectDirection } from '../content/effects/types';
import type { LayeredWeaponDefinition, WeaponAttackDirection } from '../content/weapons/types';
import type { WeaponIconSelection } from '../content/weapons/WeaponIcon';

export type WeaponStudioAnimationScope = 'idle' | 'attack' | 'effect';
export type WeaponStudioInspectorTab = 'identity' | 'combat' | 'layer' | 'on-hit';

export interface WeaponStudioHistoryState {
  readonly draft?: LayeredWeaponDefinition;
  readonly effectDraft?: EffectDefinition;
  readonly effectIsNew: boolean;
  readonly effectDirty: boolean;
  readonly dirty: boolean;
  readonly selectedId: string;
  readonly scope: WeaponStudioAnimationScope;
  readonly direction: WeaponAttackDirection;
  readonly effectDirection: EffectDirection;
  readonly selectedLayerId?: string;
  readonly selectedBlockIndex?: number;
  readonly selectedHitboxId?: string;
  readonly playhead: number;
  readonly inspectorTab: WeaponStudioInspectorTab;
  readonly playing: boolean;
  readonly notice?: string;
}

export interface WeaponIconEditableState extends WeaponStudioHistoryState {
  readonly iconPickerOpen: boolean;
  readonly iconPickerAssetId?: string;
}

export interface WeaponHistorySnapshot {
  readonly draft?: LayeredWeaponDefinition;
  readonly effectDraft?: EffectDefinition;
  readonly effectIsNew: boolean;
  readonly effectDirty: boolean;
  readonly dirty: boolean;
  readonly selectedId: string;
  readonly scope: WeaponStudioAnimationScope;
  readonly direction: WeaponAttackDirection;
  readonly effectDirection: EffectDirection;
  readonly selectedLayerId?: string;
  readonly selectedBlockIndex?: number;
  readonly selectedHitboxId?: string;
  readonly playhead: number;
  readonly inspectorTab: WeaponStudioInspectorTab;
}

export interface WeaponStudioHistory {
  readonly undo: readonly WeaponHistorySnapshot[];
  readonly redo: readonly WeaponHistorySnapshot[];
}

export interface WeaponStudioMutationResult<TState extends WeaponStudioHistoryState> {
  readonly state: TState;
  readonly history: WeaponStudioHistory;
}

export type WeaponIconAction =
  | { readonly type: 'select'; readonly selection: WeaponIconSelection }
  | { readonly type: 'clear' };

function clone<T>(value: T): T {
  return structuredClone(value);
}

export function captureWeaponHistory(state: WeaponStudioHistoryState): WeaponHistorySnapshot {
  return clone({
    draft: state.draft,
    effectDraft: state.effectDraft,
    effectIsNew: state.effectIsNew,
    effectDirty: state.effectDirty,
    dirty: state.dirty,
    selectedId: state.selectedId,
    scope: state.scope,
    direction: state.direction,
    effectDirection: state.effectDirection,
    selectedLayerId: state.selectedLayerId,
    selectedBlockIndex: state.selectedBlockIndex,
    selectedHitboxId: state.selectedHitboxId,
    playhead: state.playhead,
    inspectorTab: state.inspectorTab,
  });
}

function weaponHistoryContent(snapshot: WeaponHistorySnapshot): unknown {
  return {
    draft: snapshot.draft,
    effectDraft: snapshot.effectDraft,
    effectIsNew: snapshot.effectIsNew,
    effectDirty: snapshot.effectDirty,
    dirty: snapshot.dirty,
    selectedId: snapshot.selectedId,
  };
}

function restoreWeaponHistory<TState extends WeaponStudioHistoryState>(state: TState, snapshot: WeaponHistorySnapshot): TState {
  return {
    ...state,
    draft: snapshot.draft ? clone(snapshot.draft) : undefined,
    effectDraft: snapshot.effectDraft ? clone(snapshot.effectDraft) : undefined,
    effectIsNew: snapshot.effectIsNew,
    effectDirty: snapshot.effectDirty,
    dirty: snapshot.dirty,
    selectedId: snapshot.selectedId,
    scope: snapshot.scope,
    direction: snapshot.direction,
    effectDirection: snapshot.effectDirection,
    selectedLayerId: snapshot.selectedLayerId,
    selectedBlockIndex: snapshot.selectedBlockIndex,
    selectedHitboxId: snapshot.selectedHitboxId,
    playhead: snapshot.playhead,
    inspectorTab: snapshot.inspectorTab,
    notice: undefined,
    playing: false,
  };
}

export function reduceWeaponIconAction<TState extends WeaponIconEditableState>(state: TState, action: WeaponIconAction): TState {
  if (!state.draft) return state;
  const icon = action.type === 'select' ? action.selection : { iconKey: '', iconFrame: 0 };
  return {
    ...state,
    draft: { ...state.draft, ...icon },
    dirty: true,
    iconPickerOpen: false,
    iconPickerAssetId: undefined,
    notice: undefined,
  };
}

export function commitWeaponStudioMutation<TState extends WeaponStudioHistoryState>(
  current: TState,
  next: TState,
  history: WeaponStudioHistory,
): WeaponStudioMutationResult<TState> {
  const before = captureWeaponHistory(current);
  const after = captureWeaponHistory(next);
  if (JSON.stringify(weaponHistoryContent(before)) === JSON.stringify(weaponHistoryContent(after))) {
    return { state: next, history };
  }
  return {
    state: next,
    history: { undo: [...history.undo.slice(-99), before], redo: [] },
  };
}

export function applyWeaponStudioHistory<TState extends WeaponStudioHistoryState>(
  current: TState,
  history: WeaponStudioHistory,
  redo: boolean,
): WeaponStudioMutationResult<TState> | undefined {
  const source = redo ? history.redo : history.undo;
  const snapshot = source.at(-1);
  if (!snapshot) return undefined;
  const currentSnapshot = captureWeaponHistory(current);
  return {
    state: restoreWeaponHistory(current, snapshot),
    history: redo
      ? { undo: [...history.undo, currentSnapshot], redo: history.redo.slice(0, -1) }
      : { undo: history.undo.slice(0, -1), redo: [...history.redo, currentSnapshot] },
  };
}
