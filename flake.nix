{
  description = "Prebuilt static ffmpeg binaries for x86_64/aarch64 linux";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  inputs.nixbot.url = "github:Mic92/nixbot";
  inputs.nixbot.inputs.nixpkgs.follows = "nixpkgs";

  outputs = { self, nixpkgs, nixbot }:
    let
      # Pinned to an immutable dated autobuild release (NOT the rolling "latest"
      # tag, whose tarball changes and breaks the hash). Run ./update.sh to bump.
      release = "autobuild-2026-10-24-13-02";
      rev = "ffmpeg-N-128013-g6b05263b44"; # filename stem for this release

      # variant -> system -> hash. Managed by update.sh.
      hashes = {
        gpl = {
          x86_64-linux = "sha256-hIaOcBy/H2YTRSNFOcBLLH/YgkvvvghQyBKt3xKbDGg=";
          aarch64-linux = "sha256-/VObQSaKXbGUGqDhfnUUt/aR3YuOD+aA+xkW360T48Q=";
        };
        lgpl = {
          x86_64-linux = "sha256-w2UOhyrgqZGpx9wrdxyNj+MxVeGkVvmwE/PSJQZ/NF8=";
          aarch64-linux = "sha256-gXz34q7x7wuJLI4Pb9Stc9HeeYhcZErmvucRsmN8/CA=";
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

      # nixbot (oci-jkor-a1) scheduled effect: ./update.sh, commit, push over ssh.
      herculesCI = { ... }:
        let
          pkgs = nixpkgs.legacyPackages.aarch64-linux;
          inherit (nixbot.lib.effects { inherit pkgs; }) mkEffect;
          knownHosts = pkgs.writeText "known_hosts" ''
            github.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl
          '';
        in
        {
          onSchedule.update-hashes = {
            when = { dayOfWeek = [ "Mon" ]; hour = 6; minute = 0; }; # UTC
            outputs.effects.update = mkEffect {
              secretsMap.ssh = "ssh";
              inputs = with pkgs; [ git openssh curl python3 nix gawk gnused ];
              effectScript = ''
                writeSSHKey ssh
                export GIT_SSH_COMMAND="ssh -o UserKnownHostsFile=${knownHosts}"
                export NIX_CONFIG="experimental-features = nix-command"
                git clone git@github.com:aca/ffmpeg-builds.nix.git repo
                cd repo
                bash ./update.sh
                if git diff --quiet flake.nix; then
                  echo "No changes."
                else
                  git -c user.name=nixbot -c user.email=nixbot@oci-jkor-a1 \
                    commit -m "chore: update ffmpeg hashes ($(date -u +%Y-%m-%d))" flake.nix
                  git push
                fi
              '';
            };
          };
        };

      apps = forAllSystems (system: rec {
        ffmpeg = {
          type = "app";
          program = "${self.packages.${system}.ffmpeg}/bin/ffmpeg";
        };
        default = ffmpeg;
      });
    };
}
