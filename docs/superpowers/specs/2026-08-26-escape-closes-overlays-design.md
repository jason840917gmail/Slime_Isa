# Escape Closes Open Overlays

**Status: correction design revised after user review; re-review pending.**

## Goal

Make Escape a consistent, game-wide close action for every open gameplay or
development modal/dashboard. One press closes only the topmost open surface. A
second press may close the next surface if overlays are nested. The behavior
must extend to future Phaser or DOM-backed surfaces without requiring each new
surface to install its own global Escape listener.

## Current state

The shared, Phaser-free `ModalStack` is already implemented. It owns one
capture-phase document listener, token-scoped registrations, LIFO ordering,
stale-entry pruning, re-entrancy protection, and throw-to-top recovery.
Inventory, crafting, world map, quest journal, level-up, chat, shop, and the
development persistence dialog already register canonical IDs. Legacy
per-surface Escape listeners have already been removed, and level-up dismissal
plus `P` reopening are implemented.

The correction starts from two persistence defects in the current code:

- `bindPersistenceModal` registers `persistence` on every open, but a successful
  close calls only `handle.close()` and never `unregister()`. A second Save,
  Load, or Reset opening therefore throws the duplicate-ID error.
- `ModalStack.closeTopmost()` currently pops before calling `close`. Persistence
  returns early while `state.busy` is true, so Escape removes the stack entry
  while leaving the DOM dialog open. A failed asynchronous operation then leaves
  a visible dialog that Escape can no longer reach.

The current integration test proves most wiring with source regex checks. It
does not behaviorally cover persistence reopen/busy lifecycles,
`reopenPending()` eligibility, the `P`-while-blocked rule, or cleanup.

## Design

### Modal stack ownership

Keep the existing UI-only `ModalStack` under `src/game/ui/`. It remains unaware
of persistence, Phaser modal classes, and `WorldScene`.

Each closable surface uses this registration contract:

```ts
interface ModalRegistration {
  isOpen: () => boolean;
  canClose?: () => boolean;
  close: () => void;
}
```

`register` returns a token-scoped `ModalHandle` with `open()`, `close()`, and
`unregister()` methods. The handle's methods become no-ops after that handle
is unregistered or after the stack is destroyed; they can never operate on a
later registration that reuses the same ID.

The current IDs are canonical and unique: `inventory`, `crafting`,
`world-map`, `quest-journal`, `level-up`, `chat`, `shop`, and `persistence`.
Registration rejects a duplicate ID while the original registration is still
live. The handle's
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
  the latest active surface's `close` when allowed, and returns whether an
  active surface owned the close request.
- `destroy()` — clears registrations and removes the global keyboard listener.

`register` after `destroy` throws because it indicates a scene-lifetime bug.
Handle methods and repeated `destroy` calls after `destroy` are safe no-ops;
`hasActiveSurface()` and `closeTopmost()` return `false` after destruction.
Unregistering removes every stack occurrence for that registration and is safe
during teardown.

Before removing an entry, the stack calls its optional `canClose()` guard. A
missing guard means closable. When the guard returns false, `closeTopmost()`
returns true without removing the entry or invoking `close`; the Escape event
is consumed, but otherwise ignored, and the locked surface remains topmost.
This prevents the request from reaching an underlying dashboard and is the
required behavior for persistence operations while Save, Load, or Reset is busy.

The boolean returned by `closeTopmost()` means **consume this Escape request**.
It does not mean that the surface closed. It returns true for both an accepted
close and a guarded refusal, and false only when there is no active surface or
the stack cannot process a re-entrant request.

After the guard accepts, the stack removes the entry before invoking `close`,
so a close callback that causes a rerender or nested close cannot leave a
duplicate stack entry. Close callbacks are synchronous invocations, although
they may start an asynchronous
visual fade. A surface's `isOpen` callback is authoritative; stale entries are
skipped rather than invoking a destroyed surface. The re-entrancy guard is
released in a `finally` path. If a close callback throws, the error propagates
after the guard is released; if the same registration is still live and still
open, all occurrences of that registration are removed and exactly one entry
is restored at the top of the current stack so a later Escape can retry it.
Any surface opened as a side effect remains below that restored entry.

