import type {
  LayeredAnimationDocument,
  NormalizedLayeredAnimationDocument,
} from '../../shared/animation';

export const ANIMATION_PACKAGE_VERSION = 1 as const;

export interface AnimationPackageDocument {
  readonly $schema: string;
  readonly version: typeof ANIMATION_PACKAGE_VERSION;
  readonly animationId: string;
  readonly displayName: string;
  readonly description: string;
  readonly animation: LayeredAnimationDocument;
}

export interface NormalizedAnimationPackage {
  readonly $schema: string;
  readonly version: typeof ANIMATION_PACKAGE_VERSION;
  readonly animationId: string;
  readonly displayName: string;
  readonly description: string;
  readonly animation: NormalizedLayeredAnimationDocument;
}

export type AnimationPackageDiagnosticCode =
  | 'animation-package-invalid'
  | 'animation-id-duplicate'
  | 'animation-asset-invalid'
  | 'animation-reference-missing'
  | 'animation-slot-loop-mismatch'
  | 'animation-reference-in-use';

export interface AnimationPackageDiagnostic {
  readonly code: AnimationPackageDiagnosticCode;
  readonly packagePath?: string;
  readonly animationId?: string;
  readonly field?: string;
  readonly message: string;
}

export interface AnimationPackageCatalogEntry extends AnimationPackageDocument {
  readonly packagePath: string;
  readonly folderPath: string;
  readonly revision: string;
}

export interface AnimationPackageCatalog {
  readonly version: 1;
  readonly revision: string;
  readonly folders: readonly string[];
  readonly packages: readonly AnimationPackageCatalogEntry[];
}

export interface AnimationPackageReference {
  readonly sourcePath: string;
  readonly field: string;
  readonly animationId: string;
  readonly ownerId: string;
  readonly ownerKind: 'weapon' | 'object';
  readonly expectedLoop: boolean;
}
