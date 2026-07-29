import { createHash, randomUUID } from 'node:crypto';
import type { IncomingMessage, ServerResponse } from 'node:http';
import { promises as fs } from 'node:fs';
import path from 'node:path';

import type { Plugin, ViteDevServer } from 'vite';

import {
  buildCharacterStudioAssetCatalog,
  type CharacterStudioAssetCatalog,
  type CharacterStudioAssetManifestInput,
  type CharacterStudioAssetReference,
} from './characterAssetCatalog';
import { normalizeCharacterPackage, validateCharacterPackage, type CharacterValidationIssue } from './validation';
import type { CharacterDocument, CharacterPackage, VisualSetDocument } from './types';
import type { ProjectileDefinition } from '../projectiles/types';
import { validateProjectileDefinition } from '../projectiles/validation';
import type { WeaponDefinition } from '../weapons/types';
import { validateWeaponDefinition } from '../weapons/validation';

const VIRTUAL_ID = 'virtual-character-content';
const RESOLVED_VIRTUAL_ID = `\0${VIRTUAL_ID}`;
const PROJECTILE_VIRTUAL_ID = 'virtual-projectile-content';
const RESOLVED_PROJECTILE_VIRTUAL_ID = `\0${PROJECTILE_VIRTUAL_ID}`;
const WEAPON_VIRTUAL_ID = 'virtual-weapon-content';
const RESOLVED_WEAPON_VIRTUAL_ID = `\0${WEAPON_VIRTUAL_ID}`;
const ID_PATTERN = /^[a-z0-9]+(?:-[a-z0-9]+)*$/;
const ASSET_ID_PATTERN = /^[a-z0-9]+(?:\.[a-z0-9-]+)+$/;
const MAX_BODY_BYTES = 2 * 1024 * 1024;
const MAX_UPLOAD_BYTES = 32 * 1024 * 1024;
const AUTHORING_ASSET_DIRECTORY = 'characters/authored';

export interface CharacterContentRootOptions {
  readonly characterRoot?: string;
  readonly visualRoot?: string;
  readonly projectileRoot?: string;
  readonly weaponRoot?: string;
  readonly assetRoot?: string;
  readonly assetManifestPath?: string;
}

export interface CharacterContentModule {
  readonly characterId: string;
  readonly character: CharacterDocument;
  readonly visualSet: VisualSetDocument;
}

interface DiscoveredFile {
  readonly id: string;
  readonly characterPath?: string;
  readonly visualPath?: string;
}

interface ErrorResponse {
  readonly ok: false;
  readonly error: {
    readonly code: string;
    readonly message: string;
    readonly issues?: readonly CharacterValidationIssue[];
    readonly currentRevision?: string;
  };
}

interface AssetCatalogResponse {
  readonly ok: true;
  readonly data: CharacterStudioAssetCatalog;
}

interface MutableManifest {
  [key: string]: unknown;
  assets: Record<string, unknown>;
  bundles: Record<string, unknown>;
}

interface MultipartPayload {
  readonly fields: Readonly<Record<string, string>>;
  readonly file: Buffer;
  readonly filename?: string;
  readonly contentType?: string;
}

interface AssetRegistrationResponse {
  readonly assetId: string;
  readonly sourcePath: string;
  readonly frame: {
    readonly w: number;
    readonly h: number;
    readonly cols: number;
    readonly rows: number;
    readonly count: number;
  };
  readonly revision: string;
  readonly reloadRequired: true;
}

interface PackageCreationRequest {
  readonly characterId: string;
  readonly displayName: string;
  readonly kind: 'player' | 'enemy';
  readonly template: 'player' | 'melee-enemy' | 'ranged-enemy';
  readonly assetId: string;
}

interface PackageCreationResponse {
  readonly characterId: string;
  readonly revision: string;
  readonly reloadRequired: true;
}

interface PreparedAssetRegistration {
  readonly assetId: string;
  readonly sourcePath: string;
  readonly png: Buffer;
  readonly manifest: MutableManifest;
  readonly frame: AssetRegistrationResponse['frame'];
}

interface CharacterCreationTransaction {
  readonly transactionId: string;
  readonly operation: 'create-character';
  readonly assetId: string;
  readonly sourcePath: string;
  readonly characterId: string;
}

async function findFiles(root: string, fileName: 'character.json' | 'visual-set.json'): Promise<string[]> {
  const files: string[] = [];
  for (const entry of await fs.readdir(root, { withFileTypes: true }).catch((error: unknown) => {
    if (error instanceof Error && 'code' in error && (error as NodeJS.ErrnoException).code === 'ENOENT') return [];
    throw error;
  })) {
    if (entry.name.startsWith('.') || entry.name.startsWith('.character-studio-')) continue;
    const absolutePath = path.join(root, entry.name);
    if (entry.isFile() && entry.name === fileName) files.push(absolutePath);
    else if (entry.isDirectory()) files.push(...await findFiles(absolutePath, fileName));
  }
  return files.sort();
}

async function findProjectileFiles(root: string): Promise<string[]> {
  const files: string[] = [];
  for (const entry of await fs.readdir(root, { withFileTypes: true }).catch((error: unknown) => {
    if (error instanceof Error && 'code' in error && (error as NodeJS.ErrnoException).code === 'ENOENT') return [];
    throw error;
  })) {
    if (entry.name.startsWith('.') || entry.name.startsWith('.character-studio-')) continue;
    const absolutePath = path.join(root, entry.name);
    if (entry.isFile() && entry.name === 'projectile.json') files.push(absolutePath);
    else if (entry.isDirectory()) files.push(...await findProjectileFiles(absolutePath));
  }
  return files.sort();
}

async function findWeaponFiles(root: string): Promise<string[]> {
  const files: string[] = [];
  for (const entry of await fs.readdir(root, { withFileTypes: true }).catch((error: unknown) => {
    if (error instanceof Error && 'code' in error && (error as NodeJS.ErrnoException).code === 'ENOENT') return [];
    throw error;
  })) {
    if (entry.name.startsWith('.') || entry.name.startsWith('.character-studio-')) continue;
    const absolutePath = path.join(root, entry.name);
    if (entry.isFile() && entry.name === 'weapon.json') files.push(absolutePath);
    else if (entry.isDirectory()) files.push(...await findWeaponFiles(absolutePath));
  }
  return files.sort();
}

async function discover(rootOptions: Pick<Required<CharacterContentRootOptions>, 'characterRoot' | 'visualRoot'>): Promise<DiscoveredFile[]> {
  const characters = new Map<string, DiscoveredFile>();
  for (const characterPath of await findFiles(rootOptions.characterRoot, 'character.json')) {
    const id = path.basename(path.dirname(characterPath));
    if (!ID_PATTERN.test(id)) continue;
    characters.set(id, { id, characterPath });
  }
  const visuals = new Map<string, DiscoveredFile>();
  for (const visualPath of await findFiles(rootOptions.characterRoot, 'visual-set.json')) {
    const id = path.basename(path.dirname(visualPath));
    if (ID_PATTERN.test(id)) visuals.set(id, { id, visualPath });
  }
  for (const visualPath of await findFiles(rootOptions.visualRoot, 'visual-set.json')) {
    const id = `visual:${visualPath}`;
    visuals.set(id, { id, visualPath });
  }
  return [...characters.values()].map((entry) => ({
    ...entry,
    visualPath: visuals.get(entry.id)?.visualPath,
  }));
}

function repositoryPath(root: string, characterId: string): string {
  if (!ID_PATTERN.test(characterId)) throw new Error('Invalid character ID');
  const resolvedRoot = path.resolve(root);
  const target = path.resolve(resolvedRoot, characterId);
  if (path.dirname(target) !== resolvedRoot) throw new Error('Invalid character package path');
  return target;
}

async function readJson(filePath: string): Promise<unknown> {
  return JSON.parse(await fs.readFile(filePath, 'utf8')) as unknown;
}

function pathIsInside(root: string, target: string): boolean {
  const relativeTarget = path.relative(path.resolve(root), path.resolve(target));
  return relativeTarget === '' || (relativeTarget !== '..' && !relativeTarget.startsWith(`..${path.sep}`) && !path.isAbsolute(relativeTarget));
}

function validateAssetSourcePaths(assetRoot: string, manifest: CharacterStudioAssetManifestInput): void {
  for (const value of Object.values(manifest.assets ?? {})) {
    if (!value || typeof value !== 'object' || Array.isArray(value)) continue;
    const source = (value as Record<string, unknown>).source;
    if (!source || typeof source !== 'object' || Array.isArray(source)) continue;
    const sourceRecord = source as Record<string, unknown>;
    if (sourceRecord.kind !== 'image' && sourceRecord.kind !== 'spritesheet') continue;
    if (typeof sourceRecord.path !== 'string' || sourceRecord.path.includes('\\') || sourceRecord.path.startsWith('/') || sourceRecord.path.split('/').includes('..')) {
      throw new Error('Asset manifest contains an unsafe image path');
    }
    if (!pathIsInside(assetRoot, path.join(assetRoot, sourceRecord.path))) {
      throw new Error('Asset manifest contains an asset path outside the asset root');
    }
  }
}

