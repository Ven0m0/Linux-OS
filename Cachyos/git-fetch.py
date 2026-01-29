#!/usr/bin/env python3
"""Fetch files/folders from GitHub/GitLab using stdlib only.

This script allows downloading files or directories from GitHub or GitLab
repositories without requiring git to be installed, using only the
standard library.

Usage:
    fetch.py <github-or-gitlab-url> [output-dir] [--token TOKEN]

Environment Variables:
    GITHUB_TOKEN - Optional auth token for GitHub
    GITLAB_TOKEN - Optional auth token for GitLab
"""

import argparse
import json
import os
import sys
import urllib.parse
import urllib.request
import urllib.error
from concurrent.futures import ThreadPoolExecutor, as_completed
from dataclasses import dataclass
from pathlib import Path
from typing import Literal, Optional


@dataclass(slots=True)
class RepoSpec:
    """Repository specification parsed from URL."""

    platform: Literal["github", "gitlab"]
    owner: str
    repo: str
    path: str
    branch: str


def parse_url(url: str) -> RepoSpec:
    """Extract repo metadata from GitHub/GitLab URL."""
    u = urllib.parse.urlparse(url)
    parts = [p for p in u.path.strip("/").split("/") if p]
    host = u.hostname or ""

    if host == "github.com":
        if len(parts) < 2:
            raise ValueError(f"Invalid GitHub URL: {url}")
        owner, repo = parts[0], parts[1]
        branch = "main"
        path = ""
        if len(parts) > 3 and parts[2] in ("tree", "blob"):
            branch = parts[3]
            path = "/".join(parts[4:]) if len(parts) > 4 else ""
        return RepoSpec("github", owner, repo, path, branch)

    if host == "gitlab.com":
        if len(parts) < 2:
            raise ValueError(f"Invalid GitLab URL: {url}")
        owner, repo = parts[0], parts[1]
        branch = "main"
        path = ""
        if len(parts) > 3 and parts[2] == "-" and parts[3] == "tree":
            branch = parts[4] if len(parts) > 4 else "main"
            path = "/".join(parts[5:]) if len(parts) > 5 else ""
        return RepoSpec("gitlab", owner, repo, path, branch)

    raise ValueError(f"Unsupported platform: {u.netloc}")


_opener_cache: Optional[urllib.request.OpenerDirector] = None


def get_opener() -> urllib.request.OpenerDirector:
    """Get cached opener for connection reuse."""
    global _opener_cache
    if _opener_cache is None:
        _opener_cache = urllib.request.build_opener()
    return _opener_cache


def http_get(url: str, headers: dict[str, str] | None = None) -> bytes:
    """Execute HTTP GET with optional headers."""
    req = urllib.request.Request(url, headers=headers or {})
    try:
        with get_opener().open(req, timeout=30) as resp:
            return resp.read()
    except urllib.error.URLError as e:
        print(f"Error fetching {url}: {e}", file=sys.stderr)
        raise


def fetch_github(spec: RepoSpec, output: Path, token: Optional[str] = None) -> None:
    """Download from GitHub using Tree API (recursive)."""
    token = token or os.getenv("GITHUB_TOKEN", "")
    headers = {"Accept": "application/vnd.github.v3+json"}
    if token:
        headers["Authorization"] = f"token {token}"

    # Fetch the entire tree recursively
    api_url = f"https://api.github.com/repos/{spec.owner}/{spec.repo}/git/trees/{spec.branch}?recursive=1"

    try:
        data_bytes = http_get(api_url, headers)
        data = json.loads(data_bytes)
    except urllib.error.HTTPError as e:
        if e.code == 404:
            # Fallback: maybe spec.path is a file and not in a tree or branch issue?
            # Or the branch doesn't exist.
            # We can try raw download if spec.path is set, similar to original fallback.
            if spec.path:
                raw_url = f"https://raw.githubusercontent.com/{spec.owner}/{spec.repo}/{spec.branch}/{urllib.parse.quote(spec.path)}"
                try:
                    content = http_get(raw_url, headers)
                    output.parent.mkdir(parents=True, exist_ok=True)
                    output.write_bytes(content)
                    print(f"✓ {spec.path}")
                    return
                except urllib.error.HTTPError:
                    pass  # Original 404 was correct
            raise
        raise

    if data.get("truncated"):
        print(
            "Warning: Tree is truncated. Some files might be missing.", file=sys.stderr
        )

    files_to_download = []

    # Filter items based on spec.path
    target_path = spec.path.strip("/")

    found_any = False

    for item in data.get("tree", []):
        item_path = item["path"]

        # Check if item matches target_path
        if (
            target_path
            and item_path != target_path
            and not item_path.startswith(target_path + "/")
        ):
            continue

        found_any = True

        # Determine local path
        if target_path:
            # Relative path from target_path
            rel_path = item_path[len(target_path) :].lstrip("/")
            if not rel_path and item["type"] == "blob":
                # Use filename if we matched the file exactly
                local_path = output
            else:
                local_path = output / rel_path
        else:
            local_path = output / item_path

        if item["type"] == "tree":
            local_path.mkdir(parents=True, exist_ok=True)
        elif item["type"] == "blob":
            encoded_path = "/".join(urllib.parse.quote(p) for p in item_path.split("/"))
            raw_url = f"https://raw.githubusercontent.com/{spec.owner}/{spec.repo}/{spec.branch}/{encoded_path}"
            files_to_download.append((raw_url, local_path, item_path))

    if not found_any:
        # If path not found in tree (or tree truncated), try raw download as fallback
        if target_path:
            raw_url = f"https://raw.githubusercontent.com/{spec.owner}/{spec.repo}/{spec.branch}/{urllib.parse.quote(target_path)}"
            try:
                content = http_get(raw_url, headers)
                output.parent.mkdir(parents=True, exist_ok=True)
                output.write_bytes(content)
                print(f"✓ {target_path}")
                return
            except urllib.error.HTTPError:
                pass

        print(f"✗ Path not found: {spec.path}", file=sys.stderr)
        # We don't raise here to allow main to exit cleanly?
        # But original code raised or returned empty.
        # If we return, we print nothing else.
        return

    if not files_to_download:
        return

    # Parallel file downloads
    max_workers = min(32, (os.cpu_count() or 1) * 4)

    def download_file(url, path, item_path):
        try:
            content = http_get(url, headers)
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(content)
            print(f"✓ {item_path}")
        except Exception as e:
            print(f"✗ {item_path}: {e}")
            raise

    with ThreadPoolExecutor(max_workers=max_workers) as executor:
        futures_dl = [
            executor.submit(download_file, url, path, item_path)
            for url, path, item_path in files_to_download
        ]
        for future in as_completed(futures_dl):
            try:
                future.result()
            except Exception:
                pass  # Already logged


