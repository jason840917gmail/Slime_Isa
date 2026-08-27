import type { LayeredWeaponDefinition } from '../content/weapons/types';
import { isResourceTag, RESOURCE_TAGS, resourceTagIssue } from '../content/ResourceTags';

export const WEAPON_HARVEST_TAGS = RESOURCE_TAGS;
export const WEAPON_TARGET_TAG_SUGGESTIONS = ['enemy', 'resource', ...WEAPON_HARVEST_TAGS] as const;

export interface WeaponTargetingEditableState {
  readonly draft?: LayeredWeaponDefinition;
  readonly dirty: boolean;
  readonly notice?: string;
}

export type WeaponTargetingAction =
  | { readonly type: 'add-modifier' }
  | { readonly type: 'remove-modifier'; readonly index: number }
  | { readonly type: 'set-modifier-tag'; readonly index: number; readonly targetTag: string }
  | { readonly type: 'set-modifier-value'; readonly index: number; readonly modifier: string | number }
  | { readonly type: 'add-capability' }
  | { readonly type: 'remove-capability'; readonly targetTag: string }
  | { readonly type: 'rename-capability'; readonly targetTag: string; readonly nextTargetTag: string }
  | { readonly type: 'set-capability-tier'; readonly targetTag: string; readonly tier: string | number };

function escapeHtml(value: string | number): string {
  return String(value)
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;');
}

function firstAvailableTag(suggestions: readonly string[], used: ReadonlySet<string>, prefix: string): string {
  const suggestion = suggestions.find((tag) => !used.has(tag));
  if (suggestion) return suggestion;
  let index = 1;
  while (used.has(`${prefix}-${index}`)) index += 1;
  return `${prefix}-${index}`;
}

function changed<TState extends WeaponTargetingEditableState>(
  state: TState,
  draft: LayeredWeaponDefinition,
): TState {
  return { ...state, draft, dirty: true, notice: undefined };
}

function rejected<TState extends WeaponTargetingEditableState>(state: TState, notice: string): TState {
  return { ...state, notice };
}

function authoredNumber(value: string | number): number | undefined {
  if (typeof value === 'string' && value.trim() === '') return undefined;
  const parsed = typeof value === 'number' ? value : Number(value);
  return Number.isFinite(parsed) ? parsed : undefined;
}

export function reduceWeaponTargetingAction<TState extends WeaponTargetingEditableState>(
  state: TState,
  action: WeaponTargetingAction,
): TState {
  const draft = state.draft;
  if (!draft) return state;

  const modifiers = [...(draft.damageModifiers ?? [])];
  const capabilities = { ...(draft.harvestCapabilities ?? {}) };

  if (action.type === 'add-modifier') {
    const targetTag = firstAvailableTag(WEAPON_TARGET_TAG_SUGGESTIONS, new Set(modifiers.map((entry) => entry.targetTag)), 'target');
    return changed(state, { ...draft, damageModifiers: [...modifiers, { targetTag, modifier: 1 }] });
  }
  if (action.type === 'remove-modifier') {
    if (!modifiers[action.index]) return state;
    modifiers.splice(action.index, 1);
    return changed(state, { ...draft, damageModifiers: modifiers.length > 0 ? modifiers : undefined });
  }
  if (action.type === 'set-modifier-tag') {
    if (!modifiers[action.index]) return state;
    const targetTag = action.targetTag.trim();
    if (!targetTag) return rejected(state, 'Target tag must not be empty.');
    if (modifiers.some((entry, index) => index !== action.index && entry.targetTag.trim() === targetTag)) {
      return rejected(state, `Target tag '${targetTag}' is already used.`);
    }
    modifiers[action.index] = { ...modifiers[action.index], targetTag };
    return changed(state, { ...draft, damageModifiers: modifiers });
  }
  if (action.type === 'set-modifier-value') {
    if (!modifiers[action.index]) return state;
    const modifier = authoredNumber(action.modifier);
    if (modifier === undefined || modifier < 0) return rejected(state, 'Damage modifier must be a finite number of zero or greater.');
    modifiers[action.index] = { ...modifiers[action.index], modifier };
    return changed(state, { ...draft, damageModifiers: modifiers });
  }
  if (action.type === 'add-capability') {
    const targetTag = WEAPON_HARVEST_TAGS.find((tag) => !Object.hasOwn(capabilities, tag));
    if (!targetTag) return rejected(state, 'Every configured resource tag already has a harvest capability.');
    capabilities[targetTag] = 1;
    return changed(state, { ...draft, harvestCapabilities: capabilities });
  }
  if (action.type === 'remove-capability') {
    if (!Object.hasOwn(capabilities, action.targetTag)) return state;
    delete capabilities[action.targetTag];
    return changed(state, { ...draft, harvestCapabilities: Object.keys(capabilities).length > 0 ? capabilities : undefined });
  }
  if (action.type === 'rename-capability') {
    if (!Object.hasOwn(capabilities, action.targetTag)) return state;
    const nextTargetTag = action.nextTargetTag.trim();
    if (!nextTargetTag) return rejected(state, 'Resource tag must not be empty.');
    const issue = resourceTagIssue(nextTargetTag);
    if (issue) return rejected(state, issue);
    if (nextTargetTag !== action.targetTag && Object.hasOwn(capabilities, nextTargetTag)) {
      return rejected(state, `Resource tag '${nextTargetTag}' is already used.`);
    }
    const tier = capabilities[action.targetTag];
    const renamed = Object.fromEntries(Object.entries(capabilities).map(([tag, value]) => (
      tag === action.targetTag ? [nextTargetTag, tier] : [tag, value]
    )));
    return changed(state, { ...draft, harvestCapabilities: renamed });
  }
  if (!Object.hasOwn(capabilities, action.targetTag)) return state;
  const tier = authoredNumber(action.tier);
  if (tier === undefined || !Number.isInteger(tier) || tier < 1) return rejected(state, 'Harvest tier must be an integer of at least 1.');
  capabilities[action.targetTag] = tier;
  return changed(state, { ...draft, harvestCapabilities: capabilities });
}

