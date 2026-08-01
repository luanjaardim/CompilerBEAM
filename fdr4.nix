{ pkgs ? import <nixpkgs> {} }:

(pkgs.buildFHSEnv {
  name = "fdr4-environment";
  targetPkgs = pkgs: with pkgs; [
    stdenv.cc.cc.lib
    glib
    fontconfig
    freetype
    dbus
    libxkbcommon

    zlib
    ncurses5

    libx11
    libxft
    libxcb
    libxext
    libxrender
    libxi
    libsm
    libice

    # Renderers
    libglvnd
    mesa
  ];
  profile = ''
    export LD_LIBRARY_PATH="/lib:/usr/lib:$LD_LIBRARY_PATH"
    # Changing the source to open the fdr4 application
    export QT_QPA_PLATFORM=xcb
  '';
  runScript = "bash";
})