### Keyboard routing

`createGame` creates one `ModalStack` for the game lifetime, puts it in the
Phaser game registry, and passes the same instance to `WorldScene` and the
development panel. The stack listens to the browser document in capture phase
for `event.key === 'Escape'`. It routes the request only to the topmost active
surface. If that surface accepts, it closes; if `canClose()` refuses, it remains
open and topmost. Both outcomes consume the Escape event so nothing underneath
responds.
An active surface is the last stack entry whose registration still exists and
whose `isOpen()` returns true; stale entries are pruned before deciding whether
to consume the event. If no active surface exists, the event is left untouched.
This captures Escape consistently when focus is in a Phaser canvas or in a DOM
input such as chat or a persistence form. Non-Escape keys continue to their
existing handlers.

The document-like target is injected into the constructor through the minimal
interface with `addEventListener('keydown', handler, { capture: true })` and
the matching `removeEventListener('keydown', handler, { capture: true })`;
production construction passes `document`. Tests pass a fake target and
dispatch a `KeyboardEvent`-shaped object. The handler calls
`closeTopmost()` once. It calls `preventDefault()` and `stopPropagation()` only
when that call returns true, and never calls `stopImmediatePropagation()`.

The listener is disposed when the Phaser game is destroyed. Gameplay surfaces
unregister during scene area reload/teardown, while the shared stack remains
available to the persistent development panel. No UI surface creates its own
Escape key or document listener.
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
- shop

The development persistence dialog registers itself when opened as
`persistence`, using the same stack as the game scene. This keeps DOM dialogs
and Phaser surfaces in one true LIFO order even if they overlap. Each dialog
opening owns one transient registration through a new exported production
helper in `src/game/ui/TransientModalSession.ts`:

```ts
interface TransientModalSession {
  isOpen(): boolean;
  requestClose(): boolean;
}

function createTransientModalSession(options: {
  modalStack: ModalStack;
  id: string;
  canClose: () => boolean;
  onClosed: () => void;
}): TransientModalSession;
```

The helper registers and opens immediately. `requestClose()` evaluates the
same injected `canClose` function used by the stack registration. A refusal
returns false without calling `handle.close()`, `unregister()`, or `onClosed`.
An accepted request marks the session closed, calls `unregister()` exactly once,
then calls `onClosed()` to emit the pause event, remove the DOM node, and restore
focus. Repeated accepted close requests are safe no-ops.

`bindPersistenceModal` defines one shared predicate,
`const canClose = () => !state.busy`, and passes it to the session. Escape,
Cancel, backdrop, and other close paths all call `session.requestClose()`; none
duplicates a separate busy check. This single source of truth prevents the DOM
and stack lifecycles from diverging. Once the operation becomes idle, the same
entry can close normally. The design does not add replacement or queueing for a
second persistence open: attempting to open another while one is live continues
to fail through the existing duplicate-ID invariant.

Each long-lived gameplay surface stores its `ModalHandle`, calls `handle.open()`
after it becomes visible, and calls `handle.close()` during every normal close
path. Refreshes that destroy and rebuild the visual container keep the surface
open and therefore preserve its stack position. Destroy paths call
`handle.unregister()` and destroy any remaining visuals. Persistence instead
uses the transient-session lifecycle defined above.

For an animated close, `handle.close()` takes the surface out of the Escape
stack immediately when the close begins. The surface may remain visually
present while its fade completes, but it is not an active surface and must not
be reopened until its close transition has finished.

Integration removes the existing individual Escape listeners from
`InventoryUI`, `CraftingUI`, `WorldMapUI`, and `QuestJournal`, removes the
per-modal Escape key path from `LevelUpModal`, and removes ChatUI's document
capture listener. The development persistence dialog retains its Tab focus
trap but no longer handles Escape locally. The shared stack is the only Escape
listener for these surfaces.

