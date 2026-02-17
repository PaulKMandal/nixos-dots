{ lib
, stdenvNoCC
, fetchurl
, autoPatchelfHook
, makeWrapper

, gtk3, glib, dbus, nss, nspr
, alsa-lib, libpulseaudio
, cairo, pango, gdk-pixbuf, atk, at-spi2-atk, at-spi2-core
, libxkbcommon
, xorg
, mesa, libdrm, libglvnd
, libuuid, libffi
, fontconfig, freetype
}:

stdenvNoCC.mkDerivation rec {
  pname = "waterfox-bin";
  version = "6.6.8";

  src = fetchurl {
    url = "https://cdn1.waterfox.net/waterfox/releases/${version}/Linux_x86_64/waterfox-${version}.tar.bz2";
    # Waterfox publishes SHA512; Nix wants sha256. Get it via:
    #   nix store prefetch-file --json <url> | jq -r .hash
    sha256 = "sha256-Vj94tSPxGxMyl6D2jgz9KBZHjjpmWAfIQeklIYztcYg=";
  };

  nativeBuildInputs = [ autoPatchelfHook makeWrapper ];

  buildInputs = [
    gtk3 glib dbus nss nspr
    alsa-lib libpulseaudio
    cairo pango gdk-pixbuf atk at-spi2-atk at-spi2-core
    libxkbcommon
    mesa libdrm libglvnd
    libuuid libffi
    fontconfig freetype

    xorg.libX11 xorg.libXext xorg.libXrender xorg.libXt xorg.libXtst
    xorg.libxcb xorg.libXcomposite xorg.libXdamage xorg.libXfixes
    xorg.libXrandr xorg.libXcursor xorg.libXi
  ];

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall

    mkdir -p $out/lib $out/bin $out/share/applications $out/share/icons/hicolor/256x256/apps
    cp -r . $out/lib/waterfox

    makeWrapper $out/lib/waterfox/waterfox $out/bin/waterfox \
      --set MOZ_ENABLE_WAYLAND 1

    # icon + desktop entry (icon is present in the tarball)
    if [ -f "$out/lib/waterfox/browser/chrome/icons/default/default256.png" ]; then
      cp "$out/lib/waterfox/browser/chrome/icons/default/default256.png" \
         "$out/share/icons/hicolor/256x256/apps/waterfox.png"
    fi

    cat > $out/share/applications/waterfox.desktop <<EOF
    [Desktop Entry]
    Name=Waterfox
    Exec=waterfox %u
    Icon=waterfox
    Type=Application
    Categories=Network;WebBrowser;
    MimeType=text/html;x-scheme-handler/http;x-scheme-handler/https;
    EOF

    runHook postInstall
  '';

  # autoPatchelf needs this
  meta = with lib; {
    description = "Waterfox (official binary tarball, wrapped for NixOS)";
    platforms = [ "x86_64-linux" ];
  };
}

