#!/usr/bin/env python3
"""Mock-based unit tests for git-fetch.py."""
import json
import shutil
import tempfile
import unittest
import sys
import importlib.util
from pathlib import Path
from unittest.mock import MagicMock, patch

# Dynamically load git-fetch.py (hyphen in name prevents normal import)
_file_path = Path(__file__).parent / "git-fetch.py"
_spec = importlib.util.spec_from_file_location("git_fetch", _file_path)
git_fetch = importlib.util.module_from_spec(_spec)
sys.modules["git_fetch"] = git_fetch
_spec.loader.exec_module(git_fetch)


class TestParseUrl(unittest.TestCase):
    def test_github_root(self):
        spec = git_fetch.parse_url("https://github.com/owner/repo")
        self.assertEqual(spec.platform, "github")
        self.assertEqual(spec.owner, "owner")
        self.assertEqual(spec.repo, "repo")
        self.assertEqual(spec.path, "")
        self.assertEqual(spec.branch, "main")

    def test_github_tree_path(self):
        spec = git_fetch.parse_url(
            "https://github.com/owner/repo/tree/develop/src/lib"
        )
        self.assertEqual(spec.platform, "github")
        self.assertEqual(spec.branch, "develop")
        self.assertEqual(spec.path, "src/lib")

    def test_github_blob_path(self):
        spec = git_fetch.parse_url(
            "https://github.com/owner/repo/blob/main/README.md"
        )
        self.assertEqual(spec.platform, "github")
        self.assertEqual(spec.branch, "main")
        self.assertEqual(spec.path, "README.md")

    def test_gitlab_root(self):
        spec = git_fetch.parse_url("https://gitlab.com/owner/repo")
        self.assertEqual(spec.platform, "gitlab")
        self.assertEqual(spec.owner, "owner")
        self.assertEqual(spec.repo, "repo")
        self.assertEqual(spec.path, "")

    def test_gitlab_tree_path(self):
        spec = git_fetch.parse_url(
            "https://gitlab.com/owner/repo/-/tree/main/src"
        )
        self.assertEqual(spec.platform, "gitlab")
        self.assertEqual(spec.branch, "main")
        self.assertEqual(spec.path, "src")

    def test_unsupported_host(self):
        with self.assertRaises(ValueError):
            git_fetch.parse_url("https://bitbucket.org/owner/repo")

    def test_invalid_github_url(self):
        with self.assertRaises(ValueError):
            git_fetch.parse_url("https://github.com/onlyowner")


class TestFetchGitHub(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    def _tree_response(self, items):
        return json.dumps({"tree": items}).encode()

    def test_root_fetch_queues_blobs(self):
        spec = git_fetch.RepoSpec("github", "owner", "repo", "", "main")

        tree = [
            {"path": "file1.txt", "type": "blob"},
            {"path": "dir1", "type": "tree"},
            {"path": "dir1/file2.txt", "type": "blob"},
        ]
        with patch("git_fetch.http_get", return_value=self._tree_response(tree)), \
             patch("git_fetch.process_downloads") as mock_dl:
            git_fetch.fetch_github(spec, self.tmp, "token")

        mock_dl.assert_called_once()
        paths = {f[0] for f in mock_dl.call_args[0][0]}
        self.assertEqual(paths, {
            "/owner/repo/main/file1.txt",
            "/owner/repo/main/dir1/file2.txt",
        })

    def test_subtree_fetch_prepends_path(self):
        spec = git_fetch.RepoSpec("github", "owner", "repo", "src/lib", "main")

        tree = [{"path": "utils.py", "type": "blob"}]
        with patch("git_fetch.http_get", return_value=self._tree_response(tree)), \
             patch("git_fetch.process_downloads") as mock_dl:
            git_fetch.fetch_github(spec, self.tmp, "token")

        paths = {f[0] for f in mock_dl.call_args[0][0]}
        self.assertIn("/owner/repo/main/src/lib/utils.py", paths)

    def test_api_url_uses_correct_endpoint(self):
        spec = git_fetch.RepoSpec("github", "owner", "repo", "", "main")

        tree = [{"path": "README.md", "type": "blob"}]
        with patch("git_fetch.http_get", return_value=self._tree_response(tree)) as mock_get, \
             patch("git_fetch.process_downloads"):
            git_fetch.fetch_github(spec, self.tmp, "token")

        url_called = mock_get.call_args[0][0]
        self.assertIn("api.github.com/repos/owner/repo/git/trees/main", url_called)
        self.assertIn("recursive=1", url_called)

    def test_empty_tree_runs_without_error(self):
        spec = git_fetch.RepoSpec("github", "owner", "repo", "", "main")

        with patch("git_fetch.http_get", return_value=self._tree_response([])), \
             patch("git_fetch.process_downloads") as mock_dl:
            git_fetch.fetch_github(spec, self.tmp, "token")

        # process_downloads should be called with an empty list
        files_arg = mock_dl.call_args[0][0]
        self.assertEqual(files_arg, [])


class TestFetchGitLab(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    def test_tree_items_queued(self):
        spec = git_fetch.RepoSpec("gitlab", "owner", "repo", "src", "main")

        items = [
            {"path": "src/app.py", "type": "blob"},
            {"path": "src", "type": "tree"},
        ]
        with patch("git_fetch.http_get", return_value=json.dumps(items).encode()), \
             patch("git_fetch.process_downloads") as mock_dl:
            git_fetch.fetch_gitlab(spec, self.tmp, "token")

        paths = {f[2] for f in mock_dl.call_args[0][0]}
        self.assertIn("src/app.py", paths)


if __name__ == "__main__":
    unittest.main()
