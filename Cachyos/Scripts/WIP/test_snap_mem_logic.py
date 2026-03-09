#!/usr/bin/env python3
import importlib.util
import unittest
import sys
import threading
from pathlib import Path

# Dynamically import snap-mem.py
file_path = Path(__file__).parent / "snap-mem.py"
spec = importlib.util.spec_from_file_location("snap_mem", str(file_path))
if spec is None:
    raise ImportError(f"Could not load {file_path}")
snap_mem = importlib.util.module_from_spec(spec)
sys.modules["snap_mem"] = snap_mem
spec.loader.exec_module(snap_mem)


class TestSnapMem(unittest.TestCase):
    def test_make_unique_name(self):
        # make_unique_name updates the 'existing' set in-place
        existing = {"base.jpg", "base_1.jpg"}
        lock = threading.Lock()

        # Test finding unique name
        # base_2.jpg should be selected if logic is: base_2.jpg
        # Implementation:
        # name = f"{base}{suffix}"
        # while name in existing: name = f"{base}_{n}{suffix}"
        # base.jpg is in existing. n=1 -> base_1.jpg (in existing). n=2 -> base_2.jpg.
        name = snap_mem.make_unique_name("base", ".jpg", existing, lock)
        self.assertEqual(name, "base_2.jpg")
        self.assertIn("base_2.jpg", existing)

        # Test another one
        # base_3.jpg
        name2 = snap_mem.make_unique_name("base", ".jpg", existing, lock)
        self.assertEqual(name2, "base_3.jpg")
        self.assertIn("base_3.jpg", existing)


if __name__ == '__main__':
    unittest.main()
