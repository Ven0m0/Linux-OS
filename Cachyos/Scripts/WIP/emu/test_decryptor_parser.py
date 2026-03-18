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

class TestParser(unittest.TestCase):
    def test_parse_ctrtool_output_full(self):
        text = """
Title id:                0004000000000100
TitleVersion:            10
Crypto Key:              Secure
"""
        info = decryptor.parse_ctrtool_output(text)
        self.assertEqual(info.title_id, "0004000000000100")
        self.assertEqual(info.title_version, "10")
        self.assertEqual(info.crypto_key, "Crypto Key:              Secure")

    def test_parse_ctrtool_output_partial(self):
        text = "Title id: 0004000000000100"
        info = decryptor.parse_ctrtool_output(text)
        self.assertEqual(info.title_id, "0004000000000100")
        self.assertEqual(info.title_version, "0")
        self.assertEqual(info.crypto_key, "")

    def test_parse_ctrtool_output_empty(self):
        info = decryptor.parse_ctrtool_output("")
        self.assertEqual(info.title_id, "")
        self.assertEqual(info.title_version, "0")
        self.assertEqual(info.crypto_key, "")

    def test_parse_twl_ctrtool_output_full(self):
        text = """
TitleId:                 0004800000000100
TitleVersion:            5
Encrypted:               YES
"""
        info = decryptor.parse_twl_ctrtool_output(text)
        self.assertEqual(info.title_id, "0004800000000100")
        self.assertEqual(info.title_version, "5")
        self.assertEqual(info.crypto_key, "YES")

if __name__ == '__main__':
    unittest.main()
