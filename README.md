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
