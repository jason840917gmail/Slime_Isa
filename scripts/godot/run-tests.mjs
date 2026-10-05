#!/usr/bin/env node
/**
 * test:godot — runs the headless Godot integration tests (`godot/tests/run_tests.gd`,
 * docs/godot/CONVENTIONS.md "Checking your work") and exits with their exit code.
 *
 * Godot: `$GODOT` (path to the Godot 4.7.2 console executable), else the default install path
 * below. Needs `pnpm godot:sync`, `pnpm godot:convert` and an imported project.
 * Extra arguments go to the runner: `pnpm test:godot --filter=camp`, `--strict`.
 */
import { spawnSync } from 'node:child_process';
import { existsSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const DEFAULT_GODOT = 'C:\\Users\\User\\Downloads\\Godot_v4.7.2-stable_win64.exe\\Godot_v4.7.2-stable_win64_console.exe';
const godot = process.env.GODOT || DEFAULT_GODOT;
const projectDir = join(dirname(fileURLToPath(import.meta.url)), '..', '..', 'godot');

if (!existsSync(godot)) {
  console.error(`test:godot: Godot not found at ${godot}; set GODOT to the Godot 4.7.2 console executable.`);
  process.exit(1);
}

const runnerArgs = process.argv.slice(2).filter((arg) => arg !== '--');
const args = ['--headless', '--path', projectDir, '-s', 'res://tests/run_tests.gd'];
if (runnerArgs.length > 0) args.push('--', ...runnerArgs);

const result = spawnSync(godot, args, { stdio: 'inherit' });
if (result.error) {
  console.error(`test:godot: could not start Godot: ${result.error.message}`);
  process.exit(1);
}
process.exit(result.status ?? 1);
