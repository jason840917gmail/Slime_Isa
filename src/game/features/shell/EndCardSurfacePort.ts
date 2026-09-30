import type { EndCardDefinition } from '../../content/story/endCards';
import type { UiPresentationModel } from '../scripts/ui/UiSurfaceScript';
import { MenuSurface, type MenuSurfaceOptions } from './MenuSurface';

export interface EndCardSurfaceOptions extends MenuSurfaceOptions {
  readonly cards: readonly EndCardDefinition[];
  readonly hasFlag: (flagId: string) => boolean;
  /** Saves and goes back to the title screen. */
  readonly returnToTitle: () => void;
}

export const END_CARD_SURFACE_ID = 'end-card';

/**
 * Shows an end card when its story flag becomes set during play. Flags that
 * were already set when the world loaded never show a card again.
 */
export class EndCardSurfacePort extends MenuSurface {
  private readonly shownFlags = new Set<string>();
  private card?: EndCardDefinition;

  constructor(private readonly options: EndCardSurfaceOptions) {
    super(END_CARD_SURFACE_ID, { ...options, closableByEscape: false });
    for (const card of options.cards) if (options.hasFlag(card.flagId)) this.shownFlags.add(card.flagId);
  }

  /** Call when story flags change; opens the card for a newly set flag. */
  checkFlags(): void {
    const card = this.options.cards.find((candidate) => !this.shownFlags.has(candidate.flagId) && this.options.hasFlag(candidate.flagId));
    if (!card) return;
    this.shownFlags.add(card.flagId);
    this.card = card;
    this.open();
  }

  protected model(): UiPresentationModel {
    return { title: this.card?.title ?? '', subtitle: this.card?.subtitle ?? '', body: this.card?.body ?? '' };
  }

  protected act(actionId: string): void {
    if (actionId !== 'return-to-title') return;
    this.close();
    this.options.returnToTitle();
  }
}
