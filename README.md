# Pikachu Desktop Pet

A native macOS desktop pet built with Swift and AppKit — no dependencies, no network, no AI. Pikachu lives in a transparent floating window: it walks around on its own, sleeps at night, reacts to petting and feeding, falls with gravity when you drop it, chats through speech bubbles, and quietly keeps you company during pomodoro focus sessions. Everything is driven by local rules, a finite state machine and a weighted behavior selector, and runs fully offline.

This is a personal, non-commercial fan build. It is not affiliated with or endorsed by Nintendo, The Pokemon Company, or Game Freak.

## Run

Double-click:

```text
run.command
```

This compiles `Sources/*.swift` with the system Swift toolchain and launches the app. Launching a second copy wakes the existing instance instead of spawning a duplicate.

Run the built-in unit tests with:

```zsh
./build/PikachuPet --selftest
```

## Features

- Transparent floating desktop pet window with drag-to-move
- **Autonomous behavior**: rule/weight-based selector (personality × mood × energy × time-of-day × cooldowns) decides when to hop, wander, pose, look around, chat, or nap — never every frame, never spammy
- **Stats & mood**: energy, hunger, mood, affection, stress persist across launches; discrete moods (happy/sleepy/hungry/bored/annoyed/…) derived by rules
- **Offline settlement** capped at 8 hours — the pet is never punished because you closed the laptop for a week
- **Physics**: gravity, toss inertia with capped speed, soft edge bounces, hard-landing reactions, and an off-screen safety recovery that brings the pet back to the main display
- **Interactions**: pet the head, click the body to play, double-click to send it running, rapid-click protection (it gets annoyed and zaps), right-click context menu, Option-click control panel
- **Sleep system**: auto-sleep at night or when tired (toggleable), Zzz overlay, wake by click
- **Speech bubbles**: local template library with per-line cooldowns, daily caps, and time-of-day conditions; click to dismiss; never steals focus
- **Pomodoro**: 25/5 focus timer from the tray or context menu; the pet goes quiet while you focus and celebrates when you finish
- **Tray icon** (⚡️) with show/hide, modes, pomodoro countdown, and status
- **Global hotkeys** (work in any app), plus local keys when the pet has focus
- **Modes**: quiet mode, position lock, click-through (mouse passes through the pet), gravity toggle, reduce-flashing (photosensitivity), always-on-top
- Atomic, versioned, backed-up local save with corruption recovery
- PMD sprite sheets driven by `AnimData.xml` (data-driven — new sheets dropped into `pmd_sprites/` load automatically); falls back to `assets/pet.png`, then to a built-in vector Pikachu

## Controls

Mouse:

- Drag: move the pet (it falls to the ground when gravity is on)
- Click head (upper part): pet it (+affection)
- Click body: hop
- Double-click: run
- Rapid clicking: it gets stressed and eventually zaps you
- Right-click: full context menu (interact / actions / modes / tools / system)
- Option + click: compact control panel with live stats

Global hotkeys (any app):

| Hotkey | Action |
| --- | --- |
| ⌃⇧P | Show / hide pet |
| ⌃⇧J | Jump |
| ⌃⇧R | Random action |
| ⌃⇧S | Sleep / wake |
| ⌃⇧E | Thunderbolt ⚡️ |
| ⌃⇧H | Recall to main screen |
| ⌃⇧L | Lock / unlock position |
| ⌃⇧G | Toggle click-through |

Local keys (pet window focused): `A`/`D` run, `W` jump, `S` fall over, `B` bow, `P` pose, `E` thunderbolt, `Z` sleep.

## Data locations

| What | Where |
| --- | --- |
| Save (stats, settings, position, counters) | `~/Library/Application Support/PikachuPet/save.json` (+ `.bak` backup) |
| Log | `~/Library/Application Support/PikachuPet/pet.log` (auto-rotated at 512 KB) |

The app reads only: the current time, screen geometry, and its own files. It never reads keyboard input outside its own window, screen contents, files, or the network.

## Custom image

If `pmd_sprites/` is missing, place a custom image at `assets/pet.png` (also `pet.jpg`/`.jpeg`). White backgrounds are removed automatically.

## Build notes

Dependency-free; builds with the macOS Swift toolchain:

```zsh
swiftc \
  -target arm64-apple-macosx14.0 \
  -module-cache-path build/module-cache \
  Sources/*.swift \
  -o build/PikachuPet \
  -framework AppKit \
  -framework CoreGraphics \
  -framework Carbon
```

See `ARCHITECTURE.md` for the module layout, how to add animations/actions/dialogue, and current platform limitations.

## Assets

PMD sprite resources are from PMDCollab/SpriteCollab `sprite/0025`.

- SpriteCollab: https://github.com/PMDCollab/SpriteCollab
- PMD Collab sprites site: https://sprites.pmdcollab.org/

The included assets are intended for this local/personal fan build. Check upstream asset terms before reusing or redistributing them.
