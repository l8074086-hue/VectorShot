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