async function discoverAssetReferences(characterRoot: string): Promise<CharacterStudioAssetReference[]> {
  const references: CharacterStudioAssetReference[] = [];
  for (const file of await discover({ characterRoot, visualRoot: characterRoot })) {
    if (!file.characterPath || !file.visualPath) continue;
    try {
      const visualSet = await readJson(file.visualPath);
      if (visualSet && typeof visualSet === 'object' && !Array.isArray(visualSet)) {
        const assetId = (visualSet as Record<string, unknown>).assetId;
        if (typeof assetId === 'string') references.push({ characterId: file.id, assetId });
      }
    } catch {
      // Invalid package JSON is reported by the character validator, not hidden
      // from the source catalog through a fatal request error.
    }
  }
  return references;
}

function canonicalValue(value: unknown): string {
  if (Array.isArray(value)) return `[${value.map(canonicalValue).join(',')}]`;
  if (value !== null && typeof value === 'object') {
    const record = value as Record<string, unknown>;
    return `{${Object.keys(record).sort().map((key) => `${JSON.stringify(key)}:${canonicalValue(record[key])}`).join(',')}}`;
  }
  return JSON.stringify(value);
}

export function characterPackageRevision(packageValue: CharacterPackage): string {
  const characterBytes = Buffer.from(canonicalValue(packageValue.character), 'utf8');
  const visualBytes = Buffer.from(canonicalValue(packageValue.visualSet), 'utf8');
  const length = Buffer.allocUnsafe(8);
  const hash = createHash('sha256');
  length.writeBigUInt64BE(BigInt(characterBytes.length), 0);
  hash.update(length).update(characterBytes);
  length.writeBigUInt64BE(BigInt(visualBytes.length), 0);
  hash.update(length).update(visualBytes);
  return hash.digest('hex');
}

async function assetCatalogHandler(
  assetRoot: string,
  manifestPath: string,
  characterRoot: string,
  response: ServerResponse,
): Promise<void> {
  await recoverCreateTransactions(assetRoot, characterRoot, manifestPath);
  await recoverAssetTransactions(assetRoot, manifestPath);
  const manifestBytes = await fs.readFile(manifestPath, 'utf8');
  const manifest = JSON.parse(manifestBytes) as CharacterStudioAssetManifestInput;
  validateAssetSourcePaths(assetRoot, manifest);
  const references = await discoverAssetReferences(characterRoot);
  const revision = createHash('sha256')
    .update(manifestBytes)
    .update(canonicalValue(references))
    .digest('hex');
  const data = buildCharacterStudioAssetCatalog(manifest, references, revision);
  jsonResponse(response, 200, { ok: true, data } satisfies AssetCatalogResponse);
}

function projectileRepositoryPath(root: string, projectileId: string): string {
  if (!ID_PATTERN.test(projectileId)) throw new Error('Invalid projectile ID');
  const resolvedRoot = path.resolve(root);
  const target = path.resolve(resolvedRoot, projectileId);
  if (path.dirname(target) !== resolvedRoot) throw new Error('Invalid projectile package path');
  return target;
}

async function readProjectile(root: string, projectileId: string): Promise<ProjectileDefinition> {
  return await readJson(path.join(projectileRepositoryPath(root, projectileId), 'projectile.json')) as ProjectileDefinition;
}

function projectileRevision(projectile: ProjectileDefinition): string {
  return createHash('sha256').update(canonicalValue(projectile)).digest('hex');
}

async function projectileCatalogHandler(
  root: string,
  assetRoot: string,
  manifestPath: string,
  response: ServerResponse,
): Promise<void> {
  const manifest = JSON.parse(await fs.readFile(manifestPath, 'utf8')) as CharacterStudioAssetManifestInput;
  validateAssetSourcePaths(assetRoot, manifest);
  const projectiles: Array<ProjectileDefinition & { readonly revision: string }> = [];
  for (const file of await findProjectileFiles(root)) {
    const projectile = await readJson(file) as ProjectileDefinition;
    const issues = validateProjectileDefinition(projectile, manifest);
    if (issues.length > 0) throw new Error(`${path.basename(path.dirname(file))}: ${issues.join('; ')}`);
    projectiles.push({ ...projectile, revision: projectileRevision(projectile) });
  }
  projectiles.sort((left, right) => left.projectileId.localeCompare(right.projectileId));
  const revision = createHash('sha256').update(canonicalValue(projectiles)).digest('hex');
  jsonResponse(response, 200, ok({ version: 1, revision, projectiles }));
}

async function projectilePackageHandler(
  root: string,
  manifestPath: string,
  request: IncomingMessage,
  response: ServerResponse,
  server: ViteDevServer,
  operation: 'get' | 'create' | 'update',
  requestedId?: string,
): Promise<void> {
  if (operation === 'get') {
    if (!requestedId) { jsonResponse(response, 400, failure('invalid-request', 'Projectile ID is required')); return; }
    try {
      const projectile = await readProjectile(root, requestedId);
      jsonResponse(response, 200, ok({ projectile, revision: projectileRevision(projectile) }));
    } catch {
      jsonResponse(response, 404, failure('not-found', `Projectile '${requestedId}' was not found`));
    }
    return;
  }

  const payload = await requestBody(request);
  const projectile = payload.projectile as ProjectileDefinition | undefined;
  if (!projectile) { jsonResponse(response, 400, failure('invalid-request', 'A projectile definition is required')); return; }
  const issues = validateProjectileDefinition(projectile, JSON.parse(await fs.readFile(manifestPath, 'utf8')) as CharacterStudioAssetManifestInput);
  if (issues.length > 0) { jsonResponse(response, 400, failure('validation', 'Projectile definition is invalid', issues.map((message) => ({ path: message.split(':')[0], message })))); return; }
  const projectileId = projectile.projectileId;
  const target = projectileRepositoryPath(root, projectileId);
  if (operation === 'update') {
    let current: ProjectileDefinition;
    try { current = await readProjectile(root, projectileId); } catch { jsonResponse(response, 404, failure('not-found', `Projectile '${projectileId}' was not found`)); return; }
    if (payload.expectedRevision !== projectileRevision(current)) { jsonResponse(response, 409, failure('conflict', 'The projectile changed on disk.', undefined, projectileRevision(current))); return; }
  } else {
    try { await fs.access(target); jsonResponse(response, 409, failure('conflict', `Projectile '${projectileId}' already exists`)); return; } catch { /* expected */ }
  }
  await fs.mkdir(target, { recursive: true });
  const temporary = path.join(target, `projectile.${process.pid}.${Date.now()}.tmp`);
  await fs.writeFile(temporary, `${JSON.stringify(projectile, null, 2)}\n`, 'utf8');
  await fs.rename(temporary, path.join(target, 'projectile.json'));
  invalidateCatalog(server);
  jsonResponse(response, operation === 'create' ? 201 : 200, ok({ projectile, revision: projectileRevision(projectile), reloadRequired: true }));
}

function weaponRepositoryPath(root: string, weaponId: string): string {
  if (!ID_PATTERN.test(weaponId)) throw new Error('Invalid weapon ID');
  const resolvedRoot = path.resolve(root);
  const target = path.resolve(resolvedRoot, weaponId);
  if (path.dirname(target) !== resolvedRoot) throw new Error('Invalid weapon package path');
  return target;
}

async function readWeapon(root: string, weaponId: string): Promise<WeaponDefinition> {
  return await readJson(path.join(weaponRepositoryPath(root, weaponId), 'weapon.json')) as WeaponDefinition;
}

function weaponRevision(weapon: WeaponDefinition): string {
  return createHash('sha256').update(canonicalValue(weapon)).digest('hex');
}

async function weaponCatalogHandler(root: string, response: ServerResponse): Promise<void> {
  const weapons: Array<WeaponDefinition & { readonly revision: string }> = [];
  for (const file of await findWeaponFiles(root)) {
    const weapon = await readJson(file) as WeaponDefinition;
    const issues = validateWeaponDefinition(weapon);
    if (issues.length > 0) throw new Error(`${path.basename(path.dirname(file))}: ${issues.join('; ')}`);
    weapons.push({ ...weapon, revision: weaponRevision(weapon) });
  }
  weapons.sort((left, right) => left.weaponId.localeCompare(right.weaponId));
  const revision = createHash('sha256').update(canonicalValue(weapons)).digest('hex');
  jsonResponse(response, 200, ok({ version: 1, revision, weapons }));
}

