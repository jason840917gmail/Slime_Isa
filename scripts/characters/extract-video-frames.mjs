#!/usr/bin/env node
/**
 * Extracts every frame of local MP4 clips with headless Brave (Playwright), for machines without
 * ffmpeg. Each clip is loaded as a blob so seeking is frame-accurate; frame i is taken at
 * (i + 0.25) / fps seconds and scaled to size x size.
 *
 * usage: node scripts/characters/extract-video-frames.mjs <outDir> <fps> <size> <name>=<file.mp4> ...
 * Writes <outDir>/<name>/f000.png, f001.png, ...
 */
import { createRequire } from 'node:module';
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const repoRoot = resolve(dirname(fileURLToPath(import.meta.url)), '..', '..');
const require = createRequire(join(repoRoot, 'package.json'));
const { chromium } = require('playwright');

const BRAVE = process.env.BRAVE_PATH ?? 'C:/Program Files/BraveSoftware/Brave-Browser/Application/brave.exe';
const [outDir, fpsArg, sizeArg, ...clips] = process.argv.slice(2);
const fps = Number(fpsArg);
const size = Number(sizeArg);
if (!outDir || !(fps > 0) || !(size > 0) || clips.length === 0) {
  console.error('usage: extract-video-frames.mjs <outDir> <fps> <size> <name>=<file.mp4> ...');
  process.exit(2);
}

const files = new Map(clips.map((clip) => {
  const separator = clip.indexOf('=');
  return [clip.slice(0, separator), resolve(clip.slice(separator + 1))];
}));
const browser = await chromium.launch({ executablePath: BRAVE, headless: true });
try {
  const page = await browser.newPage();
  // Serve the page and the clips from one fake origin so the canvas is not tainted.
  await page.route('http://frames.local/**', async (route) => {
    const name = decodeURIComponent(new URL(route.request().url()).pathname.slice(1));
    if (name === 'index.html') return route.fulfill({ contentType: 'text/html', body: '<!doctype html><video muted></video><canvas></canvas>' });
    return route.fulfill({ contentType: 'video/mp4', body: readFileSync(files.get(name)) });
  });
  await page.goto('http://frames.local/index.html');

  for (const name of files.keys()) {
    const dir = join(outDir, name);
    mkdirSync(dir, { recursive: true });
    const meta = await page.evaluate(async ({ name, size }) => {
      const blob = await (await fetch(`/${encodeURIComponent(name)}`)).blob();
      const video = document.querySelector('video');
      video.src = URL.createObjectURL(blob);
      await new Promise((done, fail) => { video.onloadeddata = done; video.onerror = () => fail(new Error('cannot decode')); });
      const canvas = document.querySelector('canvas');
      canvas.width = size;
      canvas.height = size;
      return { duration: video.duration, width: video.videoWidth, height: video.videoHeight };
    }, { name, size });
    const count = Math.floor(meta.duration * fps + 1e-6);
    for (let index = 0; index < count; index += 1) {
      const dataUrl = await page.evaluate(async ({ time, size }) => {
        const video = document.querySelector('video');
        const canvas = document.querySelector('canvas');
        await new Promise((done) => { video.onseeked = done; video.currentTime = time; });
        const context = canvas.getContext('2d');
        context.imageSmoothingQuality = 'high';
        context.drawImage(video, 0, 0, size, size);
        return canvas.toDataURL('image/png');
      }, { time: (index + 0.25) / fps, size });
      writeFileSync(join(dir, `f${String(index).padStart(3, '0')}.png`), Buffer.from(dataUrl.split(',')[1], 'base64'));
    }
    console.log(`${name}: ${meta.width}x${meta.height}, ${meta.duration.toFixed(2)} s -> ${count} frames`);
  }
} finally {
  await browser.close();
}
