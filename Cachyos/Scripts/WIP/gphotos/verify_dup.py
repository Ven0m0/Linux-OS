#!/usr/bin/env python3
import os
import shutil
import tempfile
import unittest
from Dup import find_duplicate_photos

class TestDup(unittest.TestCase):
    def setUp(self):
        self.test_dir = tempfile.mkdtemp()
        self.output_file = os.path.join(self.test_dir, "duplicates.txt")

    def tearDown(self):
        shutil.rmtree(self.test_dir)

    def create_file(self, name, content, size=None):
        path = os.path.join(self.test_dir, name)
        if size:
            # Create file of specific size with repeated content
            with open(path, "wb") as f:
                f.write((content * (size // len(content) + 1))[:size])
        else:
            with open(path, "wb") as f:
                f.write(content)
        return path

    def test_find_duplicates(self):
        # Create unique files
        self.create_file("unique1.jpg", b"unique1")
        self.create_file("unique2.png", b"unique2")

        # Create duplicates
        content = b"duplicate_content" * 100
        self.create_file("dup1.jpg", content)
        self.create_file("dup2.jpg", content)

        # Create same size but different content
        # Size of content is len(content) = 1700
        size = len(content)
        self.create_file("same_size1.jpg", b"A" * size, size=size)
        self.create_file("same_size2.jpg", b"B" * size, size=size)

        # Create partial hash collision but different full hash (simulated by same first 64KB)
        # 64KB = 65536
        # Create 70KB files. First 64KB same, last part different.
        prefix = b"P" * 65536
        self.create_file("partial_collision1.jpg", prefix + b"A")
        self.create_file("partial_collision2.jpg", prefix + b"B")

        find_duplicate_photos(self.test_dir, self.output_file)

        with open(self.output_file, "r") as f:
            output = f.read()

        # dup1 and dup2 should be in output
        self.assertIn("dup1.jpg", output)
        self.assertIn("dup2.jpg", output)

        # unique files should not be in output
        self.assertNotIn("unique1.jpg", output)
        self.assertNotIn("unique2.png", output)

        # same size different content should not be in output
        self.assertNotIn("same_size1.jpg", output)
        self.assertNotIn("same_size2.jpg", output)

        # partial collision should not be in output
        self.assertNotIn("partial_collision1.jpg", output)
        self.assertNotIn("partial_collision2.jpg", output)

if __name__ == "__main__":
    unittest.main()
