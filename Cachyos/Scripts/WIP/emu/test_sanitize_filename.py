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


class TestSanitizeFilename(unittest.TestCase):
    def test_preservation_of_valid_characters(self):
        # a-z, A-Z, 0-9, -, _, ., and spaces
        input_name = "test-FILE_123.3ds"
        expected = "test-FILE_123.3ds"
        self.assertEqual(decryptor.sanitize_filename(input_name), expected)

    def test_removal_of_invalid_characters(self):
        # !@#$%^&*()+={}[]|\:;"'<>,/? should be removed
        input_name = "test!@#$ %^&*()_+= file.cia"
        # VALID_CHARS = frozenset("-_abcdefghijklmnopqrstuvwxyz1234567890. ")
        # "test", " ", "_", " ", "file.cia" are valid
        expected = "test _ file.cia"
        self.assertEqual(decryptor.sanitize_filename(input_name), expected)

    def test_fallback_behavior(self):
        # If all characters are removed, the original name is returned.
        input_name = "!!!@@@###"
        # All are invalid, so 'out' would be empty, returns original
        expected = "!!!@@@###"
        self.assertEqual(decryptor.sanitize_filename(input_name), expected)

    def test_mixed_case_preservation(self):
        input_name = "MixedCaseFILENAME.3ds"
        expected = "MixedCaseFILENAME.3ds"
        self.assertEqual(decryptor.sanitize_filename(input_name), expected)

    def test_empty_string(self):
        self.assertEqual(decryptor.sanitize_filename(""), "")

if __name__ == '__main__':
    unittest.main()
