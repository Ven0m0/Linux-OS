#!/usr/bin/env python3
import json
import unittest
import sys
import importlib.util
from pathlib import Path
from unittest.mock import MagicMock, patch

# Dynamically import git-fetch.py
file_path = Path(__file__).parent / "git-fetch.py"
spec = importlib.util.spec_from_file_location("git_fetch", file_path)
git_fetch = importlib.util.module_from_spec(spec)
sys.modules["git_fetch"] = git_fetch
spec.loader.exec_module(git_fetch)

class TestGitFetch(unittest.TestCase):
    def test_fetch_github_calls(self):
        # Mock RepoSpec
        repo_spec = git_fetch.RepoSpec("github", "owner", "repo", "", "main")
        output = Path("output")
        token = "token"

        # Mock http_get and process_downloads
        with patch('git_fetch.http_get') as mock_http_get, \
             patch('git_fetch.process_downloads') as mock_process_downloads:

            # Mock response data
            tree_response = {
                "tree": [
                    {"path": "file1.txt", "type": "blob", "mode": "100644", "sha": "sha1", "size": 123},
                    {"path": "dir1", "type": "tree", "mode": "040000", "sha": "sha2"},
                    {"path": "dir1/file2.txt", "type": "blob", "mode": "100644", "sha": "sha3", "size": 456}
                ]
            }
            mock_http_get.return_value = json.dumps(tree_response).encode('utf-8')

            git_fetch.fetch_github(repo_spec, output, token)

            # Verify http_get call
            mock_http_get.assert_called_once()
            args, _ = mock_http_get.call_args
            self.assertIn("api.github.com/repos/owner/repo/git/trees/main?recursive=1", args[0])

            # Verify process_downloads call
            mock_process_downloads.assert_called_once()
            files_to_download = mock_process_downloads.call_args[0][0]

            # Check expected files
            # The URL path part in fetch_github is constructed as:
            # path_part = f"/{spec.owner}/{spec.repo}/{spec.branch}/{encoded_path}"
            expected_paths = {
                "/owner/repo/main/file1.txt",
                "/owner/repo/main/dir1/file2.txt"
            }
            actual_paths = {f[0] for f in files_to_download}
            self.assertEqual(expected_paths, actual_paths)

if __name__ == '__main__':
    unittest.main()
