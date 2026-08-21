import { promises as fs } from 'node:fs';
import path from 'node:path';
import process from 'node:process';
import { execFileSync } from 'node:child_process';
import { pathToFileURL } from 'node:url';

const repoRoot = process.cwd();
const animationRoot = path.join(repoRoot, 'src', 'game', 'content', 'animations');
const weaponRoot = path.join(repoRoot, 'src', 'game', 'content', 'weapons');
const objectRoot = path.join(repoRoot, 'src', 'game', 'content', 'objects');
const visualRoot = path.join(repoRoot, 'src', 'game', 'content', 'visuals');
const assetManifestPath = path.join(repoRoot, 'asset', 'assets.json');
const mappingPath = path.join(repoRoot, 'scripts', 'migrations', 'animation-id-map.json');
const animationIdPattern = /^[a-z0-9]+(?:[.-][a-z0-9]+(?:-[a-z0-9]+)*)+$/;

function isRecord(value) {
  return value !== null && typeof value === 'object' && !Array.isArray(value);
}

function canonicalValue(value) {
  if (Array.isArray(value)) return `[${value.map(canonicalValue).join(',')}]`;
  if (isRecord(value)) {
    return `{${Object.keys(value).sort().map((key) => `${JSON.stringify(key)}:${canonicalValue(value[key])}`).join(',')}}`;
  }
  return JSON.stringify(value);
}

export function slugSegment(value, label = 'value') {
  if (typeof value !== 'string') throw new Error(`${label} must be a string`);
  const slug = value.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-+|-+$/g, '');
  if (slug.length === 0) throw new Error(`${label} '${value}' has no usable slug`);
  return slug;
}

function packageSchemaPath(packageDirectory) {
  return path.relative(packageDirectory, path.join(animationRoot, 'animation-package.schema.json')).replaceAll(path.sep, '/');
}

function packageDocument(animationId, displayName, description, animation, packageDirectory) {
  return {
    $schema: packageSchemaPath(packageDirectory),
    version: 1,
    animationId,
    displayName,
    description,
    animation,
  };
}

function frameTransform(visualSet, clip, sourceFrame) {
  const defaults = visualSet.defaults;
  const frame = visualSet.frameVisuals?.[String(sourceFrame)] ?? {};
  if (frame.origin && canonicalValue(frame.origin) !== canonicalValue(defaults.origin)) {
    throw new Error(`visual set '${visualSet.visualSetId}' uses per-frame origins that cannot be represented by one shared layer origin`);
  }
  return {
    offset: frame.sourceOffset ?? clip.sourceOffset ?? defaults.sourceOffset,
    scale: frame.scale ?? defaults.scale,
  };
}

export function createLayeredAnimationFromLegacyClip(visualSet, clip) {
  if (!isRecord(visualSet) || !isRecord(clip)) throw new Error('visual set and clip must be objects');
  if (!Array.isArray(clip.frames) || clip.frames.length === 0) throw new Error('legacy clip must contain at least one frame');
  if (!Number.isInteger(clip.framesPerSecond) || clip.framesPerSecond < 1 || clip.framesPerSecond > 240) {
    throw new Error('legacy clip framesPerSecond must be an integer between 1 and 240');
  }
  const durationSeconds = clip.durationSeconds ?? clip.frames.length / clip.framesPerSecond;
  const timelineFrameCount = Math.max(1, Math.round(durationSeconds * clip.framesPerSecond));
  const keyframeTimes = clip.keyframeTimes ?? clip.frames.map((_, index) => index);
  if (keyframeTimes.length !== clip.frames.length || keyframeTimes[0] !== 0) throw new Error('legacy clip keyframeTimes are invalid');
  const blocks = clip.frames.map((sourceFrame, index) => {
    const from = keyframeTimes[index];
    const through = keyframeTimes[index + 1] ?? timelineFrameCount - 1;
    if (!Number.isInteger(from) || !Number.isInteger(through) || through < from) throw new Error('legacy clip keyframeTimes are invalid');
    const transform = frameTransform(visualSet, clip, sourceFrame);
    return {
      from,
      through,
      sourceFrame,
      transform,
    };
  });
  return {
    version: 2,
    durationSeconds,
    framesPerSecond: clip.framesPerSecond,
    loop: clip.loop,
    loopMode: clip.loopMode ?? 'wrap',
    layers: [{
      layerId: 'base',
      displayName: 'Base',
      assetId: visualSet.assetId,
      depthOffset: 0,
      transform: { origin: visualSet.defaults.origin },
      blocks,
    }],
  };
}