The scene reload order is: destroy/unregister gameplay surfaces and clear their
pause-source callbacks through their normal cleanup paths. The game-level stack
is destroyed only with the Phaser game. The stack itself does not own or infer
simulation pause state.

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
builds the pending-choice surface and false when the surface is already open,
closing, or has no pending choices. The `P` hotkey calls it only when
`modalStack.hasActiveSurface()` is false. A `level.up` event with no pending
choices creates and
opens a new roll; an event while the surface is open or while a pending choice
is dismissed is ignored and does not replace the stored choices.

To make these production decisions behaviorally testable, extract two named
helpers in `src/game/ui/LevelUpReopenPolicy.ts`:

- `canReopenPendingLevelUp({ isOpen, isClosing, choiceCount }): boolean` is used
  by `LevelUpModal.reopenPending()` and rejects already-open, closing, and
  no-choice states.
- `reopenPendingLevelUpWhenIdle(modalStack, levelUpModal): boolean` is used by
  the `P` hotkey. It returns false without calling `reopenPending()` while
  `modalStack.hasActiveSurface()` is true; otherwise it returns the modal's
  `reopenPending()` result.

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
- Persistence close unregisters its transient registration exactly once, and
  repeated Save/Load/Reset open-close cycles may safely reuse `persistence`.
- A busy surface that refuses closure remains active and topmost.
- Scene reload unregisters gameplay surfaces; Phaser game destruction removes
  the document listener.
- Chat's DOM input remains focusable and keeps its existing Enter, blur, and
  message behavior; only Escape routing moves to the shared stack.

## Roadmap change

Add a cross-cutting player-experience item before UX.1 in
`docs/GAME_ROADMAP.md`:

### [~] UX.0 — Make Escape close the topmost UI surface

- Build: add a shared modal stack and route Escape through it for inventory,
  crafting, world map, quest journal, level-up, chat, shop, persistence
  dialogs, and future dashboards.
- Player proof: pressing Escape closes the currently active surface only;
  nested dialogs close from the top down, and a dismissed level-up choice can
  be reopened without losing the pending perk selection.
- Done when: no current surface installs an independent Escape listener, all
  current surfaces clean up their registrations, pause state remains correct,
  and keyboard/DOM-focused playtests plus project verification pass.

The implementation must change the existing UX.0 marker in
`docs/GAME_ROADMAP.md` from `[x]` back to `[~]` before code changes begin. It
returns to `[x]` only after the corrected lifecycle tests, runtime smoke test,
and complete project verification pass.

## Verification

Add focused tests for the stack service using an injected document-like event
target, covering registration, LIFO ordering, stale entries, duplicate IDs,
idempotent unregister/re-registration, post-destroy calls, one-close-per-press,
re-entrant callbacks, throwing callbacks with unique top-of-stack restoration,
Escape default-prevention/propagation behavior, and a `canClose()` refusal that
consumes Escape while keeping the same entry topmost until it later accepts
closure.

Import and behaviorally test `createTransientModalSession`,
`canReopenPendingLevelUp`, and `reopenPendingLevelUpWhenIdle` rather than
relying only on source regex assertions:

- open and close persistence twice with the same canonical ID, proving each
  successful close unregisters before the next open;
- press Escape while persistence is busy, proving the dialog remains open and
  active, then clear busy and prove the next Escape closes it;
- prove `reopenPending()` eligibility rejects already-open, closing, and
  no-choice states;
- prove the `P` action does not call `reopenPending()` while another surface is
  active and does call it when the stack is empty;
- retain static checks only for legacy-listener removal and registration wiring.
Manually verify in the running game:

1. Escape closes inventory, crafting, map, journal, chat, shop, persistence,
   and level-up.
2. Opening a nested surface then pressing Escape closes the child first and the
   parent on the next press.
3. Dismissing level-up leaves the skill point and choices pending; reopening
   with `P` shows the same choices, while a second level-up event does not
   replace them.
4. Closing a surface restores simulation only when no other pause source is
   active.
5. Closing chat hides its input and leaves no stale focus-dependent Escape
   handler.
6. Scene reload/shutdown leaves no active document listener or orphaned UI;
   Phaser game destruction disposes the game-level stack.

Run `pnpm typecheck`, `pnpm build`, and `pnpm check` before completion.
