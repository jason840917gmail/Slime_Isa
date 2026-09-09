import type { VisualSetDocument } from '../content/characters/types';

export interface CharacterSourceSheetIssue {
  readonly path: string;
  readonly frame: number;
  readonly message: string;
}

/**
 * Collects source-frame references that would be invalid for a replacement
 * spritesheet. The check intentionally reports every clip occurrence and
 * every frameVisuals override, including overrides that are not currently
 * used by a clip; the server performs the same validation before writing.
 */
export function collectCharacterSourceSheetIssues(
  visualSet: VisualSetDocument,
  populatedFrameCount: number,
): readonly CharacterSourceSheetIssue[] {
  const issues: CharacterSourceSheetIssue[] = [];
  const count = Number.isFinite(populatedFrameCount) ? Math.max(0, Math.floor(populatedFrameCount)) : 0;
  for (const [clipId, clip] of Object.entries(visualSet.clips)) {
    clip.frames.forEach((frame, index) => {
      if (!Number.isInteger(frame) || frame < 0 || frame >= count) {
        issues.push({ path: `visualSet.clips.${clipId}.frames[${index}]`, frame, message: `Source frame ${frame} is outside the selected sheet (${count} populated frame${count === 1 ? '' : 's'}).` });
      }
    });
  }
  for (const key of Object.keys(visualSet.frameVisuals ?? {})) {
    const frame = Number(key);
    if (!/^\d+$/.test(key) || !Number.isInteger(frame) || frame < 0 || frame >= count) {
      issues.push({ path: `visualSet.frameVisuals.${key}`, frame, message: `Frame override ${key} is outside the selected sheet (${count} populated frame${count === 1 ? '' : 's'}).` });
    }
  }
  return issues;
}
