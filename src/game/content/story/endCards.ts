/**
 * End cards: a full-screen card shown the moment its story flag is first set
 * during play (not when a save that already has the flag is loaded). The card
 * returns the player to the title after saving the run.
 */
export interface EndCardDefinition {
  readonly flagId: string;
  readonly title: string;
  readonly subtitle: string;
  readonly body: string;
}

export const END_CARDS: readonly EndCardDefinition[] = Object.freeze([
  {
    // Set by the pressure plate inside the playground's Heavy puzzle pen.
    flagId: 'playground-end-card-test',
    title: 'The End (test)',
    subtitle: 'Playground',
    body: 'This card is what finishing a chapter will look like. Your run is saved when you return to the title.',
  },
]);
