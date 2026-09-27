/**
 * The part of Arcade's `Body.preUpdate` a manually stepped world must still
 * run before every `World.step`.
 *
 * Phaser 3.90 `World.step` only calls `Body.update`; `World.update` is the
 * path that runs `Body.preUpdate`, and it is disabled while scenes step
 * physics manually. Without this, `touching`/`blocked`/`embedded` never
 * reset (contact normals go stale and separation reads old `blocked` flags)
 * and `prev`/`prevFrame` never refresh.
 *
 * `updateFromGameObject` is deliberately NOT called: managed bodies keep
 * their backend object at the node anchor, not at the body centre, and the
 * node synchronization owns the body position.
 */
export interface ArcadeStepVector { x: number; y: number }

export interface ArcadeStepBody {
  readonly enable: boolean;
  readonly moves?: boolean;
  readonly position?: ArcadeStepVector;
  readonly prev?: ArcadeStepVector;
  readonly prevFrame?: ArcadeStepVector;
  resetFlags?(clear?: boolean): void;
}

export function prepareArcadeBodyForStep(body: ArcadeStepBody): void {
  if (!body.enable) return;
  body.resetFlags?.();
  if (body.moves === false || !body.position) return;
  const { x, y } = body.position;
  if (body.prev) { body.prev.x = x; body.prev.y = y; }
  if (body.prevFrame) { body.prevFrame.x = x; body.prevFrame.y = y; }
}

export function prepareArcadeBodiesForStep(bodies: Iterable<ArcadeStepBody>): void {
  for (const body of bodies) prepareArcadeBodyForStep(body);
}
