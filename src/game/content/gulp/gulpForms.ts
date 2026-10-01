/**
 * Gulp forms: eating a Gulp material turns the slime into that material's
 * form for a while (`gulp.formDurationMs`). Each form has one look and one
 * rule; adding a form is a new entry here plus its art: a badge frame in
 * `ui.icons.gulp-forms` and a skin, the whole player sheet re-textured
 * (scripts/characters/build-gulp-form-skins.py).
 */

/** Texture of the form badges (`ui.icons.gulp-forms.2x1`), one frame per form. */
export const GULP_FORM_ICON_TEXTURE = 'ui-gulp-form-icons';
export type GulpFormId = 'heavy' | 'sticky';

export interface GulpFormDefinition {
  readonly id: GulpFormId;
  /** Shown in the HUD timer and messages. */
  readonly name: string;
  /** Item eaten from the inventory (and offered by matching Gulp spots) to take this form. */
  readonly materialItemId: string;
  /** Texture the player is drawn from while the form lasts (the player sheet's frames, re-textured). */
  readonly skinTextureKey: string;
  /** Multiply tint used only when the skin texture is missing. */
  readonly tint: number;
  /** Movement speed multiplier while in the form. */
  readonly speedMultiplier: number;
  /** Hits never push the slime back. */
  readonly knockbackImmune: boolean;
  /** Heavy enough to hold pressure plates down (and to break cracked ground). */
  readonly pressesPlates: boolean;
  /** Crosses spider webs that catch a normal slime. */
  readonly crossesWebs: boolean;
  /** Frame of this form's badge in GULP_FORM_ICON_TEXTURE (the timer and the quick wheel). */
  readonly iconFrame: number;
}

export const GULP_FORMS: readonly GulpFormDefinition[] = Object.freeze([
  {
    id: 'heavy',
    name: 'Heavy',
    materialItemId: 'stone',
    skinTextureKey: 'slime-form-heavy',
    tint: 0x9aa3ad,
    speedMultiplier: 0.6,
    knockbackImmune: true,
    pressesPlates: true,
    crossesWebs: false,
    iconFrame: 0,
  },
  {
    id: 'sticky',
    name: 'Sticky',
    materialItemId: 'silk-clump',
    skinTextureKey: 'slime-form-sticky',
    tint: 0xf1ecff,
    speedMultiplier: 0.9,
    knockbackImmune: false,
    pressesPlates: false,
    crossesWebs: true,
    iconFrame: 1,
  },
]);

export function gulpFormForMaterial(itemId: string): GulpFormDefinition | undefined {
  return GULP_FORMS.find((form) => form.materialItemId === itemId);
}