function tagSuggestions(id: string, tags: readonly string[]): string {
  return `<datalist id="${id}">${tags.map((tag) => `<option value="${tag}"></option>`).join('')}</datalist>`;
}

function harvestTagOptions(selectedTag: string): string {
  const configured = isResourceTag(selectedTag);
  return `${configured ? '' : `<option value="${escapeHtml(selectedTag)}" selected>${escapeHtml(selectedTag)} (unconfigured)</option>`}${WEAPON_HARVEST_TAGS.map((tag) => `<option value="${escapeHtml(tag)}" ${tag === selectedTag ? 'selected' : ''}>${escapeHtml(tag)}</option>`).join('')}`;
}

export function renderWeaponTargetingInspector(weapon: LayeredWeaponDefinition): string {
  const modifiers = weapon.damageModifiers ?? [];
  const capabilities = Object.entries(weapon.harvestCapabilities ?? {});
  return `<section class="studio-inspector-section weapon-targeting-section"><div class="studio-section-heading"><span class="studio-kicker">Target rules</span><strong>Damage by target</strong><button type="button" class="studio-icon-button" data-action="add-target-modifier" aria-label="Add damage modifier" title="Add damage modifier">+</button></div><p class="studio-help">Modifiers apply after harvesting permission. 0 blocks damage; 1 applies normal damage.</p><div class="weapon-targeting-rows">${modifiers.map((entry, index) => `<div class="weapon-targeting-row"><label><span>Target tag</span><input type="text" value="${escapeHtml(entry.targetTag)}" list="weapon-target-tags" data-target-modifier-tag="${index}" /></label><label><span>Multiplier</span><input type="number" min="0" step="0.1" value="${escapeHtml(entry.modifier)}" data-target-modifier-value="${index}" /></label><button type="button" class="studio-icon-button" data-action="remove-target-modifier" data-target-modifier-index="${index}" aria-label="Remove damage modifier for ${escapeHtml(entry.targetTag)}" title="Remove damage modifier">×</button></div>`).join('')}</div>${tagSuggestions('weapon-target-tags', WEAPON_TARGET_TAG_SUGGESTIONS)}</section><section class="studio-inspector-section weapon-targeting-section"><div class="studio-section-heading"><span class="studio-kicker">Tool access</span><strong>Harvest capabilities</strong><button type="button" class="studio-icon-button" data-action="add-harvest-capability" aria-label="Add harvest capability" title="Add harvest capability">+</button></div><p class="studio-help">A capability tier must meet the resource's minimum tier before damage is applied.</p><div class="weapon-targeting-rows">${capabilities.map(([targetTag, tier]) => `<div class="weapon-targeting-row"><label><span>Resource tag</span><select data-harvest-capability-tag="${escapeHtml(targetTag)}">${harvestTagOptions(targetTag)}</select></label><label><span>Tier</span><input type="number" min="1" step="1" value="${escapeHtml(tier)}" data-harvest-capability-tier="${escapeHtml(targetTag)}" /></label><button type="button" class="studio-icon-button" data-action="remove-harvest-capability" data-harvest-capability-tag="${escapeHtml(targetTag)}" aria-label="Remove harvest capability for ${escapeHtml(targetTag)}" title="Remove harvest capability">×</button></div>`).join('')}</div></section>`;
}
