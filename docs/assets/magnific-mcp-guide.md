# Magnific MCP Guide

Use the Magnific MCP server for project media generation. Keep the model and
output defaults below consistent so generated assets remain predictable.

## Required model defaults

| Media | Tool | Required model | Required output defaults |
| --- | --- | --- | --- |
| Images | `mcp__magnific__images_generate` | `gpt-2-mini` (OpenAI GPT 2.5) | Use `1:1` and `1k` unless the task specifies another format. Every request sets `transparentBackground: true`. |
| Videos | `mcp__magnific__video_generate` | `bytedance-seedance-pro-1.5` | One 5-second clip, no audio or sound effects. |

Images always use GPT 2.5, the owner's choice since 2026-10-04. Do not fall
back to `auto` or a non-OpenAI model (for example `cinematic`, Flux,
Seedream, or Nano Banana), and do not switch back to `gpt-2` (GPT 2) unless
the task asks for it. Magnific lists GPT 2.5 as a beta under the slug
`gpt-2-mini` (the name shown in its catalog is "GPT 2.5"); its catalog entry
flags alpha output (`transparentBackground`), it takes the same aspect ratios
and references as GPT 2, and its expected generation time is about 30 s
instead of 90 s. Leave its `variant` unset.

The current catalog identifies these exact slugs. If Magnific changes its
catalog, verify them with `images_models_list({ search: "gpt" })` (the entry
named "GPT 2.5" that flags `transparentBackground`) and
`video_models_list({ search: "Seedance 1.5 Pro" })` before updating this guide.

## Art style

Every generated asset follows the [Slime Isa Art Style
Guide](./visual-style-guide.md): **cozy storybook woodland, hand-painted 2D
miniatures**, seen from a three-quarter top-down view with warm light from the
upper left. It is not pixel art, not 3D, and never uses cold shadows or flat
black outlines.

