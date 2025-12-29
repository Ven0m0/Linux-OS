import argparse
import os
import shutil
import subprocess


def command_required(cmd:str):
    if shutil.which(cmd) is None:
        print(f"!! Command '{cmd}' is required.")
        exit(1)


def run_cmd(cmd:list, text:bool=False) -> subprocess.CompletedProcess:
    try:
        return subprocess.run(cmd, capture_output=True, text=text, check=True)
    except subprocess.CalledProcessError as e:
        print(f"!! Subcommand error --> {e}")
        exit(1)


def main():
    command_required("code")

    p = argparse.ArgumentParser(description="Manage VS Code extensions.")
    p.add_argument("-i", "--install", action="store_true", help="Install extensions from extensions.txt")
    p.add_argument("-u", "--update", action="store_true", help="Update extensions.txt with installed ones")
    p.add_argument("-o", "--overwrite", action="store_true", help="Overwrite extensions.txt (implies --update)")
    args = p.parse_args()

    extensions_filepath = os.path.join(os.path.dirname(os.path.abspath(__file__)), "extensions.txt")

    if args.install and not os.path.exists(extensions_filepath):
        print(f"!! File not found: '{extensions_filepath}'")
        exit(1)

    # Read file
    extensions_from_file = set()
    with open(extensions_filepath, "r") as f:
        for l in f:
            stripped = l.strip()
            if stripped:
                extensions_from_file.add(stripped)

    # Install
    if args.install:
        cmd = ["code"]
        for ext in extensions_from_file:
            cmd.extend(["--install-extension", ext, "--force"])
        run_cmd(cmd);

    # Update / Overwrite
    if args.update or args.overwrite:
        current_extensions = run_cmd(["code", "--list-extensions"], text=True)
        current_extensions = set(current_extensions.stdout.strip().splitlines())

        # Overwrite: Let this set empty.
        # Update   : Copy data from 'extensions_from_file' so intersection will merge current and saved.
        saved_extensions = set()
        if not args.overwrite and os.path.exists(extensions_filepath):
            saved_extensions = extensions_from_file

        merged_extensions = sorted(saved_extensions.union(current_extensions))

        with open(extensions_filepath, "w") as f:
            for e in merged_extensions:
                f.write(e + "\n")


if __name__ == "__main__":
    main()
