#!/usr/bin/env python3
import importlib.util
import unittest
import sys
from pathlib import Path

# Dynamically import cia_3ds_decryptor.py
file_path = Path(__file__).parent / "cia_3ds_decryptor.py"
spec = importlib.util.spec_from_file_location("cia_3ds_decryptor", str(file_path))
if spec is None:
    raise ImportError(f"Could not load {file_path}")
decryptor = importlib.util.module_from_spec(spec)
sys.modules["cia_3ds_decryptor"] = decryptor
spec.loader.exec_module(decryptor)

class TestCounters(unittest.TestCase):
    def test_counters_addition(self):
        # Updated to use new fields
        c1 = decryptor.Counters(total=10, decrypted_cnt=5, converted_cnt=2, count_3ds=2, count_cia=8)
        c2 = decryptor.Counters(total=5, decrypted_cnt=1, converted_cnt=1, count_3ds=1, count_cia=4)
        c3 = c1 + c2
        self.assertEqual(c3.total, 15)
        self.assertEqual(c3.decrypted_cnt, 6)
        self.assertEqual(c3.converted_cnt, 3)
        self.assertEqual(c3.count_3ds, 3)
        self.assertEqual(c3.count_cia, 12)

    def test_counters_default_values(self):
        c = decryptor.Counters()
        self.assertEqual(c.total, 0)
        self.assertFalse(c.convert_to_cci)

if __name__ == '__main__':
    unittest.main()
