{
  description = "Prebuilt static ffmpeg binaries for x86_64/aarch64 linux";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      # Pinned to an immutable dated autobuild release (NOT the rolling "latest"
      # tag, whose tarball changes and breaks the hash). Run ./update.sh to bump.
      release = "autobuild-2026-06-28-13-24";
      rev = "ffmpeg-N-125331-g87bd15dc3c"; # filename stem for this release

      # variant -> system -> hash. Managed by update.sh.
      hashes = {
        gpl = {
          x86_64-linux = "sha256-hNwjNQytVp7Mh5xvVAAmcWPp+dmPHuxw61591WRahlw=";
          aarch64-linux = "sha256-KackIE5v6p4kXID6jtdl9sBqDpEalF0NZFzDAR+R6b0=";
        };
        lgpl = {
          x86_64-linux = "sha256-o40tXWYbv5ab1YxRK4R4sTVmsIyvGbgGJfGQ7I8WfSo=";
          aarch64-linux = "sha256-beM72ZZ2Z7bSaT0xAheL0B6gikFTzqAGFNPUFu7puuk=";
        };
      };

      arches = {
        x86_64-linux = "linux64";
        aarch64-linux = "linuxarm64";
      };

      systems = builtins.attrNames arches;
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f system);

      # variant: "gpl" or "lgpl"
      ffmpegFor = pkgs: variant:
        let
          system = pkgs.stdenv.hostPlatform.system;
          arch = arches.${system};
          license =
            if variant == "gpl" then pkgs.lib.licenses.gpl3Plus
            else pkgs.lib.licenses.lgpl21Plus;
        in
        pkgs.stdenv.mkDerivation {
          pname = "ffmpeg-bin-${variant}";
          version = release;

          src = pkgs.fetchurl {
            url = "https://github.com/BtbN/FFmpeg-Builds/releases/download/${release}/${rev}-${arch}-${variant}.tar.xz";
            hash = hashes.${variant}.${system};
          };

          nativeBuildInputs = [ pkgs.autoPatchelfHook ];

          # The non-shared build statically links ffmpeg's own libs, so only the
          # system runtime deps need patching. SDL2/X11 are for ffplay.
          buildInputs = [
            pkgs.stdenv.cc.cc.lib # libstdc++ / libgcc_s
            pkgs.zlib
            pkgs.SDL2
            pkgs.libx11
            pkgs.libxext
            pkgs.libxv
          ];

          installPhase = ''
            runHook preInstall
            mkdir -p $out/share
            cp -r bin $out/bin
            cp -r man $out/share/man || true
            install -Dm644 LICENSE.txt $out/share/doc/ffmpeg-bin/LICENSE.txt || true
            runHook postInstall
          '';

          meta = with pkgs.lib; {
            description = "Prebuilt static ffmpeg binary (${variant})";
            homepage = "https://github.com/BtbN/FFmpeg-Builds";
            inherit license;
            platforms = systems;
            mainProgram = "ffmpeg";
          };
        };
    in
    {
      # Use in another flake: nixpkgs overlays = [ ffmpeg-bin.overlays.default ];
      # then reference pkgs.ffmpeg-bin / pkgs.ffmpeg-bin-lgpl.
      overlays.default = final: prev: {
        ffmpeg-bin = ffmpegFor final "gpl";
        ffmpeg-bin-lgpl = ffmpegFor final "lgpl";
      };

      packages = forAllSystems (system:
        let pkgs = nixpkgs.legacyPackages.${system};
        in rec {
          ffmpeg = ffmpegFor pkgs "gpl";
          ffmpeg-lgpl = ffmpegFor pkgs "lgpl";
          default = ffmpeg;
        });

      apps = forAllSystems (system: rec {
        ffmpeg = {
          type = "app";
          program = "${self.packages.${system}.ffmpeg}/bin/ffmpeg";
        };
        default = ffmpeg;
      });
    };
}
