import type Phaser from 'phaser';

export interface InteractionCandidate {
  readonly id: string;
  readonly prompt: string;
  readonly priority: number;
  execute(): boolean;
}

export interface InteractionProvider {
  getCandidate(): InteractionCandidate | undefined;
}

/** Chooses exactly one intentional F interaction and owns the shared prompt. */
export class InteractionRouter {
  private readonly providers = new Map<string, InteractionProvider>();
  private readonly prompt: Phaser.GameObjects.Text;
  private candidate?: InteractionCandidate;

  constructor(private readonly scene: Phaser.Scene) {
    this.prompt = scene.add.text(scene.cameras.main.width / 2, scene.cameras.main.height - 42, '', {
      fontFamily: 'Trebuchet MS, Segoe UI Variable, sans-serif',
      fontSize: '14px',
      color: '#e7fff5',
      backgroundColor: '#101a31cc',
      padding: { left: 12, right: 12, top: 7, bottom: 7 },
    }).setOrigin(0.5).setScrollFactor(0).setDepth(250).setVisible(false);
    scene.scale.on('resize', this.handleResize, this);
    scene.events.once('shutdown', () => this.destroy());
  }

  register(id: string, provider: InteractionProvider): () => void {
    this.providers.set(id, provider);
    return () => {
      if (this.providers.get(id) === provider) this.providers.delete(id);
      if (this.candidate?.id.startsWith(`${id}:`)) this.clearCandidate();
    };
  }

  update(): void {
    let best: InteractionCandidate | undefined;
    for (const provider of this.providers.values()) {
      const candidate = provider.getCandidate();
      if (!candidate || (best && (candidate.priority < best.priority
        || (candidate.priority === best.priority && candidate.id > best.id)))) continue;
      best = candidate;
    }
    this.candidate = best;
    this.prompt.setText(best?.prompt ?? '').setVisible(!!best);
  }

  handleInteract(): boolean {
    const candidate = this.candidate;
    return candidate ? candidate.execute() : false;
  }

  hasCandidate(): boolean {
    return this.candidate !== undefined;
  }

  destroy(): void {
    this.scene.scale.off('resize', this.handleResize, this);
    this.providers.clear();
    this.candidate = undefined;
    this.prompt.destroy();
  }

  private clearCandidate(): void {
    this.candidate = undefined;
    this.prompt.setText('').setVisible(false);
  }

  private readonly handleResize = (gameSize: Phaser.Structs.Size): void => {
    this.prompt.setPosition(gameSize.width / 2, gameSize.height - 42);
  };
}
