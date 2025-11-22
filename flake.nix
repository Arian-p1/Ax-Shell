{
  description = "A clean, elegant, and working flake for Ax-Shell";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    fabric-gtk.url = "github:poogas/fabric";
    fabric-cli.url = "github:poogas/fabric-cli";
    gray.url = "github:Fabric-Development/gray";
  };

  inputs.fabric-gtk.inputs.nixpkgs.follows = "nixpkgs";
  inputs.fabric-cli.inputs.nixpkgs.follows = "nixpkgs";
  inputs.gray.inputs.nixpkgs.follows = "nixpkgs";

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
      ...
    }@inputs:
    let
      supportedSystems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
    in
    flake-utils.lib.eachSystem supportedSystems (
      system:
      let
        pkgs = import nixpkgs {
          inherit system;
          config.allowUnfree = true;
        };

        python = pkgs.python312;

        tabler-icons-font = pkgs.stdenv.mkDerivation {
          pname = "tabler-icons-font";
          version = "local";
          src = self;

          installPhase = ''
            mkdir -p $out/share/fonts/truetype
            cp $src/assets/fonts/tabler-icons/tabler-icons.ttf $out/share/fonts/truetype/
          '';
        };

        ax-shell-python-packages =
          ps:
          [
            (ps.buildPythonPackage {
              pname = "fabric-gtk";
              version = "unstable-${self.shortRev or "dirty"}";
              src = inputs.fabric-gtk;
              format = "pyproject";
              nativeBuildInputs = [
                ps.setuptools
                ps.wheel
              ]
              ++ (with pkgs; [
                cairo
                gobject-introspection
                glib
                pkg-config
              ]);
              propagatedBuildInputs = [
                ps.click
                ps.loguru
                ps.pycairo
                ps.pygobject3
              ];
            })
            ps.dbus-python
            ps.ijson
            ps.numpy
            ps.pillow
            ps.psutil
            ps.pywayland
            ps.requests
            ps.setproctitle
            ps.toml
            ps.watchdog
          ];

        ax-shell-python = python.withPackages ax-shell-python-packages;

        ax-shell-inhibit-pkg = pkgs.stdenv.mkDerivation {
          pname = "ax-shell-inhibit";
          version = "unstable-${self.shortRev or "dirty"}";
          src = self;

          nativeBuildInputs = [ pkgs.makeWrapper ];
          buildInputs = [ ax-shell-python ];

          installPhase = ''
            runHook preInstall;
            mkdir -p $out/bin
            makeWrapper ${ax-shell-python}/bin/python $out/bin/ax-inhibit \
              --add-flags "$src/scripts/inhibit.py"
            runHook postInstall;
          '';
        };

        ax-send = pkgs.writeShellScriptBin "ax-send" ''
          #!${pkgs.stdenv.shell}
          PYTHON_CODE="
          from main import AxShellApp
          app = AxShellApp.get_default()
          app.run_command('$1')
          "
          exec ${inputs.fabric-cli.packages.${system}.default}/bin/fabric-cli exec ax-shell "$PYTHON_CODE"
        '';

        runtimeDeps = with pkgs; [
          adwaita-icon-theme
          papirus-icon-theme
          cinnamon-desktop
          gnome-bluetooth
          inputs.fabric-cli.packages.${system}.default
          glib
          gobject-introspection
          gtk-layer-shell
          gtk3
          cairo
          gdk-pixbuf
          pango
          power-profiles-daemon
          libdbusmenu-gtk3
          libnotify
          upower
          vte
          webp-pixbuf-loader
          brightnessctl
          cava
          cliphist
          gnome-bluetooth
          grimblast
          hyprpicker
          hyprshot
          hyprsunset
          imagemagick
          matugen
          networkmanager
          playerctl
          procps
          swappy
          swww
          tesseract
          tmux
          unzip
          uwsm
          wl-clipboard
          wlinhibit
          ax-shell-inhibit-pkg
          ax-send
          inputs.gray.packages.${system}.default
        ] ++ lib.optionals (system == "x86_64-linux") [
          # nvtop might not be available or functional on all architectures
          nvtopPackages.full
        ];

        ax-shell-pkg = pkgs.callPackage ./default.nix {
          inherit self runtimeDeps tabler-icons-font;
          ax-shell-python = ax-shell-python;
          adwaita-icon-theme = pkgs.adwaita-icon-theme;
        };

        configured-pygobject-stubs = (
          pkgs.python312Packages.pygobject-stubs.overrideAttrs (old: {
            __noCache = true;
            preBuild = ''
              export PYGOBJECT_STUB_CONFIG="Gtk3,Gdk3"
            '';
          })
        );

        dev-python-env = python.withPackages (
          ps: (ax-shell-python-packages ps) ++ [ configured-pygobject-stubs ]
        );

      in
      {
        devShells.default = pkgs.mkShell {
          packages = [
            dev-python-env
          ];
        };

        packages = {
          default = ax-shell-pkg;
          ax-shell = ax-shell-pkg;
          fabric-cli = inputs.fabric-cli.packages.${system}.default;
          ax-send = ax-send;
        };

        apps.default = {
          type = "app";
          program = "${ax-shell-pkg}/bin/ax-shell";
          meta.description = "A custom launcher for the Ax-Shell.";
        };
      }
    )
    // {
      overlays.default = final: prev: {
        ax-shell = self.packages.${prev.system}.ax-shell;
        fabric-cli = self.packages.${prev.system}.fabric-cli;
        ax-send = self.packages.${prev.system}.ax-send;
      };

      homeManagerModules.default = import ./nix/modules/home-manager.nix;
    };
}
