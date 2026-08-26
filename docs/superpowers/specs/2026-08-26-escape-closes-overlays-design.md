# Escape Closes Open Overlays

**Status: approved design; implementation has not started.**

## Goal

Make Escape a consistent, scene-wide close action for every open gameplay
modal or dashboard. One press closes only the topmost open surface. A second
press may close the next surface if overlays are nested. The behavior must
extend to future Phaser or DOM-backed modals without requiring each new surface
to install its own global Escape listener.

## Current state

The gameplay UI currently has independent Escape handling in
`InventoryUI`, `CraftingUI`, `WorldMapUI`, and `QuestJournal`. `LevelUpModal`
does not close until a perk is selected. `ChatUI` uses a browser document
capture listener because its input is a DOM element. `WorldScene` also owns
the pause-source set that freezes simulation while a gameplay overlay is open.

The current open-hotkey guards prevent most surfaces from overlapping, but the
architecture does not provide a reusable ordering rule for nested overlays or
future dashboards. Individual listeners also make it possible for two surfaces
to respond to one Escape press.

## Design

### Modal stack ownership

Add a small UI-only `ModalStack` service under `src/game/ui/`. It has no
knowledge of a particular modal class or of `WorldScene`.

Each closable surface registers a stable ID and two callbacks:

```ts
interface ModalRegistration {
  isOpen: () => boolean;
  close: () => void;
}
```

`register` returns a token-scoped `ModalHandle` with `open()`, `close()`, and
`unregister()` methods. The handle's methods become no-ops after that handle
is unregistered or after the stack is destroyed; they can never operate on a
later registration that reuses the same ID.

The gameplay IDs are canonical and unique: `inventory`, `crafting`,
`world-map`, `quest-journal`, `level-up`, and `chat`. Registration rejects a
duplicate ID while the original registration is still live. The handle's
`unregister()` is idempotent and removes only the registration that created it;
calling an old handle cannot unregister or operate on a newer registration with
the same ID.

The implementation keeps a private registration token for each ID. The handle
removes the entry only when its token is still the registered token,
and removes all stack occurrences for that token. A new registration may reuse
an ID only after the old handle has been unregistered.

The handle's `open()` operation always removes any existing occurrence of its
registration before appending one occurrence at the top. This is the invariant
that prevents duplicate entries even when a surface opens itself during a
callback.

The service exposes:

- `register(id, registration): ModalHandle` — adds a surface and returns its
  token-scoped lifecycle handle.
- `ModalHandle.open()` — removes the ID from its current stack position and
  appends it as the topmost surface.
- `ModalHandle.close()` — removes the handle's registration from the stack
  without invoking the surface.
- `hasActiveSurface(): boolean` — prunes stale entries and reports whether at
  least one registered surface is currently open.
- `closeTopmost(): boolean` — removes stale/closed entries as needed, invokes
  the latest active surface's `close`, and returns whether a surface closed.
- `destroy()` — clears registrations and removes the global keyboard listener.

`register` after `destroy` throws because it indicates a scene-lifetime bug.
Handle methods and repeated `destroy` calls after `destroy` are safe no-ops;
`hasActiveSurface()` and `closeTopmost()` return `false` after destruction.
Unregistering removes every stack occurrence for that registration and is safe
during teardown.

The stack removes the entry before invoking `close`, so a close callback that
causes a rerender or nested close cannot leave a duplicate stack entry. Close
callbacks are synchronous invocations, although they may start an asynchronous
visual fade. A surface's `isOpen` callback is authoritative; stale entries are
skipped rather than invoking a destroyed surface. The re-entrancy guard is
released in a `finally` path. If a close callback throws, the error propagates
after the guard is released; if the same registration is still live and still
open, all occurrences of that registration are removed and exactly one entry
is restored at the top of the current stack so a later Escape can retry it.
Any surface opened as a side effect remains below that restored entry.

### Keyboard routing

`WorldScene` creates one `ModalStack` for its UI lifetime. The stack listens to
the browser document in capture phase for `event.key === 'Escape'`. When an
active surface exists it prevents the browser default and stops propagation,
then closes only the topmost surface. An active surface is the last stack entry
whose registration still exists and whose `isOpen()` returns true; stale entries
are pruned before deciding whether to consume the event. If no active surface
exists, the event is left untouched. This captures Escape consistently when
focus is in a Phaser canvas or in a DOM input such as chat. Non-Escape keys
continue to their existing handlers.

The document-like target is injected into the constructor through the minimal
interface with `addEventListener('keydown', handler, { capture: true })` and
the matching `removeEventListener('keydown', handler, { capture: true })`;
production construction passes `document`. Tests pass a fake target and
dispatch a `KeyboardEvent`-shaped object. The handler calls
`closeTopmost()` once. It calls `preventDefault()` and `stopPropagation()` only
when that call returns true, and never calls `stopImmediatePropagation()`.

The listener is disposed during scene shutdown through the existing scene
cleanup path. No UI surface creates its own Escape key or document listener.
Closing the DOM-backed chat input keeps ChatUI's existing `blur()` behavior; no
new focus target is forced in this slice, so focus falls back to the browser's
normal document behavior after the input is hidden.

### Surface integration

The current gameplay surfaces receive the stack through their context and
register themselves during construction:

- inventory
- crafting
- world map
- quest journal
- level-up
- chat

