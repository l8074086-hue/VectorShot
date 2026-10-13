{
  pkgs ? import <nixpkgs> { },
}:
pkgs.mkShell {
  packages = with pkgs; [
    odin
    raylib
    git
  ];
}
