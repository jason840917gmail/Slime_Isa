type Point = Readonly<{ x: number; y: number }>;

/**
 * What the Stretch Lash's hook caught. It does no damage: something heavy
 * (anything solid: a tree, rock, post, wall or bell) pulls the slime to it,
 * something light (a loose pickup) flies to the slime.
 */
export type LashCatch =
  /** `anchor`: where the pull aims when that differs from the catch point (a bell post's foot). */
  | Readonly<{ kind: 'heavy'; at: Point; anchor?: Point }>
  | Readonly<{ kind: 'light'; at: Point; pickupId: string }>
  | Readonly<{ kind: 'none'; at: Point }>;

/** A strike on everything around a point (the Squash Slam). */
export interface AreaStrikeRequest {
  /** The ability striking; it names the attack source (`ability.<id>`). */
  readonly abilityId: string;
  readonly center: Point;
  readonly radius: number;
  readonly damage: number;
  /** Pushes each target away from the centre. */
  readonly knockback: number;
  readonly weaponTags: readonly string[];
}

export interface AreaStrikeResult {
  /** Receivers that took the hit, where they stand. */
  readonly hits: readonly Point[];
}

/** The scene world as the player's abilities see it. */
export interface AbilityWorldPort {
  /** Throws the lash hook from `from` towards `to` (at most) and reports what it catches. */
  lashProbe(from: Point, to: Point, halfWidth: number): LashCatch;
  /** Where the slime lands when a heavy catch pulls it towards `target` (just short of it, on walkable ground). */
  lashLanding(from: Point, target: Point): Point;
  /** Rings the bells at a heavy catch; returns how many rang. */
  lashRing(from: Point, caught: Point, halfWidth: number): number;
  /** Flies a caught pickup to `to` and picks it up. */
  lashPull(pickupId: string, to: Point): boolean;
  strikeArea(request: AreaStrikeRequest): AreaStrikeResult;
}
