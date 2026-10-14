run:
  odin build .
  ./roguelike
build:
  odin build .
# Cross-compile a Windows .exe (see README: Building for Windows).
build-windows:
  odin build . -target:windows_amd64 -out:roguelike.exe
clean:
  rm -f roguelike roguelike.exe
