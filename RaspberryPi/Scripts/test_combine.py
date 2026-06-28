import unittest
from unittest.mock import patch, MagicMock
import sys
from pathlib import Path
import importlib.util

# Import combine.py using importlib
path = Path(__file__).parent / "combine.py"
spec = importlib.util.spec_from_file_location("combine", path)
combine = importlib.util.module_from_spec(spec)
sys.modules["combine"] = combine
spec.loader.exec_module(combine)

class TestCombine(unittest.TestCase):
    def test_detect_encoding_no_chardet(self):
        """Test fallback to utf-8 when chardet is not available."""
        with patch("combine.chardet", None):
            self.assertEqual(combine.detect_encoding(b"test"), "utf-8")

    def test_detect_encoding_with_chardet_success(self):
        """Test that encoding from chardet is used when available."""
        mock_chardet = MagicMock()
        mock_chardet.detect.return_value = {"encoding": "shift_jis"}
        with patch("combine.chardet", mock_chardet):
            self.assertEqual(combine.detect_encoding(b"test"), "shift_jis")

    def test_detect_encoding_with_chardet_none_result(self):
        """Test fallback to utf-8 when chardet returns None for encoding."""
        mock_chardet = MagicMock()
        mock_chardet.detect.return_value = {"encoding": None}
        with patch("combine.chardet", mock_chardet):
            self.assertEqual(combine.detect_encoding(b"test"), "utf-8")

if __name__ == "__main__":
    unittest.main()
