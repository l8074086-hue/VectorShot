# VectorShot

## What is VectorShot?
VectorShot is a hobby game made for a computing fair at my school. It is still in active development and is honestly still a work in progress but im working on it every week
I plan to have finished at least everything in my ending.txt by the time the fair is here.

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

## Building for Windows
The Linux build produces an ELF binary, so it won't run on Windows. To get a `.exe` you have two options:

- **On Windows** (easiest): install Odin + raylib, then `odin build .` in the project folder.
- **Cross-compiling** from Linux/macOS: `just build-windows`, which runs
  `odin build . -target:windows_amd64 -out:roguelike.exe`. This needs the Windows
  raylib libs (the ones shipped with this Odin install are Git-LFS stubs you must
  fetch first) and an LLVM/`lld-link` linker, since Odin cannot cross-link to
  Windows on its own yet. On this specific environment, cross-linking is not
  feasible due to missing MSVC C runtime import libs; building on Windows is
  strongly recommended.