- **Style block:** start every image and video prompt with the style block
  from the style guide's
  [Generating Assets](./visual-style-guide.md#generating-assets) section.
  Copy it from there, not from older prompts, so the wording has one source.
- **Background line:** add the one for the output type. Every image uses the
  transparent-background line (below). Animation videos use the `#FF00FF`
  chroma background from the
  [character-animation prompt](./character-animation-video-prompt.md).
- **Style reference:** attach one reference sheet from the style guide's
  Reference Art table to every generation (see
  [Style references](#style-references)).
- **Style check:** before packing a result, compare it with the style guide's
  [checklist](./visual-style-guide.md#checklist-for-a-new-asset). Regenerate
  results that fail it instead of painting over them.

## Standard call sequence

Generation can consume credits. Before a paid generation:

```ts
await tools.mcp__magnific__account_balance({});

await tools.mcp__magnific__simulate_cost({
  tool: "images_generate",
  arguments: imageArguments,
});
```

Run the target generation only after checking the returned balance and cost.
Use `tool: "video_generate"` for video cost estimates.

## Image generation

Always pass `mode: "gpt-2-mini"` (GPT 2.5) for project images; never omit
`mode` (it defaults to `auto`). The following is the default shape:

```ts
// Copied from the style guide's Generating Assets section.
const STYLE_BLOCK = "Cozy storybook woodland game art, hand-painted 2D miniature, three-quarter top-down view, ...";

const imageArguments = {
  mode: "gpt-2-mini",
  prompt: `${STYLE_BLOCK} A ruined Workshop: collapsed roof, missing planks, overgrown with moss and weeds. Isolated on a transparent background, no ground shadow plate, no scenery.`,
  aspectRatio: "1:1",
  resolution: "1k",
  transparentBackground: true,
};

await tools.mcp__magnific__images_generate(imageArguments);
```

### Always ask for a transparent background

Every image request sets `transparentBackground: true`, with no exceptions:
sprites, sprite sheets, props, item icons, effects, and also full-frame art
(ground and cliff textures, concept art, UI backplates).

- **Cutouts** (anything placed in the world or the UI on its own): also state
  "isolated on a transparent background, no ground shadow plate, no scenery"
  in the prompt so the model does not paint a backdrop. If a result still
  contains an opaque background, chain `images_remove_background` on it
  rather than regenerating with another model.
- **Full-frame art** (a seamless texture, a concept painting): keep the flag
  and say "fills the whole frame edge to edge, no border, no empty space" in
  the prompt. Before packing, check the alpha is opaque everywhere: a hole in
  a texture would pack as a black or see-through spot.

> **If the flag is refused:** from 2026-09-30 to 2026-10-04 `gpt-2` (GPT 2)
> requests with `transparentBackground: true` failed with "Transparent
> background is not supported for this model", which is why sheets from that
> period were cut out locally. If GPT 2.5 ever refuses it the same way, retry
> once, then generate on "a plain flat pure white background" (or flat
> `#FF00FF` for white or pale subjects such as snow, silk or cobwebs) and cut
> it away locally (a border flood fill keeps white details inside dark
> outlines; see
> `cut_out` in `scripts/art/build-water-life-sheets.py`), or chain
> `images_remove_background`. Note the refusal in this guide.

### Style references

Every generation attaches one reference sheet from the style guide's
[Reference Art](./visual-style-guide.md#reference-art) table:

| Asset | Reference sheet |
| --- | --- |
| Slime characters and NPCs | `village-elder-plop.webp` or `lili.webp` |
| Enemies | the same character sheets; enemies keep the painting and light but may look meaner |
| Objects, props, and buildings | `192x192-tile_8x8-interior-mushroom-furniture-props.webp` |
| Directional objects | `256x256-tile_6x8-interior-beds-directional.webp` |

Upload the sheet once per session and reuse its creation identifier for every
generation in that session. Pass references as creation identifiers returned
by Magnific uploads or earlier generations:

```ts
await tools.mcp__magnific__images_generate({
  ...imageArguments,
  references: [
    { identifier: "style-reference-creation-id", type: "image" },
  ],
});
```

Do not pass a local filesystem path as a reference. In the app, use
`creations_upload_show({ type: "image" })` for local user-selected files. For
headless URL input, use `creations_upload_image({ url })`; for a host-provided
file object, use `creations_upload_file({ file })`.

## Video generation

Always use Seedance 1.5 Pro with one five-second clip. For no-audio output,
omit `audioUrl` and audio references, and set `withSoundEffects: false`:

```ts
const videoArguments = {
  video: {
    clips: [
      {
        slug: "bytedance-seedance-pro-1.5",
        duration: 5,
        aspectRatio: "1:1",
        resolution: "1080p",
        withSoundEffects: false,
        prompt: `${STYLE_BLOCK} Create a seamless 5-second animation of the provided slime character hopping in place...`,
      },
    ],
  },
};

await tools.mcp__magnific__simulate_cost({
  tool: "video_generate",
  arguments: videoArguments,
});

await tools.mcp__magnific__video_generate(videoArguments);
```

Do not use `multi_prompt` for the standard five-second clip. Keep the prompt
focused on one action, one facing direction, and one fixed camera view.

### Character-animation prompt reference

For character animation, use the project prompt guide:

- [Character Animation Video Prompt](./character-animation-video-prompt.md)
- [Character Animation Video Prompt Template](./character-animation-video-prompt-template.md)

That guide is the source for the character-animation constraints: fixed
direction, centered in-place motion, unchanged proportions and equipment,
the hand-painted storybook style from the art style guide, a fixed
three-quarter top-down camera, solid `#FF00FF` chroma-purple background, no
extra actions, no audio, and seamless looping. Its duration is five seconds
for Magnific output.

## Handling results

After an image or video generation, UI-capable clients should call
`creations_show` with every returned creation identifier so the result is
visible in the app. Clients without inline MCP Apps should share the returned
`webUrl` instead:

```ts
await tools.mcp__magnific__creations_show({
  identifiers: ["creation-id-1", "creation-id-2"],
});
```

Use `creations_wait` when a completed asset URL is needed for a download or
another tool call. Pass the creation identifier or returned asset URL to the
next tool; do not pass a `webUrl` as a media input.

## Project asset placement

Generated source art belongs under `asset/Originals/<family>/` (for example
`grounds/generated/`, `props/`, `items/`, `houses/`, `interiors/generated-sheets/`).
Keep experimental or future enemy art in `asset/Originals/enemies/future/`
unless the task names another folder. `asset/Originals/**` is ignored by the
manifest; only the packed runtime file in `asset/MAPS/` (or `asset/characters/`,
`asset/UI/`) is registered in `asset/assets.json`, once it passes
`pnpm assets:check`. See [Asset Creation And Integration](./README.md) for the
pack scripts.
