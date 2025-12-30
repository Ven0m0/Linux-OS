#!/usr/bin/env python3
"""Fetch files/folders from GitHub/GitLab using stdlib only."""

import json
import os
import sys
import urllib.parse
import urllib.request
from concurrent.futures import ThreadPoolExecutor, as_completed
from dataclasses import dataclass
from pathlib import Path
from typing import Literal


@dataclass(slots=True)
class RepoSpec:
    platform: Literal["github", "gitlab"]
    owner: str
    repo: str
    path: str
    branch: str


def parse_url(url: str) -> RepoSpec:
    """Extract repo metadata from GitHub/GitLab URL."""
    u = urllib.parse.urlparse(url)
    parts = [p for p in u.path.strip("/").split("/") if p]

    if "github.com" in u.netloc:
        if len(parts) < 2:
            raise ValueError(f"Invalid GitHub URL: {url}")
        owner, repo = parts[0], parts[1]
        branch = "main"
        path = ""
        if len(parts) > 3 and parts[2] in ("tree", "blob"):
            branch = parts[3]
            path = "/".join(parts[4:]) if len(parts) > 4 else ""
        return RepoSpec("github", owner, repo, path, branch)

    if "gitlab.com" in u.netloc:
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


def http_get(url: str, headers: dict[str, str] | None = None) -> bytes:
    """Execute HTTP GET with optional headers."""
    req = urllib.request.Request(url, headers=headers or {})
    with urllib.request.urlopen(req, timeout=30) as resp:
        return resp.read()


def fetch_github(spec: RepoSpec, output: Path) -> None:
    """Download from GitHub using Contents API."""
    token = os.getenv("GITHUB_TOKEN", "")
    headers = {"Accept": "application/vnd.github.v3+json"}
    if token:
        headers["Authorization"] = f"token {token}"

    api_url = (
        f"https://api.github.com/repos/{spec.owner}/{spec.repo}/contents/{spec.path}"
    )
    if spec.branch != "main":
        api_url += f"?ref={spec.branch}"

    try:
        data = json.loads(http_get(api_url, headers))
    except urllib.error.HTTPError as e:
        if e.code == 404:
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
        content = http_get(url, headers)
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(content)
        print(f"✓ {item_path}")

    with ThreadPoolExecutor(max_workers=min(32, (os.cpu_count() or 1) + 4)) as executor:
        futures = [
            executor.submit(download_file, url, path, item_path)
            for url, path, item_path in files_to_download
        ]
        for future in as_completed(futures):
            future.result()  # Raise exceptions if any

    # Process directories recursively
    for item_path, local_path in dirs_to_process:
        sub_spec = RepoSpec(
            spec.platform, spec.owner, spec.repo, item_path, spec.branch
        )
        fetch_github(sub_spec, local_path)


def fetch_gitlab(spec: RepoSpec, output: Path) -> None:
    """Download from GitLab using Repository API."""
    token = os.getenv("GITLAB_TOKEN", "")
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
        data = json.loads(http_get(full_url, headers))
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
        content = http_get(url, headers)
        path.write_bytes(content)
        print(f"✓ {item_path}")

    with ThreadPoolExecutor(max_workers=min(32, (os.cpu_count() or 1) + 4)) as executor:
        futures = [
            executor.submit(download_file, url, path, ip)
            for url, path, ip in files_to_download
        ]
        for future in as_completed(futures):
            future.result()  # Raise exceptions if any


def main() -> int:
    if len(sys.argv) < 2:
        print("Usage: fetch.py <github-or-gitlab-url> [output-dir]", file=sys.stderr)
        print("\nExamples:", file=sys.stderr)
        print(
            "  fetch.py https://github.com/owner/repo/tree/main/path", file=sys.stderr
        )
        print(
            "  fetch.py https://gitlab.com/owner/repo/-/tree/main/path output/",
            file=sys.stderr,
        )
        print("\nAuth: Set GITHUB_TOKEN or GITLAB_TOKEN env vars", file=sys.stderr)
        return 1

    url = sys.argv[1]
    output_dir = Path(sys.argv[2] if len(sys.argv) > 2 else ".")

    try:
        spec = parse_url(url)
        output_path = output_dir / (Path(spec.path).name or spec.repo)

        if spec.platform == "github":
            fetch_github(spec, output_path)
        else:
            fetch_gitlab(spec, output_path)

        print(f"\n✓ Downloaded to: {output_path}")
        return 0
    except Exception as e:
        print(f"✗ Error: {e}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
