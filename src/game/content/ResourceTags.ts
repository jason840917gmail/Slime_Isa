import { GAME_CONSTANTS } from '../Constant';

declare const resourceTagBrand: unique symbol;

export type ResourceTag = string & { readonly [resourceTagBrand]: true };

export const RESOURCE_TAGS = GAME_CONSTANTS.resources.tags as readonly ResourceTag[];

const RESOURCE_TAG_SET: ReadonlySet<string> = new Set(RESOURCE_TAGS);

export function isResourceTag(value: string): value is ResourceTag {
  return RESOURCE_TAG_SET.has(value);
}

export function resourceTagIssue(value: string): string | undefined {
  return isResourceTag(value)
    ? undefined
    : `Unknown resource tag '${value}'. Reload the Studio if the resource catalog changed.`;
}