import unittest
import importlib.util
import sys
import threading
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

    def test_build_base_name_whitespace(self):
        # build_base_name uses datetime.strptime(date_str, DATE_FMT)
        # strptime is strict about whitespace unless included in fmt
        date_str = " 2023-01-01 12:00:00 UTC "
        with self.assertRaises(ValueError):
            snap_mem.build_base_name(date_str)

    def test_build_base_name_logical_invalid_date(self):
        # 2023 is not a leap year
        date_str = "2023-02-29 12:00:00 UTC"
        with self.assertRaises(ValueError):
            snap_mem.build_base_name(date_str)

    def test_make_unique_name(self):
        # make_unique_name updates the 'existing' set in-place
        existing = {"base.jpg", "base_1.jpg"}
        lock = threading.Lock()

        # base.jpg is in existing. n=1 -> base_1.jpg (in existing). n=2 -> base_2.jpg.
        name = snap_mem.make_unique_name("base", ".jpg", existing, lock)
        self.assertEqual(name, "base_2.jpg")
        self.assertIn("base_2.jpg", existing)

        # base_3.jpg
        name2 = snap_mem.make_unique_name("base", ".jpg", existing, lock)
        self.assertEqual(name2, "base_3.jpg")
        self.assertIn("base_3.jpg", existing)

    def test_make_unique_name_empty_set(self):
        existing = set()
        lock = threading.Lock()
        name = snap_mem.make_unique_name("base", ".jpg", existing, lock)
        self.assertEqual(name, "base.jpg")
        self.assertIn("base.jpg", existing)

    def test_make_unique_name_multiple_collisions(self):
        existing = {"base.jpg", "base_1.jpg", "base_2.jpg", "base_3.jpg"}
        lock = threading.Lock()
        name = snap_mem.make_unique_name("base", ".jpg", existing, lock)
        self.assertEqual(name, "base_4.jpg")
        self.assertIn("base_4.jpg", existing)

if __name__ == '__main__':
    unittest.main()
