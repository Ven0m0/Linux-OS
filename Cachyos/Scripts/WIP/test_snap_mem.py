import unittest
import importlib.util
import sys
from pathlib import Path

# Import snap-mem.py using importlib because of the hyphen in the filename
path = Path(__file__).parent / "snap-mem.py"
spec = importlib.util.spec_from_file_location("snap_mem", path)
snap_mem = importlib.util.module_from_spec(spec)
sys.modules["snap_mem"] = snap_mem
spec.loader.exec_module(snap_mem)


class TestSnapMem(unittest.TestCase):
    def test_build_base_name_valid(self):
        # Format: %Y-%m-%d %H:%M:%S UTC
        date_str = "2023-01-01 12:00:00 UTC"
        expected = "2023-01-01_12-00-00"
        self.assertEqual(snap_mem.build_base_name(date_str), expected)

    def test_build_base_name_leap_year(self):
        date_str = "2024-02-29 23:59:59 UTC"
        expected = "2024-02-29_23-59-59"
        self.assertEqual(snap_mem.build_base_name(date_str), expected)

    def test_build_base_name_year_boundary(self):
        date_str = "9999-12-31 23:59:59 UTC"
        expected = "9999-12-31_23-59-59"
        self.assertEqual(snap_mem.build_base_name(date_str), expected)

    def test_build_base_name_invalid_format(self):
        # Wrong format
        date_str = "2023/01/01 12:00:00 UTC"
        with self.assertRaises(ValueError):
            snap_mem.build_base_name(date_str)

    def test_build_base_name_empty(self):
        with self.assertRaises(ValueError):
            snap_mem.build_base_name("")


if __name__ == '__main__':
    unittest.main()
