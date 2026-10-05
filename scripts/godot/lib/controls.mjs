/**
 * UI scene controls → Godot Controls (structure only; the styling is redone
 * as a Theme in Phase 3).
 *
 * Phaser places every scene control absolutely at the rectangle its anchors
 * and offsets give inside the parent, which is Godot's anchor/offset model, so
 * Containers become plain `Control`s (`Panel` for `game-ui` styled roots)
 * that keep their children's anchors; a BoxContainer would re-lay them out.
 * HUD-like controls ignore the mouse (attack clicks pass through); buttons,
 * lists and sliders outside a ModalRoot never take keyboard focus.
 */
import { gd } from './tscn.mjs';

export const MODAL_ROOT_SCRIPT = 'res://game/runtime/modal_root.gd';
export const ITEM_LIST_SCRIPT = 'res://game/runtime/scene_item_list.gd';
export const UI_THEME_RES_PATH = 'res://generated/resources/ui_theme.tres';

const MOUSE_STOP = 0;
const MOUSE_IGNORE = 2;
const FOCUS_NONE = 0;

export const CONTROL_TYPES = new Set(['Container', 'ModalRoot', 'ScrollContainer', 'Label', 'Button', 'ProgressBar', 'Slider', 'ItemList', 'TextureRect', 'GridContainer', 'Control']);

const ALIGN = { left: 0, center: 1, right: 2 };

const vec = (value, fallback) => (Array.isArray(value) && value.length === 2 ? value : fallback);

/** Godot type for a JSON control type. */
export function controlGodotType(node) {
  switch (node.type) {
    case 'Container': return /(^|\s)game-ui(\s|$)/.test(node.properties?.styleClass ?? '') ? 'Panel' : 'Control';
    case 'ModalRoot': return 'Panel';
    case 'Slider': return 'HSlider';
    case 'GridContainer': return 'Control';
    default: return node.type;
  }
}

/** Theme colour for a `tone` (Phaser CSS: default → text-primary). */
function toneColor(ctx, tone) {
  const values = ctx.project.themeValues;
  const key = { default: 'text-primary', muted: 'text-muted' }[tone ?? 'default'] ?? tone;
  const hex = values?.[key];
  const match = typeof hex === 'string' ? /^#([0-9a-f]{6})$/i.exec(hex) : null;
  if (!match) return null;
  const channel = (index) => Math.round((parseInt(match[1].slice(index, index + 2), 16) / 255) * 1e6) / 1e6;
  return gd.color(channel(0), channel(2), channel(4), 1);
}

function insideModalRoot(ctx) {
  for (let node = ctx.scene.parentOf(ctx.node); node; node = ctx.scene.parentOf(node)) {
    if (node.type === 'ModalRoot') return true;
  }
  return ctx.node.type === 'ModalRoot';
}

/** Anchors and offsets (anchors first, as Godot applies them). */
function layoutProps(ctx, props) {
  const p = ctx.props;
  const [minX, minY] = vec(p.anchorMin, [0, 0]);
  const [maxX, maxY] = vec(p.anchorMax, [0, 0]);
  const [left, top] = vec(p.offsetMin, [0, 0]);
  const [right, bottom] = vec(p.offsetMax, [0, 0]);
  const parent = ctx.scene.parentOf(ctx.node);
  if (parent?.type === 'ScrollContainer') {
    // ScrollContainer lays out its child: full width, authored height as minimum.
    props.push(['custom_minimum_size', gd.vec2(0, bottom - top)]);
    props.push(['size_flags_horizontal', 3]);
    return;
  }
  for (const [key, value] of [['anchor_left', minX], ['anchor_top', minY], ['anchor_right', maxX], ['anchor_bottom', maxY]]) {
    if (value !== 0) props.push([key, gd.float(value)]);
  }
  for (const [key, value] of [['offset_left', left], ['offset_top', top], ['offset_right', right], ['offset_bottom', bottom]]) {
    if (value !== 0) props.push([key, gd.float(value)]);
  }
}

