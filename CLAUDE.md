# Terrarium Game

A Godot 4 **3D PvP MOBA / tower-defense** prototype. Two heroes defend opposing
cores in a square arena; each can move, shoot, melee, cast a class buff, spend
gold to build/upgrade towers, and level up. Lane minions spawn in waves and
march on the enemy core. This file documents the layout, conventions, and the
gameplay architecture so future contributors (human and AI) can navigate quickly.

## Tech Stack

- **Engine:** Godot 4.3+ (GL Compatibility renderer for broad device support)
- **Language:** GDScript (static typing preferred)
- **Entry scene:** `res://scenes/ui/lobby.tscn` (set as `run/main_scene`)
- **Input:** twin-stick — left stick / WASD move, right stick / mouse orbits the
  camera; on-screen buttons (FIRE, TOWER, BUFF, SWAP HERO) plus keyboard fallback.

## Directory Layout

```
TerrariumGame/
├── project.godot           # Engine config (autoloads, input map, layers)
├── icon.svg
├── CLAUDE.md               # This file
│
├── scenes/
│   ├── main/               # arena.tscn (the match scene)
│   ├── entities/
│   │   ├── hero.tscn, minion.tscn, core.tscn, projectile.tscn
│   │   ├── towers/         # arrow / sniper / cannon / mortar tower scenes
│   │   └── projectiles/    # per-hero projectile scenes (warrior/mage/archer)
│   └── ui/                 # lobby.tscn, hud.tscn
│
├── scripts/                # mirrors scenes/ (see "mirrored" layout below)
│   ├── autoload/           # event_bus.gd, game_state.gd (registered singletons)
│   ├── entities/           # combat_actor.gd, hero.gd, minion.gd, tower.gd,
│   │                       #   core.gd, projectile.gd
│   ├── systems/            # team.gd, health_component.gd, targeter.gd,
│   │                       #   wave_spawner.gd, juice.gd
│   ├── effects/            # damage_popup.gd
│   ├── ui/                 # hud.gd, build_menu.gd, lobby.gd, virtual_joystick.gd
│   └── main/               # arena.gd (match orchestrator)
│
├── resources/              # .tres data + their scripts
│   ├── hero_definition.gd, tower_definition.gd
│   ├── heroes/             # warrior / mage / archer .tres
│   └── towers/             # base + tier-2 (upgrade) tower .tres
│
├── shaders/                # unit.gdshader, fx_burst, fx_ring (+ vignette in code)
└── tests/                  # disposable headless self-tests (not committed)
```


## Game Architecture

### Core combat layer
- **`Team`** (`systems/team.gd`) — team ids + the physics layer/mask helpers all
  targeting reduces to (each team lives on its own body layer).
- **`HealthComponent`** (`systems/health_component.gd`) — reusable child node:
  `take_damage()`, `heal()`, `revive()`, `health_changed` / `died` signals, and
  spawns floating `DamagePopup` numbers.
- **`Targeter`** (`systems/targeter.gd`) — an `Area3D` that tracks enemies in
  range; shared by Hero, Minion, and Tower. `acquire_target(priority)` (nearest /
  lowest-hp / highest-hp) and `nearest_in_direction()` (hero aim-assist).
- **`CombatActor`** (`entities/combat_actor.gd`) — abstract `CharacterBody3D`
  base for **Hero and Minion**. Owns the shared team/health/gravity surface **and
  the full status-effect + buff system**: slow, burn, poison, stun, root,
  chill→freeze, vulnerable, weaken, silence, knockback, plus timed attack /
  damage-reduction / speed buffs. Effects coexist and compose (`damage_mult()`,
  `incoming_mult()`, `speed_mult()`, `can_act()`, `can_use_ability()`); subclasses
  call `tick_status(delta)` each physics frame. `get_active_effects()` drives the
  HUD chips and blended aura. Towers/cores are `StaticBody3D` and do **not** get
  effects.
