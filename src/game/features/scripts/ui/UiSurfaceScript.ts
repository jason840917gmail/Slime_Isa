import type { JsonValue } from '../../../content/scenes/types';
import type { Node } from '../../../runtime/scene/Node';
import { ControlNode } from '../../../runtime/scene/ui/ControlNode';
import type { NodeConstructionContext } from '../../../runtime/scene/registries/NodeTypeRegistry';
import { ScriptNode } from '../../../runtime/scene/scripts/ScriptNode';
import {
  ButtonControlNode,
  ItemListControlNode,
  LabelControlNode,
  ModalRootControlNode,
  ProgressBarControlNode,
} from '../../../infrastructure/phaser-nodes/ui/ControlNodes';

export const UI_SURFACE_SERVICE = 'ui.surface-models';

export type UiPresentationModel = Readonly<Record<string, JsonValue>>;

export interface UiSurfacePort {
  snapshot(surfaceId: string): UiPresentationModel;
  subscribe?(surfaceId: string, listener: (model: UiPresentationModel) => void): (() => void) | undefined;
  invoke(surfaceId: string, actionId: string, payload?: JsonValue): void;
}

interface UiBinding {
  readonly nodePath: string;
  readonly property: string;
  readonly model: string;
}

const HANDLERS = ['on_primary_action', 'on_secondary_action', 'on_close_action', 'on_item_selected', 'on_jump_action', 'on_slam_action', 'on_lash_action', 'on_teleport_action'] as const;

export class UiSurfaceScript extends ScriptNode {
  readonly surfaceId: string;
  readonly modalSurface: boolean;
  private readonly bindings: readonly UiBinding[];
  private readonly actions: Readonly<Record<string, string>>;
  private port?: UiSurfacePort;
  private lastModel?: UiPresentationModel;
  private subscribed = false;

  constructor(context: NodeConstructionContext) {
    if (!context.scriptId) throw new Error('UiSurfaceScript requires a registered script identity.');
    super({ runtimeId: context.runtimeId, name: context.name, scriptId: context.scriptId, exportedProperties: context.properties });
    this.surfaceId = typeof context.properties.surfaceId === 'string' ? context.properties.surfaceId : '';
    this.modalSurface = context.properties.modal === true;
    this.bindings = parseBindings(context.properties.bindings);
    this.actions = stringRecord(context.properties.actions);
    for (const handler of HANDLERS) this.registerSignalHandler<JsonValue | undefined>(handler, (payload) => this.invoke(handler, payload));
    this.set_process(true);
    this.set_process_when_paused(true);
  }

  override _enter_tree(): void {
    super._enter_tree();
    this.port = this.service<UiSurfacePort>(UI_SURFACE_SERVICE);
    const subscription = this.port.subscribe?.(this.surfaceId, (model) => this.applyModel(model));
    this.subscribed = !!subscription;
    if (subscription) this.entryDisposables.add(subscription);
    this.applyModel(this.port.snapshot(this.surfaceId));
  }

  override _process(): void {
    if (!this.subscribed) this.applyModel(this.port?.snapshot(this.surfaceId) ?? {});
  }

  invoke(handlerId: string, payload?: JsonValue): boolean {
    const actionId = this.actions[handlerId];
    if (!actionId || !this.port) return false;
    this.queue_external_command(() => this.port?.invoke(this.surfaceId, actionId, payload));
    return true;
  }

  applyModel(model: UiPresentationModel): void {
    if (this.lastModel === model) return;
    this.lastModel = model;
    for (const binding of this.bindings) {
      const value = modelValue(model, binding.model);
      if (value === undefined) continue;
      applyBinding(this, binding, value);
    }
  }
}

