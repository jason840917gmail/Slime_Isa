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
- `pnpm typecheck` runs strict TypeScript validation.
- `pnpm build` type-checks and creates the production build.
- `pnpm check` runs the complete local verification sequence.

The Phaser project follows a feature-first structure. See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for dependency rules, state ownership, persistence, and conventions for new features.

Asset authors should follow [docs/ADDING_ASSETS.md](docs/ADDING_ASSETS.md), which explains the media manifest, reusable object archetypes, and map-instance layers.

Map authors should follow [docs/AUTHORED_MAPS.md](docs/AUTHORED_MAPS.md) for the JSON workflow, content rules, preview URL, and validation commands.

Use [docs/MAP_EDITOR.md](docs/MAP_EDITOR.md) for the dev-only Field Cartographer visual editor, controls, and safe-saving workflow.

## Android Build And Deploy

The Android version is the Godot project in `MobileVersion/`.

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

Work in progress. Core movement and animations are functional.
