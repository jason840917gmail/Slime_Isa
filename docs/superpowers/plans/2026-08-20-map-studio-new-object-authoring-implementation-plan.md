# Map Studio New Object Authoring Implementation Plan

## Status

Proposed. This plan implements roadmap task 2.5 as a Map Studio workflow.

## Decision

Create object visual templates in Map Studio, not Weapon Studio or the shared
Animation Studio.

Map Studio owns world placement, object families, source visuals, colliders,
depth bounds, occlusion bounds, and map-instance previews. Animation Studio owns
reusable layered animation packages. The object workflow may select an
`idleAnimationId` or `onHitAnimationId`, but it must not embed a second timeline
editor or move animation-package ownership into Map Studio.

Weapon Studio remains weapon-specific. It is not an appropriate owner for
object physics, world sorting, or decoration placement.

## Outcome

Add one end-to-end **New Object** action to Field Cartographer. A creator can:

1. choose the existing behavior family the visual will inherit;
2. select a registered spritesheet or import a PNG spritesheet;
3. choose the source frame and stable visual ID;
4. configure scale, offset, collision, depth, and occlusion where supported;
5. optionally assign shared idle and on-hit animation packages;
6. save the template, return to the palette with it selected, and place it;
7. save and reload the map without hand-editing JSON.

The map format remains unchanged. Instances continue to store only
`objectId`, `visualId`, position, and optional mutable state.

## Scope boundary

The first slice creates a new **visual template under an existing object
archetype**. The selected archetype supplies behavior, physics mode, resource
rules, and tags.

Examples:

- `decoration.world.floor` creates a walkable floor decoration with no collider;
- `decoration.world.solid` creates a static solid decoration with a collider;
- `tree.world.solid` creates another tree visual that inherits the tree resource
  behavior;
- other existing authored families may be enabled when their inherited behavior
  is safe and clearly described in the UI.

Creating a brand-new `objectId`, schema shape, or gameplay behavior is out of
scope. Those changes still require a new authored definition and any matching
runtime implementation. The dialog must call this distinction out as
**Behavior family** so users know that the new visual inherits family-wide
rules.

## Existing foundations to reuse

- `MapEditorPanel.ts` already renders Object Content and selects placement tools.
- `MapEditorInspector.ts` already edits visual scale, offset, collider, depth,
  occlusion, and shared animation references.
- `ObjectTemplateEditorState.ts` already validates and saves existing templates.
- `/__map-editor/object-template/duplicate` already performs atomic JSON updates,
  but it can only duplicate a frame inside the source variant.
- `/__character-studio/assets` already exposes the registered media catalog.
- `/__character-studio/asset/register` already validates and atomically registers
  uploaded PNG spritesheets; the implementation should be extracted behind a
  domain-neutral service while preserving the existing route for compatibility.
- `objects.schema.json`, `check-objects.mjs`, and `check-animations.mjs` already
  encode most geometry, frame, and animation-reference invariants.

## Authoring contract

Introduce a request shared by client state, server validation, and tests:

```ts
interface CreateObjectVisualRequest {
  readonly objectId: ObjectArchetypeId;
  readonly assetId: AssetId;
  readonly frame: number;
  readonly visualId: string;
  readonly displayName: string;
  readonly scale: number;
  readonly visualOffset: { readonly x: number; readonly y: number };
  readonly collider?: ColliderBounds;
  readonly depthBounds?: DepthBounds;
  readonly occlusionBounds?: OcclusionBounds;
  readonly idleAnimationId?: string;
  readonly onHitAnimationId?: string;
}
```

Creation must enforce:

- `objectId` references an existing authored family;
- `assetId` references a ready spritesheet in `asset/assets.json`;
- `frame` is inside the declared populated frame count;
- `visualId` is valid and unique within the selected object family;
- floor/decorative families with `physics: null` cannot define a collider;
- static solid families require a collider inside the source frame;
- depth and occlusion bounds fit inside the source frame;
- animated templates follow the existing occlusion limitation;
- idle packages exist and loop; on-hit packages exist and do not loop;
- no map instance or gameplay rule is written by template creation.

## Work sequence

### 1. Extract reusable object-creation validation

Add a pure object-authoring module close to the object content model. It should
resolve the selected archetype, manifest asset, source-frame dimensions, and
animation packages, then return either a normalized frame variant or structured
field diagnostics.

Reuse the same validator from the browser draft and server commit path. Refactor
the overlapping rules currently split between `ObjectTemplateEditorState.ts`,
the Vite object-template handlers, and `scripts/check-objects.mjs` only where it
reduces duplication without changing existing save behavior.

Add focused tests for valid floor, valid solid, tree-family inheritance,
duplicate visual IDs, bad frame indexes, unknown assets, collider policy,
out-of-frame geometry, and invalid animation loop contracts.

### 2. Add the create-template server operation

Add `POST /__map-editor/object-template/create` through a small Map Studio
authoring module rather than adding more large inline logic to `vite.config.ts`.

