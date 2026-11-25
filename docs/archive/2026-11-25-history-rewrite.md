# The history rewrite of 2026-11-25

On 2026-11-25 the owner had `asset/Originals/` (source art and audio the game never loads: 4.5 GB of
the repository's 6.3 GB) taken out of git and out of every commit. The folder stays on his disk and is
git-ignored; only its small text files (notes, prompts, manifests, packer scripts) are tracked again from
the commit after the rewrite.

Every commit kept its author, date, message and every file outside `asset/Originals/`; only the ids
changed, for 483 of the 491 commits (every one from `b7e82a60`, 2026-07-18, on). A commit id in a doc, a handover or a memory note written before that day
is an **old** id: look it up here. The old history is kept whole in a local backup beside the checkout
(`D:/projects/Slime-isa-history-backup-2026-11-25.git`, a bare mirror, sources included).

Made with `git filter-branch --index-filter "git rm -r -q --cached --ignore-unmatch asset/Originals"`
in a separate mirror clone, checked (same 491 authors, dates and subjects; no file differs outside the
folder; no path under it in any commit), then force-pushed to `origin/main`.

| Old id | New id | Date | Subject |
|---|---|---|---|
| `56699d0a` | `56699d0a` | 2026-04-25 | Initial commit |
| `df70bc96` | `df70bc96` | 2026-04-25 | Add README |
| `a3c04e0e` | `a3c04e0e` | 2026-04-25 | isa0.1 |
| `4f8790bf` | `4f8790bf` | 2026-06-07 | Add Friend and House classes; implement shop interaction and friend spawning |
| `a1101b01` | `a1101b01` | 2026-07-15 | refactor to 3 levels maps , lots of funtionalities, add some assets |
| `9bf4b453` | `9bf4b453` | 2026-07-16 | add grounds originlas |
| `ca292f28` | `ca292f28` | 2026-07-18 | refactor game structure |
| `db76d135` | `db76d135` | 2026-07-18 | Merge branch 'main' of https://github.com/jason840917gmail/Slime_Isa |
| `b7e82a60` | `a43bff3c` | 2026-07-18 | map builder |
| `1c20225e` | `1479c9b6` | 2026-07-19 | agents chatc, add more assets sand walls etc , improve the terrain builder. |
| `75e99072` | `30d31513` | 2026-07-20 | docs: define json-authoritative map runtime |
| `60b60020` | `98aef7c4` | 2026-07-20 | docs: preserve unrelated map work |
| `068021a1` | `26fb3503` | 2026-07-20 | right panel and bug of gost hauses fix |
| `695e8f83` | `2190b5d9` | 2026-07-23 | docs: design animated worm enemy roster |
| `ec6976cb` | `138f6f9b` | 2026-07-23 | docs: tighten worm enemy migration contract |
| `bd632f80` | `5a3ae56f` | 2026-07-23 | docs: specify worm enemy content and clips |
| `475b7ba6` | `1454f811` | 2026-07-24 | add JSON-driven animated visuals and begin migrating the enemy roster to authored worm spritesheets |
| `235180dc` | `df9efb29` | 2026-07-24 | docs: design combat hit feedback and future parries |
| `553f6536` | `d34051af` | 2026-07-25 | docs: design facing-preserving knockback animations |
| `0bc004a3` | `274202fe` | 2026-07-25 | docs: record projectile solid collision bug |
| `7dbfefcd` | `59598625` | 2026-07-25 | Fix pooled projectiles colliding with solid world objects and preserve facing-aware knockback animations. |
| `a9ba2d56` | `272c824b` | 2026-07-27 | docs: define map editor inspector bug fixes |
| `f84fd968` | `e055cd60` | 2026-07-27 | docs: plan top-down depth and occlusion |
| `a340a8f4` | `e241efb2` | 2026-07-27 | fix(editor): add save-as-template and toggle matching object bounds without resetting inspector scroll |
| `0aeccd65` | `e97a2228` | 2026-07-27 | feat(world): add alpha-based occlusion depth sorting and color-coded editor geometry overlays |
| `256eb954` | `7a826923` | 2026-07-27 | docs: design character studio |
| `542cda54` | `98b65177` | 2026-07-27 | docs: tighten character studio contracts |
| `a297b2f9` | `ebcb7362` | 2026-07-27 | docs: finalize character studio semantics |
| `bacdde1a` | `7057e1e7` | 2026-07-27 | docs: close character studio edge cases |
| `877deb0e` | `1cc681d3` | 2026-07-27 | docs: finish character studio review contracts |
| `a4fa78bf` | `bc237565` | 2026-07-27 | planning player enemie |
| `fed8dba8` | `7f66a60f` | 2026-07-28 | feat(character-studio): complete authoring workflow and stabilize playback/save |
| `f0b3dac8` | `63712bfc` | 2026-07-28 | images generation prompt and styling |
| `10f8d882` | `67ec5087` | 2026-07-28 | Merge branch 'main' of https://github.com/jason840917gmail/Slime_Isa |
| `8edb7cbc` | `2e077c4b` | 2026-07-29 | `feat: expand studios with ping-pong animation, reusable combat assets, attributes, and collision shapes` |
| `fc58a76e` | `e449ca6b` | 2026-07-30 | Implement enemy area authoring, boundary AI, editor controls, and Escape cancellation |
| `e0019c19` | `254bf331` | 2026-08-05 | Fix bugs and add weapons Originals |
| `07c47509` | `9feee611` | 2026-08-06 | spride projects folder |
| `adb907de` | `9a1c2344` | 2026-08-06 | docs: define weapon spritesheet prompt design |
| `d6db4b7f` | `6fe78e4e` | 2026-08-06 | docs: update weapon prompt background rules |
| `cc393752` | `d50f839b` | 2026-08-06 | docs: specify weapon visual attack events |
| `b1502af9` | `93917468` | 2026-08-06 | weapon layer and character attachment |
| `72294905` | `2f99a979` | 2026-08-09 | feat: expand weapon studio, loadouts, and depth tools |
| `b0d28618` | `d11880d8` | 2026-08-10 | docs: design timed weapon keyframe editor |
| `8a2dbce8` | `89f0d9d2` | 2026-08-10 | docs: clarify timed weapon keyframe semantics |
| `1a91de27` | `27398271` | 2026-08-10 | docs: define deterministic weapon timeline edits |
| `29abe89e` | `e0ebad5f` | 2026-08-10 | docs: finalize weapon timeline edge cases |
| `3b45b61c` | `c7e6b566` | 2026-08-10 | docs: clarify authored weapon timing scope |
| `4bb81a7d` | `24d20223` | 2026-08-10 | docs: define shared animation timeline architecture |
| `5b99dd49` | `a4ef3581` | 2026-08-10 | docs: tighten shared animation architecture |
| `8445df56` | `4d283244` | 2026-08-10 | feat: unify character and weapon animation timelines |
| `a146b88a` | `9a685f5b` | 2026-08-11 | docs: define keyframe hold control targeting |
| `a0061da7` | `a28254ec` | 2026-08-11 | docs: strengthen hold targeting verification |
| `e9bf26b3` | `b9cbd1fc` | 2026-08-11 | docs: include preview playhead targeting |
| `1f2739ce` | `440bd17a` | 2026-08-11 | docs: define seconds-first animation ruler |
| `b2a6d007` | `19654b34` | 2026-08-11 | docs: specify timeline ruler precision |
| `935cf940` | `292487be` | 2026-08-11 | docs: define ruler grid boundary behavior |
| `072f60be` | `eeb29525` | 2026-08-11 | docs: standardize timeline time labels |
| `70130b3e` | `823fbe0d` | 2026-08-11 | docs: finalize seconds ruler contract |
| `d459310a` | `5442fb03` | 2026-08-11 | docs: define timeline border drag resizing |
| `ac20fa4d` | `60c44716` | 2026-08-11 | docs: clarify timeline resize interaction |
| `39449b78` | `0881595e` | 2026-08-11 | docs: finalize timeline resize lifecycle |
| `60fdbe18` | `794c55d9` | 2026-08-11 | docs: resolve timeline resize semantics |
| `752ddc00` | `1ed39644` | 2026-08-11 | docs: define weapon hitbox preview |
| `8de86b76` | `1945b720` | 2026-08-11 | docs: clarify hitbox preview parity |
| `ca0bb881` | `d0ba45df` | 2026-08-11 | feat: unify studio animation and weapon hitbox editing |
| `5602294a` | `04c8a4fb` | 2026-08-11 | refactor: make weapon hitboxes authoritative |
| `318e058d` | `b624374b` | 2026-08-12 | docs: design layered animation effects |
| `6575cd97` | `b31bf300` | 2026-08-12 | docs: plan layered animation effects |
| `93e301db` | `39f60906` | 2026-08-12 | feat: define shared layered animations |
| `f0de60bc` | `d9b85280` | 2026-08-12 | refactor: extract shared animation clock |
| `6f34079d` | `105b018c` | 2026-08-12 | feat: render layered animations from one clock |
| `3f60cb25` | `5620c6bd` | 2026-08-12 | feat: normalize layered weapon packages |
| `de122c38` | `dfd99f84` | 2026-08-12 | feat: add shared layered timeline editor |
| `45295f24` | `3bfee99c` | 2026-08-12 | feat: add reusable confirmed-hit effects |
| `672795f7` | `e9bf19a1` | 2026-08-12 | refactor: report confirmed damage applications |
| `52be8896` | `d56d4a1e` | 2026-08-12 | refactor: synchronize weapon animation and combat tracks |
| `d3527646` | `d823d9ba` | 2026-08-12 | feat: play effects on confirmed hits |
| `dc5950c9` | `a2d92d19` | 2026-08-12 | feat: activate layered weapon studio |
| `e4863676` | `6d9b8d7f` | 2026-08-12 | content: migrate weapons to layered animations |
| `0305722c` | `8cb645f3` | 2026-08-13 | supper power |
| `63016404` | `1bd5789b` | 2026-08-13 | Fix weapon hitbox preview geometry controls |
| `fb1e6bea` | `74bc9b95` | 2026-08-13 | fix: scroll weapon studio inspector |
| `98e54f40` | `7e6f7b0c` | 2026-08-13 | docs: plan vertical directional mirroring |
| `8a6ee40b` | `856d1d68` | 2026-08-14 | feat: add directional mirroring and preview zoom |
| `ce2a7944` | `109e6763` | 2026-08-17 | feat: complete layered weapon animation workflow |
| `e1c670bd` | `64594d57` | 2026-08-17 | docs: define physics-body combat collision |
| `c0b6ae83` | `b436d9b3` | 2026-08-17 | docs: design center-following hit effects |
| `4a3ce31c` | `1b4a1f31` | 2026-08-17 | docs: plan center-following hit effects |
| `5150095e` | `aed1030a` | 2026-08-17 | feat: follow confirmed hit effects with targets |
| `eda1f11e` | `048f005a` | 2026-08-17 | fix: keep hit effects in front of moving targets |
| `d98e93e7` | `d6e855a9` | 2026-08-17 | feat: update combat collision and weapon effects |
| `9966cd87` | `8e30a45c` | 2026-08-18 | feat: add starter wooden axe resource tool |
| `8fb9242e` | `bbd80cf1` | 2026-08-19 | docs: specify stone gathering and pickaxe |
| `30ca73a9` | `d7a8e46c` | 2026-08-19 | docs: plan Object Studio animations |
| `175ea8e9` | `b3a88105` | 2026-08-19 | docs: design shared animation library |
| `4bb2f900` | `3a62e03c` | 2026-08-19 | hammer pickaxe wood axe |
| `b468c5af` | `8177c868` | 2026-08-20 | feat(map-studio): add new object authoring workflow Add a Map Studio “New object” workflow for creating visual templates under existing behavior families. Support source asset/frame selection, PNG import, IDs, geometry, colliders, depth/occlusion, and animation hooks. Add atomic object-template creation with shared validation. Register imported assets with object tags. Update the roadmap and implementation plan. Validate assets, animations, objects, and TypeScript compilation. |
| `08b86871` | `cf2e00c4` | 2026-08-21 | feat(map-editor): add object palette search Add live search for object IDs, names, assets, and tags Add clear-search control and empty-result message Make tree-autumn-01 easy to find in Map Studio |
| `00f5d914` | `52a99176` | 2026-08-21 | Implemented. - Added Delete selected beside Edit selected, with confirmation and undo support. - Added four resize handles to both stay and pursue perimeters. - Rectangle handles resize from any corner. - Circle handles resize from four diagonal positions. - Resizing preserves map bounds and stay/pursue containment. - Updated Map Studio documentation. |
| `27162c93` | `74e321c5` | 2026-08-21 | Implemented the responsive map/UI changes. - Added a dedicated screen UI camera so HUD, minimap, controls, and action bars stay anchored while zooming. - Made the minimap resize and remain pinned to the bottom-left. - Made HUD bars responsive to viewport width. - Removed the crossed-out objective/debug text. - Removed redundant weapon title and weapon-name labels. - Made the controls panel compact and scrollable on small screens. - Preserved mouse-wheel world zoom behavior. |
| `2b1e2ecf` | `388878b9` | 2026-08-23 | fix(weapons): align mirrored up attacks with combat hitboxes |
| `430c9eb6` | `1922bf3f` | 2026-08-24 | expand resource collection, persistence, and map authoring - Replace wood and stone resource piles with walk-over collectible drops. - Add collectible/resource archetypes, quantities, drop visuals, tool requirements, effects, and resource depletion. - Add resource and collectible editing tabs with shared defaults and per-instance overrides. - Group map-editor palette items by category, even when they share artwork. - Add map-size readout and resizing controls with terrain padding, coordinate scaling, validation, undo, and save support. - Widen the map-editor inspector panel. - Add save/load/reset persistence flows and related runtime state handling. - Add stone-age tools, weapons, recipes, animations, assets, and initial content. - Update schemas, validators, tests, roadmap documents, and architecture notes. |
| `fdeacce4` | `44264e53` | 2026-08-26 | add unarmed fresh starts and retire Meadow Crossing It covers: - Empty initial player state - Nullable/no-weapon combat support - First crafted weapon auto-equip - Level 1 map becoming canonical - Removal of Meadow Crossing references - 80-life stone-node confirmation and test cleanup - Updated roadmap and verification checklist |
| `3a3f8274` | `15594249` | 2026-08-26 | docs: specify legacy collectible migration cleanup |
| `fd7e5a6b` | `cd40cac1` | 2026-08-26 | docs: specify Escape overlay dismissal |
| `b979649e` | `dc07ebae` | 2026-08-26 | docs: specify single-use function checker |
| `894fb9cc` | `76d831f9` | 2026-08-26 | docs: design central gameplay constants |
| `a19de2e9` | `5042c8a4` | 2026-08-26 | docs: specify persistence modal lifecycle repair |
| `ae750ae8` | `bd0fd583` | 2026-08-26 | docs: clarify Escape lifecycle correction |
| `ec9c1df4` | `532d05b7` | 2026-08-26 | docs: complete modal lifecycle contract |
| `bdb31b81` | `ca6c4c2d` | 2026-08-26 | feat: integrate gameplay UI and content updates |
| `8a685b87` | `7dde4924` | 2026-08-26 | docs: refine central gameplay constants design |
| `b474a3b2` | `8b40d77f` | 2026-08-26 | `feat(weapons): make authored icon pairs the thumbnail source of truth` |
| `f7956ccd` | `37383f96` | 2026-08-27 | feat: centralize gameplay constants and add Character Studio authoring |
| `424ef6f9` | `bca72f67` | 2026-08-27 | feat(weapons): add targeting authoring controls |
| `fff1a8f8` | `f26deb16` | 2026-08-27 | feat(resources): centralize harvest tag catalog |
| `153f119e` | `05a33396` | 2026-08-27 | last |
| `1a84e735` | `81c678dc` | 2026-08-28 | refactor collectible event flow |
| `32004e18` | `17e75415` | 2026-08-28 | contants |
| `25297fc4` | `56c902bb` | 2026-08-31 | feat(quests): add robust quest system and first quest |
| `68ee39f7` | `06c5ddd1` | 2026-09-03 | docs: specify crafting overlay redesign |
| `431f97bd` | `0b73befe` | 2026-09-03 | docs: define game UI visual skin system |
| `022ed536` | `7daab9cb` | 2026-09-03 | docs: finalize game UI visual skin spec |
| `741bb7be` | `8f599c1b` | 2026-09-03 | feat: redesign crafting overlay interactions |
| `938e1e5f` | `5d1a7a6b` | 2026-09-03 | refine crafting row styling |
| `4ea7064d` | `872f1d89` | 2026-09-04 | docs: specify NPC character studio inclusion |
| `75cac7ad` | `6176c5b0` | 2026-09-04 | docs: specify crafting detail panel experience |
| `8ae803bd` | `0e84a7f6` | 2026-09-04 | docs: clarify NPC authoring contracts |
| `33a8963a` | `f746e2ee` | 2026-09-04 | docs: clarify crafting detail panel contracts |
| `8502b749` | `02e0bc1a` | 2026-09-04 | docs: plan NPC character studio inclusion |
| `ad003c20` | `9bc50447` | 2026-09-04 | docs: harden NPC inclusion plan |
| `e682a862` | `8e110817` | 2026-09-04 | docs: lock artwork-first world HUD direction |
| `ce6f3df3` | `fef361b9` | 2026-09-04 | docs: tighten world HUD design acceptance |
| `65b1520b` | `304aeb98` | 2026-09-04 | docs: clarify HUD fallback and teardown rules |
| `3ae8a777` | `2eb6ef68` | 2026-09-04 | docs: label approved HUD choice as option C |
| `bd0e974c` | `bbe377b6` | 2026-09-04 | docs: resolve HUD layout and fallback decisions |
| `2aa5c01a` | `40dab7dd` | 2026-09-04 | docs: design unified animation studio |
| `01e93701` | `8615b0db` | 2026-09-04 | docs: finalize unified animation studio design |
| `f5fb8c77` | `757e0e71` | 2026-09-04 | docs: plan unified animation studio implementation |
| `38f0757b` | `6d2045e8` | 2026-09-04 | docs: design map editor NPC preview fix |
| `5c0f7c68` | `52419888` | 2026-09-08 | feat: expand NPC authoring, studios, and game UI |
| `49f2ced9` | `4e64e5ee` | 2026-09-10 | refactor(world): cache terrain transitions and remove legacy map populations |
| `643d48f3` | `c27eb83f` | 2026-09-10 | docs: design shared world drop spawner |
| `b5ef29e6` | `7e2dc5db` | 2026-09-10 | docs: plan shared world drop spawner |
| `cc3fcf9f` | `41b5aff8` | 2026-09-10 | feat: animate shared world drops |
| `80d431c7` | `ef564c55` | 2026-09-10 | docs: define lethal resource hit sequencing |
| `46560f0b` | `89b079b6` | 2026-09-10 | fix: skip hit animation on lethal resource damage |
| `7a7b02c6` | `bff90d23` | 2026-09-10 | docs: design persistent inventory world drops |
| `6e4b288f` | `1fb7ebe9` | 2026-09-10 | feat: drop inventory items into the world |
| `a70d8da0` | `77de431c` | 2026-09-10 | docs: design inventory drop stacking |
| `b925c25c` | `b49d8a57` | 2026-09-10 | fix: stack inventory drops on occupied resource tiles |
| `8a84357f` | `4298fb03` | 2026-09-10 | docs: design collectible quantity badges |
| `50b2aea0` | `e8d815a0` | 2026-09-10 | feat: show collectible pile quantities |
| `f1a65d06` | `fe08192a` | 2026-09-10 | docs: specify map editor exit zone repair |
| `b16c4cf5` | `b4a9fc7f` | 2026-09-11 | Connection zones auto place on edge |
| `0275ea2e` | `e481992d` | 2026-09-11 | docs: design Fatty One Eye guarded chest |
| `19f1f5ae` | `1ecfa88c` | 2026-09-11 | docs: design Map Studio boss boss camp authoring |
| `bc9a5bf8` | `ed72a002` | 2026-09-11 | docs: design Map Studio boss camp authoring |
| `04da9dbf` | `242d642a` | 2026-09-11 | docs: design Fatty contact hop attack |
| `ff8cb25a` | `f1f018b2` | 2026-09-11 | docs: plan Fatty and boss camp implementation |
| `95ddc1ce` | `1885a2a3` | 2026-09-12 | docs: design Fatty death and return fixes |
| `0ff91848` | `c276b814` | 2026-09-12 | docs: design universal scene node architecture |
| `cea54c75` | `71ab4258` | 2026-09-12 | docs: strengthen universal scene architecture and product contracts |
| `00b54d85` | `204ad8a4` | 2026-09-12 | docs: plan universal scene node refactor |
| `ec0271e5` | `c5557bdd` | 2026-09-12 | boss one eye andplaning refactor godot |
| `f398a403` | `cc833798` | 2026-09-12 | docs: resolve universal refactor plan execution gaps |
| `a447d413` | `a0350ad4` | 2026-09-13 | docs: align damage and migration ownership contracts |
| `eb6b5db0` | `a5858557` | 2026-09-13 | test: inventory universal scene conversion baseline |
| `1f364100` | `8785cc29` | 2026-09-13 | feat: define universal scene document contracts |
| `7a82ba92` | `87f21677` | 2026-09-13 | feat: add deterministic scene tree runtime |
| `b4628f11` | `117a805b` | 2026-09-13 | feat: add packed scene resolution and transactional loading |
| `aff7d869` | `3a364f86` | 2026-09-13 | feat: host universal scene trees in Phaser |
| `c5730498` | `974254c7` | 2026-09-13 | feat: add universal physics and sensor nodes |
| `f576c4bf` | `424c90b7` | 2026-09-13 | feat: add animation audio input and script nodes |
| `20d28f4b` | `43373134` | 2026-09-13 | feat: add universal Scene Studio document workflow |
| `b13fafe6` | `7e9d2307` | 2026-09-14 | feat: complete common Scene Studio authoring tools |
| `ec6c1ef6` | `29f4d209` | 2026-09-14 | feat: add universal enemy scene slice foundation |
| `63167637` | `568fb7d8` | 2026-09-14 | feat: add deterministic vertical slice conversion |
| `8d60c22a` | `f23f961b` | 2026-09-14 | feat: prepare universal scene content for live runtime |
| `f1aa03d1` | `c522c596` | 2026-09-14 | feat: compose packed scenes in Phaser runtime |
| `3bf06816` | `532db3bf` | 2026-09-14 | feat: run universal worm enemy behavior |
| `35bf2075` | `e6bdc80b` | 2026-09-14 | feat: run universal fatty phase behavior |
| `48eb4b3b` | `a3aece93` | 2026-09-14 | feat: complete universal scene vertical slice |
| `db1d91d4` | `d4e38392` | 2026-09-15 | feat: author remaining enemy scenes |
| `ade51801` | `91029e74` | 2026-09-15 | feat: run all enemies through universal scenes |
| `4ab40f1d` | `aa2a74ee` | 2026-09-15 | refactor: extract player ability decisions |
| `55f1d5ef` | `282eda00` | 2026-09-15 | feat: author node-backed player scene |
| `c3b007b9` | `dd88b47b` | 2026-09-15 | refactor: isolate player ability presentation |
| `7f6b5aec` | `c82a966e` | 2026-09-15 | feat: author node-backed npc scenes |
| `360a9b51` | `64844c39` | 2026-09-15 | feat: run authored npcs through universal scenes |
| `542884e5` | `d19027ac` | 2026-09-15 | feat: route player damage through authored scene |
| `8f01d908` | `a6eca1fc` | 2026-09-15 | refactor: drive player motion through scene nodes |
| `8df94710` | `b6756bf2` | 2026-09-15 | refactor: route player input through scene tree |
| `dcf46c44` | `ed7eb526` | 2026-09-15 | refactor: hand character authoring to scene studio |
| `f1627b2e` | `95387eee` | 2026-09-15 | refactor: make authored player presentation live |
| `512321ac` | `ef0806c8` | 2026-09-15 | refactor: isolate player compatibility adapters |
| `3746ad10` | `aed8dc77` | 2026-09-15 | feat: author combat entities as scenes |
| `c420a2f7` | `82716165` | 2026-09-15 | refactor: hand combat authoring to scene studio |
| `8afed67f` | `0c43aa14` | 2026-09-16 | refactor: mount managed projectiles from scenes |
| `f43986a1` | `7dfdf72d` | 2026-09-16 | refactor: spawn managed effects from scenes |
| `72b00258` | `f06154ae` | 2026-09-16 | refactor: mount managed weapons from scenes |
| `34e737e0` | `c412b792` | 2026-09-16 | refactor: retire legacy weapon presentation |
| `0ffdd81d` | `82d7d67d` | 2026-09-16 | refactor: route managed weapon hits through scenes |
| `27eaf037` | `deaba8a1` | 2026-09-16 | refactor: retire legacy weapon runtime |
| `7c1ca08d` | `df489bf9` | 2026-09-16 | refactor: retire legacy projectile pool |
| `1d8191cc` | `df62694b` | 2026-09-16 | refactor: retire legacy effect pool |
| `bb1ee3d9` | `654a04ec` | 2026-09-16 | feat: add scene-backed world object scripts |
| `78499940` | `c74324b8` | 2026-09-16 | feat: author stone resources as scenes |
| `71daaefe` | `b6678fac` | 2026-09-16 | refactor: mount stone resources from scenes |
| `9081162d` | `a11f6203` | 2026-09-16 | feat: author tree resources as scenes |
| `0f6252f7` | `d049c4dd` | 2026-09-16 | refactor: mount tree resources from scenes |
| `529a1aef` | `d9ca8a06` | 2026-09-16 | feat: add transactional collectible scene contract |
| `2d15a997` | `81c4ad5a` | 2026-09-16 | feat: author collectible objects as scenes |
| `e43f19b6` | `d6ef66ce` | 2026-09-16 | refactor: mount authored collectibles from scenes |
| `94706ead` | `339e139d` | 2026-09-17 | feat: author passive world objects as scenes |
| `31b23114` | `09d1a3c8` | 2026-09-17 | refactor: mount passive world objects from scenes |
| `c0a1eaf4` | `8c5049ac` | 2026-09-17 | refactor: mount mineable amber ore from scenes |
| `8850f864` | `f7331c7b` | 2026-09-17 | test: audit scene ownership for every world object |
| `00d24b3a` | `d23f14af` | 2026-09-17 | feat: add external tile map scene resources |
| `52269951` | `b7bc717d` | 2026-09-17 | feat: author world terrain scenes |
| `e00b3121` | `81f64668` | 2026-09-17 | feat: persist nested scene placements |
| `ffe3ce5d` | `be14263a` | 2026-09-17 | feat: nest authored placements in world scenes |
| `213bafc8` | `679bc64c` | 2026-09-17 | feat: author world navigation areas |
| `5eff271f` | `7ae11c41` | 2026-09-17 | feat: prepare authored worlds atomically |
| `02e5de20` | `ec0e75ae` | 2026-09-17 | feat: cut over production to authored worlds |
| `26a1024a` | `43969602` | 2026-09-17 | feat: complete authored world scene cutover |
| `24e66fab` | `d1e2288e` | 2026-09-18 | feat: author universal UI scene foundations |
| `186fdf13` | `4bc3f5bb` | 2026-09-18 | feat: mount authored HUD in production |
| `be2729a4` | `dcd53f2d` | 2026-09-23 | feat: mount authored weapon hotbar in production |
| `42ad451e` | `bf62d6cc` | 2026-09-23 | feat: mount authored ability bar in production |
| `6ce487a2` | `c9f0d0c8` | 2026-09-23 | feat: mount authored player and boss health bars |
| `232d201f` | `ba7e1524` | 2026-09-23 | feat: mount authored area title and floating text |
| `6dad0e4d` | `4808371d` | 2026-09-24 | feat: mount authored inventory modal |
| `d5251437` | `ba64fd54` | 2026-09-24 | feat: mount authored chest inventory panel |
| `9301f2a4` | `03e71d03` | 2026-09-24 | feat: mount authored crafting workbench |
| `8ae0a20b` | `2bcac1ec` | 2026-09-24 | feat: mount authored quest journal and offer |
| `3ef16139` | `526b41c8` | 2026-09-24 | feat: mount authored world map |
| `894ca962` | `153105db` | 2026-09-24 | feat: mount authored level up modal |
| `8187b2b3` | `ce32416c` | 2026-09-24 | feat: mount canvas backed authored minimap |
| `78fdcd29` | `cd551438` | 2026-09-24 | feat: mount authored global audio composition |
| `a1d5036b` | `66621e51` | 2026-09-26 | refactor: retire legacy editors and entity construction |
| `976b9550` | `7662f510` | 2026-09-27 | feat: finish universal scene refactor fixes and Godot-style resources |
| `51236103` | `c81c5d2f` | 2026-09-27 | feat: key animation values from the timeline, viewport and inspector |
| `4a41d937` | `403d8612` | 2026-09-27 | feat: scene instancing, document tabs and editable depth guides in Scene Studio |
| `f4fd578f` | `5c7261f2` | 2026-09-27 | fix: place object collision shapes where the legacy bodies were |
| `a3aa9a2c` | `a302a511` | 2026-09-27 | feat: shape-based world areas, shared boss arena leash, and boss links in Scene Studio |
| `e688cef2` | `bef7c5f3` | 2026-09-28 | feat: restore Fatty's leap splash as authored, visible landing zone |
| `8e34a882` | `2d792954` | 2026-09-28 | feat: restore Fatty's leap splash as authored, visible landing zone |
| `d0e93d4c` | `1975da8c` | 2026-09-28 | launch.json |
| `8c4ccafb` | `d89da3fa` | 2026-09-28 | test: align scene checks with authored branch content |
| `da84a18f` | `846750b4` | 2026-09-28 | feat: mushroom-cottage interiors, mushroom house, and Scene Studio authoring tools |
| `eb8a4051` | `dfb4fcf0` | 2026-09-28 | feat: doors link to doors, arriving at the target door's arrival point |
| `f3b13a48` | `c86eb199` | 2026-09-29 | feat: Slimeshire Meadow, a full level-1 redesign with the Verdant Gate |
| `2c88f91e` | `327b10a8` | 2026-09-29 | docs: align agent guide and docs with the current game |
| `4e7f7fd5` | `a76e5ed1` | 2026-09-29 | update road map and improve documentation |
| `5cb7dc8e` | `9d4d04a1` | 2026-09-29 | update road map improve guides |
| `e1daf308` | `81c0ca94` | 2026-09-30 | feat: Workshop restoration, Gulp wheel and puzzles, game feel, gear progression |
| `88484da0` | `022f0910` | 2026-09-30 | feat: enemy territories, sound picks applied, orb-weaver, tearing webs, lighter download |
| `55a5e0fa` | `35e00097` | 2026-09-30 | docs: drop the removed ?sfx switch from audio credits |
| `342ed090` | `70eb8f00` | 2026-09-30 | docs: explain terrain blend math with diagram and playground |
| `23aba522` | `6b3a4343` | 2026-09-30 | feat: simple mouse-and-keyboard controls (roadmap 4.10) |
| `8daa01c0` | `f8affb0e` | 2026-09-30 | Merge remote-tracking branch 'origin/main' |
| `7dbfec35` | `9fa0c2e2` | 2026-09-30 | fix: browser specs and lazy audio voices (from the Playwright-specs worktree) |
| `3bd72f57` | `bd8b7e5c` | 2026-09-30 | fix: scene-conversion ledger covers every content unit (from the scene-conversion worktree) |
| `572f96ce` | `cc067668` | 2026-10-01 | feat: Chapter 2 — Gloop Forest (roadmap 8.3–8.11) |
| `255ee8df` | `1e204ee6` | 2026-10-01 | fix: owner playtest fixes after Chapter 2 (roadmap 4.11) |
| `086d7e2f` | `619c50ef` | 2026-10-01 | fix: second playtest list — ground loot, Mossy's hunt, a webbed Gloop Forest, clearer windows |
| `eb8cecec` | `994aa222` | 2026-10-01 | minnor weapon changes |
| `4d474aea` | `fac504d5` | 2026-10-02 | docs: start the story script (docs/story) |
| `5f15df8e` | `3251562a` | 2026-10-02 | docs: explain terrain blend tile decisions |
| `f10f1256` | `3186de33` | 2026-10-04 | historia work |
| `9cfdce34` | `6d357909` | 2026-10-04 | chore(assets): bring the elevation experiment's art to main |
| `745f8384` | `3d2ea34c` | 2026-10-04 | Merge branch 'chore/elevation-assets': elevation art for the Godot migration |
| `41904a0a` | `81020aa6` | 2026-10-04 | docs: plan the Godot migration and retire MobileVersion |
| `365ba71c` | `fff08080` | 2026-10-04 | feat(godot): trial port - converter, level-1 with player, worm and sword |
| `eac189cd` | `fdd0257b` | 2026-10-04 | chore(godot): enable the Godot AI editor plugin for MCP editor access |
| `faf39ec3` | `8e9ec172` | 2026-10-04 | fix(godot): trial review fixes, Arcade-style mover and a headless test suite |
| `08d14149` | `629e860f` | 2026-10-04 | fix(godot): sword combo uses the hit's own tier (24 per hit), record owner decisions |
| `67bfe406` | `ad893fe2` | 2026-10-04 | docs(assets): images use GPT 2.5 with a transparent background on every request |
| `7657a322` | `cdaea4ee` | 2026-10-05 | feat(godot): three-quarter top-down player slime, page 1, in a Godot-owned scene |
| `6eaf45d2` | `74beeead` | 2026-10-05 | feat(godot): show the weapon only while it swings |
| `b75e2b23` | `a6aae173` | 2026-10-05 | chore(godot): commit the Godot AI editor plugin (4.3.0, MIT) |
| `765436dc` | `7940c9e7` | 2026-10-05 | feat(godot): slime page 2 rolls and keyed sword swings per direction |
| `1aaf78b6` | `02631696` | 2026-10-05 | feat(godot): RunState autoload and area travel through world exits |
| `3da8f77d` | `929f43b8` | 2026-10-05 | feat(godot): port story flags and story variants |
| `d1608e38` | `c7b6c1ce` | 2026-10-05 | feat(godot): animated water surface over water and deep-water tiles |
| `48589ac6` | `297e9684` | 2026-10-05 | chore(godot): editor uids for the story scripts and test |
| `4c5ae718` | `1f1e78d6` | 2026-10-05 | feat(godot): terrain lab with hand-made snow edge tiles and 128 px grounds |
| `95ba75fc` | `3cd51456` | 2026-10-05 | feat(godot): port the Fatty One Eye boss fight and its camp |
| `1b9c41ec` | `4b45751d` | 2026-10-05 | fix(godot): render-domain clips keep running through hit-stops |
| `ad875a3d` | `9f0bd98a` | 2026-10-05 | feat(godot): resource nodes, drops, collectibles and the inventory |
| `d836a267` | `1d1d1901` | 2026-10-05 | feat(godot): converter exports NPC definitions to generated/data |
| `609f276e` | `cd1f9b5b` | 2026-10-05 | feat(godot): interaction: doors, gates, chests, beds, NPC talk |
| `bdc54997` | `70e678f0` | 2026-10-05 | feat(godot): abilities, Gulp forms and the ability puzzles |
| `f29f7704` | `7d3816a8` | 2026-10-05 | fix(godot): ability tweens run their steps in order |
| `c0ea6f09` | `2cd68e6f` | 2026-10-05 | feat(godot): ranged enemies, projectiles, the Orb-Weaver Matron and webs |
| `3e84e9d8` | `ffb68816` | 2026-10-05 | feat(godot): saves in user:// with a recovery autosave |
| `107e0ef2` | `cc62fc2a` | 2026-10-05 | feat(godot): player status effects, web rooting, every enemy camp active |
| `5b325e19` | `c02d773d` | 2026-10-05 | feat(godot): enemy coins and loot piles, respawn at a bed in another world |
| `9df4fd3f` | `4f4edeef` | 2026-10-05 | feat(godot): music director, game shell and the shared UI theme |
| `fae430c2` | `1c9bd7d3` | 2026-10-05 | feat(godot): the Goo Trail passive |
| `13b24b9c` | `b9ae7b71` | 2026-10-05 | chore(godot): register the shell and music autoloads; per-process test saves |
| `c1845d04` | `e2f59bbb` | 2026-10-05 | feat(godot): export recipes, quests, weapon names and item icons; crafting and quest specs |
| `4d57b2f8` | `bfcaf9fd` | 2026-10-05 | feat(godot): the game windows' pause owner, quest events and the RunState API for crafting and quests |
| `a8f4f0b9` | `979db94a` | 2026-10-05 | docs(godot): the abilities, puzzles, statuses, saves, loot and game windows in the architecture and migration status |
| `c674758a` | `80c66b27` | 2026-10-05 | feat(godot): the ability bar on the HUD |
| `7eea142a` | `fa80470e` | 2026-10-05 | feat(godot): Shell.mount_menu for feature windows on the shell's stack |
| `785cf86d` | `f66bc1e5` | 2026-10-05 | feat(godot): save slots window for saving and loading |
| `da2ec3b0` | `63f109de` | 2026-10-05 | fix(godot): a shell window hides the windows it covers |
| `ad650e15` | `b559579b` | 2026-10-05 | feat(godot): first-time control hints |
| `5134a7c0` | `2c09c911` | 2026-10-05 | fix(godot): particle bursts were invisible; dust puff spreads like Phaser's |
| `239b7055` | `9328d6e1` | 2026-10-05 | feat(godot): Gulp form badge beside the timer |
| `31b2c28a` | `972ce10b` | 2026-10-05 | feat(godot): the Gulp quick wheel |
| `28cb5f20` | `2db92026` | 2026-10-05 | docs(godot): spec for the quest journal and the chest window |
| `170dfa5e` | `1a753355` | 2026-10-05 | docs(godot): spec for furniture placement |
| `18d45b4d` | `fa6a73ef` | 2026-10-05 | feat(godot): minimap and world map |
| `2b6c65ac` | `cdc81cf7` | 2026-10-05 | fix(godot): LF line endings for hud.gd's minimap mount lines |
| `fe9c9d86` | `39867dbc` | 2026-10-05 | docs(godot): Fatty can be killed in play; webs root the slime now |
| `efa862ed` | `7e249b7e` | 2026-10-05 | feat(godot): crafting, the bag, the weapon belt and consumables |
| `4c6f2f1f` | `cc0e491a` | 2026-10-05 | feat(godot): quests, NPC talk, the dialogue box and the quest tracker; crafting and the belt wired in |
| `58629298` | `de79dd60` | 2026-10-05 | fix(godot): web key labels without errors; dev launch options skip the title |
| `3e2a105b` | `443a7b59` | 2026-10-05 | feat(godot): no pause menu or map key while placing furniture |
| `2da5532c` | `15f49cd4` | 2026-10-05 | feat(godot): theme variations for the hotbar, belt, dialogue and tracker |
| `db7c973c` | `bb5781eb` | 2026-10-05 | feat(godot): furniture placement; A Place to Work can be finished in play |
| `673a5bd8` | `3b7cfb52` | 2026-10-05 | feat(godot): NPC name tags |
| `f011ca0f` | `6829d415` | 2026-10-05 | test(godot): A Place to Work end to end |
| `f9a2f6da` | `0f01c7a0` | 2026-10-05 | docs(godot): refresh what the migration still lacks |
| `6c372117` | `be6e9f18` | 2026-10-05 | test(godot): Stone Tools' second stage through play |
| `4839f90d` | `857f241e` | 2026-10-05 | test(godot): Worm Trouble counts worm swordsmen defeated in the world |
| `fea3f5f0` | `a1762c11` | 2026-10-05 | test(godot): fix the Worm Trouble test's comment |
| `cc8f0909` | `c1af3555` | 2026-10-05 | docs(godot): quests spec 7.6 reflects what is ported now |
| `cef66a57` | `fe8f55c2` | 2026-10-05 | test(godot): A Tonic for Lili and Snack for the Road through play |
| `383cc1f9` | `d8ed435e` | 2026-10-05 | docs(godot): the Lili quests are verified in play |
| `b6f5fb37` | `30becd01` | 2026-10-05 | test(godot): the forge line of chapter 2 through play |
| `552a1367` | `ccfc2417` | 2026-10-05 | test(godot): A Harder Pick mines gloop-forest's iron through play |
| `96b1e60b` | `fbb750d1` | 2026-10-05 | fix(godot): the title shows Load once the save slots exist |
| `e8a7190f` | `53a562c0` | 2026-10-05 | fix(godot): the title menu hides while a shell window is open |
| `c7fd7cbb` | `04cfb780` | 2026-10-05 | feat(godot): the quest journal and the chest window |
| `8011f57a` | `686b6262` | 2026-10-05 | test(godot): Slime Basics finished with the player's own keys |
| `7c5b1096` | `3923df1b` | 2026-10-05 | test(godot): Beyond the Verdant Gate's weavers and fangs through play |
| `40b48b8f` | `216f6810` | 2026-10-05 | docs(godot): interaction interim choice I2 is resolved by the dialogue box |
| `dcabdf66` | `97c56df0` | 2026-10-05 | fix(godot): HUD views follow a load in a running game; slots without the run's sections are unreadable |
| `7ab246f5` | `135ec11a` | 2026-10-05 | feat(godot): reduce motion softens the slime's squash and stretch |
| `338ad583` | `f58361e0` | 2026-10-05 | fix(godot): arrow keys named in words; document the font's missing symbols |
| `be912680` | `52938e1a` | 2026-10-05 | fix(godot): no missing-glyph boxes in the web build's dialogue, tracker and crafting |
| `3ef8fb31` | `5cc5cec3` | 2026-10-05 | docs(godot): point the theme's symbol note at game/ui/glyphs.gd |
| `2fc4a757` | `dfbc3fca` | 2026-10-05 | test(godot): Chapter 1's main line in order through the real givers |
| `a6e38e3f` | `09104c6b` | 2026-10-05 | docs(godot): the automated Chapter 1 run is noted in the migration status |
| `e21507b9` | `4cfce5fb` | 2026-10-05 | feat(godot): defeated bosses stay 2 s and fade out |
| `c980e559` | `d57a6947` | 2026-10-05 | feat(godot): the theme builder takes font paths; boss camp guards a freed player |
| `886d8724` | `4df4137a` | 2026-10-05 | feat(godot): the minimap draws a map of the world's ground |
| `1e533a9a` | `12b382c8` | 2026-10-05 | feat(godot): a new run starts empty-handed; the playground has every weapon; release web build without dev content |
| `66d0b5a6` | `2131ab55` | 2026-10-05 | feat(godot): Heavy and Sticky skins as a shader; fix sprites drawn darker than their art |
| `7497d937` | `e5bff11c` | 2026-10-05 | chore(godot): form_skin.gdshader uid |
| `75b5529d` | `645da2b4` | 2026-10-05 | feat(godot): the abilities draw the top-down slime (keyed hop, slam, teleport, lash, eat, knockback) |
| `a43a1977` | `296a985c` | 2026-10-05 | feat(godot): hand-made terrain edges for every ground, water shores included |
| `85ac1078` | `8cefc030` | 2026-10-05 | docs(godot): terrain edges cost measured on the web build |
| `8fb61c13` | `bbba5f16` | 2026-10-05 | feat(godot): a filmed Stretch Lash; the lash tendril finally shows |
| `bc4ff11f` | `957a79f0` | 2026-10-05 | test(godot): cue checks start from silence (fix a flaky SelectSfx check) |
| `35b3b12f` | `039bf9dc` | 2026-10-05 | docs: run tests only when the owner asks or after a big breaking change |
| `8543b182` | `255d8915` | 2026-10-05 | feat(godot): the UI font is Source Sans 3, with Noto Sans Symbols 2 for symbols |
| `f51df673` | `3cfa3609` | 2026-10-05 | feat(godot): Phaser's UI symbols are back (✓ ▸ ✕ ★ ◆ ▶ ○, arrow key names) |
| `b7fb9930` | `555463e6` | 2026-10-05 | chore(godot): editor re-save of the UI theme and the terrain lab (uids only) |
| `63111043` | `1c23c84f` | 2026-10-05 | feat(godot): the playground knows every ability and carries Gulp materials |
| `8223f6f4` | `27e652b9` | 2026-10-05 | feat(godot): no old player art left (top-down doze, sleep and defeat) |
| `8f4e301c` | `d81d5995` | 2026-10-05 | test(godot): sound checks ask whether a cue started, not whether it still plays |
| `2cf60f22` | `6859a197` | 2026-10-05 | chore(godot): terrain lab re-save (tile set uid) |
| `d66c17bb` | `ef222645` | 2026-10-05 | feat(godot): true front and back rolls for the slime's down and up dodge |
| `1c1443d2` | `c9730df4` | 2026-10-05 | feat(godot): every scene is Godot's (Phase 1); scene JSON is frozen |
| `809fac10` | `40417a54` | 2026-10-05 | feat(godot): the game data is Godot's; the converter is gone |
| `0c787944` | `e57d2e2a` | 2026-10-05 | docs(godot): the Gulp quick wheel is ported |
| `b1672491` | `9ebfcd80` | 2026-10-05 | feat: new resource pile art; walk-over pickups bounce; asset/Originals is sources only |
| `5d4a2f0e` | `f9384e25` | 2026-10-05 | feat(godot): the big stone mine draws the mossy stone heap, not the stone pickup |
| `67eec0fa` | `7053de88` | 2026-10-05 | docs(godot): the cutover checklist, waiting for the owner's Chapter 1 playthrough |
| `8edbe320` | `ab4c4c83` | 2026-10-05 | chore(godot): verify_scenes.gd uid |
| `89ff8ddd` | `18e27907` | 2026-10-05 | chore: drop the elevation art (owner decision; it did not make it) |
| `c2b2d745` | `ccaaacd8` | 2026-10-05 | feat(godot): terrain layers lab, the lab's map on Godot's own Terrains |
| `5afc897b` | `09d83f3e` | 2026-10-05 | feat(godot): the game art lives in the Godot project (cutover step 1) |
| `d7aa64c0` | `683bd066` | 2026-10-05 | chore: art tools write to godot/asset; Phaser checks, tests and scene tools removed (cutover step 2) |
| `fa35ecde` | `bb189e8b` | 2026-10-05 | feat: remove the Phaser app; the game is Godot-only (cutover step 3) |
| `4bfc632d` | `09446271` | 2026-10-05 | docs: the repository is Godot-only; Phaser-era docs archived (cutover step 4) |
| `97ccfba2` | `f63a454b` | 2026-10-05 | feat(godot): terrain layers lab on the owner's tagging; dual grid vs Godot Terrains measured |
| `b15a0fc3` | `1a30e868` | 2026-10-06 | feat(godot): wade in shallow water, swim in deep water as the Frog Gulp form |
| `27780cf2` | `faac2889` | 2026-10-06 | feat(godot): elevation — hills, holes, stairs on every side and fences along rims |
| `812bc9f0` | `cbaf481b` | 2026-10-06 | feat(godot): steps, water and the silent actions get sounds (Sound Picker rounds 3 and 4) |
| `88499375` | `5528d9c4` | 2026-10-06 | chore(godot): editor re-saves and a 1440x1080 viewport |
| `ab4cc80f` | `7b13b431` | 2026-10-06 | chore(audio): keep the Sound Picker round 3 and 4 working files |
| `46606fdb` | `21d6a2a2` | 2026-10-06 | Merge branch 'feat/godot-migration': the game is Godot-only |
| `0fdde6b3` | `c1a9d3e7` | 2026-10-06 | worm updates |
| `a7993b91` | `e3a6cd08` | 2026-10-06 | Merge pull request #1 from jason840917gmail/feat/godot-migration |
| `608df3ef` | `3bfe2cd9` | 2026-10-06 | Merge branch 'main' of https://github.com/jason840917gmail/Slime_Isa |
| `3c3fa661` | `c8872408` | 2026-10-06 | 5 diferent controls |
| `1fa20841` | `1b8d89cf` | 2026-10-07 | World editor, and defining some world rules , view port change |
| `f864d29f` | `552dbe0a` | 2026-10-09 | feat(godot): essence Gulp, Zelda Roll, Clod Stomper, Tom, the ceremony and round-5 sounds |
| `43d2ec54` | `fcd444ac` | 2026-10-11 | feat(godot): ground at 128 px, editor mounts the world's drawing |
| `ded3c904` | `e8702602` | 2026-10-11 | feat(godot): hand-painted cliff experiments (tile sheet, kits, cliff builder, shape painter) |
| `3aeb1863` | `79ffb016` | 2026-10-11 | feat(godot): painted elevation, storybook cliff art cut from the H painting |
| `14aa891a` | `edb4d420` | 2026-10-11 | feat(godot): manual fixed-cell and rectangular cliff prototypes |
| `d00ded0b` | `a2fad509` | 2026-10-11 | feat(godot): elevation tops painted above the map |
| `3ca7d8e8` | `fd82019d` | 2026-10-11 | feat(godot): forest layer, tree walls painted like a terrain |
| `8096be32` | `b17ca6f8` | 2026-10-11 | chore(level-1): grouped scene tree, forest layer, elevation painting |
| `be1df2c1` | `bd1dd073` | 2026-10-11 | feat(godot): exits can arrive at a named marker |
| `127e2b1f` | `a9f90b8b` | 2026-10-11 | feat(world-map): layout file in the game, Gloop Forest east, sketch tool layout tools |
| `15b71fd6` | `dcb5659b` | 2026-10-11 | feat(world-map): placeholder region worlds built from the sketch |
| `99f36d63` | `d690c94d` | 2026-10-11 | feat(world-map): editor world atlas, the whole overworld in one scene |
| `1ef2ff9a` | `e34c3b65` | 2026-10-11 | feat(world-map): the in-game world map draws the layout |
| `858c8a78` | `bee98386` | 2026-10-11 | manual cliff sprites on work |
| `b3960565` | `d37743d5` | 2026-10-12 | feat(elevation): stairs rework, open cliffs, cliff experiments removed |
| `17c0df1a` | `5f367317` | 2026-10-12 | feat(world): bridge decks over deep water, level-1 world edits |
| `6db8b318` | `14e43054` | 2026-10-12 | feat(trees): top-down tree art for every region; chunk worlds |
| `7e465995` | `e49cbc02` | 2026-10-13 | fix(trees): sway no longer resets as the view moves; no open spots in walls |
| `37ca87cf` | `2100fbc5` | 2026-10-13 | feat(props): scenery painted from palettes on prop layers |
| `53e36b21` | `abc572c5` | 2026-10-14 | feat(world): chunk worlds for every region but level-1, prop layers, fieldstone walls, cliff sides |
| `8a8f3d53` | `cbcc99a3` | 2026-10-14 | feat(world): cut level-1 into chunk worlds; tests moved to chunks |
| `8fa2dd30` | `7b6f63b5` | 2026-10-14 | feat(hud): console sits on a solid full-width band |
| `38e8868d` | `202c7e88` | 2026-10-14 | docs(elevation): side walls are the cliff look; front-only look deprecated |
| `090d12a7` | `432ab618` | 2026-10-14 | feat(props): level-1 props movable as nodes; Scenery dock sizes |
| `83991bba` | `46d3623c` | 2026-10-14 | feat(world): Zelda-style screen scroll between chunks |
| `02bddf04` | `b2679f45` | 2026-10-14 | fix(props): palette pictures left out of exports; dock sizes work |
| `e97c2a7f` | `3bcd6cf4` | 2026-10-14 | feat(elevation): Zelda-like stairs walk, stairs kept off for enemies |
| `90fe7786` | `ef8e809c` | 2026-10-14 | feat(world): level-1 c5 scenery edits (camp, rocks, webs as nodes) |
| `d3fa2a86` | `216dd6e8` | 2026-10-14 | docs(elevation): archive the feat/elevation-levels design before deleting the branch |
| `1a777411` | `c5b57a4a` | 2026-10-14 | fix(ui): theme icons as files, so editor re-saves keep them |
| `697979ce` | `d34f007c` | 2026-10-15 | feat(shapes): body-shape weapons, Goo Bomb, Lantern, heavy puzzles, Zelda doors |
| `215590d5` | `05adb415` | 2026-10-15 | Merge branch 'main' into exp/body-shapes |
| `854a3195` | `de583706` | 2026-10-15 | test: update the suite for chunk worlds and push doors; fix chunk data, music carry-on, chunk area names |
| `8d65fa12` | `8a6c911e` | 2026-10-15 | fix(world): the copied cliff goo heart gets its own id and moves into level-1-d4 |
| `73af49c4` | `f7408783` | 2026-10-15 | docs(story): rework the direction around skins, shapes and abilities |
| `9d6b1cdb` | `f72530a6` | 2026-10-16 | docs(story): skins, Release 1's eight powers, the prologue and the bestiary |
| `7973880e` | `d6dbaf81` | 2026-10-17 | feat: the 33-enemy bestiary, the prologue, placed enemies, line-up aim and Gulp feel |
| `53e5df74` | `cca92105` | 2026-10-17 | feat: the three Release 1 dungeons, the dungeon kit, side walls everywhere, clean-out wave 1 |
| `48a7b514` | `555fb462` | 2026-10-17 | feat: the Pearl inside each dungeon, the skins, and Chapter 1's maps with the Lair on a D5 hill |
| `2a04028b` | `694d643e` | 2026-10-17 | wip: snapshot of 2026-10-17's sessions (rooms-and-doors part rejected, to revert) |
| `442dd8b2` | `b504ae36` | 2026-10-18 | fix: unified fences, C4's props as grouped nodes, the first bell, one safe spot for D5's moat |
| `0a6b9954` | `05e2b5e1` | 2026-10-19 | feat: Fatty's Lair as one world per room, bevel interior walls, dungeon music, painted level collision |
| `c687e988` | `c8a8b541` | 2026-10-19 | docs: the review prompt for checking the 2026-10-17..19 work |
| `644d09d3` | `8d7527b6` | 2026-10-19 | docs: the 2026-10-19 session summary for the next agent; ignore the agents' output folders |
| `1d4d756b` | `c8d4df21` | 2026-10-19 | fix: painted layers keep doors and gates the designer set up; flat-world fences collide; one banner for the Lair |
| `18182054` | `0fdb0e89` | 2026-10-19 | feat: Heavy grab poses, key-named skin texts and touch hint; Lair review fixes and other sessions' work |
| `dabd9e8e` | `52af5658` | 2026-10-19 | feat: real walk cycles for every legged bestiary enemy |
| `b4ca2a64` | `13a70483` | 2026-10-20 | feat: Lair caves in after Fatty; its come-back secrets move into Slimeshire |
| `606ffbcb` | `e00bd258` | 2026-10-20 | feat: keys-only chest, bag and interact badge need no mouse |
| `e73ad413` | `529adb91` | 2026-10-20 | chore: other sessions' pending work (dungeon decor, darkness, lantern, scenery dock, Slimeshire rooms) |
| `7f5d62df` | `87e6fbbd` | 2026-10-20 | feat: throw-combat experiment (the Gulp is the whole fight) |
| `eaf72af4` | `9e27a958` | 2026-10-22 | fix: Scenery dock hint on one line so the editor bottom panel stays visible |
| `f78f9c8e` | `3c7b8226` | 2026-10-22 | fix: Scenery dock hint on one line so the editor bottom panel stays visible |
| `6197823d` | `691887cd` | 2026-10-22 | fix: the throw yard checks a taken thing is still valid before testing its type |
| `ffe696ae` | `6d6ce8a3` | 2026-10-22 | fix: the shapes testbed's pen checks an enemy is still valid before testing its type |
| `8d899923` | `6716e04b` | 2026-10-22 | fix: check is_instance_valid before 'is' everywhere |
| `7cbe368a` | `67153e3b` | 2026-10-22 | Merge branch 'main' into exp/throw-combat |
| `e69bbd4c` | `2e27dc5b` | 2026-10-22 | feat: keys-only throw layout: A Gulp, S Roll, D ability |
| `c3325139` | `00626ada` | 2026-10-22 | chore: rooms entered from a chunk live in rooms/<chunk>/ |
| `a82dfb0e` | `272fb9de` | 2026-10-22 | feat: Lair throwables, light liftables, Squints take throws, bats wake by day |
| `e0e730cd` | `70f7d68e` | 2026-10-23 | feat: Glint Bats are awake while their room is dark, asleep once it is fully lit |
| `8d557e25` | `ca0cf6ee` | 2026-10-23 | Merge branch 'main' into exp/throw-combat |
| `21aa2adb` | `96a3e381` | 2026-10-23 | docs: handover for the throw-combat workspace |
| `84ee5d69` | `263d80f5` | 2026-10-23 | chore: move the playground caves and dev worlds out of worlds/ |
| `08346fe4` | `65eb5ecf` | 2026-10-23 | fix: find layers by class, not by node name |
| `46b8a32e` | `7d172ec5` | 2026-10-23 | feat: Fatty's random mock; a Heavy Roll knocks him down only then |
| `9ea301c6` | `bc475de3` | 2026-10-24 | feat: stair door replaces the stair hatch and ladder |
| `705964cf` | `dd7ce31b` | 2026-10-24 | fix: the gatehouse winch is gone; the outer gate drops again each time |
| `9507c9e6` | `85f015fd` | 2026-10-24 | chore: commit the remaining pending work |
| `2cc2bbb9` | `fcef57e7` | 2026-10-28 | feat: lair-ledge edge fence, dungeon map floors, room fight in R4, heart quarters |
| `64259c9d` | `8e223de2` | 2026-10-28 | fix: jumps by painted walls follow what collides |
| `674b5639` | `66a53e5e` | 2026-10-31 | feat: earth bank along deep water |
| `e3d128db` | `76c61b9d` | 2026-11-01 | feat: crossings and arrivals, closed chunk lines in Gloop, floor trims, throw knockback |
| `95470bb8` | `e6ca2118` | 2026-11-01 | feat: atlas signs off by default, a West village – Slimeshire link with no crossing removed |
| `3e8ed765` | `3b008561` | 2026-11-01 | docs: throw combat is on main; drop the branch from docs and comments |
| `034d7e1f` | `6c319935` | 2026-11-05 | feat: tile compare lab, paused (Zelda tile set, our stone and dirt tiles) |
| `b75aedca` | `ee82b062` | 2026-11-07 | feat: painted stairs in six art sets, walls per ground, fixed ledges; rejected art and code removed |
| `c5ea4a13` | `2a7653b0` | 2026-11-12 | feat: sky floor, cliff joints that fold, foot shadows laid once |
| `c045ec05` | `74a28323` | 2026-11-12 | feat: house doors open again, West town, edit areas, the elevation maze |
| `4dbd9be6` | `9e6e0649` | 2026-11-12 | docs: before/after picture of the ledge joints in desert-b7 |
| `382f3177` | `abc2ad24` | 2026-11-13 | feat: village and interior loops, baths, the slime's home moved, door walk, two sound rounds |
| `bb10a62a` | `bfc161db` | 2026-11-13 | feat: sky floor feet and side walls, cave animals, climbing vines and balconies, Gloomling in the dark |
| `937560a0` | `ebd8fbba` | 2026-11-16 | feat: balconies by wall style, wall doors and pictures, climbing monsters |
| `f23fc90e` | `7e165ec8` | 2026-11-17 | feat: throw feel rework - Zelda-pot hit, knockback, rebound, enemies as ammo, hazards |
| `71d19772` | `0d44a241` | 2026-11-17 | docs(story): the owner's 2026-11-17 answers after the docs review |
| `fb0103c3` | `1a5b7c82` | 2026-11-18 | feat: Burr's house in Slimeshire's C4, with his room and young Burr |
| `7f73fa34` | `d7937ab8` | 2026-11-18 | feat(walls): picket fence, the WallLayer's third style |
| `74c90c01` | `045e520a` | 2026-11-18 | fix(atlas): Edit area round-trips chunks whose nodes lack a unique_id |
| `9aa40c01` | `76541ab5` | 2026-11-18 | chore(glimmerhill): B5 dressing, snail house collision |
| `3d1ea5a5` | `0599ef36` | 2026-11-18 | chore: walk speed 180, throw-hazard rules confirmed, rebaked caches |
| `9023917e` | `7dd9515a` | 2026-11-20 | feat(interiors): cottage and mushroom walls, round rooms, every village house room converted |
| `55d7787f` | `9b2f99af` | 2026-11-21 | feat(release-1): story playable end to end, Pip's bow rune, Roll fragments, canopy walls, Caverns Spiral |
| `5260d6e5` | `67f18312` | 2026-11-21 | feat: border woods become canopy walls; the Pearl's card before the roar |
| `bffd9920` | `d1f1b019` | 2026-11-21 | feat(fatty): rework the Lair fight around his eye and the falling dirt |
| `5e8981e1` | `1094d04d` | 2026-11-23 | feat: Jelly Bouncer (row 39), arrows deal 20; Worm Bulwark, Carnivore Plant, River Roads, sound rounds 13-14 |
| `850c98eb` | `65a7954b` | 2026-11-25 | feat(dungeons): mechanisms, both boss fights in their labs, health and damage rebalance |
| `d620e774` | `6de12ff5` | 2026-11-25 | feat(dungeons): the Weaver Hollow rebuilt one world per room, and switched over |
