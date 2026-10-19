# VectorShot

## What is VectorShot?
VectorShot is a hobby game made for a computing fair at my school. It is still in active development and is honestly still a work in progress but im working on it every week.
I plan to have finished at least everything in my [done.txt](done.txt) by the time the fair is here.

The short version: a top-down wave shooter where you pick a character, fight
through an arena, and try to survive its boss. Everything is drawn with simple
shapes and all the audio is synthesized at runtime, so the repo carries no
binary assets at all.

## What's in it

- **4 playable characters** — RR, TRACER, BUD and NAVY, each with a passive and
  a dash, plus character/dash synergies
- **7 arenas**, each with a hand-built boss that is the map's finale. Beating
  one clears the map, unlocks the next, and drops you into endless survival
- **4 run modes** — Standard (waves → boss → endless), Endless, Boss Rush, and
  Expedition (a branching node map where you pick your path)
- **8 run modifiers** you can compose, like TOUGH, SWARM, NO CARDS or ONE LIFE
- **A card deck.** Cards are things you own, not stat bumps handed to you: each
  cleared wave deals the top three and you keep one. Throwing a card away at
  the Deckmaster puts it in the graveyard, and it comes back as an enemy
- **Relics** — a persistent collection you equip up to three of
- **A codex** — 26 bestiary entries that unlock as you meet things
- **Missions**, **three tiers of hands-on tutorial**, difficulty levels, and a
  hidden comfort mode (Ctrl+G)
- Save and resume, and a Quake-style debug console (`` ` ``)

## So, what does it use?

Language: Odin
Library: raylib
Build helper: just (optional)
To make it you just need Odin installed and reachable in PATH and you also need to have raylib installed

## Installing dependencies

### NixOS
```nix
nix shell
```
The repo contains the shell.nix required.

### Arch Linux
```Bash
sudo pacman -S odin
sudo pacman -S raylib
```
If they aren't available in your configured repo you must find another way to get them as I'm too lazy to do it for you.

### Other Operating Systems
Install odin and raylib with their respective installation instructions.

## Running the game
then you can either just `just run` or `odin run .` it's the same either way, I only have the justfile for convenience and also because I'm more comfortable typing it.

The justfile also has:

| target | what it does |
| --- | --- |
| `just run` | build and launch |
| `just build` | build the binary |
| `just build-windows` | cross-compile `roguelike.exe` (see below) |
| `just clean` | remove the built binaries |
| `just clean-windows` | also drop the Windows cross-compile cache |

## Building for Windows
The Linux build produces an ELF binary, so it won't run on Windows.

### From Linux (cross-compile)
Run `just build-windows` (or `./build-windows.sh`) to produce `roguelike.exe`.
Odin can't cross-link to Windows by itself (it only supports Android), so the
script does it in stages:

1. Downloads the real Windows `raylib.lib` / `raygui.lib` — the ones shipped
   with Odin are Git-LFS pointer stubs — from the matching Odin commit.
2. Compiles the sources to Windows objects with
   `odin build . -target:windows_amd64 -build-mode:obj`.
3. Links them with Zig's bundled MinGW-w64 toolchain:
   `zig cc -target x86_64-windows-gnu ...`.

`windows_shims.c` supplies a few MSVC-only CRT symbols (`__security_cookie`,
`__GSHandlerCheck`, `_fltused`) that the MSVC-built `raylib.lib` expects but
MinGW-w64 doesn't provide.

Requirements: `odin`, `zig`, `ar` (binutils) and `curl`. Use `just
clean-windows` to drop the `.build-windows/` cache (downloaded libs + objects).

### On Windows
Install Odin + raylib and run `build-windows.cmd` (or `odin build .`) in the
project folder.

## How the code is laid out

Everything is one Odin package, split by role:

| file | what lives there |
| --- | --- |
| `main.odin` | the main loop and every screen (menus, shop, codex, results...) |
| `game.odin` | run state, enemies, the card deck, save/load |
| `boss.odin` | the seven arena boss AI state machines |
| `content.odin` | every data table — cards, enemies, arenas, characters, relics, bestiary |
| `types.odin` | structs and enums |
| `settings.odin` | `settings.cfg` and the options in it |
| `tutorial.odin` | the three tutorial tiers |
| `console.odin` | the debug command panel |
| `audio.odin` | runtime-synthesized sound effects |

Content lives in `content.odin` and is keyed by name, so tuning the game
usually means editing data rather than code.

## Lore
The setting is written down in [lore.txt](lore.txt) — VectorPlane, the Crimson
Star, and what it means to fall into a world made of vectors. The codex in the
game draws from it.