The handler must:

1. parse and validate the request with a bounded body size;
2. locate the existing object-definition file safely;
3. validate against the current asset and animation catalogs;
4. append to the matching `assetId` variant, or create that variant when absent;
5. serialize the complete definition and run object validation;
6. write to a sibling temporary file and atomically rename it;
7. preserve every unrelated frame and field;
8. return the created `objectId`, `visualId`, and normalized template.

Write failures must leave the original definition untouched. The endpoint must
reject new archetype IDs rather than silently creating unsupported behavior.

### 3. Add Map Studio creation state

Create `MapEditorObjectCreateState.ts` to own dialog state independently from
map state and the existing-template inspector. It should load:

- available existing object families and their inherited physics/tags/behavior;
- registered ready spritesheets and frame metadata;
- shared animation packages for optional assignment.

State must track the chosen family, source asset, source frame, identifiers,
geometry, animation references, validation errors, import progress, save
progress, and a recoverable server error. Switching family or source frame must
revalidate and initialize safe defaults without discarding entered identity
fields unnecessarily.

### 4. Build the New Object dialog in Map Studio

Add a **New Object** button beside the Object Content heading. Render the flow as
one focused dialog with these sections:

1. **Behavior family** — searchable family cards showing tags, physics, and a
   warning that behavior is inherited.
2. **Source artwork** — registered spritesheet library plus **Import PNG**.
3. **Source frame** — tile grid using the manifest's real frame width, height,
   columns, rows, and populated count; frame metadata is cropping information,
   not artwork scaling.
4. **Identity** — stable visual ID and display name.
5. **World geometry** — scale, offset, collider, depth, and occlusion controls
   using the same fields and overlays as the template inspector.
6. **Animations** — the existing searchable idle/on-hit package picker.
7. **Review and create** — inherited behavior summary and validation status.

Keep rendering and event handling outside the already-large
`MapEditorPanel.ts`; mount the dialog from a dedicated component/controller.
Reuse the existing Phaser overlay preview so geometry is shown against the
selected source frame before saving.

### 5. Reuse the shared asset import pipeline

Extract the current PNG registration implementation behind a neutral asset
authoring service. Keep `/__character-studio/asset/register` working, and either
add a neutral alias such as `/__content-assets/register` or call the shared
service from a Map Studio route.

Object imports must collect asset ID, frame width, frame height, populated
count, and the `object` tag. Registration validates PNG dimensions, exact grid
division, safe destination paths, unique asset/texture IDs, and manifest
integrity. After success, refresh the source catalog and select the new asset.

Asset registration and template creation may remain two explicit commits. If
template creation fails, the successfully registered asset remains available in
the source library rather than being deleted or hidden.

### 6. Refresh, select, and place the created template

After creation, refresh the object catalog through HMR or a controlled Map
Studio reload that preserves the current map ID. Open the created template in
the inspector, select the Object tool, and select the new visual for stamping.

The palette must place it in the existing group derived from its object family.
Map instances continue to use the stable pair `{ objectId, visualId }`; no
asset/frame data may leak into authored maps.

### 7. Verification and documentation

Add automated coverage under `scripts/tests/map-editor/` for:

- creating a floor decoration from an existing asset;
- creating a solid decoration with a valid collider;
- appending to an existing asset variant;
- creating a new variant for a different registered asset;
- rejecting duplicate IDs and invalid frame references;
- rejecting collider/physics mismatches and invalid bounds;
- accepting valid idle/on-hit package references and rejecting wrong loop modes;
- preserving the original JSON on validation or write failure;
- selecting the created template after catalog refresh.

Manual acceptance pass:

1. Create and place a floor decoration from an existing sheet.
2. Create and place a solid decoration with a visible collider overlay.
3. Import a new PNG sheet, create a template from one frame, and place it.
4. Create a tree-family visual and assign a shared idle animation.
5. Save the map, reload Map Studio, and confirm all visuals and geometry persist.
6. Play the map and confirm collision, depth, inherited behavior, and animation.

Run:

```text
pnpm assets:check
pnpm animations:check
pnpm objects:check
pnpm maps:check
pnpm test:animation-packages
pnpm test:object-animation
pnpm typecheck
pnpm build
pnpm check
```

Update `docs/STUDIO_TABS.md`, `docs/ARCHITECTURE.md`, and the roadmap status when
the workflow is verified in the running editor and game.

## Acceptance criteria

- The New Object action is discoverable from Object Content in Map Studio.
- A creator can select or import a spritesheet and choose a real source frame.
- The workflow creates a validated visual under an existing behavior family.
- Floor decorations remain non-solid; solid families cannot be saved without a
  valid collider.
- Shared animations are selected by ID and remain authored in Animation Studio.
- The created template appears in the palette, is selected for placement, and
  survives map/editor reload.
- Object-definition writes are atomic and preserve unrelated content.
- Existing template editing, placement, maps, and runtime behavior remain
  unchanged.