async function readJson(filePath) {
  return JSON.parse(await fs.readFile(filePath, 'utf8'));
}

async function findFiles(directory, fileName) {
  const entries = await fs.readdir(directory, { withFileTypes: true }).catch((error) => {
    if (error.code === 'ENOENT') return [];
    throw error;
  });
  const files = [];
  for (const entry of entries) {
    if (entry.name.startsWith('.')) continue;
    const candidate = path.join(directory, entry.name);
    if (entry.isDirectory()) files.push(...await findFiles(candidate, fileName));
    else if (entry.isFile() && entry.name === fileName) files.push(candidate);
  }
  return files.sort();
}

function relativeRepoPath(filePath) {
  return path.relative(repoRoot, filePath).replaceAll(path.sep, '/');
}

function addPackage(plan, packageValue, destinationRelativePath, sourcePath, sourceField, decision = 'created') {
  const destinationPath = path.join(animationRoot, destinationRelativePath);
  const destinationId = packageValue.animationId;
  const existing = plan.packagesById.get(destinationId);
  if (existing) {
    const same = canonicalValue(existing.value) === canonicalValue(packageValue);
    if (!same) throw new Error(`animation ID collision '${destinationId}' between ${existing.sourcePath} and ${sourcePath}`);
    plan.entries.push({ sourcePath, sourceField, destinationPath: relativeRepoPath(destinationPath), destinationId, decision: 'reused-in-migration' });
    return destinationId;
  }
  plan.packagesById.set(destinationId, { value: packageValue, destinationRelativePath, sourcePath, generated: true });
  plan.entries.push({ sourcePath, sourceField, destinationPath: relativeRepoPath(destinationPath), destinationId, decision });
  return destinationId;
}

function addVisualLessEntry(plan, sourcePath, sourceField, animationId) {
  plan.entries.push({
    sourcePath,
    sourceField,
    destinationPath: null,
    destinationId: animationId,
    decision: 'visual-less-timeline-kept-on-definition',
  });
}

function addExistingReferenceEntry(plan, sourcePath, sourceField, animationId) {
  if (plan.entries.some((entry) => entry.sourcePath === sourcePath && entry.sourceField === sourceField)) return;
  const packageEntry = plan.packagesById.get(animationId);
  const destinationPath = packageEntry
    ? packageEntry.generated
      ? relativeRepoPath(path.join(animationRoot, packageEntry.destinationRelativePath))
      : packageEntry.destinationRelativePath
    : null;
  plan.entries.push({ sourcePath, sourceField, destinationPath, destinationId: animationId, decision: packageEntry ? 'existing-migrated-reference' : 'visual-less-timeline-kept-on-definition' });
}

function timelineFromLayeredAnimation(animation) {
  return {
    version: 2,
    durationSeconds: animation.durationSeconds,
    framesPerSecond: animation.framesPerSecond,
    loop: animation.loop,
    loopMode: animation.loopMode ?? 'wrap',
  };
}

async function readExistingPackages() {
  const existingPackages = new Map();
  for (const file of await findFiles(animationRoot, 'animation.json')) {
    const value = await readJson(file);
    if (!isRecord(value) || typeof value.animationId !== 'string') throw new Error(`${relativeRepoPath(file)}: existing animation package is missing animationId`);
    const prior = existingPackages.get(value.animationId);
    if (prior && canonicalValue(prior.value) !== canonicalValue(value)) throw new Error(`existing animation ID collision '${value.animationId}' between ${prior.path} and ${relativeRepoPath(file)}`);
    existingPackages.set(value.animationId, { value, path: relativeRepoPath(file) });
  }
  return existingPackages;
}

function readGitJson(relativePath) {
  const content = execFileSync('git', ['show', `HEAD:${relativePath}`], { cwd: repoRoot, encoding: 'utf8' });
  return JSON.parse(content);
}

function registerExistingPackage(plan, animationId, value, packagePath) {
  const prior = plan.packagesById.get(animationId);
  if (prior && canonicalValue(prior.value) !== canonicalValue(value)) throw new Error(`animation ID collision '${animationId}' between ${prior.sourcePath} and ${packagePath}`);
  if (!prior) plan.packagesById.set(animationId, { value, destinationRelativePath: packagePath, sourcePath: packagePath, generated: false });
}