async function weaponPackageHandler(
  root: string,
  request: IncomingMessage,
  response: ServerResponse,
  server: ViteDevServer,
  operation: 'get' | 'create' | 'update',
  requestedId?: string,
): Promise<void> {
  if (operation === 'get') {
    if (!requestedId) { jsonResponse(response, 400, failure('invalid-request', 'Weapon ID is required')); return; }
    try {
      const weapon = await readWeapon(root, requestedId);
      jsonResponse(response, 200, ok({ weapon, revision: weaponRevision(weapon) }));
    } catch {
      jsonResponse(response, 404, failure('not-found', `Weapon '${requestedId}' was not found`));
    }
    return;
  }
  const payload = await requestBody(request);
  const weapon = payload.weapon as WeaponDefinition | undefined;
  if (!weapon) { jsonResponse(response, 400, failure('invalid-request', 'A weapon definition is required')); return; }
  const issues = validateWeaponDefinition(weapon);
  if (issues.length > 0) { jsonResponse(response, 400, failure('validation', 'Weapon definition is invalid', issues.map((message) => ({ path: message.split(':')[0], message })))); return; }
  const weaponId = weapon.weaponId;
  const target = weaponRepositoryPath(root, weaponId);
  if (operation === 'update') {
    let current: WeaponDefinition;
    try { current = await readWeapon(root, weaponId); } catch { jsonResponse(response, 404, failure('not-found', `Weapon '${weaponId}' was not found`)); return; }
    if (payload.expectedRevision !== weaponRevision(current)) { jsonResponse(response, 409, failure('conflict', 'The weapon changed on disk.', undefined, weaponRevision(current))); return; }
  } else {
    try { await fs.access(target); jsonResponse(response, 409, failure('conflict', `Weapon '${weaponId}' already exists`)); return; } catch { /* expected */ }
  }
  await fs.mkdir(target, { recursive: true });
  const temporary = path.join(target, `weapon.${process.pid}.${Date.now()}.tmp`);
  await fs.writeFile(temporary, `${JSON.stringify(weapon, null, 2)}\n`, 'utf8');
  await fs.rename(temporary, path.join(target, 'weapon.json'));
  invalidateCatalog(server);
  jsonResponse(response, operation === 'create' ? 201 : 200, ok({ weapon, revision: weaponRevision(weapon), reloadRequired: true }));
}

function jsonResponse(response: ServerResponse, statusCode: number, value: unknown): void {
  response.statusCode = statusCode;
  response.setHeader('Content-Type', 'application/json; charset=utf-8');
  response.end(JSON.stringify(value));
}

async function requestBody(request: IncomingMessage): Promise<Record<string, unknown>> {
  const chunks: Buffer[] = [];
  let size = 0;
  for await (const chunk of request) {
    const buffer = typeof chunk === 'string' ? Buffer.from(chunk) : Buffer.from(chunk);
    size += buffer.length;
    if (size > MAX_BODY_BYTES) throw new Error('Character payload exceeds the 2 MB editor limit');
    chunks.push(buffer);
  }
  const parsed: unknown = JSON.parse(Buffer.concat(chunks).toString('utf8'));
  if (parsed === null || typeof parsed !== 'object' || Array.isArray(parsed)) throw new Error('Request body must be an object');
  return parsed as Record<string, unknown>;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === 'object' && !Array.isArray(value);
}

function headerParameter(header: string, name: string): string | undefined {
  const escapedName = name.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const match = header.match(new RegExp(`${escapedName}=(?:"([^"]+)"|([^;\\r\\n]+))`, 'i'));
  return (match?.[1] ?? match?.[2])?.trim();
}

