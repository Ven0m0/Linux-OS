#!/bin/bash
set -e
python3 Cachyos/Scripts/WIP/emu/test_decryptor_counters.py
python3 Cachyos/Scripts/WIP/gh/test_git_fetch_mock.py
python3 Cachyos/Scripts/WIP/gphotos/test_splitter.py
python3 Cachyos/Scripts/WIP/gphotos/verify_dup.py
python3 Cachyos/Scripts/WIP/test_snap_mem.py
python3 Cachyos/Scripts/WIP/test_snap_mem_logic.py
echo "All tests passed"