- **`Projectile`** (`entities/projectile.gd`) — `Area3D` shot reused by heroes and
  towers. Supports straight or gravity-lobbed flight, blast radius + falloff, slow,
  an applied status effect, and an `owner_unit` for last-hit kill credit.

### Entities
- **`Hero`** — player unit. Class comes from a **`HeroDefinition`** (mesh, stats,
  projectile scene, buff). Fires on button **press**, auto-melees, throws towers
  (`ability_1`), casts its class buff (`ability_2`). Has **XP/leveling**: last-hit
  kills grant XP; level-ups scale melee/projectile/HP via tunable `@export`
  growth weights and raise the team minion level. Gets all buffs (and, behind a
  debug flag, all debuffs) for a few seconds on (re)spawn.
- **`Minion`** — navmesh lane creep; scales off its team's hero level on spawn;
  awards bounty + XP to its killer.
- **`Tower`** — buildable, data-driven by **`TowerDefinition`**; auto-fires via its
  `Targeter`; supports tiered **upgrades** (`definition.upgrade` / `upgrade_cost`).
- **`Core`** — the structure each team defends; its destruction ends the match.

### Data resources
- **`HeroDefinition`** (`resources/hero_definition.gd`) — per-class mesh, stats,
  `projectile_scene`, and buff kind/magnitude/duration.
- **`TowerDefinition`** (`resources/tower_definition.gd`) — stats, projectile
  behavior, area/slow/status effect, targeting priority, and `upgrade` tier.

### Presentation
- **`Juice`** (`systems/juice.gd`) — stateless FX helpers. Hit flash, impact/ring
  bursts use the GPU shaders in `shaders/`; coins use `CPUParticles3D`; hitstop +
  camera shake are time/transform effects.
- **`GameHUD`** (`ui/hud.gd`) — twin sticks, action buttons, health/XP/level,
  status chips, build menu, floating tower inspect + Upgrade button, low-HP and
  core-attack vignette (canvas shader), match result.
- **`arena.gd`** — match orchestrator: bakes navigation, wires spawners, routes
  bounties to the economy, assigns/swaps local hero control, resolves win/lose.

### Match flow
`lobby.tscn` (pick side + hero class) → `arena.tscn`. Bounties feed `GameState`
gold; gold builds/upgrades towers; destroying a core ends the match.

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

Registered in **Project Settings → Autoload** (`scripts/autoload/`):

- **`GameState`** — match + per-team data: currency, tower counts/cap, team
  level, selected hero defs, selected tower + targeting priority, winner.
- **`EventBus`** — decoupled signal hub: `minion_died`, `hero_died/respawned`,
  `hero_leveled`, `core_damaged/destroyed`, `tower_built`, `currency_changed`,
  `match_started/ended`, `swap_control_requested`.

## Running

Open `project.godot` in Godot 4.3+ and press F5, or from the command line:

```bash
godot --path . res://scenes/ui/lobby.tscn
```

In the lobby, pick which side you control and each side's hero class, then
"Start Match". Controls: **WASD / left stick** move, **mouse / right stick**
orbit camera, **FIRE button or J / left-click** shoot (on press), **K** melee
(auto), **TOWER button or Q** arm/throw a tower, **BUFF button or E** class buff,
**SWAP HERO button or Tab** switch the controlled hero, **Esc** quits.

For headless smoke checks, run a scene with `--headless ... --quit-after N`;
shaders don't render without a GPU, so visual FX still need an in-editor look.

## Git Hygiene

- `.godot/` is gitignored — it's regenerated on first open.
- Commit `.import` metadata for assets so other contributors don't re-import.
- Keep binary asset diffs small; prefer optimized PNG/OGG over raw files.
- Default workflow: develop on the feature branch, then bring `main` up to date
  and push it at the end of each task (the user has set pushing to `main` as the
  standard — no need to ask first).
- NEVER force push (no `--force`, `--force-with-lease`, or `-f`) to any branch,
  under any circumstance. If a normal push is rejected, stop and investigate
  (e.g. integrate the remote first) — do not override.
