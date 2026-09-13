export class NodePath {
  readonly absolute: boolean;
  readonly segments: readonly string[];

  constructor(readonly value: string) {
    if (value.length === 0) throw new Error('Node path cannot be empty');
    this.absolute = value.startsWith('/');
    this.segments = value === '/' ? [] : value.split('/').filter((segment, index) => !(index === 0 && segment === ''));
    if (this.segments.some((segment) => segment.length === 0)) throw new Error(`Node path '${value}' contains an empty segment`);
  }

  toString(): string { return this.value; }
}

export const nodePath = (value: string | NodePath): NodePath => value instanceof NodePath ? value : new NodePath(value);
