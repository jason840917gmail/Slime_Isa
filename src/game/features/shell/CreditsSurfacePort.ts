import credits from '../../content/credits/credits.json';
import type { UiPresentationModel } from '../scripts/ui/UiSurfaceScript';
import { MenuSurface, type MenuSurfaceOptions } from './MenuSurface';

export interface CreditEntry {
  readonly name: string;
  readonly detail?: string;
  readonly license?: string;
  readonly url?: string;
}

export interface CreditSection {
  readonly heading: string;
  readonly entries: readonly CreditEntry[];
}

export const CREDIT_SECTIONS: readonly CreditSection[] = credits.sections;

export const CREDITS_SURFACE_ID = 'credits';

/** One readable block: a heading per section, one line per entry. */
export function creditsText(sections: readonly CreditSection[] = CREDIT_SECTIONS): string {
  return sections.map((section) => [
    section.heading.toUpperCase(),
    ...section.entries.map((entry) => [entry.name, entry.detail, entry.license].filter(Boolean).join('  ·  ')),
  ].join('\n')).join('\n\n');
}

/** The credits (from the title), read from `content/credits/credits.json`. */
export class CreditsSurfacePort extends MenuSurface {
  constructor(options: MenuSurfaceOptions) {
    super(CREDITS_SURFACE_ID, options);
  }

  protected model(): UiPresentationModel {
    return { text: creditsText() };
  }

  protected act(): void {}
}