function applyBinding(script: UiSurfaceScript, binding: UiBinding, value: JsonValue): void {
  let target: Node;
  try { target = script.get_node(binding.nodePath); } catch { return; }
  if (target instanceof LabelControlNode && binding.property === 'text' && typeof value === 'string') target.text = value;
  else if (target instanceof LabelControlNode && binding.property === 'color' && typeof value === 'string' && /^#[0-9a-f]{6}$/i.test(value)) target.color = value;
  else if (target instanceof LabelControlNode && binding.property === 'fontSize' && typeof value === 'number' && Number.isFinite(value) && value > 0) target.fontSize = value;
  else if (target instanceof ProgressBarControlNode && binding.property === 'value' && typeof value === 'number') target.value = value;
  else if (target instanceof ProgressBarControlNode && binding.property === 'max' && typeof value === 'number' && value > 0) target.max = value;
  else if (target instanceof ProgressBarControlNode && binding.property === 'label' && typeof value === 'string') target.label = value;
  else if (target instanceof ProgressBarControlNode && binding.property === 'tone' && isTone(value)) target.tone = value;
  else if (target instanceof ControlNode && (binding.property === 'offsetMin' || binding.property === 'offsetMax')
    && Array.isArray(value) && value.length === 2 && typeof value[0] === 'number' && typeof value[1] === 'number') {
    target.setLayoutOffset(binding.property, { x: value[0], y: value[1] });
  }
  else if (target instanceof ButtonControlNode && binding.property === 'disabled' && typeof value === 'boolean') target.disabled = value;
  else if (target instanceof ItemListControlNode && binding.property === 'selectedIndex' && Number.isSafeInteger(value)) target.selectedIndex = value as number;
  else if (target instanceof ItemListControlNode && binding.property === 'items' && Array.isArray(value)) target.items = value.flatMap((entry) => {
    if (!entry || typeof entry !== 'object' || Array.isArray(entry) || typeof entry.id !== 'string' || typeof entry.label !== 'string') return [];
    return [{ id: entry.id, label: entry.label, ...(typeof entry.disabled === 'boolean' ? { disabled: entry.disabled } : {}), ...('metadata' in entry ? { metadata: entry.metadata } : {}) }];
  });
  else if (target instanceof ModalRootControlNode && binding.property === 'open' && typeof value === 'boolean') target.setOpen(value);
  else if (target instanceof ControlNode && binding.property === 'opacity' && typeof value === 'number' && Number.isFinite(value) && value >= 0 && value <= 1) target.opacity = value;
  else if (target instanceof ControlNode && binding.property === 'scale' && typeof value === 'number' && Number.isFinite(value) && value > 0) target.scale = value;
  else if ('visible' in target && binding.property === 'visible' && typeof value === 'boolean') (target as { visible: boolean }).visible = value;
  else if ('focused' in target && binding.property === 'focused' && typeof value === 'boolean') (target as { focused: boolean }).focused = value;
}

function isTone(value: JsonValue): value is 'default' | 'muted' | 'accent' | 'info' | 'warning' | 'danger' | 'special' {
  return typeof value === 'string' && ['default', 'muted', 'accent', 'info', 'warning', 'danger', 'special'].includes(value);
}

function parseBindings(value: JsonValue | undefined): readonly UiBinding[] {
  if (!Array.isArray(value)) return [];
  return value.flatMap((entry) => {
    if (!entry || typeof entry !== 'object' || Array.isArray(entry)
      || typeof entry.nodePath !== 'string' || typeof entry.property !== 'string' || typeof entry.model !== 'string') return [];
    return [{ nodePath: entry.nodePath, property: entry.property, model: entry.model }];
  });
}

function stringRecord(value: JsonValue | undefined): Readonly<Record<string, string>> {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return {};
  return Object.fromEntries(Object.entries(value).filter((entry): entry is [string, string] => typeof entry[1] === 'string'));
}

function modelValue(model: UiPresentationModel, path: string): JsonValue | undefined {
  let value: JsonValue | undefined = model;
  for (const segment of path.split('.')) {
    if (!value || typeof value !== 'object' || Array.isArray(value)) return undefined;
    value = (value as Readonly<Record<string, JsonValue>>)[segment];
  }
  return value;
}