Each surface stores its `ModalHandle`, calls `handle.open()` after it becomes
visible, and calls `handle.close()` during every normal close path. Refreshes
that destroy and rebuild the visual container keep the surface open and
therefore preserve its stack position. Destroy paths call
`handle.unregister()` and destroy any remaining visuals.

For an animated close, `handle.close()` takes the surface out of the Escape
stack immediately when the close begins. The surface may remain visually
present while its fade completes, but it is not an active surface and must not
be reopened until its close transition has finished.

Integration removes the existing individual Escape listeners from
`InventoryUI`, `CraftingUI`, `WorldMapUI`, and `QuestJournal`, removes the
per-modal Escape key path from `LevelUpModal`, and removes ChatUI's document
capture listener. The shared stack is the only Escape listener for the gameplay
scene.

The scene shutdown order is: destroy/unregister all surfaces, clear their
pause-source callbacks through their normal cleanup paths, then call
`ModalStack.destroy()`. The stack itself does not own or infer simulation pause
state.

The existing `WorldScene` pause-source callbacks remain the authority for
simulation pause state. Closing one surface clears only that surface's pause
source; other open surfaces, if any, keep simulation paused.

### Level-up behavior

Escape is allowed to dismiss the level-up surface without spending a skill
point. The rolled choices remain stored in `LevelUpModal` as a pending choice.
The modal exposes a public reopen path for the current/future player action
dashboard to invoke, and the current game binds that path to `P` when no other
surface is open. Reopening reuses the stored choices rather than rolling a
different set. Reopening while already open is a no-op; reopening with no
pending choices returns false. A second `level.up` event while a pending choice
exists is ignored so it cannot overwrite the pending roll. Picking a perk
clears the pending choices through the existing spend flow. Escape emits
`levelup.modal.close` with `pickedPerkId: null`; selecting a perk continues to
emit the selected ID.

The public method is `reopenPending(): boolean`: it returns true only when it
builds the pending-choice surface and false when the surface is already open or
there are no pending choices. The `P` hotkey calls it only when
`modalStack.hasActiveSurface()` is false. A `level.up` event with no pending
choices creates and
opens a new roll; an event while the surface is open or while a pending choice
is dismissed is ignored and does not replace the stored choices.

This slice does not add a second gameplay progression system or persist a
pending modal choice in save data. The existing in-memory level-up state lasts
for the active scene.

### Future surfaces

Future modals and dashboards that should respond to Escape implement the same
registration contract and call `open`/`close` at their visibility boundary.
They do not edit `WorldScene`'s Escape handler or add another global listener.
Nested dialogs naturally become topmost when opened, and closing a child
returns Escape handling to its parent.

## Error handling and cleanup

- Registering an ID twice is an error; this catches accidental duplicate
  ownership during scene setup.
- Calls made through an unregistered or destroyed `ModalHandle` are no-ops;
  they cannot affect a later registration that reuses the same ID.
- Stale stack entries are skipped when `isOpen()` is false.
- Close callbacks are invoked at most once per Escape press.
- While `closeTopmost` is invoking a callback, a re-entrant
  `closeTopmost` call returns false. If the callback opens another surface, that
  new surface remains topmost for the next Escape press; the current press
  never loops to close it.
- Scene shutdown unregisters all surfaces and removes the document listener.
- Chat's DOM input remains focusable and keeps its existing Enter, blur, and
  message behavior; only Escape routing moves to the shared stack.

## Roadmap change

Add a cross-cutting player-experience item before UX.1 in
`docs/GAME_ROADMAP.md`:

### [ ] UX.0 — Make Escape close the topmost UI surface

- Build: add a shared modal stack and route Escape through it for inventory,
  crafting, world map, quest journal, level-up, chat, and future dashboards.
- Player proof: pressing Escape closes the currently active surface only;
  nested dialogs close from the top down, and a dismissed level-up choice can
  be reopened without losing the pending perk selection.
- Done when: no current UI installs an independent Escape listener, all current
  surfaces clean up their registrations, pause state remains correct, and
  keyboard/DOM-focused playtests plus project verification pass.

## Verification

Add focused tests for the stack service using an injected document-like event
target, covering registration, LIFO ordering, stale entries, duplicate IDs,
idempotent unregister/re-registration, post-destroy calls, one-close-per-press,
re-entrant callbacks, throwing callbacks with unique top-of-stack restoration,
and Escape default-prevention/propagation behavior. Also cover that `P` does
nothing while another surface is active and that `reopenPending()` returns
false when already open or when no pending choices exist.
Add one integration-level test or harness covering all six registrations,
legacy-listener removal, scene shutdown cleanup, and level-up `P` reopening.
Manually verify in the running game:

1. Escape closes inventory, crafting, map, journal, chat, and level-up.
2. Opening a nested surface then pressing Escape closes the child first and the
   parent on the next press.
3. Dismissing level-up leaves the skill point and choices pending; reopening
   with `P` shows the same choices, while a second level-up event does not
   replace them.
4. Closing a surface restores simulation only when no other pause source is
   active.
5. Closing chat hides its input and leaves no stale focus-dependent Escape
   handler.
6. Scene reload/shutdown leaves no active document listener or orphaned UI.

Run `pnpm typecheck`, `pnpm build`, and `pnpm check` before completion.
