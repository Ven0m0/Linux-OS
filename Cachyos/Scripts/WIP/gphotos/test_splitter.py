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

    def create_dummy_file(self, name, size):
        path = os.path.join(self.PHOTOS_DIR, name)
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

if __name__ == '__main__':
    unittest.main()
