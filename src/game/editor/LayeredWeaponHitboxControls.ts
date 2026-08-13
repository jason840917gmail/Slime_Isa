import type { WeaponHitboxDocument, WeaponHitboxShape } from '../content/weapons/types';

const HITBOX_SHAPES = ['rectangle', 'circle', 'ellipse', 'sector'] as const satisfies readonly WeaponHitboxShape[];

function escapeHtml(value: unknown): string {
  return String(value ?? '').replace(/[&<>"']/g, (character) => ({
    '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#039;',
  })[character] ?? character);
}

function numberField(
  label: string,
  hitboxId: string,
  field: string,
  value: number,
  hint: string,
  constraints = '',
  step = '1',
): string {
  return `<label class="studio-field"><span>${escapeHtml(label)}<small>${escapeHtml(hint)}</small></span><input type="number" inputmode="decimal" step="${step}" ${constraints} value="${escapeHtml(value)}" data-weapon-field="hitbox:${escapeHtml(hitboxId)}:${escapeHtml(field)}" data-weapon-hitbox-control /></label>`;
}

function arcDegrees(radians: number): number {
  return Math.round(radians * 1800 / Math.PI) / 10;
}

export function renderLayeredWeaponHitboxControls(hitboxId: string, hitbox: WeaponHitboxDocument): string {
  const geometryFields = hitbox.shape === 'sector'
    ? `${numberField('Inner radius', hitboxId, 'innerRadius', hitbox.innerRadius ?? 0, 'near edge', 'min="0"')}${numberField('Outer radius', hitboxId, 'outerRadius', hitbox.outerRadius ?? Math.max(1, hitbox.offsetX + hitbox.width / 2), 'reach', 'min="1"')}${numberField('Arc width', hitboxId, 'arcWidthDeg', arcDegrees(hitbox.arcWidthRad ?? 1.35), 'degrees', 'min="0" max="360"')}${numberField('Offset X', hitboxId, 'offsetX', hitbox.offsetX, 'forward')}${numberField('Offset Y', hitboxId, 'offsetY', hitbox.offsetY, 'side axis')}<p class="studio-help layered-hitbox-geometry-note">Outer radius and arc width define the sector size. Offset moves its origin from the player anchor.</p>`
    : hitbox.shape === 'circle'
      ? `${numberField('Radius', hitboxId, 'radius', hitbox.radius ?? hitbox.width / 2, 'world units', 'min="1"')}${numberField('Offset X', hitboxId, 'offsetX', hitbox.offsetX, 'forward')}${numberField('Offset Y', hitboxId, 'offsetY', hitbox.offsetY, 'side axis')}`
      : hitbox.shape === 'ellipse'
        ? `${numberField('Radius X', hitboxId, 'radiusX', hitbox.radiusX ?? hitbox.width / 2, 'world units', 'min="1"')}${numberField('Radius Y', hitboxId, 'radiusY', hitbox.radiusY ?? hitbox.height / 2, 'world units', 'min="1"')}${numberField('Offset X', hitboxId, 'offsetX', hitbox.offsetX, 'forward')}${numberField('Offset Y', hitboxId, 'offsetY', hitbox.offsetY, 'side axis')}`
        : `${numberField('Width', hitboxId, 'width', hitbox.width, 'world units', 'min="1"')}${numberField('Height', hitboxId, 'height', hitbox.height, 'world units', 'min="1"')}${numberField('Offset X', hitboxId, 'offsetX', hitbox.offsetX, 'forward')}${numberField('Offset Y', hitboxId, 'offsetY', hitbox.offsetY, 'side axis')}`;

  return `<div class="layered-hitbox-editor"><div class="studio-field-grid layered-hitbox-geometry-grid"><label class="studio-field"><span>Shape<small>runtime primitive</small></span><select data-weapon-field="hitbox:${escapeHtml(hitboxId)}:shape" data-weapon-hitbox-control>${HITBOX_SHAPES.map((shape) => `<option value="${shape}" ${hitbox.shape === shape ? 'selected' : ''}>${shape}</option>`).join('')}</select></label>${geometryFields}</div><div class="studio-field-grid layered-hitbox-effects-grid">${numberField('Damage ×', hitboxId, 'damageMultiplier', hitbox.damageMultiplier ?? 1, 'multiplier', 'min="0"', '0.05')}${numberField('Knockback ×', hitboxId, 'knockbackMultiplier', hitbox.knockbackMultiplier ?? 1, 'multiplier', 'min="0"', '0.05')}</div><button type="button" class="studio-button studio-button--danger" data-action="delete-hitbox" data-hitbox-id="${escapeHtml(hitboxId)}">DELETE HITBOX</button></div>`;
}

function withShape(hitbox: WeaponHitboxDocument, shape: WeaponHitboxShape): WeaponHitboxDocument {
  if (shape === 'circle') return { ...hitbox, shape, radius: hitbox.radius ?? Math.max(1, Math.min(hitbox.width, hitbox.height) / 2) };
  if (shape === 'ellipse') return {
    ...hitbox,
    shape,
    radiusX: hitbox.radiusX ?? Math.max(1, hitbox.radius ?? hitbox.width / 2),
    radiusY: hitbox.radiusY ?? Math.max(1, hitbox.radius ?? hitbox.height / 2),
  };
  if (shape === 'sector') return {
    ...hitbox,
    shape,
    innerRadius: hitbox.innerRadius ?? 0,
    outerRadius: hitbox.outerRadius ?? Math.max(1, hitbox.offsetX + hitbox.width / 2),
    arcWidthRad: hitbox.arcWidthRad ?? 1.35,
  };
  return { ...hitbox, shape };
}

export function updateWeaponHitboxControl(
  hitbox: WeaponHitboxDocument,
  field: string,
  rawValue: string,
): WeaponHitboxDocument {
  if (field === 'shape') {
    return HITBOX_SHAPES.includes(rawValue as WeaponHitboxShape)
      ? withShape(hitbox, rawValue as WeaponHitboxShape)
      : hitbox;
  }
  const value = Number(rawValue);
  if (!Number.isFinite(value)) return hitbox;
  if (field === 'arcWidthDeg') return { ...hitbox, arcWidthRad: value * Math.PI / 180 };
  if (field === 'width') return { ...hitbox, width: value };
  if (field === 'height') return { ...hitbox, height: value };
  if (field === 'radius') return { ...hitbox, radius: value };
  if (field === 'radiusX') return { ...hitbox, radiusX: value };
  if (field === 'radiusY') return { ...hitbox, radiusY: value };
  if (field === 'offsetX') return { ...hitbox, offsetX: value };
  if (field === 'offsetY') return { ...hitbox, offsetY: value };
  if (field === 'innerRadius') return { ...hitbox, innerRadius: value };
  if (field === 'outerRadius') return { ...hitbox, outerRadius: value };
  if (field === 'arcWidthRad') return { ...hitbox, arcWidthRad: value };
  if (field === 'damageMultiplier') return { ...hitbox, damageMultiplier: value };
  if (field === 'knockbackMultiplier') return { ...hitbox, knockbackMultiplier: value };
  return hitbox;
}
