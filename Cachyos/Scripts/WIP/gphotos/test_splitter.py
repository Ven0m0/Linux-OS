import unittest
import os
import shutil
import io
from contextlib import redirect_stdout
import Splitter

class TestSplitter(unittest.TestCase):
    TEST_DIR = "test_photos_env_unit"
    PHOTOS_DIR = os.path.join(TEST_DIR, "photos")
    TARGET_SIZE = 1024 * 1024 * 5 # 5 MB
    FILE_SIZE = 1024 * 1024 * 1 # 1 MB

    def setUp(self):
        if os.path.exists(self.TEST_DIR):
            shutil.rmtree(self.TEST_DIR)
        os.makedirs(self.PHOTOS_DIR)

    def tearDown(self):
        if os.path.exists(self.TEST_DIR):
            shutil.rmtree(self.TEST_DIR)

    def create_dummy_file(self, name, size, subfolder=""):
        path = os.path.join(self.PHOTOS_DIR, subfolder, name)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, 'wb') as f:
            f.seek(size - 1)
            f.write(b'\0')

    def test_grouping_logic_and_redundancy(self):
        # Create 10 files
        for i in range(10):
            self.create_dummy_file(f"photo_{i}.jpg", self.FILE_SIZE)

        # First run
        f = io.StringIO()
        with redirect_stdout(f):
            Splitter.group_photos(self.PHOTOS_DIR, self.TARGET_SIZE)
        output = f.getvalue()

        moves = output.count("Moved photo")
        self.assertEqual(moves, 10, "Should move 10 files initially")

        # Add 5 more files
        for i in range(10, 15):
            self.create_dummy_file(f"photo_{i}.jpg", self.FILE_SIZE)

        # Second run
        f = io.StringIO()
        with redirect_stdout(f):
            Splitter.group_photos(self.PHOTOS_DIR, self.TARGET_SIZE)
        output = f.getvalue()

        moves = output.count("Moved photo")
        self.assertEqual(moves, 5, "Should only move the 5 new files")

    def test_incremental_respects_limits(self):
        # Create 5 files (Total 5MB, exactly the limit)
        for i in range(5):
            self.create_dummy_file(f"p1_{i}.jpg", self.FILE_SIZE)

        with redirect_stdout(io.StringIO()):
            Splitter.group_photos(self.PHOTOS_DIR, self.TARGET_SIZE)

        self.assertEqual(Splitter.get_folder_size(os.path.join(self.PHOTOS_DIR, "Group_1")), self.TARGET_SIZE)

        # Add 1 more file
        self.create_dummy_file("p2_0.jpg", self.FILE_SIZE)

        with redirect_stdout(io.StringIO()):
            Splitter.group_photos(self.PHOTOS_DIR, self.TARGET_SIZE)

        # Group_1 should still be exactly 5MB, and p2_0 should be in Group_2
        self.assertEqual(Splitter.get_folder_size(os.path.join(self.PHOTOS_DIR, "Group_1")), self.TARGET_SIZE)
        self.assertTrue(os.path.exists(os.path.join(self.PHOTOS_DIR, "Group_2", "p2_0.jpg")))

    def test_parse_size(self):
        self.assertEqual(Splitter.parse_size("100"), 100)
        self.assertEqual(Splitter.parse_size("1KB"), 1024)
        self.assertEqual(Splitter.parse_size("1 MB"), 1024*1024)
        self.assertEqual(Splitter.parse_size("1.5GB"), int(1.5 * 1024*1024*1024))
        with self.assertRaises(Exception):
            Splitter.parse_size("invalid")

    def test_skip_large_files(self):
        # Create a file larger than target size
        self.create_dummy_file("huge.jpg", self.TARGET_SIZE + 1)

        f = io.StringIO()
        with redirect_stdout(f):
            Splitter.group_photos(self.PHOTOS_DIR, self.TARGET_SIZE)
        output = f.getvalue()

        self.assertIn("Skipping photo", output)
        self.assertTrue(os.path.exists(os.path.join(self.PHOTOS_DIR, "huge.jpg")))

if __name__ == '__main__':
    unittest.main()
