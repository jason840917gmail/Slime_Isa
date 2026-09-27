import { createHash } from 'node:crypto';

/**
 * Hash text content independent of the checkout's line endings or a UTF-8 BOM.
 * Git on Windows may materialize files with CRLF while tools write LF; a raw
 * byte hash would make every ledger check machine-dependent.
 */
export function normalizeContent(value) {
  const text = typeof value === 'string' ? value : Buffer.from(value).toString('utf8');
  return text.replace(/^﻿/, '').replace(/\r\n?/g, '\n');
}

export function contentSha256(value) {
  return createHash('sha256').update(normalizeContent(value)).digest('hex');
}
