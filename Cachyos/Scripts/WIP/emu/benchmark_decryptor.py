import sys
import os
import time
import tempfile
from pathlib import Path
from unittest.mock import patch

# Add current dir to path to import the script
sys.path.append(os.path.dirname(os.path.abspath(__file__)))
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import cia_3ds_decryptor

# Setup dummy environment
def setup_env(root):
    bin_dir = root / "bin"
    bin_dir.mkdir()
    # Create dummy tools
    ext = ".exe" if cia_3ds_decryptor.IS_WIN else ""
    (bin_dir / f"ctrtool{ext}").touch(mode=0o755)
    (bin_dir / f"decrypt{ext}").touch(mode=0o755)
    (bin_dir / f"makerom{ext}").touch(mode=0o755)
    (bin_dir / "seeddb.bin").touch()

    # Create dummy 3DS files
    for i in range(10):
        (root / f"game_{i}.3ds").touch()

def mock_run_tool(tool, args, stdin="", cwd=None):
    # Simulate work
    time.sleep(0.1)

    tool_name = Path(tool).name

    # Determine bin_dir. In the real code, tools are in bin_dir.
    # When parallelized, tool might be in a temp dir.
    # We can infer the "working bin dir" from the tool path.
    tool_dir = Path(tool).parent

    if "ctrtool" in tool_name:
        # Return dummy TitleInfo
        return 0, "Title id: 0004000000000000\nTitleVersion: 0\nCrypto Key: Secure"

    if "decrypt" in tool_name:
        # Simulate creating NCCH files.
        # The real tool drops them in the current directory or tool directory?
        # Based on my analysis: likely tool directory or CWD.
        # But 'rename_ncch_to_tmp' looks in 'bin_dir'.
        # If the tool path is in a temp dir, we should write there.
        # If 'cwd' is passed, maybe there?
        # The script calls run_tool(..., cwd=root).
        # But rename_ncch_to_tmp takes 'bin_dir'.
        # This implies 'decrypt' outputs to the directory where the executable resides?
        # Let's assume tool_dir.
        (tool_dir / f"random_{time.time()}.ncch").touch()
        return 0, ""

    if "makerom" in tool_name:
        # args: ..., "-o", output_file, ...
        if "-o" in args:
            idx = args.index("-o")
            out_file = Path(args[idx+1])
            out_file.touch()
        return 0, ""

    return 0, ""

def run_benchmark():
    # Use a specific temp dir so we can debug if needed, or just standard
    with tempfile.TemporaryDirectory() as tmp_dir:
        root = Path(tmp_dir)
        setup_env(root)

        print(f"Running benchmark in {root} with 10 files...")
        start_time = time.time()

        # Patch environment and run main
        # We assume the tools are in bin_dir, so find_tool should just return them
        def mock_find_tool(name, bin_dir):
            # Just return the path in bin_dir, assuming it exists because we made it
            # We made them with .exe if IS_WIN, else without.
            # But find_tool on linux looks for native (no ext) or .exe + wine.
            # Our setup_env creates 'ctrtool' (no ext) on linux.
            return bin_dir / name

        with patch('pathlib.Path.cwd', return_value=root), \
             patch('cia_3ds_decryptor.run_tool', side_effect=mock_run_tool), \
             patch('cia_3ds_decryptor.find_tool', side_effect=mock_find_tool), \
             patch('cia_3ds_decryptor.input', return_value="n"), \
             patch('cia_3ds_decryptor.setup_logging'):

             try:
                 cia_3ds_decryptor.main()
             except SystemExit as e:
                 if e.code != 0:
                     print(f"Script exited with code {e.code}")

        end_time = time.time()
        print(f"Time taken: {end_time - start_time:.4f} seconds")

if __name__ == "__main__":
    run_benchmark()