async function buildPlan() {
  const plan = { packagesById: new Map(), entries: [], rewrites: new Map() };
  for (const [animationId, existing] of await readExistingPackages()) registerExistingPackage(plan, animationId, existing.value, existing.path);

  const visualSets = new Map();
  for (const file of await findFiles(visualRoot, 'visual-set.json')) {
    const value = await readJson(file);
    if (typeof value.visualSetId === 'string') visualSets.set(value.visualSetId, value);
  }

  for (const weaponFile of await findFiles(weaponRoot, 'weapon.json')) {
    const currentWeapon = await readJson(weaponFile);
    const weaponPath = relativeRepoPath(weaponFile);
    const missingMigratedPackage = [
      currentWeapon.animations?.idleAnimationId,
      ...Object.values(currentWeapon.directionalAttacks ?? {}).map((attack) => attack?.animationId),
    ].some((animationId) => typeof animationId === 'string' && !plan.packagesById.has(animationId));
    const weapon = missingMigratedPackage && currentWeapon.version === 2 ? readGitJson(weaponPath) : currentWeapon;
    const alreadyMigrated = weapon !== currentWeapon;
    const slug = slugSegment(weapon.weaponId, `${weaponPath}.weaponId`);
    const weaponPackageRoot = `weapons/${slug}`;
    const nextWeapon = structuredClone(currentWeapon);
    let changed = false;
    if (isRecord(weapon.animations) && isRecord(weapon.animations.idle)) {
      const animationId = `weapon.${slug}.idle`;
      if (!Array.isArray(weapon.animations.idle.layers) || weapon.animations.idle.layers.length === 0) {
        delete nextWeapon.animations.idle;
        delete nextWeapon.animations.idleAnimationId;
        nextWeapon.animations.idleTimeline = timelineFromLayeredAnimation(weapon.animations.idle);
        addVisualLessEntry(plan, weaponPath, 'animations.idle', animationId);
        changed = true;
      } else {
      const destinationRelativePath = `${weaponPackageRoot}/idle/animation.json`;
      const packageValue = packageDocument(
        animationId,
        `${weapon.displayName} idle`,
        `Shared idle animation extracted from ${weapon.displayName}.`,
        weapon.animations.idle,
        path.join(animationRoot, path.dirname(destinationRelativePath)),
      );
      addPackage(plan, packageValue, destinationRelativePath, weaponPath, 'animations.idle');
      delete nextWeapon.animations.idle;
      nextWeapon.animations.idleAnimationId = animationId;
      changed = true;
      }
    }
    if (isRecord(weapon.directionalAttacks)) {
      for (const [direction, attack] of Object.entries(weapon.directionalAttacks)) {
        if (!isRecord(attack) || !isRecord(attack.animation)) continue;
        const directionSlug = slugSegment(direction, `${weaponPath}.directionalAttacks direction`);
        const animationId = `weapon.${slug}.attack.${directionSlug}`;
        if (!Array.isArray(attack.animation.layers) || attack.animation.layers.length === 0) {
          delete nextWeapon.directionalAttacks[direction].animation;
          delete nextWeapon.directionalAttacks[direction].animationId;
          nextWeapon.directionalAttacks[direction].animationTimeline = timelineFromLayeredAnimation(attack.animation);
          addVisualLessEntry(plan, weaponPath, `directionalAttacks.${direction}.animation`, animationId);
        } else {
          const destinationRelativePath = `${weaponPackageRoot}/attack-${directionSlug}/animation.json`;
          const packageValue = packageDocument(
            animationId,
            `${weapon.displayName} ${directionSlug} attack`,
            `Shared ${directionSlug} attack animation extracted from ${weapon.displayName}.`,
            attack.animation,
            path.join(animationRoot, path.dirname(destinationRelativePath)),
          );
          addPackage(plan, packageValue, destinationRelativePath, weaponPath, `directionalAttacks.${direction}.animation`);
          delete nextWeapon.directionalAttacks[direction].animation;
          nextWeapon.directionalAttacks[direction].animationId = animationId;
        }
        changed = true;
      }
    }
    if (changed && canonicalValue(nextWeapon) !== canonicalValue(currentWeapon)) plan.rewrites.set(weaponFile, nextWeapon);
    if (typeof currentWeapon.animations?.idleAnimationId === 'string') addExistingReferenceEntry(plan, weaponPath, 'animations.idle', currentWeapon.animations.idleAnimationId);
    else if (currentWeapon.animations?.idleTimeline) addExistingReferenceEntry(plan, weaponPath, 'animations.idle', `weapon.${slug}.idle`);
    for (const [direction, attack] of Object.entries(currentWeapon.directionalAttacks ?? {})) {
      if (typeof attack?.animationId === 'string') addExistingReferenceEntry(plan, weaponPath, `directionalAttacks.${direction}.animation`, attack.animationId);
      else if (attack?.animationTimeline) addExistingReferenceEntry(plan, weaponPath, `directionalAttacks.${direction}.animation`, `weapon.${slug}.attack.${slugSegment(direction)}`);
    }
  }

  for (const objectFile of await findFiles(objectRoot, 'tree-world-solid.json')) {
    const object = await readJson(objectFile);
    const objectPath = relativeRepoPath(objectFile);
    const nextObject = structuredClone(object);
    let changed = false;
    for (const [variantIndex, variant] of (object.variants ?? []).entries()) {
      for (const [frameIndex, frame] of (variant.frames ?? []).entries()) {
        if (!isRecord(frame) || typeof frame.visualSetId !== 'string' || typeof frame.animationClip !== 'string') continue;
        const visualSet = visualSets.get(frame.visualSetId);
        const clip = visualSet?.clips?.[frame.animationClip];
        if (!visualSet || !isRecord(clip)) throw new Error(`${objectPath}.variants[${variantIndex}].frames[${frameIndex}]: cannot resolve visual set '${frame.visualSetId}' and clip '${frame.animationClip}'`);
        const animationId = frame.visualSetId === 'object.tree.world' && frame.animationClip === 'snow-pine-idle'
          ? 'object.tree.idle'
          : `object.${slugSegment(object.objectId, `${objectPath}.objectId`)}.${slugSegment(frame.visualId, `${objectPath}.visualId`)}.${slugSegment(frame.animationClip, `${objectPath}.animationClip`)}`;
        const destinationRelativePath = animationId === 'object.tree.idle'
          ? 'objects/tree/idle/animation.json'
          : `objects/${slugSegment(object.objectId)}/${slugSegment(frame.visualId)}-${slugSegment(frame.animationClip)}/animation.json`;
        const packageValue = packageDocument(
          animationId,
          `${frame.displayName ?? frame.visualId} idle`,
          `Shared idle animation extracted from ${frame.displayName ?? frame.visualId}.`,
          createLayeredAnimationFromLegacyClip(visualSet, clip),
          path.join(animationRoot, path.dirname(destinationRelativePath)),
        );
        addPackage(plan, packageValue, destinationRelativePath, objectPath, `variants[${variantIndex}].frames[${frameIndex}].visualSetId + animationClip`);
        delete nextObject.variants[variantIndex].frames[frameIndex].visualSetId;
        delete nextObject.variants[variantIndex].frames[frameIndex].animationClip;
        nextObject.variants[variantIndex].frames[frameIndex].idleAnimationId = animationId;
        changed = true;
      }
    }
    if (changed) plan.rewrites.set(objectFile, nextObject);
    for (const [variantIndex, variant] of (object.variants ?? []).entries()) {
      for (const [frameIndex, frame] of (variant.frames ?? []).entries()) {
        if (typeof frame?.idleAnimationId === 'string') addExistingReferenceEntry(plan, objectPath, `variants[${variantIndex}].frames[${frameIndex}].visualSetId + animationClip`, frame.idleAnimationId);
      }
    }
  }

  for (const [file, value] of plan.rewrites) {
    const referenceIds = [];
    if (isRecord(value.animations) && typeof value.animations.idleAnimationId === 'string') referenceIds.push(['animations.idleAnimationId', value.animations.idleAnimationId]);
    for (const [direction, attack] of Object.entries(value.directionalAttacks ?? {})) {
      if (isRecord(attack) && typeof attack.animationId === 'string') referenceIds.push([`directionalAttacks.${direction}.animationId`, attack.animationId]);
    }
    for (const [variantIndex, variant] of (value.variants ?? []).entries()) {
      for (const [frameIndex, frame] of (variant.frames ?? []).entries()) {
        if (isRecord(frame) && typeof frame.idleAnimationId === 'string') referenceIds.push([`variants[${variantIndex}].frames[${frameIndex}].idleAnimationId`, frame.idleAnimationId]);
      }
    }
    for (const [field, animationId] of referenceIds) {
      if (!animationIdPattern.test(animationId) || !plan.packagesById.has(animationId)) throw new Error(`${relativeRepoPath(file)}.${field}: migrated animation reference '${animationId}' is not in the generated catalog`);
    }
  }
  return plan;
}

