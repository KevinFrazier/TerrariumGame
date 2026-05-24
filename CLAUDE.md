# Terrarium Game

A Godot 4 project. This file documents the layout, conventions, and tooling so
future contributors (human and AI) can navigate the codebase quickly.

## Tech Stack

- **Engine:** Godot 4.3+ (GL Compatibility renderer for broad device support)
- **Language:** GDScript (static typing preferred)
- **Entry scene:** `res://scenes/main/main.tscn`

## Directory Layout

```
TerrariumGame/
├── project.godot           # Engine config (edit via Godot editor when possible)
├── icon.svg                # Project icon
├── CLAUDE.md               # This file
├── .gitignore              # Excludes .godot/, exports, IDE files
├── .gitattributes          # Enforces LF line endings on text resources
│
├── addons/                 # Third-party plugins (one folder per plugin)
│
├── assets/                 # Raw source assets, imported by Godot
│   ├── audio/
│   │   ├── music/          # Looping background tracks (.ogg preferred)
│   │   └── sfx/            # One-shot sound effects (.wav preferred)
│   ├── fonts/              # .ttf / .otf font files
│   ├── sprites/            # Character/entity sprites and spritesheets
│   └── textures/           # Tileable textures, backgrounds, UI atlases
│
├── scenes/                 # .tscn files, grouped by purpose
│   ├── main/               # Top-level / bootstrap scenes (main.tscn lives here)
│   ├── entities/           # Reusable in-world objects (plants, creatures, props)
│   └── ui/                 # Menus, HUD, dialogs
│
├── scripts/                # .gd files mirroring the scenes/ layout
│   ├── autoload/           # Singletons registered in Project Settings → Autoload
│   ├── entities/           # Behavior for scenes/entities/*
│   ├── systems/            # Cross-cutting game systems (save, weather, economy)
│   ├── ui/                 # Behavior for scenes/ui/*
│   └── main/               # Bootstrap and scene-router scripts
│
├── resources/              # Custom .tres data resources (item defs, configs)
├── shaders/                # .gdshader files and shader includes
└── tests/                  # GUT or similar test suites
```

### Co-locating vs. mirroring

Two valid patterns:

1. **Mirrored** (current default): scripts live in `scripts/` paralleling
   `scenes/`. Easier to bulk-edit code without touching scene metadata.
2. **Co-located**: `MyScene.tscn` and `MyScene.gd` live in the same folder.
   Easier to move or delete a feature as a unit.

Pick one and stick to it within a subsystem. Don't mix inside the same folder.

## Naming Conventions

- **Files & folders:** `snake_case` (e.g. `plant_growth.gd`, `main_menu.tscn`)
- **Classes (`class_name`):** `PascalCase` (e.g. `class_name PlantGrowth`)
- **Variables & functions:** `snake_case`
- **Constants & enums:** `SCREAMING_SNAKE_CASE`
- **Private members:** prefix with `_` (`_internal_state`)
- **Signals:** past tense verbs (`health_changed`, `item_collected`)
- **Node names in scenes:** `PascalCase` (matches Godot defaults)

## Resource Paths

Always reference assets with absolute `res://` paths, never relative. Example:

```gdscript
const PLANT_SCENE := preload("res://scenes/entities/plant.tscn")
```

## GDScript Style

- Use static typing on function signatures and exported vars.
- Prefer `@onready var foo: Type = $NodePath` over `_ready()` assignment.
- Use `@export` for inspector-tunable values; document units in the var name
  (e.g. `growth_rate_per_second`).
- Connect signals in the editor when the connection is permanent; connect in
  code (`signal.connect(handler)`) when conditional or dynamic.

## Autoloads (Singletons)

Register globals in **Project Settings → Autoload**. Scripts live in
`scripts/autoload/`. Common candidates:

- `GameState` — persistent run/save data
- `EventBus` — decoupled signal hub
- `AudioManager` — central play/stop for music & sfx

## Running

Open `project.godot` in Godot 4.3+ and press F5, or from the command line:

```bash
godot --path . res://scenes/ui/lobby.tscn
```

The lobby's "Start Match" button loads the arena. `Esc` quits.

## Git Hygiene

- `.godot/` is gitignored — it's regenerated on first open.
- Commit `.import` metadata for assets so other contributors don't re-import.
- Keep binary asset diffs small; prefer optimized PNG/OGG over raw files.
- Default workflow: develop on the feature branch, and at the end of each task
  fast-forward `main` to the latest commit and push it (no need to ask first).
- NEVER force push (no `--force`, `--force-with-lease`, or `-f`) to any branch,
  under any circumstance. If a normal push is rejected, stop and ask — do not
  override.
