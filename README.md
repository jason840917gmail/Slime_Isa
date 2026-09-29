# Slime Isa

An open-world game built with Phaser 3, TypeScript, and Vite. Still early in development.

## Stack

- [Phaser 3](https://phaser.io/) — game engine
- TypeScript + Vite — build tooling

## Run locally

```bash
pnpm install
pnpm dev
```

Then open `http://localhost:3000`.

## Development

- `pnpm dev` starts Vite on port 3000.
- `pnpm typecheck` runs strict TypeScript validation (game, Vite config, and browser-test configs).
- Targeted checks and tests: `pnpm scenes:check`, `pnpm maps:check`, `pnpm assets:check`, `pnpm test:<suite>` (see `package.json`).
- `pnpm build` type-checks and creates the production build in `dist/`.
- `pnpm check` runs every check, all Node test suites, the build, and the Playwright browser tests (slow; use before releases or broad commits).

See [AGENTS.md](AGENTS.md) for the full command list and [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for dependency rules, ownership, and persistence. Asset authors start with [docs/assets/README.md](docs/assets/README.md).

Open `http://localhost:3000/?studio=scenes` (dev server only) for Scene Studio, the editor for every authored scene: worlds, characters, weapons, objects, effects, UI, and audio, plus shared resources. It provides a scene tree, inspector, animation timeline, tile painting, undo/redo, and saves straight to `src/game/content/scenes/authored/`. Old editor URLs (including `?editor=<map>`) redirect to it. In development, `http://localhost:3000/?map=<map-id>` starts directly in a world.

## Android Build And Deploy

The Android version is the separate Godot project in `MobileVersion/`. The paths below are from one developer machine; adjust them to your JDK, Android SDK, Godot, and checkout locations.

Use an Android virtual device with **API 35**. For emulator testing, the debug export includes `x86_64` and `arm64-v8a`.

### Export Debug APK

PowerShell:

```powershell
$env:JAVA_HOME = "C:\Program Files\Microsoft\jdk-17.0.18.8-hotspot"
$env:ANDROID_HOME = "C:\Users\User\AppData\Local\Android\Sdk"
$env:ANDROID_SDK_ROOT = $env:ANDROID_HOME
$env:Path = "$env:JAVA_HOME\bin;$env:ANDROID_HOME\platform-tools;$env:ANDROID_HOME\build-tools\35.0.0;$env:Path"

& "C:\Users\User\Downloads\Godot_v4.6.2-stable_win64.exe\Godot_v4.6.2-stable_win64_console.exe" `
  --headless `
  --path "D:\projects\Slime isa\MobileVersion" `
  --export-debug "Android Debug" `
  "D:\projects\Slime isa\MobileVersion\export\android\slime-isa-debug.apk"
```

APK output:

```text
MobileVersion/export/android/slime-isa-debug.apk
```

### Deploy To Virtual Device

Start the Android emulator first, then run:

```powershell
adb devices
adb install -r "D:\projects\Slime isa\MobileVersion\export\android\slime-isa-debug.apk"
```

If more than one device is connected, install to a specific emulator:

```powershell
adb -s emulator-5554 install -r "D:\projects\Slime isa\MobileVersion\export\android\slime-isa-debug.apk"
```

### Verify APK Signature

```powershell
& "C:\Users\User\AppData\Local\Android\Sdk\build-tools\35.0.0\apksigner.bat" verify --verbose "D:\projects\Slime isa\MobileVersion\export\android\slime-isa-debug.apk"
```

## Status

Work in progress. Playable today: the Slimeshire Meadow level-1 world and several other areas, combat with a six-slot weapon hotbar, enemies and bosses, harvesting, crafting, quests and NPCs, house interiors, named saves, and sound effects. Gameplay tuning and visual polish are ongoing, and there is no CI.