function textProps(ctx, props, { label }) {
  const p = ctx.props;
  const wrap = Boolean(p.wrap);
  const text = typeof p.text === 'string' ? (wrap ? p.text : p.text.replace(/\s*\n\s*/g, ' ')) : '';
  if (text) props.push(['text', text]);
  if (wrap) props.push(['autowrap_mode', 3]);
  const color = toneColor(ctx, p.tone);
  if (color) props.push(['theme_override_colors/font_color', color]);
  if (p.fontSize) props.push(['theme_override_font_sizes/font_size', p.fontSize]);
  if (p.fontWeight && p.fontWeight >= 600) ctx.report.dropped(ctx.node.type, 'fontWeight');
  const align = ALIGN[p.textAlign ?? (label ? 'left' : 'center')];
  if (align !== undefined && (label ? align !== 0 : align !== 1)) props.push(['horizontal_alignment', align]);
  if (label) props.push(['vertical_alignment', 1]);
}

/** Properties shared by every control, then the per-type ones. Returns { props, children }. */
export function convertControl(ctx) {
  const p = ctx.props;
  const type = ctx.node.type;
  const props = [];
  const children = [];
  if (type === 'ModalRoot') props.push(['script', gd.ext('Script', MODAL_ROOT_SCRIPT)]);
  if (type === 'ItemList') props.push(['script', gd.ext('Script', ITEM_LIST_SCRIPT)]);
  const visible = type === 'ModalRoot' ? Boolean(p.open) : p.visible !== false;
  if (!visible) props.push(['visible', false]);
  if (p.zIndex) props.push(['z_index', p.zIndex]);
  if (p.processWhenPaused !== false) props.push(['process_mode', 3]);
  layoutProps(ctx, props);
  const stops = type === 'ModalRoot' || type === 'Button' || type === 'ItemList' || type === 'Slider';
  if (!stops && type !== 'Label' && type !== 'ScrollContainer') props.push(['mouse_filter', MOUSE_IGNORE]);
  if (type === 'ModalRoot') props.push(['mouse_filter', MOUSE_STOP]);
  if ((type === 'Button' || type === 'ItemList' || type === 'Slider') && !insideModalRoot(ctx)) props.push(['focus_mode', FOCUS_NONE]);
  if (p.tooltip) props.push(['tooltip_text', p.tooltip]);
  const accessibleName = p.ariaLabel || p.alt;
  if (accessibleName) props.push(['accessibility_name', accessibleName]);
  if (p.theme?.resourceId) {
    if (p.theme.resourceId === 'ui.field-kit.theme') props.push(['theme', gd.ext('Theme', UI_THEME_RES_PATH)]);
    else ctx.warn('ui-theme-unknown', `${ctx.label}: theme '${p.theme.resourceId}' is not converted`);
  }
  switch (type) {
    case 'Label': textProps(ctx, props, { label: true }); break;
    case 'Button':
      textProps(ctx, props, { label: false });
      if (p.disabled) props.push(['disabled', true]);
      break;
    case 'ProgressBar': progressBar(ctx, props, children); break;
    case 'Slider': slider(ctx, props, children); break;
    case 'ItemList': itemList(ctx, props); break;
    case 'TextureRect': textureRect(ctx, props); break;
    case 'ScrollContainer':
      if ((p.scrollAxis ?? 'vertical') === 'vertical') props.push(['horizontal_scroll_mode', 0]);
      else props.push(['vertical_scroll_mode', 0]);
      break;
    default: break;
  }
  if (p.styleClass) props.push(['metadata/style_class', p.styleClass]);
  if (p.inputPriority !== undefined) props.push(['metadata/input_priority', p.inputPriority]);
  for (const key of ['direction', 'gap', 'padding', 'align', 'justify']) {
    if (p[key] !== undefined && type === 'Container') ctx.report.dropped('Container', key);
  }
  return { props, children };
}

/** Caption Label child (ProgressBar text / Slider label). */
function caption(ctx, text, layout) {
  const props = [['mouse_filter', MOUSE_IGNORE], ...layout];
  if (text) props.push(['text', text]);
  const color = toneColor(ctx, 'default');
  if (color) props.push(['theme_override_colors/font_color', color]);
  return { name: 'Caption', type: 'Label', props, children: [] };
}

function progressBar(ctx, props, children) {
  const p = ctx.props;
  props.push(['max_value', gd.float(p.max ?? 1)], ['step', gd.float(0)]);
  if (p.value) props.push(['value', gd.float(p.value)]);
  props.push(['show_percentage', false]);
  const fill = toneColor(ctx, p.tone ?? 'accent');
  if (fill) props.push(['metadata/fill_color', fill]);
  if (p.label) props.push(['metadata/label', p.label]);
  if (p.showValue) props.push(['metadata/show_value', true]);
  children.push(caption(ctx, p.label ?? '', [
    ['anchor_right', gd.float(1)], ['anchor_bottom', gd.float(1)],
    ['theme_override_font_sizes/font_size', 11], ['horizontal_alignment', 1], ['vertical_alignment', 1],
  ]));
}

