# Magnific MCP Guide

Use the Magnific MCP server for project media generation. Keep the model and
output defaults below consistent so generated assets remain predictable.

## Required model defaults

| Media | Tool | Required model | Required output defaults |
| --- | --- | --- | --- |
| Images | `mcp__magnific__images_generate` | `cinematic` | Use `1:1` and `1k` unless the task specifies another format. |
| Videos | `mcp__magnific__video_generate` | `bytedance-seedance-pro-1.5` | One 5-second clip, no audio or sound effects. |

The current catalog identifies these exact slugs. If Magnific changes its
catalog, verify them with `images_models_list({ search: "cinematic" })` and
`video_models_list({ search: "Seedance 1.5 Pro" })` before updating this guide.

Project visual direction: [Modernized Pixel-Stylized Top-Down Visual
Guide](./visual-style-guide.md).

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

Always pass `mode: "cinematic"` for project images. This is the project's
subscription-backed default image model. The following is the default shape
for a square image:

```ts
const imageArguments = {
  mode: "cinematic",
  prompt: "A modernized pixel-stylized top-down 2D game asset of the Sticky Spider-Slime...",
  aspectRatio: "1:1",
  resolution: "1k",
};

await tools.mcp__magnific__images_generate(imageArguments);
```

For style matching, pass references as creation identifiers returned by
Magnific uploads or earlier generations:

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
        prompt: "Create a seamless modernized pixel-stylized top-down character animation...",
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

- [Character Animation Video Prompt](./Prompts/videos/character_videos.md)

That guide is the source for the character-animation constraints: fixed
direction, centered in-place motion, unchanged proportions and equipment,
modernized pixel-stylized top-down 2D visual language, solid `#FF00FF`
chroma-purple background, fixed camera, no extra actions, no audio, and
seamless looping. Its duration is five seconds for Magnific output.

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

Generated source art belongs under `asset/Originals/`. Keep experimental or
future enemy art in `asset/Originals/enemies/future/` unless the task
explicitly requests a different folder. Do not add source art to
`asset/assets.json` until it is ready to be a runtime-loaded asset and has
passed the repository asset checks.