async function writeStaged(plan, stageRoot) {
  for (const packageEntry of plan.packagesById.values()) {
    if (!packageEntry.generated || !packageEntry.destinationRelativePath.endsWith('/animation.json')) continue;
    const target = path.join(stageRoot, 'animations', packageEntry.destinationRelativePath);
    await fs.mkdir(path.dirname(target), { recursive: true });
    await fs.writeFile(target, `${JSON.stringify(packageEntry.value, null, 2)}\n`);
  }
  for (const [source, value] of plan.rewrites) {
    const target = path.join(stageRoot, 'rewrites', relativeRepoPath(source));
    await fs.mkdir(path.dirname(target), { recursive: true });
    await fs.writeFile(target, `${JSON.stringify(value, null, 2)}\n`);
  }
  const stagedMapping = path.join(stageRoot, 'mapping', 'animation-id-map.json');
  await fs.mkdir(path.dirname(stagedMapping), { recursive: true });
  await fs.writeFile(stagedMapping, `${JSON.stringify({ version: 1, entries: plan.entries }, null, 2)}\n`);
}

async function commit(plan, stageRoot) {
  const installedPackages = [];
  const backups = new Map();
  const installFile = async (staged, destination, key) => {
    const exists = await fs.access(destination).then(() => true).catch(() => false);
    if (exists) {
      const backup = path.join(stageRoot, 'backups', key);
      await fs.mkdir(path.dirname(backup), { recursive: true });
      await fs.copyFile(destination, backup);
      backups.set(destination, backup);
    }
    const temporary = `${destination}.animation-migrate-${process.pid}`;
    await fs.mkdir(path.dirname(destination), { recursive: true });
    await fs.copyFile(staged, temporary);
    await fs.rename(temporary, destination);
  };
  try {
    for (const packageEntry of plan.packagesById.values()) {
      if (!packageEntry.generated || !packageEntry.destinationRelativePath.endsWith('/animation.json')) continue;
      const source = path.join(stageRoot, 'animations', packageEntry.destinationRelativePath);
      const destination = path.join(animationRoot, packageEntry.destinationRelativePath);
      if (await fs.access(destination).then(() => true).catch(() => false)) continue;
      await fs.mkdir(path.dirname(destination), { recursive: true });
      await fs.rename(source, destination);
      installedPackages.push(destination);
    }
    for (const [source] of plan.rewrites) {
      const staged = path.join(stageRoot, 'rewrites', relativeRepoPath(source));
      await installFile(staged, source, relativeRepoPath(source));
    }
    await installFile(path.join(stageRoot, 'mapping', 'animation-id-map.json'), mappingPath, 'scripts/migrations/animation-id-map.json');
  } catch (error) {
    for (const destination of installedPackages) await fs.rm(destination, { force: true }).catch(() => undefined);
    for (const [destination, backup] of backups) {
      const temporary = `${destination}.animation-rollback-${process.pid}`;
      await fs.copyFile(backup, temporary).catch(() => undefined);
      await fs.rename(temporary, destination).catch(() => undefined);
    }
    throw error;
  }
}

export async function runMigration({ write = false } = {}) {
  const plan = await buildPlan();
  const stageRoot = await fs.mkdtemp(path.join(path.dirname(animationRoot), '.animation-library-migration-'));
  try {
    await writeStaged(plan, stageRoot);
    if (write) {
      await commit(plan, stageRoot);
    }
    return { packageCount: plan.packagesById.size, rewriteCount: plan.rewrites.size, entryCount: plan.entries.length, stageRoot, write };
  } finally {
    await fs.rm(stageRoot, { recursive: true, force: true });
  }
}

async function main() {
  const write = process.argv.includes('--write');
  const result = await runMigration({ write });
  console.log(`animation migration ${write ? 'committed' : 'preflight'} — ${result.packageCount} package(s), ${result.rewriteCount} definition rewrite(s), ${result.entryCount} mapping entr${result.entryCount === 1 ? 'y' : 'ies'}`);
}

if (process.argv[1] && import.meta.url === pathToFileURL(path.resolve(process.argv[1])).href) {
  main().catch((error) => {
    console.error(`animation migration FAILED — ${error.message}`);
    process.exitCode = 1;
  });
}
