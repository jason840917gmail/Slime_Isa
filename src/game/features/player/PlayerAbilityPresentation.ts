import type { PlayerAbilityId } from './PlayerAbilityDefinitions';
import type { PlayerAbilityIntent, PlayerAbilityRejectionReason } from './PlayerAbilityService';

export interface PlayerAbilityPresentationLease {
  /** Release ownership after natural completion without cancelling residual VFX. */
  complete?(): void;
  /** Cancel the presentation and remove every owned transient immediately. */
  dispose(): void;
}

export interface PlayerAbilityPresentationBackend {
  present(intent: PlayerAbilityIntent, complete: () => void): PlayerAbilityPresentationLease;
  notifyRejected(
    abilityId: PlayerAbilityId,
    reason: PlayerAbilityRejectionReason,
    unlockLevel?: number,
  ): void;
}

interface ActivePresentation {
  readonly sequenceId: number;
  lease?: PlayerAbilityPresentationLease;
  finished: boolean;
}

/**
 * Owns the lifetime of one ability presentation without knowing which engine
 * renders it. PlayerAbilityService owns the decision; a backend owns visuals.
 */
export class PlayerAbilityPresentation {
  private active?: ActivePresentation;
  private disposed = false;

  constructor(private readonly backend: PlayerAbilityPresentationBackend) {}

  get activeSequenceId(): number | undefined {
    return this.active?.sequenceId;
  }

  present(intent: PlayerAbilityIntent, complete: (sequenceId: number) => void): boolean {
    if (this.disposed || this.active) return false;
    const record: ActivePresentation = { sequenceId: intent.sequenceId, finished: false };
    this.active = record;
    try {
      const lease = this.backend.present(intent, () => this.finish(record, complete));
      record.lease = lease;
      // Backends may complete synchronously. In that case finish() ran before
      // the lease was returned, so dispose it here instead of leaking it.
      if (record.finished) this.completeLease(lease);
      return true;
    } catch (error) {
      if (this.active === record) this.active = undefined;
      throw error;
    }
  }

  notifyRejected(
    abilityId: PlayerAbilityId,
    reason: PlayerAbilityRejectionReason,
    unlockLevel?: number,
  ): void {
    if (!this.disposed) this.backend.notifyRejected(abilityId, reason, unlockLevel);
  }

  cancel(): void {
    const active = this.active;
    this.active = undefined;
    if (!active || active.finished) return;
    active.finished = true;
    active.lease?.dispose();
  }

  dispose(): void {
    if (this.disposed) return;
    this.disposed = true;
    this.cancel();
  }

  private finish(record: ActivePresentation, complete: (sequenceId: number) => void): void {
    if (record.finished || this.active !== record) return;
    record.finished = true;
    this.active = undefined;
    if (record.lease) this.completeLease(record.lease);
    complete(record.sequenceId);
  }

  private completeLease(lease: PlayerAbilityPresentationLease): void {
    if (lease.complete) lease.complete();
    else lease.dispose();
  }
}
