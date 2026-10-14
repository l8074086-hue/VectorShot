run:
  odin build .
  ./roguelike
build:
  odin build .
# Cross-compile a Windows .exe from Linux (Odin objects + Zig's MinGW linker).
build-windows:
  ./build-windows.sh
clean:
  rm -f roguelike roguelike.exe
# Also drop the Windows cross-compile cache (downloaded raylib libs, objects).
clean-windows:
  rm -rf roguelike.exe .build-windows