async function requestMultipart(request: IncomingMessage): Promise<MultipartPayload> {
  const contentType = request.headers['content-type'];
  if (typeof contentType !== 'string' || !contentType.startsWith('multipart/form-data')) throw new Error('Multipart form data is required');
  const boundary = headerParameter(contentType, 'boundary');
  if (!boundary || !/^[A-Za-z0-9'()+_,\-./:=? ]+$/.test(boundary)) throw new Error('Multipart boundary is invalid');

  const chunks: Buffer[] = [];
  let size = 0;
  for await (const chunk of request) {
    const buffer = typeof chunk === 'string' ? Buffer.from(chunk) : Buffer.from(chunk);
    size += buffer.length;
    if (size > MAX_UPLOAD_BYTES) throw new Error('Spritesheet upload exceeds the 32 MB editor limit');
    chunks.push(buffer);
  }
  const body = Buffer.concat(chunks);
  const boundaryMarker = Buffer.from(`--${boundary}`);
  const headerSeparator = Buffer.from('\r\n\r\n');
  const fields: Record<string, string> = {};
  let file: Buffer | undefined;
  let filename: string | undefined;
  let fileContentType: string | undefined;
  let boundaryStart = body.indexOf(boundaryMarker);

  while (boundaryStart >= 0) {
    let partStart = boundaryStart + boundaryMarker.length;
    if (body[partStart] === 45 && body[partStart + 1] === 45) break;
    if (body[partStart] === 13 && body[partStart + 1] === 10) partStart += 2;
    const headersEnd = body.indexOf(headerSeparator, partStart);
    if (headersEnd < 0) throw new Error('Multipart part headers are incomplete');
    const headersText = body.subarray(partStart, headersEnd).toString('utf8');
    const nextBoundary = body.indexOf(Buffer.from(`\r\n${boundaryMarker}`), headersEnd + headerSeparator.length);
    if (nextBoundary < 0) throw new Error('Multipart part is incomplete');
    const partData = body.subarray(headersEnd + headerSeparator.length, nextBoundary);
    const disposition = headersText.split('\r\n').find((line) => line.toLowerCase().startsWith('content-disposition:')) ?? '';
    const fieldName = headerParameter(disposition, 'name');
    if (!fieldName) throw new Error('Multipart field name is missing');
    const partContentType = headersText.split('\r\n').find((line) => line.toLowerCase().startsWith('content-type:'))?.split(':').slice(1).join(':').trim();
    const partFilename = headerParameter(disposition, 'filename');
    if (partFilename !== undefined || fieldName === 'file') {
      if (file) throw new Error('Only one spritesheet file may be uploaded');
      file = Buffer.from(partData);
      filename = partFilename;
      fileContentType = partContentType;
    } else {
      fields[fieldName] = partData.toString('utf8');
    }
    boundaryStart = nextBoundary + 2;
  }

  if (!file || file.length === 0) throw new Error('A non-empty spritesheet file is required');
  return { fields, file, ...(filename ? { filename } : {}), ...(fileContentType ? { contentType: fileContentType } : {}) };
}

function multipartMetadata(multipart: MultipartPayload): Record<string, unknown> {
  const metadataText = multipart.fields.metadata ?? JSON.stringify(multipart.fields);
  let metadataValue: unknown;
  try {
    metadataValue = JSON.parse(metadataText);
  } catch {
    throw new Error('Asset metadata must be valid JSON');
  }
  if (!isRecord(metadataValue)) throw new Error('Asset metadata must be an object');
  return metadataValue;
}

function pngDimensions(buffer: Buffer): { readonly w: number; readonly h: number } {
  if (buffer.length < 24 || buffer.subarray(0, 8).toString('hex') !== '89504e470d0a1a0a') throw new Error('Spritesheet must be a readable PNG');
  const width = buffer.readUInt32BE(16);
  const height = buffer.readUInt32BE(20);
  if (width < 1 || height < 1) throw new Error('PNG dimensions must be positive');
  return { w: width, h: height };
}

function requiredText(fields: Readonly<Record<string, unknown>>, key: string, message: string): string {
  const raw = fields[key];
  const value = typeof raw === 'string' ? raw.trim() : '';
  if (!value) throw new Error(message);
  return value;
}

function requiredInteger(fields: Readonly<Record<string, unknown>>, key: string, minimum: number): number {
  const value = Number(fields[key]);
  if (!Number.isInteger(value) || value < minimum) throw new Error(`${key} must be an integer >= ${minimum}`);
  return value;
}

async function fileExists(filePath: string): Promise<boolean> {
  return fs.access(filePath).then(() => true).catch(() => false);
}

async function loadMutableManifest(manifestPath: string): Promise<{ readonly text: string; readonly value: MutableManifest }> {
  const text = await fs.readFile(manifestPath, 'utf8');
  const parsed: unknown = JSON.parse(text);
  if (!isRecord(parsed) || !isRecord(parsed.assets)) throw new Error('Asset manifest must contain an assets object');
  if (parsed.bundles !== undefined && !isRecord(parsed.bundles)) throw new Error('Asset manifest bundles must be an object');
  const value = JSON.parse(JSON.stringify(parsed)) as MutableManifest;
  value.bundles ??= {};
  return { text, value };
}

function manifestRevision(manifestText: string): string {
  return createHash('sha256').update(manifestText).digest('hex');
}

function manifestHasAsset(manifest: MutableManifest, assetId: string): boolean {
  return Object.prototype.hasOwnProperty.call(manifest.assets, assetId);
}

function textureKeyExists(manifest: MutableManifest, textureKey: string): boolean {
  return Object.values(manifest.assets).some((value) => isRecord(value) && isRecord(value.runtime) && value.runtime.textureKey === textureKey);
}

async function recoverAssetTransactions(assetRoot: string, manifestPath: string): Promise<void> {
  const entries = await fs.readdir(assetRoot, { withFileTypes: true }).catch((error: unknown) => {
    if (error instanceof Error && 'code' in error && (error as NodeJS.ErrnoException).code === 'ENOENT') return [];
    throw error;
  });
  for (const entry of entries.filter((candidate) => candidate.name.startsWith('.character-studio-asset-') && candidate.name.endsWith('.tmp'))) {
    const transactionPath = path.join(assetRoot, entry.name, 'transaction.json');
    const transaction = await readJson(transactionPath).catch(() => undefined);
    if (!isRecord(transaction) || typeof transaction.assetId !== 'string' || typeof transaction.sourcePath !== 'string') throw new Error(`Asset recovery metadata is invalid in '${entry.name}'`);
    if (!ASSET_ID_PATTERN.test(transaction.assetId) || !pathIsInside(assetRoot, path.join(assetRoot, transaction.sourcePath))) throw new Error(`Asset recovery path is invalid in '${entry.name}'`);
    const target = path.join(assetRoot, transaction.sourcePath);
    const stagedAsset = path.join(assetRoot, entry.name, 'asset.png');
    const stagedManifest = path.join(assetRoot, entry.name, 'assets.json');
    const manifest = await loadMutableManifest(manifestPath);
    const committed = manifestHasAsset(manifest.value, transaction.assetId);
    const targetExists = await fs.access(target).then(() => true).catch(() => false);
    const stagedExists = await fs.access(stagedAsset).then(() => true).catch(() => false);
    if (committed && targetExists) {
      await fs.rm(path.join(assetRoot, entry.name), { recursive: true, force: true });
      continue;
    }
    if (!committed && stagedExists && await fs.access(stagedManifest).then(() => true).catch(() => false) && !targetExists) {
      await fs.mkdir(path.dirname(target), { recursive: true });
      await fs.rename(stagedAsset, target);
      await fs.rename(stagedManifest, manifestPath);
      await fs.rm(path.join(assetRoot, entry.name), { recursive: true, force: true });
      continue;
    }
    if (committed && !targetExists && stagedExists) {
      await fs.mkdir(path.dirname(target), { recursive: true });
      await fs.rename(stagedAsset, target);
      await fs.rm(path.join(assetRoot, entry.name), { recursive: true, force: true });
      continue;
    }
    throw new Error(`Asset transaction '${entry.name}' needs manual recovery`);
  }
}

type PackageCommitState = 'missing' | 'complete' | 'partial';

async function packageCommitState(packagePath: string, characterId: string): Promise<PackageCommitState> {
  if (!await fileExists(packagePath)) return 'missing';
  try {
    const character = await readJson(path.join(packagePath, 'character.json'));
    const visualSet = await readJson(path.join(packagePath, 'visual-set.json'));
    if (isRecord(character) && character.characterId === characterId && isRecord(visualSet)) return 'complete';
  } catch {
    // A package directory without both valid files is an ambiguous partial commit.
  }
  return 'partial';
}

async function recoverCreateTransactions(assetRoot: string, characterRoot: string, manifestPath: string): Promise<void> {
  const entries = await fs.readdir(assetRoot, { withFileTypes: true }).catch((error: unknown) => {
    if (error instanceof Error && 'code' in error && (error as NodeJS.ErrnoException).code === 'ENOENT') return [];
    throw error;
  });
  for (const entry of entries.filter((candidate) => candidate.name.startsWith('.character-studio-create-') && candidate.name.endsWith('.tmp'))) {
    const transactionDirectory = path.join(assetRoot, entry.name);
    const transactionValue = await readJson(path.join(transactionDirectory, 'transaction.json')).catch(() => undefined);
    if (!isRecord(transactionValue)
      || transactionValue.operation !== 'create-character'
      || typeof transactionValue.transactionId !== 'string'
      || typeof transactionValue.assetId !== 'string'
      || typeof transactionValue.sourcePath !== 'string'
      || typeof transactionValue.characterId !== 'string') {
      throw new Error(`Character creation recovery metadata is invalid in '${entry.name}'`);
    }
    const transaction = transactionValue as unknown as CharacterCreationTransaction;
    if (!ASSET_ID_PATTERN.test(transaction.assetId) || !ID_PATTERN.test(transaction.characterId)
      || transaction.sourcePath.includes('\\') || transaction.sourcePath.startsWith('/')
      || transaction.sourcePath.split('/').includes('..')
      || !pathIsInside(assetRoot, path.join(assetRoot, transaction.sourcePath))) {
      throw new Error(`Character creation recovery path is invalid in '${entry.name}'`);
    }

    const targetAsset = path.join(assetRoot, transaction.sourcePath);
    const targetPackage = repositoryPath(characterRoot, transaction.characterId);
    const stagedAsset = path.join(transactionDirectory, 'asset.png');
    const stagedManifest = path.join(transactionDirectory, 'assets.json');
    const stagedPackage = path.join(transactionDirectory, 'package');
    const stagedPackageCharacter = path.join(stagedPackage, 'character.json');
    const stagedPackageVisual = path.join(stagedPackage, 'visual-set.json');
    const manifest = await loadMutableManifest(manifestPath);
    const manifestEntry = manifest.value.assets[transaction.assetId];
    const manifestEntrySource = isRecord(manifestEntry) && isRecord(manifestEntry.source) ? manifestEntry.source.path : undefined;
    if (manifestEntry !== undefined && manifestEntrySource !== transaction.sourcePath) {
      throw new Error(`Character creation transaction '${entry.name}' conflicts with the current asset manifest`);
    }
    const manifestCommitted = manifestEntrySource === transaction.sourcePath;
    const targetAssetExists = await fileExists(targetAsset);
    const stagedAssetExists = await fileExists(stagedAsset);
    if (targetAssetExists && stagedAssetExists) throw new Error(`Character creation transaction '${entry.name}' needs manual recovery`);
    const packageState = await packageCommitState(targetPackage, transaction.characterId);
    if (packageState === 'partial') throw new Error(`Character creation transaction '${entry.name}' needs manual recovery`);

    if (!targetAssetExists) {
      if (!stagedAssetExists) throw new Error(`Character creation transaction '${entry.name}' needs manual recovery`);
      await fs.mkdir(path.dirname(targetAsset), { recursive: true });
      await fs.rename(stagedAsset, targetAsset);
    }
    if (!manifestCommitted) {
      if (!await fileExists(stagedManifest)) throw new Error(`Character creation transaction '${entry.name}' needs manual recovery`);
      await fs.rename(stagedManifest, manifestPath);
    }
    if (packageState === 'missing') {
      if (!await fileExists(stagedPackageCharacter) || !await fileExists(stagedPackageVisual)) {
        throw new Error(`Character creation transaction '${entry.name}' needs manual recovery`);
      }
      await fs.mkdir(path.dirname(targetPackage), { recursive: true });
      await fs.rename(stagedPackage, targetPackage);
    }

    const finalManifest = await loadMutableManifest(manifestPath);
    const finalEntry = finalManifest.value.assets[transaction.assetId];
    const finalSourcePath = isRecord(finalEntry) && isRecord(finalEntry.source) ? finalEntry.source.path : undefined;
    if (finalSourcePath !== transaction.sourcePath || await packageCommitState(targetPackage, transaction.characterId) !== 'complete') {
      throw new Error(`Character creation transaction '${entry.name}' needs manual recovery`);
    }
    await fs.rm(transactionDirectory, { recursive: true, force: true });
  }
}

async function writeAuthoringTransaction(
  assetRoot: string,
  characterRoot: string,
  manifestPath: string,
  registration: PreparedAssetRegistration,
  packageValue: CharacterPackage,
): Promise<void> {
  const transactionId = randomUUID();
  const temporary = path.join(assetRoot, `.character-studio-create-${transactionId}.tmp`);
  const targetAsset = path.join(assetRoot, registration.sourcePath);
  const targetPackage = repositoryPath(characterRoot, packageValue.character.characterId);
  if (await fileExists(targetAsset)) throw new Error(`Asset source '${registration.sourcePath}' already exists`);
  if (await fileExists(targetPackage)) throw new Error(`Character '${packageValue.character.characterId}' already exists`);

  const stagedPackage = path.join(temporary, 'package');
  await fs.mkdir(stagedPackage, { recursive: true });
  await fs.writeFile(path.join(temporary, 'transaction.json'), JSON.stringify({
    transactionId,
    operation: 'create-character',
    assetId: registration.assetId,
    sourcePath: registration.sourcePath,
    characterId: packageValue.character.characterId,
  }, null, 2));
  await fs.writeFile(path.join(temporary, 'asset.png'), registration.png);
  await fs.writeFile(path.join(temporary, 'assets.json'), `${JSON.stringify(registration.manifest, null, 2)}\n`);
  await fs.writeFile(path.join(stagedPackage, 'character.json'), `${JSON.stringify(packageValue.character, null, 2)}\n`);
  await fs.writeFile(path.join(stagedPackage, 'visual-set.json'), `${JSON.stringify(packageValue.visualSet, null, 2)}\n`);

  await fs.mkdir(path.dirname(targetAsset), { recursive: true });
  await fs.rename(path.join(temporary, 'asset.png'), targetAsset);
  await fs.rename(path.join(temporary, 'assets.json'), manifestPath);
  await fs.mkdir(path.dirname(targetPackage), { recursive: true });
  await fs.rename(stagedPackage, targetPackage);
  await fs.rm(temporary, { recursive: true, force: true }).catch(() => undefined);
}

async function writeAssetTransaction(
  assetRoot: string,
  manifestPath: string,
  assetId: string,
  sourcePath: string,
  png: Buffer,
  manifest: MutableManifest,
): Promise<void> {
  const transactionId = randomUUID();
  const directoryName = `.character-studio-asset-${Buffer.from(assetId, 'utf8').toString('base64url')}-${transactionId}.tmp`;
  const temporary = path.join(assetRoot, directoryName);
  const target = path.join(assetRoot, sourcePath);
  await fs.mkdir(temporary, { recursive: true });
  await fs.writeFile(path.join(temporary, 'transaction.json'), JSON.stringify({ transactionId, operation: 'asset-register', assetId, sourcePath }, null, 2));
  await fs.writeFile(path.join(temporary, 'asset.png'), png);
  await fs.writeFile(path.join(temporary, 'assets.json'), `${JSON.stringify(manifest, null, 2)}\n`);
  let sourceCommitted = false;
  let manifestCommitted = false;
  try {
    await fs.mkdir(path.dirname(target), { recursive: true });
    await fs.rename(path.join(temporary, 'asset.png'), target);
    sourceCommitted = true;
    await fs.rename(path.join(temporary, 'assets.json'), manifestPath);
    manifestCommitted = true;
  } catch (error) {
    if (!manifestCommitted && sourceCommitted) {
      await fs.rm(target, { force: true }).catch(() => undefined);
      await fs.writeFile(path.join(temporary, 'asset.png'), png).catch(() => undefined);
    }
    throw error;
  }
  await fs.rm(temporary, { recursive: true, force: true }).catch(() => undefined);
}

function ok<T>(data: T): { ok: true; data: T } {
  return { ok: true, data };
}

function failure(code: string, message: string, issues?: readonly CharacterValidationIssue[], currentRevision?: string): ErrorResponse {
  return { ok: false, error: { code, message, ...(issues && issues.length > 0 ? { issues } : {}), ...(currentRevision ? { currentRevision } : {}) } };
}

async function loadPackage(root: string, characterId: string): Promise<CharacterPackage> {
  const directory = repositoryPath(root, characterId);
  const [character, visualSet] = await Promise.all([
    readJson(path.join(directory, 'character.json')),
    readJson(path.join(directory, 'visual-set.json')),
  ]);
  return { character: character as CharacterDocument, visualSet: visualSet as VisualSetDocument };
}

function cloneValue<T>(value: T): T {
  return JSON.parse(JSON.stringify(value)) as T;
}

async function starterPackage(root: string, request: PackageCreationRequest): Promise<CharacterPackage> {
  const files = await discover({ characterRoot: root, visualRoot: root });
  const candidates: CharacterPackage[] = [];
  for (const file of files) {
    if (!file.characterPath || !file.visualPath) continue;
    try {
      const candidate = await loadPackage(root, file.id);
      if (candidate.character.kind === request.kind) candidates.push(candidate);
    } catch {
      // The package validator reports malformed source packages separately.
    }
  }
  const template = request.kind === 'player'
    ? candidates.find((entry) => entry.character.runtimeRole === 'primary-player')
    : request.template === 'ranged-enemy'
      ? candidates.find((entry) => entry.character.enemy?.ai.isRanged)
      : candidates.find((entry) => !entry.character.enemy?.ai.isRanged);
  if (!template) throw new Error(`No ${request.template} starter package is available`);

  const character = cloneValue(template.character);
  const visualSet = cloneValue(template.visualSet);
  const visualSetId = request.kind === 'enemy' ? `enemy.${request.characterId.replaceAll('-', '.')}` : `character.${request.characterId.replaceAll('-', '.')}`;
  character.characterId = request.characterId;
  character.displayName = request.displayName;
  character.visualSetId = visualSetId;
  character.runtimeRole = undefined;
  character.hitboxes = {};
  character.animationTracks = { idle: {} };
  if (request.kind === 'player') {
    character.kind = 'player';
    character.player = cloneValue(template.character.player!);
    delete character.enemy;
  } else {
    character.kind = 'enemy';
    character.enemy = cloneValue(template.character.enemy!);
    delete character.player;
    delete character.runtimeRole;
  }
  visualSet.visualSetId = visualSetId;
  visualSet.assetId = request.assetId;
  visualSet.frameVisuals = undefined;
  visualSet.clips = { idle: { frames: [0], framesPerSecond: 8, loop: true, loopMode: 'wrap' } };
  return { character, visualSet };
}

function parsePackageCreationRequest(payload: Readonly<Record<string, unknown>>): PackageCreationRequest {
  const characterId = payload.characterId;
  const displayName = payload.displayName;
  const kind = payload.kind;
  const template = payload.template;
  const assetId = payload.assetId;
  if (typeof characterId !== 'string' || !ID_PATTERN.test(characterId)) throw new Error('characterId must be a lowercase kebab-case ID');
  if (typeof displayName !== 'string' || displayName.trim().length === 0 || displayName.length > 80) throw new Error('displayName must be between 1 and 80 characters');
  if (kind !== 'player' && kind !== 'enemy') throw new Error("kind must be 'player' or 'enemy'");
  if (template !== 'player' && template !== 'melee-enemy' && template !== 'ranged-enemy') throw new Error('template is invalid');
  if (kind === 'player' && template !== 'player') throw new Error('player packages require the player starter');
  if (kind === 'enemy' && template === 'player') throw new Error('enemy packages require an enemy starter');
  if (typeof assetId !== 'string' || !ASSET_ID_PATTERN.test(assetId)) throw new Error('assetId must be a lowercase dotted stable ID');
  return { characterId, displayName: displayName.trim(), kind, template, assetId };
}

async function prepareAssetRegistration(assetRoot: string, manifestPath: string, multipart: MultipartPayload): Promise<PreparedAssetRegistration> {
  const metadataValue = multipartMetadata(multipart);
  const assetId = requiredText(metadataValue, 'assetId', 'assetId is required');
  if (!ASSET_ID_PATTERN.test(assetId)) throw new Error('assetId must be a lowercase dotted stable ID');
  const frameWidth = requiredInteger(metadataValue, 'frameWidth', 1);
  const frameHeight = requiredInteger(metadataValue, 'frameHeight', 1);
  const dimensions = pngDimensions(multipart.file);
  if (dimensions.w % frameWidth !== 0 || dimensions.h % frameHeight !== 0) throw new Error(`PNG dimensions ${dimensions.w}x${dimensions.h} do not divide evenly by ${frameWidth}x${frameHeight}`);
  const columns = dimensions.w / frameWidth;
  const rows = dimensions.h / frameHeight;
  const capacity = columns * rows;
  const populatedCount = metadataValue.populatedCount === undefined ? capacity : Number(metadataValue.populatedCount);
  if (!Number.isInteger(populatedCount) || populatedCount < 1 || populatedCount > capacity) throw new Error(`populatedCount must be inside 1..${capacity}`);
  const { value: manifest } = await loadMutableManifest(manifestPath);
  if (manifestHasAsset(manifest, assetId)) throw new Error(`Asset '${assetId}' already exists`);
  const sourcePath = `${AUTHORING_ASSET_DIRECTORY}/${assetId.replaceAll('.', '-')}.png`;
  const target = path.join(assetRoot, sourcePath);
  if (!pathIsInside(assetRoot, target)) throw new Error('Derived asset path escapes the asset root');
  if (await fileExists(target)) throw new Error(`Asset source '${sourcePath}' already exists`);
  const textureKey = `character-${assetId.replaceAll('.', '-')}`;
  if (textureKeyExists(manifest, textureKey)) throw new Error(`Texture key '${textureKey}' already exists`);
  const kind = metadataValue.kind === 'enemy' ? 'enemy' : 'player';
  const extraTags = Array.isArray(metadataValue.tags)
    ? metadataValue.tags.filter((tag): tag is string => typeof tag === 'string' && /^[a-z0-9-]+$/.test(tag))
    : [];
  manifest.assets[assetId] = {
    source: { kind: 'spritesheet', path: sourcePath, frame: { w: frameWidth, h: frameHeight, cols: columns, rows, count: populatedCount }, expect: dimensions },
    runtime: { textureKey },
    tags: [...new Set(['character', kind, ...extraTags])],
    status: 'ready',
  };
  const bootBundle = Array.isArray(manifest.bundles.boot) ? [...manifest.bundles.boot] : [];
  if (!bootBundle.includes(assetId)) bootBundle.push(assetId);
  manifest.bundles.boot = bootBundle;
  validateAssetSourcePaths(assetRoot, manifest);
  return {
    assetId,
    sourcePath,
    png: multipart.file,
    manifest,
    frame: { w: frameWidth, h: frameHeight, cols: columns, rows, count: populatedCount },
  };
}

async function assetRegistrationHandler(
  assetRoot: string,
  manifestPath: string,
  request: IncomingMessage,
  response: ServerResponse,
): Promise<void> {
  await recoverAssetTransactions(assetRoot, manifestPath);
  const multipart = await requestMultipart(request);
  const registration = await prepareAssetRegistration(assetRoot, manifestPath, multipart);
  await writeAssetTransaction(assetRoot, manifestPath, registration.assetId, registration.sourcePath, registration.png, registration.manifest);
  const manifestText = `${JSON.stringify(registration.manifest, null, 2)}\n`;
  jsonResponse(response, 201, ok<AssetRegistrationResponse>({
    assetId: registration.assetId,
    sourcePath: registration.sourcePath,
    frame: registration.frame,
    revision: manifestRevision(manifestText),
    reloadRequired: true,
  }));
}

async function packageCreationHandler(
  root: string,
  assetRoot: string,
  manifestPath: string,
  request: IncomingMessage,
  response: ServerResponse,
  server: ViteDevServer,
): Promise<void> {
  await recoverRoot(root);
  const payload = await requestBody(request);
  const creation = parsePackageCreationRequest(payload);
  const { characterId, assetId } = creation;
  const { value: manifest } = await loadMutableManifest(manifestPath);
  if (!manifestHasAsset(manifest, assetId)) throw new Error(`Unknown manifest asset '${assetId}'`);
  const assetEntry = manifest.assets[assetId];
  const source = isRecord(assetEntry) && isRecord(assetEntry.source) ? assetEntry.source : undefined;
  if (!source || typeof source.path !== 'string' || !pathIsInside(assetRoot, path.join(assetRoot, source.path))) throw new Error(`Manifest asset '${assetId}' has no safe source path`);
  if (!await fs.access(path.join(assetRoot, source.path)).then(() => true).catch(() => false)) throw new Error(`Manifest asset '${assetId}' source is missing`);
  try {
    await fs.access(repositoryPath(root, characterId));
    throw new Error(`Character '${characterId}' already exists`);
  } catch (error) {
    if (error instanceof Error && error.message.includes('already exists')) throw error;
  }
  const packageValue = await starterPackage(root, creation);
  const issues = await validatePackageAgainstRoot(root, packageValue, undefined, manifest);
  if (issues.length > 0) {
    jsonResponse(response, 400, failure('validation', 'Created character package is invalid', issues));
    return;
  }
  await writePackageTransaction(root, characterId, normalizeCharacterPackage(packageValue), 'create');
  const saved = await loadPackage(root, characterId);
  jsonResponse(response, 201, ok<PackageCreationResponse>({ characterId, revision: characterPackageRevision(saved), reloadRequired: true }));
  invalidateCatalog(server);
}

async function unifiedCharacterCreationHandler(
  root: string,
  assetRoot: string,
  manifestPath: string,
  request: IncomingMessage,
  response: ServerResponse,
  server: ViteDevServer,
): Promise<void> {
  await recoverRoot(root);
  await recoverCreateTransactions(assetRoot, root, manifestPath);
  await recoverAssetTransactions(assetRoot, manifestPath);
  const multipart = await requestMultipart(request);
  const metadata = multipartMetadata(multipart);
  const creation = parsePackageCreationRequest(metadata);
  const registration = await prepareAssetRegistration(assetRoot, manifestPath, multipart);
  const packageValue = await starterPackage(root, creation);
  const issues = await validatePackageAgainstRoot(root, packageValue, undefined, registration.manifest);
  if (issues.length > 0) {
    jsonResponse(response, 400, failure('validation', 'Created character package is invalid', issues));
    return;
  }

  const normalized = normalizeCharacterPackage(packageValue);
  try {
    await writeAuthoringTransaction(assetRoot, root, manifestPath, registration, normalized);
  } catch (error) {
    jsonResponse(response, 500, failure('unknown-commit', error instanceof Error
      ? `Character creation may be partially committed: ${error.message}`
      : 'Character creation may be partially committed; retry after recovery.'));
    return;
  }
  jsonResponse(response, 201, ok<PackageCreationResponse>({
    characterId: normalized.character.characterId,
    revision: characterPackageRevision(normalized),
    reloadRequired: true,
  }));
  invalidateCatalog(server);
}

async function validatePackageAgainstRoot(root: string, packageValue: CharacterPackage, excludeId?: string, assetManifest?: CharacterStudioAssetManifestInput): Promise<CharacterValidationIssue[]> {
  const files = await discover({ characterRoot: root, visualRoot: root });
  const characterIds = new Set(files.filter((file) => file.characterPath).map((file) => file.id));
  if (excludeId) characterIds.delete(excludeId);
  const visualSetIds = new Set<string>();
  for (const file of files.filter((entry) => entry.visualPath)) {
    try {
      const value = await readJson(file.visualPath!);
      if (value && typeof value === 'object' && 'visualSetId' in value && typeof value.visualSetId === 'string') visualSetIds.add(value.visualSetId);
    } catch { /* the package validator reports malformed content separately */ }
  }
  if (excludeId) visualSetIds.delete(packageValue.visualSet.visualSetId);
  return validateCharacterPackage(packageValue, { characterIds, visualSetIds, assetManifest });
}

async function recoverRoot(root: string): Promise<void> {
  const entries = await fs.readdir(root, { withFileTypes: true }).catch((error: unknown) => {
    if (error instanceof Error && 'code' in error && (error as NodeJS.ErrnoException).code === 'ENOENT') return [];
    throw error;
  });
  const artifacts = entries
    .filter((entry) => entry.name.startsWith('.character-studio-') && (entry.name.endsWith('.tmp') || entry.name.endsWith('.bak')))
    .sort((a, b) => Number(b.name.endsWith('.tmp')) - Number(a.name.endsWith('.tmp')));
  for (const artifact of artifacts) {
    const artifactPath = path.join(root, artifact.name);
    const match = artifact.name.match(/^\.character-studio-([A-Za-z0-9_-]+)-[0-9a-f-]+\.(?:tmp|bak)$/);
    if (!match) continue;
    const targetId = Buffer.from(match[1], 'base64url').toString('utf8');
    if (!ID_PATTERN.test(targetId)) continue;
    const targetPath = repositoryPath(root, targetId);
    try {
      await fs.access(targetPath);
      await fs.rm(artifactPath, { recursive: true, force: true });
    } catch {
      if (artifact.name.endsWith('.tmp')) {
        try {
          await fs.access(path.join(artifactPath, 'character.json'));
          await fs.access(path.join(artifactPath, 'visual-set.json'));
          await fs.rename(artifactPath, targetPath);
        } catch {
          await fs.rm(artifactPath, { recursive: true, force: true });
        }
      } else if (artifact.name.endsWith('.bak')) {
        await fs.rename(artifactPath, targetPath).catch(() => undefined);
      }
    }
  }
}

async function writePackageTransaction(root: string, characterId: string, packageValue: CharacterPackage, operation: 'update' | 'duplicate' | 'create'): Promise<void> {
  const target = repositoryPath(root, characterId);
  const transactionId = randomUUID();
  const encodedCharacterId = Buffer.from(characterId, 'utf8').toString('base64url');
  const temporary = path.join(root, `.character-studio-${encodedCharacterId}-${transactionId}.tmp`);
  const backup = path.join(root, `.character-studio-${encodedCharacterId}-${transactionId}.bak`);
  await fs.mkdir(temporary, { recursive: true });
  await fs.writeFile(path.join(temporary, 'transaction.json'), JSON.stringify({ transactionId, operation, targetId: characterId }, null, 2));
  await fs.writeFile(path.join(temporary, 'character.json'), `${JSON.stringify(packageValue.character, null, 2)}\n`);
  await fs.writeFile(path.join(temporary, 'visual-set.json'), `${JSON.stringify(packageValue.visualSet, null, 2)}\n`);
  let backedUp = false;
  try {
    try {
      await fs.rename(target, backup);
      backedUp = true;
    } catch (error) {
      if (!(error instanceof Error && 'code' in error && (error as NodeJS.ErrnoException).code === 'ENOENT')) throw error;
    }
    await fs.rename(temporary, target);
    await fs.rm(backup, { recursive: true, force: true });
  } catch (error) {
    await fs.rm(target, { recursive: true, force: true }).catch(() => undefined);
    if (backedUp) await fs.rename(backup, target).catch(() => undefined);
    await fs.rm(temporary, { recursive: true, force: true }).catch(() => undefined);
    throw error;
  }
}

function invalidateCatalog(server: ViteDevServer): void {
  const module = server.moduleGraph.getModuleById(RESOLVED_VIRTUAL_ID);
  if (module) server.moduleGraph.invalidateModule(module);
  const projectileModule = server.moduleGraph.getModuleById(RESOLVED_PROJECTILE_VIRTUAL_ID);
  if (projectileModule) server.moduleGraph.invalidateModule(projectileModule);
  const weaponModule = server.moduleGraph.getModuleById(RESOLVED_WEAPON_VIRTUAL_ID);
  if (weaponModule) server.moduleGraph.invalidateModule(weaponModule);
}

async function packageHandler(
  root: string,
  manifestPath: string,
  request: IncomingMessage,
  response: ServerResponse,
  server: ViteDevServer,
  operation: 'get' | 'update' | 'duplicate',
  requestedId?: string,
): Promise<void> {
  await recoverRoot(root);
  if (operation === 'get') {
    if (!requestedId) { jsonResponse(response, 400, failure('invalid-request', 'Character ID is required')); return; }
    try {
      const packageValue = await loadPackage(root, requestedId);
      jsonResponse(response, 200, ok({ ...packageValue, revision: characterPackageRevision(packageValue) }));
    } catch {
      jsonResponse(response, 404, failure('not-found', `Character '${requestedId}' was not found`));
    }
    return;
  }
  if (request.method !== 'POST') { jsonResponse(response, 405, failure('invalid-request', 'POST required')); return; }
  const { value: manifest } = await loadMutableManifest(manifestPath);
  const payload = await requestBody(request);
  const characterId = operation === 'duplicate' || operation === 'update' ? payload.characterId : requestedId;
  if (typeof characterId !== 'string' || characterId.trim().length === 0) { jsonResponse(response, 400, failure('invalid-request', 'Character ID is required')); return; }
  const submittedCharacter = payload.character;
  const submittedVisualSet = payload.visualSet;
  if (!submittedCharacter || !submittedVisualSet) { jsonResponse(response, 400, failure('invalid-request', 'Complete character and visualSet documents are required')); return; }
  const packageValue = { character: submittedCharacter as CharacterDocument, visualSet: submittedVisualSet as VisualSetDocument };
  if (operation === 'update') {
    let saved: CharacterPackage;
    try { saved = await loadPackage(root, characterId); } catch { jsonResponse(response, 404, failure('not-found', `Character '${characterId}' was not found`)); return; }
    const expectedRevision = payload.expectedRevision;
    const actualRevision = characterPackageRevision(saved);
    if (typeof expectedRevision !== 'string' || expectedRevision !== actualRevision) {
      jsonResponse(response, 409, failure('conflict', 'The package changed on disk.', undefined, actualRevision));
      return;
    }
    if (packageValue.character.characterId !== saved.character.characterId || packageValue.character.kind !== saved.character.kind || packageValue.character.runtimeRole !== saved.character.runtimeRole || packageValue.character.visualSetId !== saved.character.visualSetId || packageValue.visualSet.visualSetId !== saved.visualSet.visualSetId || packageValue.visualSet.assetId !== saved.visualSet.assetId) {
      jsonResponse(response, 400, failure('validation', 'Package identity fields cannot be changed.'));
      return;
    }
    const issues = await validatePackageAgainstRoot(root, packageValue, characterId, manifest);
    if (issues.length > 0) { jsonResponse(response, 400, failure('validation', 'Character package is invalid', issues)); return; }
    const normalized = normalizeCharacterPackage(packageValue);
    await writePackageTransaction(root, characterId, normalized, 'update');
    const data = { ...normalized, revision: characterPackageRevision(normalized) };
    jsonResponse(response, 200, ok(data));
    invalidateCatalog(server);
    return;
  }

  const sourceId = payload.sourceCharacterId;
  const newDisplayName = payload.newDisplayName;
  if (typeof sourceId !== 'string' || typeof newDisplayName !== 'string' || newDisplayName.trim().length === 0 || newDisplayName.length > 80) {
    jsonResponse(response, 400, failure('invalid-request', 'sourceCharacterId and a display name are required'));
    return;
  }
  let savedSource: CharacterPackage;
  try { savedSource = await loadPackage(root, sourceId); } catch { jsonResponse(response, 404, failure('not-found', `Character '${sourceId}' was not found`)); return; }
  if (packageValue.character.characterId !== savedSource.character.characterId || packageValue.character.kind !== savedSource.character.kind || packageValue.character.visualSetId !== savedSource.character.visualSetId || packageValue.visualSet.assetId !== savedSource.visualSet.assetId) {
    jsonResponse(response, 409, failure('conflict', 'The duplicate draft no longer matches the source identity.')); return;
  }
  const visualSetId = packageValue.character.kind === 'enemy' ? `enemy.${characterId.replaceAll('-', '.')}` : `character.${characterId.replaceAll('-', '.')}`;
  const duplicate: CharacterPackage = {
    character: { ...packageValue.character, characterId, displayName: newDisplayName.trim(), visualSetId, runtimeRole: undefined },
    visualSet: { ...packageValue.visualSet, visualSetId },
  };
  if (duplicate.character.kind === 'enemy') delete duplicate.character.runtimeRole;
  try {
    await fs.access(repositoryPath(root, characterId));
    jsonResponse(response, 409, failure('conflict', `Character '${characterId}' already exists.`));
    return;
  } catch { /* expected */ }
  const issues = await validatePackageAgainstRoot(root, duplicate, undefined, manifest);
  if (issues.length > 0) { jsonResponse(response, 400, failure('validation', 'Duplicated character package is invalid', issues)); return; }
  await writePackageTransaction(root, characterId, normalizeCharacterPackage(duplicate), 'duplicate');
  jsonResponse(response, 201, ok({ characterId, reloadRequired: true }));
  invalidateCatalog(server);
}

export function characterContentModulesPlugin(options: CharacterContentRootOptions = {}): Plugin {
  const assetRoot = path.resolve(options.assetRoot ?? path.join(process.cwd(), 'asset'));
  const assetManifestPath = path.resolve(options.assetManifestPath ?? path.join(assetRoot, 'assets.json'));
  if (!pathIsInside(assetRoot, assetManifestPath)) throw new Error('Character Studio asset manifest must live inside the asset root');
  const roots: Required<CharacterContentRootOptions> = {
    characterRoot: path.resolve(options.characterRoot ?? path.join(process.cwd(), 'src/game/content/characters')),
    visualRoot: path.resolve(options.visualRoot ?? path.join(process.cwd(), 'src/game/content/visuals')),
    projectileRoot: path.resolve(options.projectileRoot ?? path.join(process.cwd(), 'src/game/content/projectiles')),
    weaponRoot: path.resolve(options.weaponRoot ?? path.join(process.cwd(), 'src/game/content/weapons')),
    assetRoot,
    assetManifestPath,
  };
  const invalidate = (server: ViteDevServer): void => invalidateCatalog(server);
  return {
    name: 'slime-character-content-modules',
    resolveId(id) {
      if (id === VIRTUAL_ID) return RESOLVED_VIRTUAL_ID;
      if (id === PROJECTILE_VIRTUAL_ID) return RESOLVED_PROJECTILE_VIRTUAL_ID;
      if (id === WEAPON_VIRTUAL_ID) return RESOLVED_WEAPON_VIRTUAL_ID;
      return undefined;
    },
    async load(id) {
      if (id === RESOLVED_PROJECTILE_VIRTUAL_ID) {
        const projectileFiles = await findProjectileFiles(roots.projectileRoot);
        const imports = projectileFiles.map((file, index) => `import projectile${index} from ${JSON.stringify(file)};`).join('\n');
        const definitions = projectileFiles.map((_, index) => `projectile${index}`).join(',');
        return `${imports}\nexport const projectileDefinitions = [${definitions}];`;
      }
      if (id === RESOLVED_WEAPON_VIRTUAL_ID) {
        const weaponFiles = await findWeaponFiles(roots.weaponRoot);
        const imports = weaponFiles.map((file, index) => `import weapon${index} from ${JSON.stringify(file)};`).join('\n');
        const definitions = weaponFiles.map((_, index) => `weapon${index}`).join(',');
        return `${imports}\nexport const weaponDefinitions = [${definitions}];`;
      }
      if (id !== RESOLVED_VIRTUAL_ID) return undefined;
      const files = await discover(roots);
      const characterImports: string[] = [];
      const visualImports: string[] = [];
      let index = 0;
      for (const file of files) {
        if (file.characterPath && file.visualPath) {
          characterImports.push(`import character${index} from ${JSON.stringify(file.characterPath)};`);
          visualImports.push(`import visual${index} from ${JSON.stringify(file.visualPath)};`);
          index += 1;
        }
      }
      const nonCharacterVisuals = (await findFiles(roots.visualRoot, 'visual-set.json')).map((visualPath, visualIndex) => `import looseVisual${visualIndex} from ${JSON.stringify(visualPath)};`).join('\n');
      const characterEntries = files.filter((file) => file.characterPath && file.visualPath).map((file, entryIndex) => `{ characterId: ${JSON.stringify(file.id)}, character: character${entryIndex}, visualSet: visual${entryIndex} }`).join(',\n');
      return `${characterImports.join('\n')}\n${visualImports.join('\n')}\n${nonCharacterVisuals}\nexport const characterPackages = [${characterEntries}];\nexport const visualSets = [...characterPackages.map((entry) => entry.visualSet), ...[${(await findFiles(roots.visualRoot, 'visual-set.json')).map((_, visualIndex) => `looseVisual${visualIndex}`).join(',')}]];`;
    },
    handleHotUpdate(context) {
      const changed = context.file.replaceAll('\\', '/');
      if (changed.endsWith('/character.json') || changed.endsWith('/visual-set.json') || changed.endsWith('/projectile.json') || changed.endsWith('/weapon.json')) {
        invalidate(context.server);
        return [];
      }
      return undefined;
    },
    configureServer(server) {
      void recoverRoot(roots.characterRoot);
      void recoverCreateTransactions(roots.assetRoot, roots.characterRoot, roots.assetManifestPath);
      void recoverAssetTransactions(roots.assetRoot, roots.assetManifestPath);
      server.middlewares.use('/__character-studio/asset/register', (request, response, next) => {
        if (request.method !== 'POST') { jsonResponse(response, 405, failure('invalid-request', 'POST required')); return; }
        void assetRegistrationHandler(roots.assetRoot, roots.assetManifestPath, request, response).catch((error: unknown) => {
          jsonResponse(response, 400, failure('asset-registration', error instanceof Error ? error.message : String(error)));
        });
        void next;
      });
      server.middlewares.use('/__character-studio/create', (request, response, next) => {
        if (request.method !== 'POST') { jsonResponse(response, 405, failure('invalid-request', 'POST required')); return; }
        void unifiedCharacterCreationHandler(roots.characterRoot, roots.assetRoot, roots.assetManifestPath, request, response, server).catch((error: unknown) => {
          jsonResponse(response, 400, failure('character-creation', error instanceof Error ? error.message : String(error)));
        });
        void next;
      });
      server.middlewares.use('/__character-studio/package/create', (request, response, next) => {
        if (request.method !== 'POST') { jsonResponse(response, 405, failure('invalid-request', 'POST required')); return; }
        void packageCreationHandler(roots.characterRoot, roots.assetRoot, roots.assetManifestPath, request, response, server).catch((error: unknown) => {
          jsonResponse(response, 400, failure('package-creation', error instanceof Error ? error.message : String(error)));
        });
        void next;
      });
      server.middlewares.use('/__character-studio/package/update', (request, response, next) => {
        if (request.method !== 'POST') { jsonResponse(response, 405, failure('invalid-request', 'POST required')); return; }
        void packageHandler(roots.characterRoot, roots.assetManifestPath, request, response, server, 'update').catch((error: unknown) => {
          jsonResponse(response, 400, failure('unknown-commit', error instanceof Error ? error.message : String(error)));
        });
        void next;
      });
      server.middlewares.use('/__character-studio/package/duplicate', (request, response, next) => {
        void packageHandler(roots.characterRoot, roots.assetManifestPath, request, response, server, 'duplicate').catch((error: unknown) => {
          jsonResponse(response, 400, failure('unknown-commit', error instanceof Error ? error.message : String(error)));
        });
        void next;
      });
      server.middlewares.use('/__character-studio/projectile/create', (request, response, next) => {
        if (request.method !== 'POST') { jsonResponse(response, 405, failure('invalid-request', 'POST required')); return; }
        void projectilePackageHandler(roots.projectileRoot, roots.assetManifestPath, request, response, server, 'create').catch((error: unknown) => {
          jsonResponse(response, 400, failure('projectile-creation', error instanceof Error ? error.message : String(error)));
        });
        void next;
      });
      server.middlewares.use('/__character-studio/projectile/update', (request, response, next) => {
        if (request.method !== 'POST') { jsonResponse(response, 405, failure('invalid-request', 'POST required')); return; }
        void projectilePackageHandler(roots.projectileRoot, roots.assetManifestPath, request, response, server, 'update').catch((error: unknown) => {
          jsonResponse(response, 400, failure('projectile-update', error instanceof Error ? error.message : String(error)));
        });
        void next;
      });
      server.middlewares.use('/__character-studio/weapon/create', (request, response, next) => {
        if (request.method !== 'POST') { jsonResponse(response, 405, failure('invalid-request', 'POST required')); return; }
        void weaponPackageHandler(roots.weaponRoot, request, response, server, 'create').catch((error: unknown) => {
          jsonResponse(response, 400, failure('weapon-creation', error instanceof Error ? error.message : String(error)));
        });
        void next;
      });
      server.middlewares.use('/__character-studio/weapon/update', (request, response, next) => {
        if (request.method !== 'POST') { jsonResponse(response, 405, failure('invalid-request', 'POST required')); return; }
        void weaponPackageHandler(roots.weaponRoot, request, response, server, 'update').catch((error: unknown) => {
          jsonResponse(response, 400, failure('weapon-update', error instanceof Error ? error.message : String(error)));
        });
        void next;
      });
      server.middlewares.use((request, response, next) => {
        const requestPath = request.url?.split('?')[0];
        if (requestPath === '/__character-studio/assets') {
          if (request.method !== 'GET') { jsonResponse(response, 405, failure('invalid-request', 'GET required')); return; }
          void assetCatalogHandler(roots.assetRoot, roots.assetManifestPath, roots.characterRoot, response).catch((error: unknown) => {
            jsonResponse(response, 500, failure('asset-catalog', error instanceof Error ? error.message : String(error)));
          });
          return;
        }
        if (requestPath === '/__character-studio/projectiles') {
          if (request.method !== 'GET') { jsonResponse(response, 405, failure('invalid-request', 'GET required')); return; }
          void projectileCatalogHandler(roots.projectileRoot, roots.assetRoot, roots.assetManifestPath, response).catch((error: unknown) => {
            jsonResponse(response, 500, failure('projectile-catalog', error instanceof Error ? error.message : String(error)));
          });
          return;
        }
        if (requestPath === '/__character-studio/weapons') {
          if (request.method !== 'GET') { jsonResponse(response, 405, failure('invalid-request', 'GET required')); return; }
          void weaponCatalogHandler(roots.weaponRoot, response).catch((error: unknown) => {
            jsonResponse(response, 500, failure('weapon-catalog', error instanceof Error ? error.message : String(error)));
          });
          return;
        }
        const match = requestPath?.match(/^\/__character-studio\/package\/([^/]+)$/);
        if (!match) { next(); return; }
        void packageHandler(roots.characterRoot, roots.assetManifestPath, request, response, server, 'get', decodeURIComponent(match[1])).catch((error: unknown) => {
          jsonResponse(response, 400, failure('unknown-commit', error instanceof Error ? error.message : String(error)));
        });
        return;
      });
    },
  };
}

export { VIRTUAL_ID as CHARACTER_CONTENT_MODULE_ID };