function slider(ctx, props, children) {
  const p = ctx.props;
  props.push(['min_value', gd.float(p.min ?? 0)], ['max_value', gd.float(p.max ?? 1)], ['step', gd.float(p.step ?? 0.05)]);
  if (p.value) props.push(['value', gd.float(p.value)]);
  if (p.disabled) props.push(['editable', false]);
  if (p.label) props.push(['metadata/label', p.label]);
  children.push(caption(ctx, p.label ?? '', [
    ['anchor_right', gd.float(1)], ['offset_bottom', gd.float(18)], ['theme_override_font_sizes/font_size', 14],
  ]));
}

function itemList(ctx, props) {
  const p = ctx.props;
  props.push(['max_columns', p.columns ?? 1]);
  const gap = p.gap ?? 8;
  props.push(['theme_override_constants/h_separation', gap], ['theme_override_constants/v_separation', gap]);
  if (p.dropTarget) props.push(['drop_target', true]);
}

function textureRect(ctx, props) {
  const p = ctx.props;
  const resource = p.texture?.resourceId ? ctx.resource(p.texture.resourceId) : null;
  if (resource && ctx.project.assets.has(resource.assetId)) {
    const assets = ctx.project.assets;
    const grid = assets.grid(resource.assetId);
    const frame = p.frame ?? resource.frame ?? 0;
    const sheet = grid.cols * grid.rows > 1;
    props.push(['texture', sheet
      ? gd.sub('AtlasTexture', `${resource.assetId}:${frame}`, [
        ['atlas', assets.texture(resource.assetId)],
        ['region', gd.rect2((frame % grid.cols) * grid.frameW, Math.floor(frame / grid.cols) * grid.frameH, grid.frameW, grid.frameH)],
      ])
      : assets.texture(resource.assetId)]);
  } else if (p.texture) {
    ctx.warn('ui-texture-missing', `${ctx.label}: texture '${p.texture.resourceId}' has no known asset`);
  }
  const fit = p.fit ?? 'contain';
  props.push(['expand_mode', 1]);
  props.push(['stretch_mode', { contain: 5, cover: 6, fill: 0, none: 3 }[fit] ?? 5]);
}

/** A minimal Theme from `ui.field-kit.theme` (font colour, panel and button boxes). */
export function buildUiTheme(themeResource) {
  const values = themeResource?.values ?? {};
  const color = (key, alpha = 1) => {
    const match = /^#([0-9a-f]{6})$/i.exec(values[key] ?? '');
    if (!match) return gd.color(1, 1, 1, alpha);
    const channel = (index) => Math.round((parseInt(match[1].slice(index, index + 2), 16) / 255) * 1e6) / 1e6;
    return gd.color(channel(0), channel(2), channel(4), alpha);
  };
  const box = (key, background, border) => gd.sub('StyleBoxFlat', key, [
    ['bg_color', background],
    ['border_width_left', 1], ['border_width_top', 1], ['border_width_right', 1], ['border_width_bottom', 1],
    ['border_color', border],
    ['corner_radius_top_left', 6], ['corner_radius_top_right', 6], ['corner_radius_bottom_right', 6], ['corner_radius_bottom_left', 6],
  ]);
  return [
    ['default_font_size', 14],
    ['Label/colors/font_color', color('text-primary')],
    ['Button/colors/font_color', color('text-primary')],
    ['Button/styles/normal', box('button-normal', color('surface-raised'), color('border-standard', 0.74))],
    ['Button/styles/hover', box('button-hover', color('surface-inset'), color('accent', 0.74))],
    ['Button/styles/pressed', box('button-pressed', color('surface-base'), color('accent'))],
    ['Button/styles/disabled', box('button-disabled', color('surface-base', 0.6), color('border-standard', 0.4))],
    ['Panel/styles/panel', box('panel', color('surface-base', 0.94), color('border-standard', 0.74))],
    ['ProgressBar/styles/background', box('progress-background', color('surface-inset'), color('border-standard', 0.74))],
    ['ProgressBar/styles/fill', box('progress-fill', color('accent'), color('accent'))],
  ];
}
