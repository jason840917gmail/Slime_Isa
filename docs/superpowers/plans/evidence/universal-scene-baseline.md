# Universal Scene Refactor Baseline

## Repository state

- Baseline commit: `a447d41` (`docs: align damage and migration ownership contracts`)
- Initial worktree: clean (`git status --short` produced no entries)
- Node: `v24.19.0`
- Project package manager: pnpm `10.33.2`; the initially resolved shell command reported pnpm `11.19.0`
- Captured: 2026-09-13, America/New_York

## Existing verification

`pnpm check` was run before runtime/content ownership changes. It failed in the existing `test:ui` suite after all preceding checks passed.

Existing failure: six assertions in `scripts/tests/crafting/crafting-layout.test.mjs` disagree with the current `CraftingLayout` behavior:

| Test | Expected | Actual |
| --- | ---: | ---: |
| normal layouts cap eight readable rows | 8 | 6 |
| compact layouts reduce visible capacity | 69 | 46 |
| short catalogs render only their rows | 8 | 6 |
| non-finite and negative inputs normalize safely | 68 | 40 |
| selection movement wraps and remains reachable | 1 | 3 |
| visible ranges map to absolute indices | `{ start: 1, end: 9 }` | `{ start: 1, end: 7 }` |

The run also printed non-fatal Vite WebSocket port `24678` contention warnings in suites that create development servers. These are recorded as baseline noise and are not treated as passing browser evidence.

No unrelated failure is fixed in Work Package 0.

The commands skipped by the failing `pnpm check` chain were then run directly: `pnpm test:map-editor` passed 26 tests, `pnpm test:depth` passed 7 tests, `pnpm typecheck` passed, and `pnpm build` passed. The new baseline suites also pass: `pnpm test:scene-conversion` passes 5 tests and `pnpm test:scene-browser` passes 2 real-browser tests.

## Browser and performance procedure

- Playwright dependency: `@playwright/test` `1.63.0` (exactly pinned)
- Browser: installed system Google Chrome `152.0.7977.84` through Playwright's Chromium driver
- Matching Playwright Chromium `153.0.8010.12` download: blocked on this machine by `UNABLE_TO_GET_ISSUER_CERT_LOCALLY`; the harness therefore uses the installed Chromium-based Chrome executable and records this exception explicitly
- Hardware recorded by the available process environment: Intel64 Family 6 Model 154 Stepping 4, 12 logical processors. WMI denied access to model, memory, and GPU details, so those fields are explicitly unavailable rather than guessed.
- Viewport: 1280 × 720
- Renderer: Phaser `AUTO` in the actual game baseline; Phaser `CANVAS` in the deterministic smoke harness
- Small authored map: `test-rectangle`
- Large authored map: `tiktok`
- Warm-up: 120 `requestAnimationFrame` samples
- Measurement: 300 `requestAnimationFrame` samples
- Frame statistic: sorted median and p95 wall-clock delta
- Load statistic: navigation/fixture start until the actual `world` scene becomes active
- Object/body counts: actual active Phaser scene child lists plus Arcade dynamic/static body sets
- Cleanup count: live object plus body count released by `game.destroy(true)`; the test separately requires zero remaining canvases
- Randomness/clocks: normal runtime clocks and map seeds; fresh Playwright context/storage per test; no mocked timers for the performance run

The values below come from the checked-in browser suite. Controlled-step smoke-fixture timings are never used as performance data.

## Baseline measurements

The recorded full-suite comparison run used the procedure above:

| Map | Load ms | Median frame ms | p95 frame ms | Phaser objects | Arcade bodies | Cleanup count |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `test-rectangle` | 4265.9 | 16.7 | 16.8 | 62 | 2 | 64 |
| `tiktok` | 4374.2 | 16.7 | 16.8 | 5065 | 1269 | 6334 |

Both runs destroyed the game and reached zero remaining fixture canvases. Load time includes cold module/asset startup within the fresh browser document and is therefore not expected to scale only with map size; the final comparison must use the same order and procedure.

## Content hashes

Asset-manifest and per-map SHA-256 values are recorded in `universal-scene-conversion-ledger.md`, generated from the same inventory command as the machine ledger.

## Interpretation boundary

These checks are deterministic technical evidence. Gameplay testing was not performed and remains reserved for user verification.
