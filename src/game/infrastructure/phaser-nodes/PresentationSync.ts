export interface PresentationParticipant {
  syncPresentation(alpha: number): void;
}

export class PresentationSync {
  private readonly participants = new Set<PresentationParticipant>();

  get size(): number { return this.participants.size; }

  register(participant: PresentationParticipant): () => void {
    this.participants.add(participant);
    let active = true;
    return () => { if (!active) return; active = false; this.participants.delete(participant); };
  }

  synchronize(alpha: number): void {
    for (const participant of [...this.participants]) {
      if (this.participants.has(participant)) participant.syncPresentation(alpha);
    }
  }

  clear(): void { this.participants.clear(); }
}
