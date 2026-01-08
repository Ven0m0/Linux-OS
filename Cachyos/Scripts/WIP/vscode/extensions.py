#!/usr/bin/env python3
import argparse
import shutil
import subprocess
import sys
from pathlib import Path


def command_required(cmd: str) -> None:
    if shutil.which(cmd) is None:
        print(f"!! Command '{cmd}' is required.", file=sys.stderr)
        sys.exit(1)


def run_cmd(cmd: list[str], text: bool = False) -> subprocess.CompletedProcess:
    try:
        return subprocess.run(cmd, capture_output=True, text=text, check=True)
    except subprocess.CalledProcessError as e:
        print(f"!! Subcommand error --> {e}", file=sys.stderr)
        sys.exit(1)


def main() -> None:
    command_required("code")

    parser = argparse.ArgumentParser(description="Manage VS Code extensions.")
    parser.add_argument(
        "-i",
        "--install",
        action="store_true",
        help="Install extensions from extensions.txt",
    )
    parser.add_argument(
        "-u",
        "--update",
        action="store_true",
        help="Update extensions.txt with installed ones",
    )
    parser.add_argument(
        "-o",
        "--overwrite",
        action="store_true",
        help="Overwrite extensions.txt (implies --update)",
    )
    args = parser.parse_args()

    extensions_file = Path(__file__).parent / "extensions.txt"

    if args.install and not extensions_file.exists():
        print(f"!! File not found: '{extensions_file}'", file=sys.stderr)
        sys.exit(1)

    extensions_from_file = set()
    if extensions_file.exists():
        extensions_from_file = {
            line.strip()
            for line in extensions_file.read_text().splitlines()
            if line.strip()
        }

    if args.install:
        for ext in sorted(extensions_from_file):
            run_cmd(["code", "--install-extension", ext, "--force"])
        print(f"✓ Installed {len(extensions_from_file)} extensions")

    if args.update or args.overwrite:
        result = run_cmd(["code", "--list-extensions"], text=True)
        current_extensions = set(result.stdout.strip().splitlines())

        saved_extensions = set() if args.overwrite else extensions_from_file
        merged = sorted(saved_extensions | current_extensions)

        extensions_file.write_text("\n".join(merged) + "\n")
        print(f"✓ Saved {len(merged)} extensions to {extensions_file}")


if __name__ == "__main__":
    main()