def fetch_gitlab(spec: RepoSpec, output: Path, token: Optional[str] = None) -> None:
    """Download from GitLab using Repository API."""
    token = token or os.getenv("GITLAB_TOKEN", "")
    headers = {}
    if token:
        headers["PRIVATE-TOKEN"] = token

    project_id = urllib.parse.quote(f"{spec.owner}/{spec.repo}", safe="")

    tree_url = f"https://gitlab.com/api/v4/projects/{project_id}/repository/tree"
    params = {
        "path": spec.path,
        "ref": spec.branch,
        "per_page": "100",
        "recursive": "true",
    }
    full_url = f"{tree_url}?{urllib.parse.urlencode(params)}"

    try:
        data_bytes = http_get(full_url, headers)
        data = json.loads(data_bytes)
    except urllib.error.HTTPError as e:
        if e.code == 404:
            file_path_enc = urllib.parse.quote(spec.path, safe="")
            raw_url = f"https://gitlab.com/api/v4/projects/{project_id}/repository/files/{file_path_enc}/raw?ref={spec.branch}"
            content = http_get(raw_url, headers)
            output.parent.mkdir(parents=True, exist_ok=True)
            output.write_bytes(content)
            print(f"✓ {spec.path}")
            return
        raise

    dirs_created = set()
    files_to_download = []

    # First pass: create directories and collect files
    for item in data:
        item_path = item["path"]
        rel_path = item_path[len(spec.path) :].lstrip("/") if spec.path else item_path
        local_path = output / rel_path

        if item["type"] == "tree":
            local_path.mkdir(parents=True, exist_ok=True)
            dirs_created.add(str(local_path))
        elif item["type"] == "blob":
            if str(local_path.parent) not in dirs_created:
                local_path.parent.mkdir(parents=True, exist_ok=True)
                dirs_created.add(str(local_path.parent))

            file_path_enc = urllib.parse.quote(item_path, safe="")
            raw_url = f"https://gitlab.com/api/v4/projects/{project_id}/repository/files/{file_path_enc}/raw?ref={spec.branch}"
            files_to_download.append((raw_url, local_path, item_path))

    # Parallel file downloads
    def download_file(url, path, item_path):
        try:
            content = http_get(url, headers)
            path.write_bytes(content)
            print(f"✓ {item_path}")
        except Exception as e:
            print(f"✗ {item_path}: {e}")
            raise

    max_workers = min(32, (os.cpu_count() or 1) * 4)
    with ThreadPoolExecutor(max_workers=max_workers) as executor:
        futures = [
            executor.submit(download_file, url, path, ip)
            for url, path, ip in files_to_download
        ]
        for future in as_completed(futures):
            try:
                future.result()
            except Exception:
                pass


def main() -> int:
    parser = argparse.ArgumentParser(description="Fetch files from GitHub/GitLab.")
    parser.add_argument("url", help="GitHub or GitLab URL")
    parser.add_argument("output_dir", nargs="?", default=".", help="Output directory")
    parser.add_argument("--token", help="Auth token (overrides env vars)")

    args = parser.parse_args()

    try:
        spec = parse_url(args.url)
        output_path = Path(args.output_dir) / (Path(spec.path).name or spec.repo)

        if spec.platform == "github":
            fetch_github(spec, output_path, args.token)
        else:
            fetch_gitlab(spec, output_path, args.token)

        print(f"\n✓ Downloaded to: {output_path}")
        return 0
    except Exception as e:
        print(f"✗ Error: {e}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
