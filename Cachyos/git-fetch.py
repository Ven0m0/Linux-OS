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
    """Download from GitHub using Contents API."""
    token = token or os.getenv("GITHUB_TOKEN", "")
    headers = {"Accept": "application/vnd.github.v3+json"}
    if token:
        headers["Authorization"] = f"token {token}"

    api_url = (
        f"https://api.github.com/repos/{spec.owner}/{spec.repo}/contents/{spec.path}"
    )
    if spec.branch != "main":
        api_url += f"?ref={spec.branch}"

    try:
        data_bytes = http_get(api_url, headers)
        data = json.loads(data_bytes)
    except urllib.error.HTTPError as e:
        if e.code == 404:
            # Fallback to raw file download if API fails (maybe it's a file, not dir)
            raw_url = f"https://raw.githubusercontent.com/{spec.owner}/{spec.repo}/{spec.branch}/{spec.path}"
            content = http_get(raw_url, headers)
            output.parent.mkdir(parents=True, exist_ok=True)
            output.write_bytes(content)
            print(f"✓ {spec.path}")
            return
        raise

    if isinstance(data, dict):
        data = [data]

    # Separate files and dirs for parallel processing
    files_to_download = []
    dirs_to_process = []

    for item in data:
        item_path = item["path"]
        local_path = output / Path(item_path).name

        if item["type"] == "file":
            files_to_download.append((item["download_url"], local_path, item_path))
        elif item["type"] == "dir":
            local_path.mkdir(parents=True, exist_ok=True)
            dirs_to_process.append((item_path, local_path))

    # Parallel file downloads
    def download_file(url, path, item_path):
        try:
            content = http_get(url, headers)
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(content)
            print(f"✓ {item_path}")
        except Exception as e:
            print(f"✗ {item_path}: {e}")
            raise

    max_workers = min(32, (os.cpu_count() or 1) * 4)
    with ThreadPoolExecutor(max_workers=max_workers) as executor:
        futures = [
            executor.submit(download_file, url, path, item_path)
            for url, path, item_path in files_to_download
        ]
        for future in as_completed(futures):
            try:
                future.result()
            except Exception:
                pass # Already logged

    # Process directories recursively
    for item_path, local_path in dirs_to_process:
        sub_spec = RepoSpec(
            spec.platform, spec.owner, spec.repo, item_path, spec.branch
        )
        fetch_github(sub_spec, local_path, token)


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