#!/usr/bin/env python3
import importlib.util
import unittest
import sys
from pathlib import Path
import tempfile

# Dynamically import cia_3ds_decryptor.py
file_path = Path(__file__).parent / "cia_3ds_decryptor.py"
spec = importlib.util.spec_from_file_location("cia_3ds_decryptor", str(file_path))
if spec is None:
    raise ImportError(f"Could not load {file_path}")
decryptor = importlib.util.module_from_spec(spec)
sys.modules["cia_3ds_decryptor"] = decryptor
spec.loader.exec_module(decryptor)

class TestDecryptorContentId(unittest.TestCase):
    def setUp(self):
        self.temp_dir = tempfile.TemporaryDirectory()
        self.bin_dir = Path(self.temp_dir.name)
        self.content_txt = self.bin_dir / "content.txt"

    def tearDown(self):
        self.temp_dir.cleanup()

    def test_extract_content_ids_no_text(self):
        self.assertEqual(decryptor._extract_content_ids(""), [])

    def test_extract_content_ids_valid_text(self):
        text = (
            "ContentId: 00000001\n"
            "Some other line\n"
            "ContentId:  00000002 \n"
            "ContentId:\n"  # Invalid, empty after split
        )
        expected = [1, 2]
        self.assertEqual(decryptor._extract_content_ids(text), expected)

    def test_build_ncch_args_contentid(self):
        text = (
            "ContentId: 0000000A\n"
            "ContentId: 0000000B\n"
        )
        content_ids = decryptor._extract_content_ids(text)

        # Create some fake ncch files
        (self.bin_dir / "tmp.0.ncch").touch()
        (self.bin_dir / "tmp.1.ncch").touch()
        (self.bin_dir / "tmp.2.ncch").touch() # More files than IDs

        ncch0 = self.bin_dir / "tmp.0.ncch"
        ncch1 = self.bin_dir / "tmp.1.ncch"
        ncch2 = self.bin_dir / "tmp.2.ncch"

        ncch_files = [ncch0, ncch1, ncch2]

        args = decryptor.build_ncch_args_contentid(ncch_files, content_ids)

        # Expect content ids 10 and 11, and fallback to 2 for the last one
        expected_parts = [
            f'-i "{ncch0}:0:10"',
            f'-i "{ncch1}:1:11"',
            f'-i "{ncch2}:2:2"',
        ]
        self.assertEqual(args, " ".join(expected_parts))

if __name__ == '__main__':
    unittest.main()
