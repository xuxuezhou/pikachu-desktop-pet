# Pikachu Desktop Pet

A native macOS desktop pet built with Swift and AppKit. It runs as a transparent floating window, can be dragged around the desktop, plays sprite-based animations, and includes a compact interaction panel.

This is a personal, non-commercial fan build. It is not affiliated with or endorsed by Nintendo, The Pokemon Company, or Game Freak.

## Run

Double-click:

```text
run.command
```

The app can also be launched from:

```text
/Applications/PikachuPet.app
```

The default window is intentionally small. Use the interaction panel to resize it.

## Features

- Transparent floating macOS desktop pet window
- Drag-to-move behavior
- Compact side interaction panel
- Keyboard action commands
- Static idle pose with animated actions
- Autonomous playful behavior after a period of no interaction
- Optional custom pet image in `assets/pet.png`
- PMD-style sprite animation support through `pmd_sprites/`

When `pmd_sprites/` is available, the app uses the PMD sprite animations:

- Idle: fixed first frame from `Idle-Anim.png`
- Click: jump in place
- Rapid click: run outward based on screen position
- Commands: run left, run right, jump, bow, pose, and fall down
- Running: `Walk-Anim.png`

If no sprite assets are available, the app falls back to `assets/pet.png`, and then to the built-in drawing.

## Controls

- Drag: move the pet
- Click: jump in place
- Rapid click: run outward
- Option + click: open the side interaction panel

Keyboard commands:

- `A`: run left
- `D`: run right
- `W`: jump up
- `S`: fall down
- `B`: bow
- `P`: pose

The interaction panel uses short English labels:

- `Left A`
- `Jump W`
- `Right D`
- `Bow B`
- `Pose P`
- `Down S`
- `Sm`, `Lg`, `Pin`, `Quit`

The panel opens on the left or right side of the pet, depending on available screen space.

## Custom Image

Place a custom pet image here:

```text
assets/pet.png
```

The app also supports `pet.jpg` and `pet.jpeg`, but PNG is recommended for cleaner transparency.

For custom images, the app tries to remove white backgrounds automatically, including larger interior white gaps while preserving small highlights.

## Build Notes

This project is intentionally dependency-free. It builds with the macOS Swift toolchain and AppKit:

```zsh
swiftc \
  -target arm64-apple-macosx14.0 \
  -module-cache-path build/module-cache \
  DesktopPet.swift \
  -o build/PikachuPet \
  -framework AppKit \
  -framework CoreGraphics
```

`run.command` wraps this build command and runs the compiled app.

## Assets

PMD sprite resources are from PMDCollab/SpriteCollab `sprite/0025`.

- SpriteCollab: https://github.com/PMDCollab/SpriteCollab
- PMD Collab sprites site: https://sprites.pmdcollab.org/

The included assets are intended for this local/personal fan build. Check upstream asset terms before reusing or redistributing them.
