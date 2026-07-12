# Architecture

The app is a dependency-free Swift/AppKit program compiled from `Sources/*.swift` by `run.command`. Everything runs offline; there is no AI, no network, and no login. Behavior is driven by local rules, a state machine, and a weighted behavior selector.

## Module layout

```text
Sources/
├── Support.swift      Logger (file, rotated), paths, seedable RNG (SplitMix64)
├── Config.swift       Settings, Personality, DailyFlags, LifetimeTotals,
│                      SaveData + SaveManager (atomic write, .bak backup,
│                      versioned migration, corruption recovery, offline settlement)
├── Stats.swift        PetStats (energy/hunger/mood/affection/stress),
│                      passive tick rates, capped offline settlement,
│                      Mood enum + deriveMood() rules
├── Sprites.swift      AnimData.xml parser + SpriteLibrary. Loads every
│                      "<Name>-Anim.png" that exists; missing sheets fall
│                      back to Idle. Direction rows resolved per sheet.
├── Dialogue.swift     DialogueLibrary: local template lines with weights,
│                      per-line cooldowns, daily caps, hour ranges,
│                      {petName} substitution, category anti-spam
├── Actions.swift      ActionDef catalog (id, kind, priority, interruptLevel,
│                      cooldown, stat effects, bubble category, min energy)
│                      + CooldownTracker
├── Behavior.swift     BehaviorSelector: score = base × personality × mood ×
│                      energy × time × cooldown × randomness; weighted roll;
│                      "do nothing" is always a candidate
├── Controller.swift   PetController: the state machine. Owns state
│                      (idle/acting/running/sleeping/dragged/falling/hidden),
│                      stat ticking, mood, greetings, autonomous evaluation
│                      (every 6–14 s, never per frame), click/drag/feed logic,
│                      rapid-click protection, sleep/wake. UI-free; talks to
│                      the view through PetCommand + PetControllerDelegate.
├── PetView.swift      Rendering + input + mechanics only: sprite drawing,
│                      thunder glow (photosensitivity-safe mode), Zzz overlay,
│                      jump lift, run stepping, gravity/toss physics, edge
│                      bounce, off-screen safety recovery, context menu,
│                      keyboard, redraw-skipping (idle costs ~0 CPU)
├── Bubble.swift       SpeechBubbleWindow: non-activating panel, click to
│                      dismiss, auto-hide, clamped to the screen
├── Panel.swift        Option-click control panel (ported from the original
│                      app) + live mood/energy status line
├── Pomodoro.swift     25/5 local focus timer; drives controller.focusMode
├── Hotkeys.swift      Carbon global hotkeys with failure logging
├── Tray.swift         NSStatusItem menu (rebuilt on open) + countdown title
├── ImageTools.swift   Custom-image white background removal
├── SelfTest.swift     Dependency-free unit tests (--selftest)
└── main.swift         AppCoordinator (NSApplicationDelegate): window setup,
                       single-instance flock, sleep/wake + screen-change
                       observers, settings toggles, autosave, shutdown
```

## Control flow

```text
input (mouse/keys/hotkeys/menus) ─► PetController ── PetCommand ─► PetView (mechanics)
30 Hz timer ─► controller.tick() ─► stats/mood/behavior selector ─┘        │
                                                          actionFinished() ◄┘
```

- The controller decides *what and when* (priorities, cooldowns, interrupt levels, stat effects); the view executes *how* (animation ticks, window movement, physics) and reports completion.
- User commands (priority 80) interrupt autonomous actions (priority 30) but not system states (dragging, 95+). Reactions to clicks sit in between (60).
- Autonomous evaluation runs every ~6–14 s (scaled by the autonomy setting), immediately deferred by user interaction; never per frame.
- Deterministic debugging: set `settings.behaviorSeed` in `save.json` to fix the RNG.

## Persistence

`~/Library/Application Support/PikachuPet/save.json` — written atomically every 30 s when dirty, plus on sleep/quit; previous good save kept as `save.json.bak`; corrupted saves fall back to the backup, then to defaults. `version` field + `migrate()` hook handle future format changes. Offline time is settled on launch, capped at 8 h, and never punitive (hunger caps at 85, stress clears, mood floors at baseline).

## Adding content

**A new animation**: drop `<Name>-Anim.png` into `pmd_sprites/` and make sure `AnimData.xml` has a matching `<Anim>` entry (frame size + durations). It loads automatically; the sheet may have 8 direction rows or a single row.

**A new action**: add an `ActionDef` to `ActionCatalog.all` (choose a `kind`: `.anim("SheetName")`, `.jump`, `.run`, `.thunder`, `.sleepToggle`). Give it a cooldown, stat effects and optionally a bubble category. To make it autonomous, add a weighted `add("id", …)` line in `BehaviorSelector.choose`. To expose it to users, reference it from the context menu / hotkeys / panel.

**New dialogue**: add lines to `DialogueLibrary.lines` under an existing or new category and emit with `controller.emitBubble(category:)`.

**A new character**: the engine reads any sprite folder shaped like PMDCollab output (`AnimData.xml` + `<Name>-Anim.png`). Swap the `pmd_sprites/` folder, adjust `Personality` defaults and dialogue lines. (A full multi-character-pack loader is a planned follow-up; the seams — data-driven sprites, catalog, personality struct — are already in place.)

## Platform notes & limitations

- Global hotkeys use Carbon `RegisterEventHotKey` — no accessibility permission needed; registration failures are logged and non-fatal.
- Single instance via `flock` on a lock file; a second launch pings the first through a distributed notification and exits.
- System sleep/wake pauses/resumes the frame timer; screen configuration changes re-validate the pet position (with a bottom-right safety recovery if the pet ends up off every screen).
- Not implemented (deliberately deferred, documented rather than stubbed): fullscreen-app detection, standing on other apps' windows, multi-monitor auto-roaming, sound, inventory/achievement UI panels, shortcut editor UI, reminders. None of these have placeholder buttons.
