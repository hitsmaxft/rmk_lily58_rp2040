{
  description = "flake rmk with rust toolchain";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, utils }:
    let
      systemBuildInputs = system: pkgs:
        [ pkgs.iconv pkgs.openssl ]
        ++ (if pkgs.lib.strings.hasInfix "$system" "darwin" then [
          pkgs.darwin.apple_sdk.frameworks.Security
          pkgs.darwin.apple_sdk.frameworks.SystemConfiguration
        ] else
          [ ]);
    in utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
        pico-dfu = pkgs.writeShellApplication {
          name = "pico-dfu";
          text = ''
            #!/bin/bash
            SKIP_CONFIRM=0

            while getopts ":y" opt; do
                case $opt in
                    y )
                        SKIP_CONFIRM=1
                        ;;
                    \? )
                        echo "Invalid option: -$OPTARG" >&2
                        exit 1
                        ;;
                esac
            done
            shift $((OPTIND -1))
            # Ensure the UF2 file is provided as a command-line argument
            if [ -z "$1" ]; then
                echo "Usage: $0 <path_to_uf2_file>"
                exit 1
            fi

            UF2_FILE="$1"
            VOLUME_PATH="/Volumes/RPI-RP2"

            # Check if the UF2 file exists
            if [ ! -f "$UF2_FILE" ]; then
                echo "The file $UF2_FILE does not exist."
                exit 1
            fi

            echo "Ensure sudo permission..."

            sudo bash -c 'echo "" >/dev/null'

            echo "Waiting for volume $VOLUME_PATH to appear..."

            # Loop until the volume appears
            while [ ! -d "$VOLUME_PATH" ]; do
                sleep 1
            done

            # Find which disk the volume belongs to
            while [ ! "$(mount | grep "$VOLUME_PATH" | awk '{print $1}')" ]; do
                sleep 1
            done

            echo "Volume $VOLUME_PATH detected."

            DISK_ID="$(mount | grep "$VOLUME_PATH" | awk '{print $1}')"

            if [[ -z "$DISK_ID" ]]; then
                echo "Could not determine the disk for $VOLUME_PATH." >> /dev/stderr
                exit 1
            fi

            echo "The volume $VOLUME_PATH is associated with $DISK_ID."
            # delay 2s
            sleep 2

            # Define the final shell command
            FINAL_COMMAND="sudo bash -c 'umount $VOLUME_PATH && cat $UF2_FILE > $DISK_ID'"

            # Show the final command to the user and ask for confirmation
            echo "The following command will be executed:"
            echo "$FINAL_COMMAND"

            if [[ SKIP_CONFIRM -ne 1 ]] ; then
                read -r -p "Do you want to proceed? (y/n) " CONFIRM
            else
                CONFIRM="y"
            fi

            if [[ "$CONFIRM" =~ ^[Yy]$ ]]; then
                echo "Running the command: $FINAL_COMMAND"
                if [[ $(sudo bash -c "umount $VOLUME_PATH && cat $UF2_FILE > $DISK_ID") -eq 0 ]]; then
                    echo "Command executed successfully."
                else
                    echo "Command failed."
                fi
            else
                echo "Operation cancelled by the user."
            fi
          '';
        };

      in {
        # defaultPackage = naersk-lib.buildPackage {
        #   src = ./.;
        #   buildInputs = (systemBuildInputs system pkgs).${system};
        # };

        devShell = with pkgs;
          mkShell {
            shellHook = "export PATH=${"$"}PATH:~/.cargo/bin;";
            buildInputs = [
              rustup
              rustfmt
              cargo-make
              probe-rs-tools
              openocd-rp2040
              pico-dfu
              minicom
              # pre-commit
              # rustPackages.clippy
            ] ++ (systemBuildInputs system pkgs);
            RUST_SRC_PATH = rustPlatform.rustLibSrc;
          };
      });
}
