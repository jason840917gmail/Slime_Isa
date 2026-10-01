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
    // Set by The Matron's Nest, the last Chapter 2 quest (roadmap 8.11).
    flagId: 'chapter-2-complete',
    title: 'End of Chapter 2',
    subtitle: 'Gloop Forest',
    body: "The Matron's web is broken, the Forge burns again, and Slimeshire has iron. The Crystal Caverns wait beyond the forest: Chapter 3 is still to come. Your run is saved when you return to the title.",
  },
  {
    // Set by the pressure plate inside the playground's Heavy puzzle pen.
    flagId: 'playground-end-card-test',
    title: 'The End (test)',
    subtitle: 'Playground',
    body: 'This card is what finishing a chapter will look like. Your run is saved when you return to the title.',
  },
]);
